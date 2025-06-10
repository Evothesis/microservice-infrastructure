#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
source "$SCRIPT_DIR/../configs/common.env"
source "$SCRIPT_DIR/../configs/${ENVIRONMENT}.env"
source "/tmp/${PROJECT_NAME}-${ENVIRONMENT}-lambda.env"

echo "⏰ Setting up CloudWatch Events scheduler for $ENVIRONMENT..."

RULE_NAME="${PROJECT_NAME}-hourly-archive-${ENVIRONMENT}"
S3_ARCHIVER_FUNCTION_NAME="${LAMBDA_PREFIX}-s3-archiver-${ENVIRONMENT}"

# Create CloudWatch Events rule
if aws events describe-rule --name "$RULE_NAME" &>/dev/null; then
    echo "  ✅ CloudWatch rule $RULE_NAME already exists"
else
    echo "  🔧 Creating hourly schedule rule..."
    
    aws events put-rule \
        --name "$RULE_NAME" \
        --schedule-expression "rate(1 hour)" \
        --description "Hourly S3 archival for evothesis analytics - $ENVIRONMENT" \
        --state ENABLED
    
    echo "  ✅ CloudWatch rule created: $RULE_NAME"
fi

# Add Lambda target to the rule
echo "  🎯 Adding Lambda target to rule..."

aws events put-targets \
    --rule "$RULE_NAME" \
    --targets "Id"="1","Arn"="$S3_ARCHIVER_ARN"

# Add permission for CloudWatch Events to invoke Lambda
echo "  🔧 Adding Lambda permission for CloudWatch Events..."

aws lambda add-permission \
    --function-name "$S3_ARCHIVER_FUNCTION_NAME" \
    --statement-id "allow-cloudwatch-${ENVIRONMENT}-$(date +%s)" \
    --action lambda:InvokeFunction \
    --principal events.amazonaws.com \
    --source-arn "arn:aws:events:${AWS_REGION}:${AWS_ACCOUNT_ID}:rule/${RULE_NAME}" \
    2>/dev/null || echo "  ℹ️ Permission may already exist"

echo "✅ Scheduler setup complete for $ENVIRONMENT"
echo "  📅 S3 archival will run every hour"
echo "  🎯 Target function: $S3_ARCHIVER_FUNCTION_NAME"