# Evothesis Analytics Platform v2

A privacy-first, cookieless web analytics platform built on AWS serverless infrastructure with real-time identity resolution. This system collects rich behavioral data through a JavaScript pixel, processes events through Lambda functions, performs cookieless identity resolution, and provides analytics through CSV exports and dashboards.

## 🏗️ Architecture Overview

```
JavaScript Pixel → API Gateway → Lambda → DynamoDB → Hourly S3 Archive → Export/Dashboard
                                             ↓
                              DynamoDB Streams → Enrichment Lambda
                                             ↓
                              Identity Resolution → Enriched Events DynamoDB
                                             ↓
                              Hourly S3 Archiver → Enriched S3 Archive
```

### Core Components

- **Event Collection**: API Gateway + Lambda for high-throughput event ingestion
- **Real-time Storage**: DynamoDB for immediate event processing and queries
- **Identity Resolution**: Cookieless visitor identification via device fingerprinting
- **Enrichment Pipeline**: Lambda functions for identity resolution and data normalization
- **Batch Archival**: Hourly S3 exports organized by site domain (raw + enriched)
- **Export System**: Automated CSV generation to client-owned S3 buckets
- **Analytics Dashboard**: Retool integration for real-time analytics

### Key Features

- ✅ **Privacy-First**: No cookies, GDPR/CCPA compliant
- ✅ **Cookieless Identity Resolution**: Device fingerprinting and behavioral analysis
- ✅ **Cross-Device Tracking**: Household-level visitor identification
- ✅ **Real-time Processing**: DynamoDB Streams trigger immediate enrichment
- ✅ **Serverless**: Auto-scaling, pay-per-use AWS infrastructure
- ✅ **Multi-Tenant**: Domain-based client isolation
- ✅ **HIPAA-Ready**: Encryption at rest and in transit
- ✅ **Cost-Optimized**: Optimized for <$10/month operational costs
- ✅ **Efficient Batching**: Hourly S3 writes instead of per-event writes

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
# Deploy complete infrastructure including identity resolution
./deploy/scripts/deploy.sh dev
```

### 3. Test Your Deployment
```bash
# Test the complete identity resolution pipeline
./tests/test-identity-resolution.sh dev
```

**Expected Response:**
```
🎉 ALL TESTS PASSED! Identity resolution pipeline is working correctly.
✅ Raw event collection: WORKING
✅ Identity resolution: WORKING  
✅ Session tracking: WORKING
✅ Enriched events storage: WORKING
```

## 📁 Project Structure

```
evothesis-infrastructure/
├── src/
│   ├── lambdas/                     # Lambda function source code
│   │   ├── event-collector/         # Main event ingestion
│   │   ├── enrichment/              # Identity resolution & enrichment
│   │   ├── export/                  # CSV export to client buckets
│   │   └── s3-archiver/             # Hourly S3 batch archival (raw events)
│   └── pixel/                       # Client-side tracking code
│       ├── evothesis-pixel.html     # GTM-compatible HTML snippet
│       ├── config/                  # Pixel configuration
│       ├── utils/                   # Utility functions
│       └── examples/                # Integration examples
├── deploy/
│   ├── configs/                     # Environment configurations
│   │   ├── common.env              # Shared settings
│   │   ├── dev.env                 # Development environment
│   │   └── prod.env                # Production environment
│   └── scripts/                     # Deployment automation
│       ├── deploy.sh               # Master deployment script
│       ├── setup-iam.sh            # IAM roles and policies
│       ├── setup-dynamodb.sh       # Database tables (raw events)
│       ├── setup-identity-tables.sh # Identity resolution tables
│       ├── setup-s3.sh             # Storage buckets
│       ├── setup-lambda.sh         # Function deployment
│       ├── setup-enrichment-lambda.sh # Identity resolution Lambda
│       ├── setup-enriched-archiver.sh # Enriched events infrastructure
│       ├── setup-api-gateway.sh    # API endpoints
│       └── setup-scheduler.sh      # CloudWatch Events
├── tests/                           # Testing scripts
│   └── test-identity-resolution.sh # Complete pipeline integration tests
├── backups/                         # Infrastructure backups (git-ignored)
└── README.md
```

## 🔧 Configuration

### Environment Settings

**Development (`deploy/configs/dev.env`):**
- Event retention: 7 days raw events, 7 days enriched events
- Lambda memory: 128MB (collector), 512MB (enrichment)
- Pay-per-request billing
- CORS: Allow all origins

**Production (`deploy/configs/prod.env`):**
- Event retention: 180 days
- Lambda memory: 256MB (collector), 512MB (enrichment)
- Pay-per-request billing
- CORS: Restricted to your domains

### Cost Optimization

All resources configured for minimal cost:
- **DynamoDB**: Pay-per-request (no provisioned capacity)
- **Lambda**: ARM64 architecture (20% cheaper)
- **S3**: Lifecycle policies + hourly batching (99.3% cost reduction)
- **API Gateway**: Pay-per-request pricing

**Expected Monthly Costs:**
- Development: ~$2-5/month
- Production: ~$10-25/month (depends on traffic)

## 🧠 Identity Resolution System

### Cookieless Visitor Identification
The platform uses advanced device fingerprinting and behavioral analysis to identify visitors without cookies:

#### Device Fingerprinting
```json
{
  "device_fingerprint": "fp_abc123def456",
  "components": {
    "screen_resolution": "1920x1080",
    "viewport_size": "1440x900",
    "user_agent_hash": "xyz789",
    "timezone": "America/Los_Angeles",
    "language": "en-US",
    "device_pixel_ratio": 2,
    "platform": "macos_desktop"
  }
}
```

#### Household Grouping
- **IP Subnet Analysis**: Groups devices by /24 IPv4 subnets
- **Cross-Device Recognition**: Links devices within same household
- **Privacy Compliant**: No PII stored, only network-level grouping

#### Identity Resolution
```json
{
  "identity": {
    "identity_id": "id_xyz789uvw012",
    "household_id": "hh_mno345pqr678",
    "device_fingerprint": "fp_abc123def456",
    "session_sequence": 3,
    "is_new_visitor": false,
    "total_sessions": 5,
    "confidence_score": 0.87
  }
}
```

### Enriched Data Schema
All events are enriched with normalized analytics-ready fields:

```json
{
  "normalized": {
    "device_category": "desktop",
    "browser_family": "chrome",
    "os_family": "macos", 
    "page_category": "product",
    "traffic_source_category": "paid",
    "is_mobile": false
  }
}
```

## 📊 Event Data Structures

### Page View Event
```json
{
  "eventType": "pageview",
  "timestamp": "2025-06-11T17:34:14.000Z",
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
        "utm_campaign": "summer-sale"
      }
    }
  },
  "browser": {
    "userAgent": "Mozilla/5.0...",
    "language": "en-US",
    "screenWidth": 1920,
    "screenHeight": 1080,
    "timezone": "America/Los_Angeles"
  }
}
```

### Enriched Event (After Identity Resolution)
```json
{
  "eventType": "pageview",
  "timestamp": "2025-06-11T17:34:14.000Z",
  "sessionId": "sess_abc123def456", 
  "visitorId": "vis_xyz789uvw012",
  "siteId": "example-com",
  "identity": {
    "identity_id": "id_xyz789uvw012",
    "household_id": "hh_mno345pqr678",
    "device_fingerprint": "fp_abc123def456",
    "session_sequence": 3,
    "is_new_visitor": false,
    "total_sessions": 5,
    "confidence_score": 0.87
  },
  "normalized": {
    "device_category": "desktop",
    "browser_family": "chrome",
    "os_family": "macos",
    "page_category": "product",
    "traffic_source_category": "paid"
  },
  "enrichment_metadata": {
    "processed_at": "2025-06-11T17:34:15.123Z",
    "enrichment_version": "1.0"
  }
}
```

## 🛠️ Deployment Commands

### Full Infrastructure Deployment
```bash
# Deploy complete infrastructure (raw + identity resolution)
./deploy/scripts/deploy.sh dev

