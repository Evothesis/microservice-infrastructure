#!/bin/bash
set -e

BACKUP_DIR="backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "🔍 Backing up existing AWS resources to $BACKUP_DIR..."

# Get your existing API Gateway (from your endpoint)
API_ID="hcq9ldokwb"
echo "📋 Backing up API Gateway: $API_ID"

# Export API Gateway
if aws apigateway get-rest-api --rest-api-id "$API_ID" &>/dev/null; then
    echo "  📤 Exporting API Gateway configuration..."
    aws apigateway get-export \
        --rest-api-id "$API_ID" \
        --stage-name prod \
        --export-type swagger \
        --accepts application/json \
        "$BACKUP_DIR/api-gateway-swagger.json"
    
    # Get API Gateway details
    aws apigateway get-rest-api \
        --rest-api-id "$API_ID" \
        > "$BACKUP_DIR/api-gateway-details.json"
    
    # Get all resources
    aws apigateway get-resources \
        --rest-api-id "$API_ID" \
        > "$BACKUP_DIR/api-gateway-resources.json"
    
    # Get deployment info
    aws apigateway get-deployments \
        --rest-api-id "$API_ID" \
        > "$BACKUP_DIR/api-gateway-deployments.json"
    
    echo "  ✅ API Gateway backed up"
else
    echo "  ⚠️  API Gateway $API_ID not found or not accessible"
fi

# List and backup Lambda functions
echo "📋 Backing up Lambda functions..."
aws lambda list-functions --region us-west-1 > "$BACKUP_DIR/lambda-functions-list.json"

# Look for functions that might be related to your project
LAMBDA_FUNCTIONS=$(aws lambda list-functions \
    --query "Functions[?contains(FunctionName, 'collect') || contains(FunctionName, 'analytics') || contains(FunctionName, 'evothesis')].FunctionName" \
    --output text)

if [ -n "$LAMBDA_FUNCTIONS" ]; then
    for func in $LAMBDA_FUNCTIONS; do
        echo "  📤 Backing up Lambda function: $func"
        
        # Get function configuration
        aws lambda get-function \
            --function-name "$func" \
            > "$BACKUP_DIR/lambda-${func}-config.json"
        
        # Download function code
        DOWNLOAD_URL=$(aws lambda get-function \
            --function-name "$func" \
            --query 'Code.Location' \
            --output text)
        
        if [ "$DOWNLOAD_URL" != "None" ]; then
            curl -s "$DOWNLOAD_URL" -o "$BACKUP_DIR/lambda-${func}-code.zip"
        fi
        
        # Get function policy if it exists
        aws lambda get-policy \
            --function-name "$func" \
            > "$BACKUP_DIR/lambda-${func}-policy.json" 2>/dev/null || echo "No policy found for $func"
    done
    echo "  ✅ Lambda functions backed up"
else
    echo "  ℹ️  No obvious Lambda functions found"
fi

# Backup DynamoDB tables
echo "📋 Backing up DynamoDB tables..."
aws dynamodb list-tables --region us-west-1 > "$BACKUP_DIR/dynamodb-tables-list.json"

# Look for tables that might be related
DYNAMODB_TABLES=$(aws dynamodb list-tables \
    --query "TableNames[?contains(@, 'analytics') || contains(@, 'events') || contains(@, 'evothesis')]" \
    --output text)

if [ -n "$DYNAMODB_TABLES" ]; then
    for table in $DYNAMODB_TABLES; do
        echo "  📤 Backing up DynamoDB table: $table"
        
        # Get table description
        aws dynamodb describe-table \
            --table-name "$table" \
            > "$BACKUP_DIR/dynamodb-${table}-description.json"
        
        # Get table tags
        aws dynamodb list-tags-of-resource \
            --resource-arn "arn:aws:dynamodb:us-west-1:$(aws sts get-caller-identity --query Account --output text):table/$table" \
            > "$BACKUP_DIR/dynamodb-${table}-tags.json" 2>/dev/null || echo "No tags for $table"
    done
    echo "  ✅ DynamoDB tables backed up"
