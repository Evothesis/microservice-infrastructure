#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
source "$SCRIPT_DIR/../configs/common.env"
source "$SCRIPT_DIR/../configs/${ENVIRONMENT}.env"
source "/tmp/${PROJECT_NAME}-${ENVIRONMENT}-lambda.env"

echo "🌐 Setting up API Gateway for $ENVIRONMENT..."

API_NAME="${API_GATEWAY_NAME}-${ENVIRONMENT}"

# Check if API exists - get only the first match
API_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME'].id | [0]" --output text)

if [ -n "$API_ID" ] && [ "$API_ID" != "None" ] && [ "$API_ID" != "" ]; then
    echo "  ✅ API Gateway $API_NAME already exists (ID: $API_ID)"
else
    echo "  🔧 Creating API Gateway: $API_NAME"
    API_ID=$(aws apigateway create-rest-api \
        --name "$API_NAME" \
        --description "Evothesis Analytics API - $ENVIRONMENT" \
        --endpoint-configuration types=REGIONAL \
        --query 'id' \
        --output text)
    
    echo "  ✅ API created with ID: $API_ID"
fi

# Get root resource ID
ROOT_RESOURCE_ID=$(aws apigateway get-resources \
    --rest-api-id "$API_ID" \
    --query 'items[?path==`/`].id' \
    --output text)

# Create /collect resource
COLLECT_RESOURCE_ID=$(aws apigateway get-resources \
    --rest-api-id "$API_ID" \
    --query 'items[?pathPart==`collect`].id' \
    --output text)

if [ -z "$COLLECT_RESOURCE_ID" ] || [ "$COLLECT_RESOURCE_ID" == "None" ] || [ "$COLLECT_RESOURCE_ID" == "" ]; then
    echo "  🔧 Creating /collect resource..."
    COLLECT_RESOURCE_ID=$(aws apigateway create-resource \
        --rest-api-id "$API_ID" \
        --parent-id "$ROOT_RESOURCE_ID" \
        --path-part "collect" \
        --query 'id' \
        --output text)
fi

# Create POST method
if ! aws apigateway get-method \
    --rest-api-id "$API_ID" \
    --resource-id "$COLLECT_RESOURCE_ID" \
    --http-method POST &>/dev/null; then
    
    echo "  🔧 Creating POST method for /collect..."
    aws apigateway put-method \
        --rest-api-id "$API_ID" \
        --resource-id "$COLLECT_RESOURCE_ID" \
        --http-method POST \
        --authorization-type NONE \
        --no-api-key-required >/dev/null

    # Get Lambda function details
    LAMBDA_FUNCTION_NAME="${LAMBDA_PREFIX}-event-collector-${ENVIRONMENT}"
    LAMBDA_ARN=$(aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --query 'Configuration.FunctionArn' --output text)

    echo "  🔧 Setting up Lambda integration..."
    
    # Set up Lambda integration
    LAMBDA_URI="arn:aws:apigateway:${AWS_REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations"

    aws apigateway put-integration \
        --rest-api-id "$API_ID" \
        --resource-id "$COLLECT_RESOURCE_ID" \
        --http-method POST \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri "$LAMBDA_URI" >/dev/null

    echo "  🔧 Adding Lambda permission..."
    
    # Add Lambda permission
    STATEMENT_ID="apigateway-${ENVIRONMENT}-$(date +%s)"
    aws lambda add-permission \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --statement-id "$STATEMENT_ID" \
        --action lambda:InvokeFunction \
        --principal apigateway.amazonaws.com \
        --source-arn "arn:aws:execute-api:${AWS_REGION}:${AWS_ACCOUNT_ID}:${API_ID}/*/*" >/dev/null
    
    echo "  ✅ POST method and integration created"
else
    echo "  ✅ POST method already exists"
fi

# Deploy API
echo "  🚀 Deploying API to $API_STAGE stage..."
aws apigateway create-deployment \
    --rest-api-id "$API_ID" \
    --stage-name "$API_STAGE" \
    --description "Deployment for $ENVIRONMENT environment" >/dev/null

# Store API details
API_ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/${API_STAGE}"

cat > "/tmp/${PROJECT_NAME}-${ENVIRONMENT}-api.env" << EOF
export API_ID='$API_ID'
export API_ENDPOINT='$API_ENDPOINT'
export API_STAGE='$API_STAGE'
EOF

echo "  ✅ API Gateway deployed!"
echo "  🔗 Endpoint: $API_ENDPOINT/collect"
echo ""
echo "📝 Note: CORS will be handled by Lambda function headers"
echo "✅ API Gateway setup complete for $ENVIRONMENT"