# Deploy only identity resolution components
./deploy/scripts/deploy.sh dev --identity-only

# Production deployment
./deploy/scripts/deploy.sh prod
```

### Individual Component Deployment
```bash
# Core infrastructure
./deploy/scripts/setup-iam.sh dev
./deploy/scripts/setup-dynamodb.sh dev
./deploy/scripts/setup-s3.sh dev
./deploy/scripts/setup-lambda.sh dev
./deploy/scripts/setup-api-gateway.sh dev

# Identity resolution components
./deploy/scripts/setup-identity-tables.sh dev
./deploy/scripts/setup-enrichment-lambda.sh dev
./deploy/scripts/setup-enriched-archiver.sh dev

# Scheduling
./deploy/scripts/setup-scheduler.sh dev
```

### S3 Archival Management
```bash
# Check archival status
aws events describe-rule --name evothesis-hourly-archive-dev --query 'State'

# Enable/disable raw events archival
aws events enable-rule --name evothesis-hourly-archive-dev
aws events disable-rule --name evothesis-hourly-archive-dev

# Manually trigger archival
aws lambda invoke \
  --function-name evothesis-v2-s3-archiver-dev \
  --payload '{}' \
  response.json && cat response.json
```

## 📊 Infrastructure Resources

### Created AWS Resources

**DynamoDB Tables:**
- `evothesis-v2-raw-events-{env}` - Raw event storage with TTL and composite keys
- `evothesis-v2-identities-{env}` - Device fingerprint → identity mapping
- `evothesis-v2-sessions-{env}` - Session tracking by identity
- `evothesis-v2-enriched-events-{env}` - Temporary enriched event storage for batching
- `evothesis-v2-client-config-{env}` - Client configuration

**S3 Buckets:**
- `evothesis-analytics-v2-archive-{env}` - Hourly batched raw event logs by site
- `evothesis-analytics-v2-enriched-{env}` - Hourly batched enriched event logs by site
- `evothesis-analytics-v2-export-{env}` - Client CSV exports
- `evothesis-analytics-v2-internal-{env}` - Internal analytics data

**Lambda Functions:**
- `evothesis-v2-event-collector-{env}` - Real-time event ingestion
- `evothesis-v2-enrichment-{env}` - Identity resolution and data enrichment
- `evothesis-v2-s3-archiver-{env}` - Hourly raw events S3 archival
- `evothesis-v2-export-{env}` - Export automation (placeholder)

**API Gateway:**
- `evothesis-analytics-api-v2-{env}` - RESTful API endpoint

**CloudWatch Events:**
- `evothesis-hourly-archive-{env}` - Hourly raw events archival scheduler

**IAM Roles:**
- `evothesis-lambda-role-{env}` - Lambda execution role with required permissions

### S3 Archive Structure
```
# Raw Events Archive
s3://evothesis-analytics-v2-archive-dev/
└── site-logs/
    └── domain=example-com/
        └── year=2025/month=06/day=11/hour=14/
            └── events-2025-06-11-14.jsonl

