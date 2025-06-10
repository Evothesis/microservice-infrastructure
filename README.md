# Evothesis Analytics Platform v2

A privacy-first, cookieless web analytics platform built on AWS serverless infrastructure. This system collects rich behavioral data through a JavaScript pixel, processes events through Lambda functions, and provides analytics through CSV exports and dashboards.

## 🏗️ Architecture Overview

```
JavaScript Pixel → API Gateway → Lambda → DynamoDB → Hourly S3 Archive → Export/Dashboard
```

### Core Components

- **Event Collection**: API Gateway + Lambda for high-throughput event ingestion
- **Real-time Storage**: DynamoDB for immediate event processing and queries
- **Batch Archival**: Hourly S3 exports organized by site domain
- **Processing Pipeline**: Lambda functions for enrichment and identity resolution
- **Export System**: Automated CSV generation to client-owned S3 buckets
- **Analytics Dashboard**: Retool integration for real-time analytics

### Key Features

- ✅ **Privacy-First**: No cookies, GDPR/CCPA compliant
- ✅ **Cookieless Tracking**: Device fingerprinting and behavioral analysis
- ✅ **Serverless**: Auto-scaling, pay-per-use AWS infrastructure
- ✅ **Multi-Tenant**: Domain-based client isolation
- ✅ **HIPAA-Ready**: Encryption at rest and in transit
- ✅ **Cost-Optimized**: Optimized for <$10/month operational costs
- ✅ **Efficient Archival**: Hourly batched S3 writes instead of per-event writes

## 📋 Prerequisites

### Required Tools
- **AWS CLI** configured with admin permissions
- **Bash** (macOS/Linux terminal)
- **curl** for testing
- **Git** for version control

### AWS Account Setup
```bash
# Configure AWS CLI with your credentials
aws configure

# Verify access
aws sts get-caller-identity
```

## 🚀 Quick Start

### 1. Clone and Setup
```bash
git clone <your-repo-url>
cd evothesis-infrastructure

# Make scripts executable
chmod +x deploy/scripts/*.sh
```

### 2. Deploy Development Environment
```bash
# Deploy complete infrastructure
./deploy/scripts/deploy.sh dev
```

### 3. Test Your Deployment
```bash
# Test the API endpoint (use URL from deployment output)
curl -X POST https://[your-api-id].execute-api.us-west-1.amazonaws.com/dev/collect \
  -H "Content-Type: application/json" \
  -d '{"eventType":"pageview","sessionId":"test-123","visitorId":"test-456","siteId":"test-site"}'
```

**Expected Response:**
```json
{"status": "success", "message": "Tracking data received"}
```

## 📁 Project Structure

```
evothesis-infrastructure/
├── src/
│   ├── lambdas/                 # Lambda function source code
│   │   ├── event-collector/     # Main event ingestion
│   │   ├── enrichment/          # Identity resolution & enrichment
│   │   ├── export/              # CSV export to client buckets
│   │   └── s3-archiver/         # Hourly S3 batch archival
│   └── pixel/                   # Client-side tracking code
│       ├── evothesis-pixel.html # GTM-compatible HTML snippet
│       ├── config/              # Pixel configuration
│       ├── utils/               # Utility functions
│       └── examples/            # Integration examples
├── deploy/
│   ├── configs/                 # Environment configurations
│   │   ├── common.env          # Shared settings
│   │   ├── dev.env             # Development environment
│   │   └── prod.env            # Production environment
│   └── scripts/                 # Deployment automation
│       ├── deploy.sh           # Master deployment script
│       ├── setup-iam.sh        # IAM roles and policies
│       ├── setup-dynamodb.sh   # Database tables
│       ├── setup-s3.sh         # Storage buckets
│       ├── setup-lambda.sh     # Function deployment
│       ├── setup-api-gateway.sh # API endpoints
│       └── setup-scheduler.sh  # CloudWatch Events
├── tests/                       # Testing scripts
│   └── test-analytics.sh       # Integration tests
├── backups/                     # Infrastructure backups (git-ignored)
└── README.md
```

## 🔧 Configuration

### Environment Settings

**Development (`deploy/configs/dev.env`):**
- Event retention: 7 days
- Lambda memory: 128 MB
- Pay-per-request billing
- CORS: Allow all origins

**Production (`deploy/configs/prod.env`):**
- Event retention: 180 days
- Lambda memory: 256 MB
- Pay-per-request billing
- CORS: Restricted to your domains

### Cost Optimization

