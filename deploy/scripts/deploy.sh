#!/bin/bash
set -e

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Default environment
ENVIRONMENT=${1:-dev}

echo "🚀 Deploying Evothesis Analytics Platform v2 - Environment: $ENVIRONMENT"

# Load configuration
source "$SCRIPT_DIR/../configs/common.env"
source "$SCRIPT_DIR/../configs/${ENVIRONMENT}.env"

# Validate AWS CLI is configured
if ! aws sts get-caller-identity &>/dev/null; then
    echo "❌ AWS CLI not configured. Run 'aws configure' first."
    exit 1
fi

# Get AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "📋 Deployment Configuration:"
echo "  Environment: $ENVIRONMENT"
echo "  Region: $AWS_REGION"
echo "  Account: $AWS_ACCOUNT_ID"
echo "  Project: $PROJECT_NAME"
echo ""

# Deploy in order
echo "🔧 Setting up IAM roles..."
bash "$SCRIPT_DIR/setup-iam.sh" "$ENVIRONMENT"
echo ""

echo "🗄️  Setting up DynamoDB..."
bash "$SCRIPT_DIR/setup-dynamodb.sh" "$ENVIRONMENT"
echo ""

echo "🪣 Setting up S3 buckets..."
bash "$SCRIPT_DIR/setup-s3.sh" "$ENVIRONMENT"
echo ""

echo "⚡ Setting up Lambda functions..."
bash "$SCRIPT_DIR/setup-lambda.sh" "$ENVIRONMENT"
echo ""

echo "🌐 Setting up API Gateway..."
bash "$SCRIPT_DIR/setup-api-gateway.sh" "$ENVIRONMENT"
echo ""

# Load final configuration
source "/tmp/${PROJECT_NAME}-${ENVIRONMENT}-api.env"

echo "✅ Deployment complete!"
echo ""
echo "🔗 Resources created:"
echo "  API Endpoint: $API_ENDPOINT/collect"
echo "  Environment: $ENVIRONMENT"
echo "  Region: $AWS_REGION"
echo ""
echo "📝 Next steps:"
echo "  1. Test the API endpoint: curl -X POST $API_ENDPOINT/collect -d '{\"test\":\"data\"}'"
echo "  2. Update your JavaScript pixel to use the new endpoint"
echo "  3. Monitor logs in CloudWatch"
echo "  4. Set up CloudFront distribution (optional)"
echo ""
echo "💰 Cost optimization:"
echo "  - All resources configured for pay-per-use"
echo "  - ARM64 Lambda functions (20% cheaper)"
echo "  - S3 lifecycle policies enabled"
echo "  - DynamoDB TTL configured"