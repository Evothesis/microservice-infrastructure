#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Fix: Ensure PROJECT_ROOT is always the actual project root
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load configuration
source "$SCRIPT_DIR/../configs/common.env"
source "$SCRIPT_DIR/../configs/${ENVIRONMENT}.env"

# Load IAM and other configs - check if they exist first
if [ ! -f "/tmp/${PROJECT_NAME}-${ENVIRONMENT}-iam.env" ]; then
    echo "❌ Missing IAM configuration. Run: ./deploy/scripts/setup-iam.sh $ENVIRONMENT"
    exit 1
fi

if [ ! -f "/tmp/${PROJECT_NAME}-${ENVIRONMENT}-dynamodb.env" ]; then
    echo "❌ Missing DynamoDB configuration. Run: ./deploy/scripts/setup-dynamodb.sh $ENVIRONMENT"
    exit 1
fi

if [ ! -f "/tmp/${PROJECT_NAME}-${ENVIRONMENT}-s3.env" ]; then
    echo "❌ Missing S3 configuration. Run: ./deploy/scripts/setup-s3.sh $ENVIRONMENT"
    exit 1
fi

source "/tmp/${PROJECT_NAME}-${ENVIRONMENT}-iam.env"
source "/tmp/${PROJECT_NAME}-${ENVIRONMENT}-dynamodb.env"
source "/tmp/${PROJECT_NAME}-${ENVIRONMENT}-s3.env"

echo "⚡ Setting up Lambda functions for $ENVIRONMENT..."

# Debug: Show what PROJECT_ROOT resolves to
echo "  📁 Project root: $PROJECT_ROOT"

# Create Lambda deployment package
create_lambda_package() {
    local function_name=$1
    local source_dir="$PROJECT_ROOT/src/lambdas/$function_name"
    local zip_file="/tmp/${function_name}-${ENVIRONMENT}.zip"
    
    echo "  📦 Creating deployment package for $function_name..."
    echo "  📁 Source directory: $source_dir"
    
    # Create temporary directory for packaging
    local temp_dir="/tmp/lambda-package-$function_name"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"
    
    # Ensure the correct source directory exists in project root
    mkdir -p "$source_dir"
    
    # Copy source code if it exists
    if [ -d "$source_dir" ] && [ "$(ls -A "$source_dir" 2>/dev/null)" ]; then
        cp -r "$source_dir"/* "$temp_dir/" 2>/dev/null || true
    fi
    
    # Create basic Lambda function if source doesn't exist
    if [ ! -f "$temp_dir/lambda_function.py" ]; then
        cat > "$temp_dir/lambda_function.py" << EOF
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    $function_name Lambda function
    Environment: $ENVIRONMENT
    """
    logger.info(f"Event: {json.dumps(event)}")
    
    return {
        'statusCode': 200,
        'headers': {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type',
            'Access-Control-Allow-Methods': 'POST,OPTIONS'
        },
        'body': json.dumps({
            'message': '$function_name is working',
            'environment': '$ENVIRONMENT',
            'timestamp': datetime.utcnow().isoformat()
        })
    }
EOF
        # Copy to the CORRECT source directory
        cp "$temp_dir/lambda_function.py" "$source_dir/"
        echo "  📄 Created placeholder function in $source_dir"
    fi
    
    # Create zip file
    cd "$temp_dir"
    zip -q -r "$zip_file" . >/dev/null 2>&1
    cd - >/dev/null
    
    # Cleanup
    rm -rf "$temp_dir"
    
    echo "$zip_file"
}

# Deploy Lambda function
deploy_lambda() {
    local function_name=$1
    local description=$2
    local environment_vars=$3
    
    local lambda_function_name="${LAMBDA_PREFIX}-${function_name}-${ENVIRONMENT}"
    
    local zip_file=$(create_lambda_package "$function_name")
    
    # Check if function exists
    if aws lambda get-function --function-name "$lambda_function_name" &>/dev/null; then
        echo "  🔄 Updating existing function: $lambda_function_name"
        
        # Update function code
        aws lambda update-function-code \
            --function-name "$lambda_function_name" \
            --zip-file "fileb://$zip_file" >/dev/null
        
        # Update function configuration
        aws lambda update-function-configuration \
            --function-name "$lambda_function_name" \
            --description "$description" \
            --timeout "$LAMBDA_TIMEOUT" \
            --memory-size "$LAMBDA_MEMORY" \
            --environment "$environment_vars" >/dev/null
    else
        echo "  🔧 Creating new function: $lambda_function_name"
        
        aws lambda create-function \
            --function-name "$lambda_function_name" \
            --runtime "$LAMBDA_RUNTIME" \
            --architectures "$LAMBDA_ARCHITECTURE" \
            --role "$LAMBDA_ROLE_ARN" \
            --handler "lambda_function.lambda_handler" \
            --zip-file "fileb://$zip_file" \
            --description "$description" \
            --timeout "$LAMBDA_TIMEOUT" \
            --memory-size "$LAMBDA_MEMORY" \
            --environment "$environment_vars" \
            --tags "Environment=$ENVIRONMENT,Project=$PROJECT_NAME" >/dev/null
    fi
    
    echo "  ✅ Function deployed: $lambda_function_name"
    
    # Clean up zip file
    rm -f "$zip_file"
    
    # Return function ARN
    aws lambda get-function --function-name "$lambda_function_name" --query 'Configuration.FunctionArn' --output text
}

# Deploy event collector function
echo "  🚀 Deploying event collector..."
EVENT_COLLECTOR_ARN=$(deploy_lambda "event-collector" \
    "Collects and processes incoming analytics events" \
    "Variables={RAW_EVENTS_TABLE=$RAW_EVENTS_TABLE,S3_ARCHIVE_BUCKET=$S3_ARCHIVE_BUCKET,ENVIRONMENT=$ENVIRONMENT}")

# Deploy enrichment function
echo "  🚀 Deploying enrichment function..."
ENRICHMENT_ARN=$(deploy_lambda "enrichment" \
    "Enriches raw events with identity resolution" \
    "Variables={RAW_EVENTS_TABLE=$RAW_EVENTS_TABLE,S3_INTERNAL_BUCKET=$S3_INTERNAL_BUCKET,ENVIRONMENT=$ENVIRONMENT}")

# Deploy export function
echo "  🚀 Deploying export function..."
EXPORT_ARN=$(deploy_lambda "export" \
    "Exports processed data to client buckets" \
    "Variables={S3_INTERNAL_BUCKET=$S3_INTERNAL_BUCKET,S3_EXPORT_BUCKET=$S3_EXPORT_BUCKET,CLIENT_CONFIG_TABLE=$CLIENT_CONFIG_TABLE,ENVIRONMENT=$ENVIRONMENT}")

# Store function ARNs for other scripts
cat > "/tmp/${PROJECT_NAME}-${ENVIRONMENT}-lambda.env" << EOF
export EVENT_COLLECTOR_ARN='$EVENT_COLLECTOR_ARN'
export ENRICHMENT_ARN='$ENRICHMENT_ARN'
export EXPORT_ARN='$EXPORT_ARN'
export EVENT_COLLECTOR_NAME='${LAMBDA_PREFIX}-event-collector-${ENVIRONMENT}'
export ENRICHMENT_NAME='${LAMBDA_PREFIX}-enrichment-${ENVIRONMENT}'
export EXPORT_NAME='${LAMBDA_PREFIX}-export-${ENVIRONMENT}'
EOF

echo "✅ Lambda setup complete for $ENVIRONMENT"