All resources configured for minimal cost:
- **DynamoDB**: Pay-per-request (no provisioned capacity)
- **Lambda**: ARM64 architecture (20% cheaper)
- **S3**: Lifecycle policies + hourly batching (99.3% cost reduction)
- **API Gateway**: Pay-per-request pricing

**Expected Monthly Costs:**
- Development: ~$2/month
- Production: ~$5-10/month (depends on traffic)

## 📊 Event Data Structures

### Page View Event
```json
{
  "eventType": "pageview",
  "timestamp": "2025-06-09T23:11:20Z",
  "sessionId": "sess_abc123def456",
  "visitorId": "vis_xyz789uvw012",
  "siteId": "example-com",
  "url": "https://example.com/products/widget",
  "path": "/products/widget",
  "page": {
    "title": "Amazing Widget - Product Page",
    "referrer": "https://google.com",
    "queryParams": "?utm_source=google&utm_medium=cpc",
    "hash": "#reviews"
  },
  "attribution": {
    "firstTouch": {
      "source": "google",
      "medium": "cpc",
      "campaign": "summer-sale",
      "category": "paid_search",
      "utmParams": {
        "utm_source": "google",
        "utm_medium": "cpc",
        "utm_campaign": "summer-sale",
        "utm_content": "widget-ad",
        "utm_term": "best-widget"
      }
    },
    "currentTouch": {
      "source": "direct",
      "medium": "none",
      "category": "direct"
    },
    "touchCount": 3
  },
  "browser": {
    "userAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)...",
    "language": "en-US",
    "screenWidth": 1920,
    "screenHeight": 1080,
    "viewportWidth": 1440,
    "viewportHeight": 900,
    "devicePixelRatio": 2,
    "timezone": "America/Los_Angeles"
  },
  "scroll": {
    "maxScrollPercentage": 0,
    "milestonesReached": []
  }
}
```

### Batch Event (Activity-Based)
```json
{
  "eventType": "batch",
  "timestamp": "2025-06-09T23:15:30Z",
  "sessionId": "sess_abc123def456",
  "visitorId": "vis_xyz789uvw012",
  "siteId": "example-com",
  "batchMetadata": {
    "eventCount": 5,
    "batchStartTime": "2025-06-09T23:14:15Z",
    "batchEndTime": "2025-06-09T23:15:30Z",
    "activityDuration": 75000,
    "sentOnExit": false
  },
  "events": [
    {
      "eventType": "click",
      "timestamp": "2025-06-09T23:14:20Z",
      "eventData": {
        "tagName": "button",
        "classes": "btn btn-primary add-to-cart",
        "id": "add-cart-btn",
        "text": "Add to Cart",
        "href": "",
        "position": {"x": 456, "y": 234}
      }
    },
    {
      "eventType": "scroll",
      "timestamp": "2025-06-09T23:14:45Z",
      "eventData": {
        "scrollPercentage": 65,
        "scrollTop": 1200,
        "documentHeight": 2400,
        "windowHeight": 900
      }
    },
    {
      "eventType": "scroll_depth",
      "timestamp": "2025-06-09T23:15:10Z",
      "eventData": {
        "milestone": 75,
        "timeToMilestone": 55000,
        "scrollPercentage": 76,
        "scrollTop": 1450,
        "documentHeight": 2400,
        "windowHeight": 900
      }
    }
  ]
}
```

### Page Exit Event
```json
{
  "eventType": "page_exit",
  "timestamp": "2025-06-09T23:18:45Z",
  "sessionId": "sess_abc123def456",
  "visitorId": "vis_xyz789uvw012",
  "siteId": "example-com",
  "url": "https://example.com/products/widget",
  "path": "/products/widget",
  "eventData": {
    "timeSpent": 195000
  },
  "scroll": {
    "maxScrollPercentage": 85,
    "milestonesReached": [25, 50, 75]
  }
}
```

### Form Submission Event
```json
{
  "eventType": "form_submit",
  "timestamp": "2025-06-09T23:16:20Z",
  "sessionId": "sess_abc123def456",
  "visitorId": "vis_xyz789uvw012",
  "siteId": "example-com",
  "url": "https://example.com/contact",
  "path": "/contact",
  "eventData": {
    "formId": "contact-form",
    "formAction": "https://example.com/submit-contact",
    "formMethod": "post",
    "formData": {
      "name": "John Doe",
      "email": "john@example.com",
      "message": "I'm interested in your product",
      "newsletter": "yes",
      "credit_card": "[REDACTED]"
    }
  }
}
```

## 🛠️ Deployment Commands

