import json
import boto3
import uuid
from datetime import datetime, timezone
from decimal import Decimal
import time
import os

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
s3_client = boto3.client('s3')

# Environment variables for v2 infrastructure
RAW_EVENTS_TABLE = os.environ.get('RAW_EVENTS_TABLE')
S3_ARCHIVE_BUCKET = os.environ.get('S3_ARCHIVE_BUCKET')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')

# Initialize DynamoDB table
table = dynamodb.Table(RAW_EVENTS_TABLE)

def convert_floats_to_decimal(obj):
    """Convert float values to Decimal for DynamoDB compatibility"""
    if isinstance(obj, float):
        return Decimal(str(obj))
    elif isinstance(obj, dict):
        return {key: convert_floats_to_decimal(value) for key, value in obj.items()}
    elif isinstance(obj, list):
        return [convert_floats_to_decimal(item) for item in obj]
    else:
        return obj

def lambda_handler(event, context):
    try:
        # Set CORS headers for browser requests
        headers = {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
            "Access-Control-Allow-Headers": "Content-Type"
        }
        
        # Log incoming request for debugging (remove in production)
        print(f"Received event: {json.dumps(event, default=str)}")
        
        # Handle preflight OPTIONS request
        if event.get('httpMethod') == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': headers,
                'body': ''
            }
        
        current_time = datetime.utcnow().isoformat()
        
        # Extract client IP and user agent safely
        request_context = event.get('requestContext', {})
        if request_context is None:
            request_context = {}
        identity = request_context.get('identity', {})
        if identity is None:
            identity = {}
        client_ip = identity.get('sourceIp', 'unknown')
        
        request_headers = event.get('headers', {})
        if request_headers is None:
            request_headers = {}
        user_agent = request_headers.get('User-Agent', '')
        
        # Process based on HTTP method
        if event.get('httpMethod') == 'GET':
            # Process GET request (tracking pixel fallback)
            query_params = event.get('queryStringParameters')
            if query_params is None:
                query_params = {}
            
            tracking_data = {
                'eventType': query_params.get('type', 'pageview'),
                'sessionId': query_params.get('sid', 'unknown'),
                'visitorId': query_params.get('vid', 'unknown'),
                'url': query_params.get('url', ''),
                'timestamp': current_time,
                'referrer': query_params.get('ref', ''),
                'userAgent': user_agent,
                'ip': client_ip,
                'source': query_params.get('source', ''),
                'medium': query_params.get('medium', ''),
                'campaign': query_params.get('campaign', '')
            }
            
            # Store single event
            store_single_event(tracking_data, client_ip, user_agent, current_time, context)
            
        else:
            # Process POST request (JSON data)
            try:
                body = json.loads(event.get('body', '{}'))
            except json.JSONDecodeError:
                body = {}
            
            event_type = body.get('eventType', 'unknown')
            
            if event_type == 'batch':
                # Handle batch events as single records
                store_batch_record(body, client_ip, user_agent, current_time, context)
            else:
                # Handle single events (pageview, page_exit, form_submit)
                store_single_event(body, client_ip, user_agent, current_time, context)
        
        # Return success response
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'status': 'success',
                'message': 'Tracking data received'
            })
        }
        
    except Exception as e:
        # Log the error
        print(f"Error processing tracking data: {str(e)}")
        
        # Return error response
        return {
            'statusCode': 500,
            'headers': {
                "Access-Control-Allow-Origin": "*"
            },
            'body': json.dumps({
                'status': 'error',
                'message': 'Failed to process tracking data'
            })
        }

