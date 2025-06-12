#!/bin/bash

# Enhanced Lambda Deployment Script for Identity Resolution
# Deploys the enrichment Lambda with DynamoDB Streams trigger

set -e

# Check if environment parameter is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <environment>"
    echo "Example: $0 dev"
    exit 1
fi

ENVIRONMENT=$1

# Source environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../configs/common.env"
source "${SCRIPT_DIR}/../configs/${ENVIRONMENT}.env"

echo "Deploying enrichment Lambda for environment: ${ENVIRONMENT}"

# Define function names and resources
ENRICHMENT_FUNCTION="evothesis-v2-enrichment-${ENVIRONMENT}"
RAW_EVENTS_TABLE="evothesis-v2-raw-events-${ENVIRONMENT}"
IDENTITIES_TABLE="evothesis-v2-identities-${ENVIRONMENT}"
SESSIONS_TABLE="evothesis-v2-sessions-${ENVIRONMENT}"
ENRICHED_BUCKET="evothesis-analytics-v2-enriched-${ENVIRONMENT}"
LAMBDA_ROLE="evothesis-lambda-role-${ENVIRONMENT}"

# Create enhanced IAM policy for enrichment Lambda
echo "Creating enhanced IAM policy for enrichment Lambda..."

cat > /tmp/enrichment-lambda-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:${AWS_REGION}:*:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:Query",
                "dynamodb:Scan"
            ],
            "Resource": [
                "arn:aws:dynamodb:${AWS_REGION}:*:table/${RAW_EVENTS_TABLE}",
                "arn:aws:dynamodb:${AWS_REGION}:*:table/${IDENTITIES_TABLE}",
                "arn:aws:dynamodb:${AWS_REGION}:*:table/${IDENTITIES_TABLE}/index/*",
                "arn:aws:dynamodb:${AWS_REGION}:*:table/${SESSIONS_TABLE}",
                "arn:aws:dynamodb:${AWS_REGION}:*:table/${SESSIONS_TABLE}/index/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:DescribeStream",
                "dynamodb:GetRecords",
                "dynamodb:GetShardIterator",
                "dynamodb:ListStreams"
            ],
            "Resource": "arn:aws:dynamodb:${AWS_REGION}:*:table/${RAW_EVENTS_TABLE}/stream/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:PutObjectAcl",
                "s3:GetObject"
            ],
            "Resource": [
                "arn:aws:s3:::${ENRICHED_BUCKET}/*"
            ]
        }
    ]
}
EOF

# Update the Lambda role with enhanced permissions
aws iam put-role-policy \
    --role-name "${LAMBDA_ROLE}" \
    --policy-name "EnrichmentLambdaPolicy" \
    --policy-document file:///tmp/enrichment-lambda-policy.json \
    --region "${AWS_REGION}"

echo "✅ Updated IAM role with enrichment permissions"

# Create the Lambda deployment package
echo "Creating Lambda deployment package..."

# Create temporary directory for Lambda code
LAMBDA_DIR="/tmp/enrichment-lambda-${ENVIRONMENT}"
mkdir -p "${LAMBDA_DIR}"

# Copy the enrichment Lambda function
cp "${SCRIPT_DIR}/../../src/lambdas/enrichment/lambda_function.py" "${LAMBDA_DIR}/"

# Create requirements.txt for dependencies
cat > "${LAMBDA_DIR}/requirements.txt" << EOF
user-agents==2.2.0
boto3
EOF

# Install dependencies in the package directory
cd "${LAMBDA_DIR}"
pip install -r requirements.txt -t .

# Remove unnecessary files to reduce package size
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete 2>/dev/null || true

# Create deployment package
zip -r9 enrichment-lambda.zip . > /dev/null

echo "✅ Created Lambda deployment package"

# Deploy or update the Lambda function
LAMBDA_EXISTS=$(aws lambda list-functions --query "Functions[?FunctionName=='${ENRICHMENT_FUNCTION}'].FunctionName" --output text --region "${AWS_REGION}")

if [ -z "$LAMBDA_EXISTS" ]; then
    echo "Creating new Lambda function: ${ENRICHMENT_FUNCTION}"
    
    aws lambda create-function \
        --function-name "${ENRICHMENT_FUNCTION}" \
        --runtime python3.13 \
        --role "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/${LAMBDA_ROLE}" \
        --handler lambda_function.lambda_handler \
        --zip-file fileb://enrichment-lambda.zip \
        --timeout 300 \
        --memory-size 256 \
        --architectures arm64 \
        --environment Variables="{
            RAW_EVENTS_TABLE=${RAW_EVENTS_TABLE},
            IDENTITIES_TABLE=${IDENTITIES_TABLE},
            SESSIONS_TABLE=${SESSIONS_TABLE},
            ENRICHED_S3_BUCKET=${ENRICHED_BUCKET},
            ENRICHED_EVENTS_TABLE=evothesis-v2-enriched-events-${ENVIRONMENT},
            ENVIRONMENT=${ENVIRONMENT}
        }" \
        --tags "Project=evothesis-analytics,Environment=${ENVIRONMENT},Component=enrichment" \
        --region "${AWS_REGION}"