### Individual Component Deployment
```bash
# Deploy specific components
./deploy/scripts/setup-iam.sh dev
./deploy/scripts/setup-dynamodb.sh dev
./deploy/scripts/setup-s3.sh dev
./deploy/scripts/setup-lambda.sh dev
./deploy/scripts/setup-api-gateway.sh dev
./deploy/scripts/setup-scheduler.sh dev
```

### Full Environment Deployment
```bash
# Development environment
./deploy/scripts/deploy.sh dev

# Production environment
./deploy/scripts/deploy.sh prod
```

### S3 Archival Management
```bash
# Disable hourly archival (temporarily)
aws events disable-rule --name evothesis-hourly-archive-dev

# Re-enable hourly archival
aws events enable-rule --name evothesis-hourly-archive-dev

# Check archival status
aws events describe-rule --name evothesis-hourly-archive-dev --query 'State'

# Manually trigger archival
aws lambda invoke \
  --function-name evothesis-v2-s3-archiver-dev \
  --payload '{}' \
  response.json && cat response.json
```

## 📊 Infrastructure Resources

### Created AWS Resources

**DynamoDB Tables:**
- `evothesis-v2-raw-events-{env}` - Event storage with TTL and composite keys
- `evothesis-v2-client-config-{env}` - Client configuration

**S3 Buckets:**
- `evothesis-analytics-v2-archive-{env}` - Hourly batched event logs by site
- `evothesis-analytics-v2-export-{env}` - Client CSV exports
- `evothesis-analytics-v2-internal-{env}` - Internal analytics data

**Lambda Functions:**
- `evothesis-v2-event-collector-{env}` - Real-time event ingestion
- `evothesis-v2-enrichment-{env}` - Data enrichment (placeholder)
- `evothesis-v2-export-{env}` - Export automation (placeholder)
- `evothesis-v2-s3-archiver-{env}` - Hourly S3 batch archival

**API Gateway:**
- `evothesis-analytics-api-v2-{env}` - RESTful API endpoint

**CloudWatch Events:**
- `evothesis-hourly-archive-{env}` - Hourly archival scheduler

**IAM Roles:**
- `evothesis-lambda-role-{env}` - Lambda execution role with required permissions

### S3 Archive Structure
```
s3://evothesis-analytics-v2-archive-dev/
└── site-logs/
    ├── domain=example-com/
    │   └── year=2025/month=06/day=09/hour=14/
    │       └── events-2025-06-09-14.jsonl
    └── domain=another-site-com/
        └── year=2025/month=06/day=09/hour=15/
            └── events-2025-06-09-15.jsonl
```

## 🔍 Monitoring & Debugging

### CloudWatch Logs
```bash
# View Lambda function logs
aws logs tail /aws/lambda/evothesis-v2-event-collector-dev --follow

# Check S3 archiver logs
aws logs tail /aws/lambda/evothesis-v2-s3-archiver-dev --follow

# Check for errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/evothesis-v2-event-collector-dev \
  --filter-pattern "ERROR"
```

### Testing Individual Functions
```bash
# Test event collector directly
aws lambda invoke \
  --function-name evothesis-v2-event-collector-dev \
  --payload '{"httpMethod":"POST","body":"{\"eventType\":\"pageview\",\"sessionId\":\"test\",\"visitorId\":\"test\",\"siteId\":\"test\"}"}' \
  response.json && cat response.json

# Test S3 archiver
aws lambda invoke \
  --function-name evothesis-v2-s3-archiver-dev \
  --payload '{}' \
  response.json && cat response.json
```

### Resource Verification
```bash
# List created resources
aws dynamodb list-tables --query 'TableNames[?contains(@, `evothesis`)]'
aws lambda list-functions --query 'Functions[?contains(FunctionName, `evothesis`)].FunctionName'
aws s3 ls | grep evothesis
aws apigateway get-rest-apis --query 'items[?contains(name, `evothesis`)].{Name:name, ID:id}'

# Check DynamoDB data
aws dynamodb scan --table-name evothesis-v2-raw-events-dev --limit 5

# Check S3 archived files
aws s3 ls s3://evothesis-analytics-v2-archive-dev/site-logs/ --recursive

# Check scheduled events
aws events list-rules --query 'Rules[?contains(Name, `evothesis`)]'
```

## 🧪 Testing

### Run Integration Tests
```bash
./tests/test-analytics.sh
```