def store_batch_record(batch_data, client_ip, user_agent, current_time, context):
    """Store entire batch as one DynamoDB record"""
    
    batch_id = str(uuid.uuid4())
    events = batch_data.get('events', [])
    batch_metadata = batch_data.get('batchMetadata', {})
    
    print(f"Storing batch record with {len(events)} events, batch_id: {batch_id}")
    
    # Analyze batch contents
    event_types = {}
    click_count = 0
    scroll_events = 0
    scroll_milestones = []
    total_scroll_depth = 0
    
    for event in events:
        event_type = event.get('eventType', 'unknown')
        event_types[event_type] = event_types.get(event_type, 0) + 1
        
        # Extract specific metrics for easy querying
        if event_type == 'click':
            click_count += 1
        elif event_type == 'scroll':
            scroll_events += 1
            scroll_percentage = event.get('eventData', {}).get('scrollPercentage', 0)
            if scroll_percentage > total_scroll_depth:
                total_scroll_depth = scroll_percentage
        elif event_type == 'scroll_depth':
            milestone = event.get('eventData', {}).get('milestone', 0)
            if milestone not in scroll_milestones:
                scroll_milestones.append(milestone)
    
    # Sort milestones for easier analysis
    scroll_milestones.sort()
    
    # Extract session/visitor data
    session_id = batch_data.get('sessionId', 'unknown')
    visitor_id = batch_data.get('visitorId', 'unknown')
    site_id = batch_data.get('siteId', 'unknown')
    
    # Calculate engagement metrics
    activity_duration = batch_metadata.get('activityDuration', 0)
    engagement_intensity = len(events) / max(activity_duration / 1000, 1) if activity_duration > 0 else 0
    
    # Generate v2 composite key fields
    domain_session = f"{site_id}#{session_id}"
    timestamp_ms = int(datetime.now(timezone.utc).timestamp() * 1000)
    
    # Prepare DynamoDB item
    dynamodb_item = {
        # v2 composite key fields for partitioning
        'domain_session': domain_session,
        'timestamp': timestamp_ms,
        
        # Original fields (preserve compatibility)
        'eventId': batch_id,
        'eventType': 'batch',
        'sessionId': session_id,
        'visitorId': visitor_id,
        'siteId': site_id,
        'batchId': batch_id,
        
        # Batch metadata
        'eventCount': len(events),
        'activityDuration': activity_duration,
        'sentOnExit': batch_metadata.get('sentOnExit', False),
        'batchStartTime': batch_metadata.get('batchStartTime', ''),
        'batchEndTime': batch_metadata.get('batchEndTime', ''),
        
        # Event type breakdown
        'eventTypes': event_types,
        'clickCount': click_count,
        'scrollEvents': scroll_events,
        'scrollMilestones': scroll_milestones,
        'maxScrollDepth': total_scroll_depth,
        
        # Engagement metrics
        'engagementIntensity': round(engagement_intensity, 2),
        
        # Request metadata
        'ip': client_ip,
        'userAgent': user_agent,
        
        # v2 enhancements
        'processed_at': current_time,
        'lambda_request_id': context.aws_request_id,
        'environment': ENVIRONMENT,
        'ttl': int((datetime.now(timezone.utc).timestamp() + (180 * 24 * 60 * 60))),  # 180 days TTL
        
        # Full batch data for detailed analysis
        'data': batch_data
    }
    
    # Remove empty fields to save space
    dynamodb_item = {k: v for k, v in dynamodb_item.items() if v not in ['', [], {}]}
    
    # Convert floats to Decimal for DynamoDB
    dynamodb_item = convert_floats_to_decimal(dynamodb_item)
    
    # Store in DynamoDB
    table.put_item(Item=dynamodb_item)
    
    print(f"Stored batch record: {batch_id} - {click_count} clicks, {scroll_events} scrolls, milestones: {scroll_milestones}")