# Enriched Events Archive (Future)
s3://evothesis-analytics-v2-enriched-dev/
└── enriched-events/
    └── domain=example-com/
        └── year=2025/month=06/day=11/hour=14/
            └── enriched-2025-06-11-14.jsonl
```

### DynamoDB Schema

#### Raw Events Table
```
Primary Key: domain_session (HASH) + timestamp (RANGE)
TTL: 180 days
Streams: NEW_AND_OLD_IMAGES (triggers enrichment)
```

#### Identities Table
```
Primary Key: device_fingerprint (HASH) + ip_subnet_hour (RANGE)
GSI: household_id + identity_id
GSI: identity_id
TTL: 180 days
```

#### Sessions Table
```
Primary Key: identity_id (HASH) + session_start (RANGE)
GSI: site_id + session_start
GSI: session_id
TTL: 180 days
```

#### Enriched Events Table
```
Primary Key: site_id (HASH) + timestamp (RANGE)
TTL: 7 days (temporary storage for batching)
Purpose: Hourly batching to S3
```

## 🔍 Monitoring & Debugging

### CloudWatch Logs
```bash
# View event collector logs
aws logs tail /aws/lambda/evothesis-v2-event-collector-dev --follow

# Check identity resolution processing
aws logs tail /aws/lambda/evothesis-v2-enrichment-dev --follow