### Manual API Testing
```bash
# Test page view
curl -X POST https://[api-id].execute-api.us-west-1.amazonaws.com/dev/collect \
  -H "Content-Type: application/json" \
  -d '{"eventType":"pageview","sessionId":"test-123","visitorId":"test-456","siteId":"test-site"}'

# Test batch events
curl -X POST https://[api-id].execute-api.us-west-1.amazonaws.com/dev/collect \
  -H "Content-Type: application/json" \
  -d '{"eventType":"batch","sessionId":"test-123","visitorId":"test-456","siteId":"test-site","events":[{"eventType":"click","eventData":{"tagName":"button"}}]}'

# Test CORS preflight
curl -X OPTIONS https://[api-id].execute-api.us-west-1.amazonaws.com/dev/collect \
  -H "Origin: https://test-site.com" \
  -H "Access-Control-Request-Method: POST"
```

## 🚨 Troubleshooting

### Common Issues

**❌ "AWS CLI not configured"**
```bash
aws configure
# Enter your AWS Access Key, Secret Key, Region (us-west-1), and output format (json)
```

**❌ "Float types are not supported. Use Decimal types instead"**
- Fixed in v2 - automatic Decimal conversion for DynamoDB compatibility

**❌ "Invalid FilterExpression: Attribute name is a reserved keyword; reserved keyword: timestamp"**
- Fixed in S3 archiver - uses expression attribute names

**❌ "Table already exists" errors**
- Scripts are idempotent - safe to re-run
- Existing resources will be skipped, not duplicated

### Debug Mode
```bash
# Run scripts with verbose output
bash -x ./deploy/scripts/deploy.sh dev

# Check CloudWatch Events status
aws events describe-rule --name evothesis-hourly-archive-dev

# Verify Lambda permissions
aws lambda get-policy --function-name evothesis-v2-event-collector-dev
```

## 🔐 Security & Compliance

### Data Protection
- All S3 buckets private by default with lifecycle policies
- DynamoDB encryption at rest enabled with TTL
- Lambda functions run with least-privilege IAM roles
- API Gateway with CORS properly configured
- Automatic float-to-Decimal conversion for data integrity

### HIPAA Compliance
- AWS Business Associate Agreement (BAA) ready
- Encryption in transit and at rest
- Audit logging through CloudTrail
- Data retention policies configurable via TTL

## 🌐 API Reference

### Event Collection Endpoint

**POST** `https://[api-id].execute-api.us-west-1.amazonaws.com/{stage}/collect`

**Supported Event Types:**
- `pageview` - Page view with attribution and browser data
- `batch` - Collection of user interaction events (clicks, scrolls)
- `page_exit` - Page exit with time spent and engagement metrics
- `form_submit` - Form submission with sanitized data

**Response:**
```json
{
  "status": "success",
  "message": "Tracking data received"
}
```

**CORS Support:**
- `OPTIONS` preflight requests supported
- Cross-origin requests allowed with proper headers

## 🚀 Next Steps

### Phase 1: Enhanced Data Processing
- [ ] Implement enrichment Lambda for identity resolution
- [ ] Add device fingerprinting and session stitching
- [ ] Enhance attribution modeling

### Phase 2: Export & Analytics
- [ ] Automated CSV export scheduling from S3 archives
- [ ] Retool dashboard integration with S3 data source
- [ ] Client data delivery automation

### Phase 3: Production Readiness
- [ ] CloudWatch monitoring and alerting setup
- [ ] Performance optimization and capacity planning
- [ ] Load testing with realistic traffic patterns

### Phase 4: Advanced Features
- [ ] Real-time event streaming for immediate insights
- [ ] Advanced analytics and conversion funnel analysis
- [ ] Custom event schema validation

## 📞 Support

### Getting Help
1. Check CloudWatch logs for error details
2. Verify AWS permissions and configuration
3. Test individual components in isolation
4. Review AWS service quotas and limits

### Useful Commands
```bash
# Quick health check
curl -X POST https://[your-api-id].execute-api.us-west-1.amazonaws.com/dev/collect \
  -H "Content-Type: application/json" \
  -d '{"eventType":"pageview","sessionId":"health-check","visitorId":"health-check","siteId":"health-check"}'

# View recent event collector logs
aws logs tail /aws/lambda/evothesis-v2-event-collector-dev --since 1h

# Check S3 archival status
aws events describe-rule --name evothesis-hourly-archive-dev

# Monitor costs
aws ce get-cost-and-usage \
  --time-period Start=2025-06-01,End=2025-06-30 \
  --granularity MONTHLY \
  --metrics BlendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

---

## 📄 License

[Your License Here]

## 🤝 Contributing

[Your Contributing Guidelines Here]