def store_single_event(event_data, client_ip, user_agent, current_time, context):
    """Store a single event in DynamoDB (pageview, page_exit, form_submit only)"""
    
    event_id = str(uuid.uuid4())
    event_timestamp = event_data.get('timestamp', current_time)
    
    # Extract key fields for easier querying
    session_id = event_data.get('sessionId', 'unknown')
    visitor_id = event_data.get('visitorId', 'unknown')
    event_type = event_data.get('eventType', 'unknown')
    site_id = event_data.get('siteId', 'unknown')
    url = event_data.get('url', '')
    path = event_data.get('path', '')
    
    # Validate event type - only certain events should be stored individually
    allowed_individual_events = ['pageview', 'page_exit', 'form_submit']
    if event_type not in allowed_individual_events:
        print(f"WARNING: Individual event of type '{event_type}' should be in batch, not stored individually")
    
    # Extract attribution data if present (pageview events)
    attribution = event_data.get('attribution', {})
    first_touch = attribution.get('firstTouch', {})
    current_touch = attribution.get('currentTouch', {})
    
    # Extract UTM parameters
    utm_source = ''
    utm_medium = ''
    utm_campaign = ''
    
    if first_touch.get('utmParams'):
        utm_source = first_touch['utmParams'].get('utm_source', '')
        utm_medium = first_touch['utmParams'].get('utm_medium', '')
        utm_campaign = first_touch['utmParams'].get('utm_campaign', '')
    elif current_touch.get('utmParams'):
        utm_source = current_touch['utmParams'].get('utm_source', '')
        utm_medium = current_touch['utmParams'].get('utm_medium', '')
        utm_campaign = current_touch['utmParams'].get('utm_campaign', '')
    
    # Extract traffic source
    traffic_source = first_touch.get('source', '') or current_touch.get('source', '')
    traffic_medium = first_touch.get('medium', '') or current_touch.get('medium', '')
    traffic_category = first_touch.get('category', '') or current_touch.get('category', '')
    
    # Extract browser data if present (pageview events)
    browser_data = event_data.get('browser', {})
    device_type = get_device_type(browser_data.get('userAgent', user_agent))
    
    # Extract scroll data if present
    scroll_data = event_data.get('scroll', {})
    max_scroll_percentage = scroll_data.get('maxScrollPercentage', 0)
    
    # Extract page data if present
    page_data = event_data.get('page', {})
    page_title = page_data.get('title', '')
    referrer = page_data.get('referrer', '')
    
    # Extract event-specific data
    event_specific_data = event_data.get('eventData', {})
    time_spent = event_specific_data.get('timeSpent', 0) if event_type == 'page_exit' else 0
    
    # Generate v2 composite key fields
    domain_session = f"{site_id}#{session_id}"
    timestamp_ms = int(datetime.fromisoformat(event_timestamp.replace('Z', '+00:00')).timestamp() * 1000) if isinstance(event_timestamp, str) else int(time.time() * 1000)
    
    # Prepare item for DynamoDB
    dynamodb_item = {
        # v2 composite key fields for partitioning
        'domain_session': domain_session,
        'timestamp': timestamp_ms,
        
        # Original fields (preserve compatibility)
        'eventId': event_id,
        'sessionId': session_id,
        'visitorId': visitor_id,
        'eventType': event_type,
        'siteId': site_id,
        'url': url,
        'path': path,
        'pageTitle': page_title,
        'referrer': referrer,
        'ip': client_ip,
        'userAgent': user_agent,
        'deviceType': device_type,
        
        # Attribution fields for easy querying
        'utmSource': utm_source,
        'utmMedium': utm_medium,
        'utmCampaign': utm_campaign,
        'trafficSource': traffic_source,
        'trafficMedium': traffic_medium,
        'trafficCategory': traffic_category,
        
        # Engagement fields
        'maxScrollPercentage': max_scroll_percentage,
        'timeSpent': time_spent,
        
        # v2 enhancements
        'processed_at': current_time,
        'lambda_request_id': context.aws_request_id,
        'environment': ENVIRONMENT,
        'ttl': int((datetime.now(timezone.utc).timestamp() + (180 * 24 * 60 * 60))),  # 180 days TTL
        
        # Store full event data as well
        'data': event_data
    }
    
    # Remove empty strings to save space
    dynamodb_item = {k: v for k, v in dynamodb_item.items() if v not in ['', 0]}
    
    # Convert floats to Decimal for DynamoDB
    dynamodb_item = convert_floats_to_decimal(dynamodb_item)
    
    # Store in DynamoDB
    table.put_item(Item=dynamodb_item)
    
    print(f"Stored individual event: {event_type} for session {session_id}")

def archive_to_s3(event_data, event_type):
    """Archive event to S3 for long-term storage"""
    try:
        # Create S3 key with date partitioning
        now = datetime.now(timezone.utc)
        s3_key = f"raw-events/year={now.year}/month={now.month:02d}/day={now.day:02d}/type={event_type}/{event_data['eventId']}.json"
        
        # Convert Decimal back to float for JSON serialization
        def decimal_default(obj):
            if isinstance(obj, Decimal):
                return float(obj)
            raise TypeError
        
        # Upload to S3
        s3_client.put_object(
            Bucket=S3_ARCHIVE_BUCKET,
            Key=s3_key,
            Body=json.dumps(event_data, default=decimal_default),
            ContentType='application/json'
        )
        
        print(f"Event archived to S3: {s3_key}")
        return True
        
    except Exception as e:
        print(f"Failed to archive event to S3: {str(e)}")
        return False

def get_device_type(user_agent):
    """Simple device type detection"""
    if not user_agent:
        return 'unknown'
    
    user_agent_lower = user_agent.lower()
    
    if any(mobile in user_agent_lower for mobile in ['mobile', 'android', 'iphone', 'ipod', 'blackberry', 'windows phone']):
        return 'mobile'
    elif any(tablet in user_agent_lower for tablet in ['ipad', 'tablet', 'playbook', 'silk']):
        return 'tablet'
    else:
        return 'desktop'