else
    echo "  ℹ️  No obvious DynamoDB tables found"
fi

# Backup S3 buckets
echo "📋 Backing up S3 buckets..."
aws s3api list-buckets > "$BACKUP_DIR/s3-buckets-list.json"

# Look for buckets that might be related
S3_BUCKETS=$(aws s3api list-buckets \
    --query "Buckets[?contains(Name, 'analytics') || contains(Name, 'events') || contains(Name, 'evothesis')].Name" \
    --output text)

if [ -n "$S3_BUCKETS" ]; then
    for bucket in $S3_BUCKETS; do
        echo "  📤 Backing up S3 bucket config: $bucket"
        
        # Get bucket location
        aws s3api get-bucket-location \
            --bucket "$bucket" \
            > "$BACKUP_DIR/s3-${bucket}-location.json" 2>/dev/null || echo "Access denied for $bucket location"
        
        # Get bucket policy
        aws s3api get-bucket-policy \
            --bucket "$bucket" \
            > "$BACKUP_DIR/s3-${bucket}-policy.json" 2>/dev/null || echo "No policy for $bucket"
        
        # Get bucket tags
        aws s3api get-bucket-tagging \
            --bucket "$bucket" \
            > "$BACKUP_DIR/s3-${bucket}-tags.json" 2>/dev/null || echo "No tags for $bucket"
        
        # Get bucket cors
        aws s3api get-bucket-cors \
            --bucket "$bucket" \
            > "$BACKUP_DIR/s3-${bucket}-cors.json" 2>/dev/null || echo "No CORS for $bucket"
    done
    echo "  ✅ S3 buckets backed up"
else
    echo "  ℹ️  No obvious S3 buckets found"
fi

# Backup IAM roles
echo "📋 Backing up IAM roles..."
aws iam list-roles > "$BACKUP_DIR/iam-roles-list.json"

# Look for roles that might be related
IAM_ROLES=$(aws iam list-roles \
    --query "Roles[?contains(RoleName, 'lambda') || contains(RoleName, 'analytics') || contains(RoleName, 'evothesis')].RoleName" \
    --output text)

if [ -n "$IAM_ROLES" ]; then
    for role in $IAM_ROLES; do
        echo "  📤 Backing up IAM role: $role"
        
        # Get role details
        aws iam get-role \
            --role-name "$role" \
            > "$BACKUP_DIR/iam-role-${role}.json"
        
        # Get attached policies
        aws iam list-attached-role-policies \
            --role-name "$role" \
            > "$BACKUP_DIR/iam-role-${role}-attached-policies.json"
        
        # Get inline policies
        aws iam list-role-policies \
            --role-name "$role" \
            > "$BACKUP_DIR/iam-role-${role}-inline-policies.json"
    done
    echo "  ✅ IAM roles backed up"
else
    echo "  ℹ️  No obvious IAM roles found"
fi

# Create backup summary
cat > "$BACKUP_DIR/backup-summary.md" << EOF
# Backup Summary - $(date)

## API Gateway
- API ID: $API_ID
- Endpoint: https://$API_ID.execute-api.us-west-1.amazonaws.com/prod/collect

## Files Created
- API Gateway: api-gateway-*.json
- Lambda Functions: lambda-*-*.json/zip
- DynamoDB Tables: dynamodb-*-*.json
- S3 Buckets: s3-*-*.json
- IAM Roles: iam-role-*.json

## Restoration Notes
To restore from this backup:
1. Use the swagger.json to recreate API Gateway
2. Use the lambda code.zip files to restore function code
3. Use the DynamoDB descriptions to recreate tables
4. Use the IAM role configurations to recreate permissions

## Original Endpoint
Your current endpoint: https://hcq9ldokwb.execute-api.us-west-1.amazonaws.com/prod/collect
EOF

echo ""
echo "✅ Backup complete! Files saved to: $BACKUP_DIR"
echo "📋 See backup-summary.md for details"
echo ""
echo "🔄 You can now safely proceed with new infrastructure deployment"