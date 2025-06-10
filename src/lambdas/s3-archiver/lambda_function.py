import json
import boto3
from datetime import datetime, timezone, timedelta
from decimal import Decimal
import os

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
s3_client = boto3.client('s3')

# Environment variables
RAW_EVENTS_TABLE = os.environ.get('RAW_EVENTS_TABLE')
S3_ARCHIVE_BUCKET = os.environ.get('S3_ARCHIVE_BUCKET')
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')

def lambda_handler(event, context):
    """
    Hourly batch export of events to S3
    Processes events from the last hour and creates site-specific log files
    """
    print(f"Starting hourly S3 archival for environment: {ENVIRONMENT}")
    
    # Calculate time range for the previous hour
    now = datetime.now(timezone.utc)
    end_time = now.replace(minute=0, second=0, microsecond=0)  # Top of current hour
    start_time = end_time - timedelta(hours=1)  # Previous hour
    
    start_timestamp = int(start_time.timestamp() * 1000)
    end_timestamp = int(end_time.timestamp() * 1000)
    
    print(f"Processing events from {start_time.isoformat()} to {end_time.isoformat()}")
    print(f"Timestamp range: {start_timestamp} to {end_timestamp}")
    
    try:
        # Get all events from the last hour
        events_by_site = get_events_by_site(start_timestamp, end_timestamp)
        
        if not events_by_site:
            print("No events found for the last hour")
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': 'No events to archive',
                    'time_range': f"{start_time.isoformat()} to {end_time.isoformat()}"
                })
            }
        
        # Archive events by site
        archived_files = []
        for site_id, events in events_by_site.items():
            file_key = archive_site_events(site_id, events, start_time)
            if file_key:
                archived_files.append(file_key)
        
        print(f"Successfully archived {len(archived_files)} log files")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Events archived successfully',
                'files_created': len(archived_files),
                'sites_processed': len(events_by_site),
                'time_range': f"{start_time.isoformat()} to {end_time.isoformat()}",
                'archived_files': archived_files
            })
        }
        
    except Exception as e:
        print(f"Error during archival: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Archival failed',
                'message': str(e)
            })
        }

def get_events_by_site(start_timestamp, end_timestamp):
    """
    Scan DynamoDB for events in the time range and group by site
    """
    table = dynamodb.Table(RAW_EVENTS_TABLE)
    events_by_site = {}
    
    print(f"Scanning DynamoDB table: {RAW_EVENTS_TABLE}")
    
    try:
        # Use expression attribute names to handle reserved keyword 'timestamp'
        response = table.scan(
            FilterExpression="#ts BETWEEN :start_ts AND :end_ts",
            ExpressionAttributeNames={
                '#ts': 'timestamp'
            },
            ExpressionAttributeValues={
                ':start_ts': start_timestamp,
                ':end_ts': end_timestamp
            }
        )
        
        events = response.get('Items', [])
        print(f"Found {len(events)} events in time range")
        
        # Handle pagination
        while 'LastEvaluatedKey' in response:
            response = table.scan(
                FilterExpression="#ts BETWEEN :start_ts AND :end_ts",
                ExpressionAttributeNames={
                    '#ts': 'timestamp'
                },
                ExpressionAttributeValues={
                    ':start_ts': start_timestamp,
                    ':end_ts': end_timestamp
                },
                ExclusiveStartKey=response['LastEvaluatedKey']
            )
            events.extend(response.get('Items', []))
            print(f"Total events found: {len(events)}")
        
        # Group events by site
        for event in events:
            site_id = event.get('siteId', 'unknown')
            if site_id not in events_by_site:
                events_by_site[site_id] = []
            events_by_site[site_id].append(event)
        
        print(f"Events grouped by site: {dict((k, len(v)) for k, v in events_by_site.items())}")
        
        return events_by_site
        
    except Exception as e:
        print(f"Error scanning DynamoDB: {str(e)}")
        raise

def archive_site_events(site_id, events, hour_start):
    """
    Create an S3 log file for a site's events from a specific hour
    """
    if not events:
        return None
    
    # Clean site_id for S3 path (replace dots with dashes)
    clean_site_id = site_id.replace('.', '-').replace('/', '-').lower()
    
    # Create S3 key with site-based partitioning
    s3_key = (
        f"site-logs/domain={clean_site_id}/"
        f"year={hour_start.year}/month={hour_start.month:02d}/"
        f"day={hour_start.day:02d}/hour={hour_start.hour:02d}/"
        f"events-{hour_start.strftime('%Y-%m-%d-%H')}.jsonl"
    )
    
    print(f"Creating log file for site {site_id}: {s3_key}")
    
    try:
        # Convert events to JSONL format (one JSON object per line)
        jsonl_lines = []
        for event in events:
            # Convert Decimal types to float for JSON serialization
            event_json = json.dumps(event, default=decimal_default, separators=(',', ':'))
            jsonl_lines.append(event_json)
        
        jsonl_content = '\n'.join(jsonl_lines) + '\n'
        
        # Add metadata header
        metadata = {
            'archive_info': {
                'site_id': site_id,
                'hour_start': hour_start.isoformat(),
                'event_count': len(events),
                'archived_at': datetime.now(timezone.utc).isoformat(),
                'environment': ENVIRONMENT
            }
        }
        
        final_content = json.dumps(metadata, default=decimal_default) + '\n' + jsonl_content
        
        # Upload to S3
        s3_client.put_object(
            Bucket=S3_ARCHIVE_BUCKET,
            Key=s3_key,
            Body=final_content.encode('utf-8'),
            ContentType='application/jsonl',
            Metadata={
                'site-id': site_id,
                'event-count': str(len(events)),
                'hour-start': hour_start.isoformat(),
                'environment': ENVIRONMENT
            }
        )
        
        print(f"Successfully archived {len(events)} events for site {site_id}")
        return s3_key
        
    except Exception as e:
        print(f"Error archiving events for site {site_id}: {str(e)}")
        return None

def decimal_default(obj):
    """Convert Decimal types to float for JSON serialization"""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError(f"Object {obj} is not JSON serializable")