else
    echo "Updating existing Lambda function: ${ENRICHMENT_FUNCTION}"
    
    aws lambda update-function-code \
        --function-name "${ENRICHMENT_FUNCTION}" \
        --zip-file fileb://enrichment-lambda.zip \
        --region "${AWS_REGION}"
    
    aws lambda update-function-configuration \
        --function-name "${ENRICHMENT_FUNCTION}" \
        --timeout 300 \
        --memory-size 512 \
        --environment Variables="{
            RAW_EVENTS_TABLE=${RAW_EVENTS_TABLE},
            IDENTITIES_TABLE=${IDENTITIES_TABLE},
            SESSIONS_TABLE=${SESSIONS_TABLE},
            ENRICHED_S3_BUCKET=${ENRICHED_BUCKET},
            ENRICHED_EVENTS_TABLE=evothesis-v2-enriched-events-${ENVIRONMENT},
            ENVIRONMENT=${ENVIRONMENT}
        }" \
        --region "${AWS_REGION}"
fi

echo "✅ Deployed enrichment Lambda function"

# Enable DynamoDB Streams on raw events table if not already enabled
echo "Configuring DynamoDB Streams for raw events table..."

STREAM_ARN=$(aws dynamodb describe-table \
    --table-name "${RAW_EVENTS_TABLE}" \
    --query 'Table.LatestStreamArn' \
    --output text \
    --region "${AWS_REGION}")

if [ "$STREAM_ARN" = "None" ] || [ -z "$STREAM_ARN" ]; then
    echo "Enabling DynamoDB Streams on ${RAW_EVENTS_TABLE}..."
    
    aws dynamodb update-table \
        --table-name "${RAW_EVENTS_TABLE}" \
        --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES \
        --region "${AWS_REGION}"
    
    # Wait for stream to be enabled
    echo "Waiting for stream to be enabled..."
    sleep 30
    
    STREAM_ARN=$(aws dynamodb describe-table \
        --table-name "${RAW_EVENTS_TABLE}" \
        --query 'Table.LatestStreamArn' \
        --output text \
        --region "${AWS_REGION}")
fi

echo "✅ DynamoDB Stream ARN: ${STREAM_ARN}"

# Create event source mapping from DynamoDB Stream to Lambda
echo "Creating event source mapping..."

# Check if mapping already exists
EXISTING_MAPPING=$(aws lambda list-event-source-mappings \
    --function-name "${ENRICHMENT_FUNCTION}" \
    --query "EventSourceMappings[?EventSourceArn=='${STREAM_ARN}'].UUID" \
    --output text \
    --region "${AWS_REGION}")

if [ -z "$EXISTING_MAPPING" ]; then
    aws lambda create-event-source-mapping \
        --function-name "${ENRICHMENT_FUNCTION}" \
        --event-source-arn "${STREAM_ARN}" \
        --starting-position LATEST \
        --batch-size 25 \
        --maximum-batching-window-in-seconds 5 \
        --parallelization-factor 2 \
        --maximum-retry-attempts 3 \
        --maximum-record-age-in-seconds 3600 \
        --bisect-batch-on-function-error \
        --region "${AWS_REGION}"
    
    echo "✅ Created event source mapping"
else
    echo "✅ Event source mapping already exists: ${EXISTING_MAPPING}"
fi

# Clean up
cd - > /dev/null
rm -rf "${LAMBDA_DIR}"
rm -f /tmp/enrichment-lambda-policy.json

echo ""
echo "🎉 Enrichment Lambda deployment complete!"
echo ""
echo "Function Details:"
echo "  • Name: ${ENRICHMENT_FUNCTION}"
echo "  • Runtime: Python 3.9 (ARM64)"
echo "  • Memory: 512 MB"
echo "  • Timeout: 300 seconds"
echo "  • Trigger: DynamoDB Streams from ${RAW_EVENTS_TABLE}"
echo ""
echo "Environment Variables:"
echo "  • RAW_EVENTS_TABLE: ${RAW_EVENTS_TABLE}"
echo "  • IDENTITIES_TABLE: ${IDENTITIES_TABLE}"
echo "  • SESSIONS_TABLE: ${SESSIONS_TABLE}"
echo "  • ENRICHED_S3_BUCKET: ${ENRICHED_BUCKET}"
echo "  • ENRICHED_EVENTS_TABLE: evothesis-v2-enriched-events-${ENVIRONMENT}"
echo "  • ENVIRONMENT: ${ENVIRONMENT}"
echo ""
echo "Next Steps:"
echo "  1. Test the enrichment pipeline with sample events"
echo "  2. Monitor CloudWatch logs for processing"
echo "  3. Verify enriched events are stored in S3"
echo "  4. Set up export automation from enriched data"

# Display function ARN for reference
FUNCTION_ARN=$(aws lambda get-function --function-name "${ENRICHMENT_FUNCTION}" --query 'Configuration.FunctionArn' --output text --region "${AWS_REGION}")
echo ""
echo "Function ARN: ${FUNCTION_ARN}"