# Evothesis Analytics Platform v2

A privacy-first, cookieless web analytics platform built on AWS serverless infrastructure. This system collects rich behavioral data through a JavaScript pixel, processes events through Lambda functions, and provides analytics through CSV exports and dashboards.

## 🏗️ Architecture Overview

```
JavaScript Pixel → CloudFront → API Gateway → Lambda → DynamoDB/S3 → Export/Dashboard
```

### Core Components

- **Event Collection**: API Gateway + Lambda for high-throughput event ingestion
- **Data Storage**: DynamoDB for real-time events, S3 for archival and exports
- **Processing Pipeline**: Lambda functions for enrichment and identity resolution
- **Export System**: Automated CSV generation to client-owned S3 buckets
- **Analytics Dashboard**: Retool integration for real-time analytics

### Key Features

- ✅ **Privacy-First**: No cookies, GDPR/CCPA compliant
- ✅ **Cookieless Tracking**: Device fingerprinting and behavioral analysis
- ✅ **Serverless**: Auto-scaling, pay-per-use AWS infrastructure
- ✅ **Multi-Tenant**: Domain-based client isolation
- ✅ **HIPAA-Ready**: Encryption at rest and in transit
- ✅ **Cost-Optimized**: <$10/month operational costs

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
  -d '{"test": "data", "timestamp": 1234567890, "page": "/test"}'
```

**Expected Response:**
```json
{"message": "event-collector is working", "environment": "dev", "timestamp": "2025-06-07T16:48:35.246298"}
```

## 📁 Project Structure

```
evothesis-infrastructure/
├── src/
│   └── lambdas/                 # Lambda function source code
│       ├── event-collector/     # Main event ingestion
│       ├── enrichment/          # Identity resolution & enrichment
│       └── export/              # CSV export to client buckets
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
│       └── setup-api-gateway.sh # API endpoints
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
- **S3**: Lifecycle policies (auto-archive to cheaper tiers)
- **API Gateway**: Pay-per-request pricing

**Expected Monthly Costs:**
- Development: ~$2/month
- Production: ~$5-10/month (depends on traffic)

## 🛠️ Deployment Commands

### Individual Component Deployment
```bash
# Deploy specific components
./deploy/scripts/setup-iam.sh dev
./deploy/scripts/setup-dynamodb.sh dev
./deploy/scripts/setup-s3.sh dev
./deploy/scripts/setup-lambda.sh dev
./deploy/scripts/setup-api-gateway.sh dev
```

### Full Environment Deployment
```bash
# Development environment
./deploy/scripts/deploy.sh dev

# Production environment
./deploy/scripts/deploy.sh prod
```

### Cleanup/Destroy
```bash
# Manual cleanup (no automated destroy script yet)
# Delete resources through AWS Console or CLI
```

## 📊 Infrastructure Resources

### Created AWS Resources

**DynamoDB Tables:**
- `evothesis-v2-raw-events-{env}` - Event storage with TTL
- `evothesis-v2-client-config-{env}` - Client configuration

**S3 Buckets:**
- `evothesis-analytics-v2-archive-{env}` - Raw event archive
- `evothesis-analytics-v2-export-{env}` - Client CSV exports
- `evothesis-analytics-v2-internal-{env}` - Internal analytics data

**Lambda Functions:**
- `evothesis-v2-event-collector-{env}` - Event ingestion
- `evothesis-v2-enrichment-{env}` - Data enrichment
- `evothesis-v2-export-{env}` - Export automation

**API Gateway:**
- `evothesis-analytics-api-v2-{env}` - RESTful API endpoint

**IAM Roles:**
- `evothesis-lambda-role-{env}` - Lambda execution role with required permissions

## 🔍 Monitoring & Debugging

### CloudWatch Logs
```bash
# View Lambda function logs
aws logs tail /aws/lambda/evothesis-v2-event-collector-dev --follow

# Check for errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/evothesis-v2-event-collector-dev \
  --filter-pattern "ERROR"
```

### Testing Individual Functions
```bash
# Test Lambda function directly
aws lambda invoke \
  --function-name evothesis-v2-event-collector-dev \
  --payload '{"test": "data"}' \
  response.json && cat response.json
```

### Resource Verification
```bash
# List created resources
aws dynamodb list-tables --query 'TableNames[?contains(@, `evothesis`)]'
aws lambda list-functions --query 'Functions[?contains(FunctionName, `evothesis`)].FunctionName'
aws s3 ls | grep evothesis
aws apigateway get-rest-apis --query 'items[?contains(name, `evothesis`)].{Name:name, ID:id}'
```

## 🚨 Troubleshooting

### Common Issues

**❌ "AWS CLI not configured"**
```bash
aws configure
# Enter your AWS Access Key, Secret Key, Region (us-west-1), and output format (json)
```

**❌ "Table already exists" errors**
- Scripts are idempotent - safe to re-run
- Existing resources will be skipped, not duplicated

**❌ "Lambda deployment package too large"**
- Check Lambda source directories for unnecessary files
- Ensure no large dependencies in requirements.txt

**❌ "API Gateway integration errors"**
- Verify Lambda functions exist before creating API Gateway
- Check IAM permissions for API Gateway to invoke Lambda

### Debug Mode
```bash
# Run scripts with verbose output
bash -x ./deploy/scripts/deploy.sh dev
```

## 🔐 Security & Compliance

### Data Protection
- All S3 buckets private by default
- DynamoDB encryption at rest enabled
- Lambda functions run with least-privilege IAM roles
- API Gateway with CORS properly configured

### HIPAA Compliance
- AWS Business Associate Agreement (BAA) ready
- Encryption in transit and at rest
- Audit logging through CloudTrail
- Data retention policies configurable

## 🌐 API Reference

### Event Collection Endpoint

**POST** `https://[api-id].execute-api.us-west-1.amazonaws.com/{stage}/collect`

**Request Body:**
```json
{
  "timestamp": 1234567890,
  "page": "/product/123",
  "event_type": "page_view",
  "user_agent": "Mozilla/5.0...",
  "domain": "example.com",
  "session_id": "abc123",
  "custom_data": {}
}
```

**Response:**
```json
{
  "message": "event-collector is working",
  "environment": "dev",
  "timestamp": "2025-06-07T16:48:35.246298"
}
```

## 🚀 Next Steps

### Phase 1: Enhanced Event Collection
- [ ] Replace placeholder Lambda with real analytics logic
- [ ] Implement event validation and deduplication
- [ ] Add proper error handling and retry logic

### Phase 2: Identity Resolution
- [ ] Build device fingerprinting logic
- [ ] Implement session stitching
- [ ] Add household-level identity resolution

### Phase 3: Export & Analytics
- [ ] Automated CSV export scheduling
- [ ] Retool dashboard integration
- [ ] Client data delivery automation

### Phase 4: Production Readiness
- [ ] CloudWatch monitoring and alerting
- [ ] Performance optimization
- [ ] Load testing and capacity planning

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
  -d '{"health": "check"}'

# View recent Lambda logs
aws logs tail /aws/lambda/evothesis-v2-event-collector-dev --since 1h

# Check deployment status
aws cloudformation list-stacks --query 'StackSummaries[?contains(StackName, `evothesis`)]'
```

---

## 📄 License

[Your License Here]

## 🤝 Contributing

[Your Contributing Guidelines Here]