# Monitor S3 archiver
aws logs tail /aws/lambda/evothesis-v2-s3-archiver-dev --follow

# Check for errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/evothesis-v2-enrichment-dev \
  --filter-pattern "ERROR"
```

### Testing Individual Functions
```bash
# Test complete identity resolution pipeline
./tests/test-identity-resolution.sh dev

# Test event collector directly
curl -X POST https://[your-api-id].execute-api.us-west-1.amazonaws.com/dev/collect \
  -H "Content-Type: application/json" \
  -d '{"eventType":"pageview","sessionId":"test-123","visitorId":"test-456","siteId":"test-site"}'

# Test enrichment Lambda
aws lambda invoke \
  --function-name evothesis-v2-enrichment-dev \
  --payload '{}' \
  response.json && cat response.json
```

### Data Verification
```bash
# Check raw events
aws dynamodb scan --table-name evothesis-v2-raw-events-dev --limit 5

# Check identity resolution results
aws dynamodb scan --table-name evothesis-v2-identities-dev --limit 5

# Check enriched events (temporary storage)
aws dynamodb scan --table-name evothesis-v2-enriched-events-dev --limit 5

# Check S3 archived files
aws s3 ls s3://evothesis-analytics-v2-archive-dev/site-logs/ --recursive
```

## 🧪 Testing

### Complete Pipeline Test
```bash
# Run comprehensive identity resolution test
./tests/test-identity-resolution.sh dev
```

This test validates:
- ✅ API event collection
- ✅ DynamoDB Streams triggering
- ✅ Identity resolution accuracy
- ✅ Session tracking
- ✅ Data enrichment and normalization
- ✅ Temporary DynamoDB storage

### Manual API Testing
```bash
# Test pageview with attribution
curl -X POST https://[api-id].execute-api.us-west-1.amazonaws.com/dev/collect \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "pageview",
    "sessionId": "test-123",
    "visitorId": "test-456", 
    "siteId": "test-site",
    "url": "https://test-site.com/products/widget",
    "attribution": {
      "firstTouch": {
        "source": "google",
        "medium": "cpc",
        "campaign": "summer-sale"
      }
    },
    "browser": {
      "screenWidth": 1920,
      "screenHeight": 1080,
      "userAgent": "Mozilla/5.0..."
    }
  }'

# Test batch interaction events
curl -X POST https://[api-id].execute-api.us-west-1.amazonaws.com/dev/collect \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "batch",
    "sessionId": "test-123",
    "visitorId": "test-456",
    "siteId": "test-site",
    "events": [
      {
        "eventType": "click",
        "eventData": {"tagName": "button", "text": "Add to Cart"}
      }
    ]
  }'
```

## 🚨 Troubleshooting

### Common Issues

**❌ "AWS CLI not configured"**
```bash
aws configure
# Enter your AWS Access Key, Secret Key, Region (us-west-1), and output format (json)
```

**❌ Identity resolution not working**
```bash
# Check DynamoDB Streams status
aws dynamodb describe-table --table-name evothesis-v2-raw-events-dev --query 'Table.StreamSpecification'

# Check enrichment Lambda logs
aws logs tail /aws/lambda/evothesis-v2-enrichment-dev --since 10m

# Verify identity tables exist
aws dynamodb list-tables --query 'TableNames[?contains(@, `identities`)]'
```

**❌ "No enriched events in DynamoDB"**
```bash
# Check Lambda permissions
aws iam get-role-policy --role-name evothesis-lambda-role-dev --policy-name EnrichmentLambdaPolicy

# Test Lambda function directly
aws lambda invoke --function-name evothesis-v2-enrichment-dev --payload '{}' response.json
```

**❌ "Float types not supported"**
- Fixed in v2 - automatic Decimal conversion for DynamoDB compatibility

### Debug Mode
```bash
# Run scripts with verbose output
bash -x ./deploy/scripts/deploy.sh dev

# Check event source mapping
aws lambda list-event-source-mappings --function-name evothesis-v2-enrichment-dev

# Verify table schemas
aws dynamodb describe-table --table-name evothesis-v2-identities-dev
```

## 🔐 Security & Compliance

### Data Protection
- All S3 buckets private by default with lifecycle policies
- DynamoDB encryption at rest enabled with TTL
- Lambda functions run with least-privilege IAM roles
- API Gateway with CORS properly configured
- Automatic float-to-Decimal conversion for data integrity

### Privacy Features
- **No Cookies**: 100% cookieless visitor identification
- **Device Fingerprinting**: Technical identifiers only, no PII
- **Household Grouping**: IP subnet analysis, privacy-compliant
- **Data Minimization**: Only necessary data collected and stored
- **Retention Limits**: Automatic TTL cleanup of old data

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

### Current Status: ✅ **Identity Resolution Implemented**

**Completed:**
- ✅ Cookieless identity resolution with device fingerprinting
- ✅ Cross-device household grouping
- ✅ Real-time enrichment via DynamoDB Streams
- ✅ Enriched events storing in DynamoDB for batching
- ✅ Comprehensive testing pipeline

### Phase 1: Enhanced Archival System
- [ ] Create enriched events S3 archiver Lambda
- [ ] Rename existing s3-archiver to raw-events-s3-archiver
- [ ] Set up hourly scheduling for both archivers (offset timing)
- [ ] Enable raw events archival (currently disabled)

### Phase 2: Export & Analytics
- [ ] Automated CSV export scheduling from S3 archives
- [ ] Retool dashboard integration with enriched S3 data
- [ ] Client data delivery automation to their S3 buckets

### Phase 3: Production Readiness
- [ ] CloudWatch monitoring and alerting setup
- [ ] Performance optimization and capacity planning
- [ ] Load testing with realistic traffic patterns

### Phase 4: Advanced Features
- [ ] Cross-device identity stitching improvements
- [ ] Advanced behavioral analysis and scoring
- [ ] Custom event schema validation
- [ ] Real-time dashboard features

## 📞 Support

### Getting Help
1. Check CloudWatch logs for error details
2. Verify AWS permissions and configuration
3. Test individual components in isolation
4. Review AWS service quotas and limits

### Useful Commands
```bash
# Complete pipeline health check
./tests/test-identity-resolution.sh dev

# Quick API test
curl -X POST https://[your-api-id].execute-api.us-west-1.amazonaws.com/dev/collect \
  -H "Content-Type: application/json" \
  -d '{"eventType":"pageview","sessionId":"health-check","visitorId":"health-check","siteId":"health-check"}'

# Monitor enrichment processing
aws logs tail /aws/lambda/evothesis-v2-enrichment-dev --follow

# Check identity resolution results
aws dynamodb scan --table-name evothesis-v2-identities-dev --limit 5

# Verify enriched events batching
aws dynamodb scan --table-name evothesis-v2-enriched-events-dev --limit 5

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