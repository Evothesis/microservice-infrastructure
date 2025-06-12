#!/bin/bash

# Fixed Identity Resolution Tables Setup Script
# Creates DynamoDB tables for identity mapping and session tracking

set -e

# Check if environment parameter is provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <environment>"
    echo "Example: $0 dev"
    exit 1
fi

ENVIRONMENT=$1

# Source common environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../configs/common.env"
source "${SCRIPT_DIR}/../configs/${ENVIRONMENT}.env"

echo "Setting up identity resolution tables for environment: ${ENVIRONMENT}"
echo "Region: ${AWS_REGION}"

# Define table names
IDENTITIES_TABLE="evothesis-v2-identities-${ENVIRONMENT}"
SESSIONS_TABLE="evothesis-v2-sessions-${ENVIRONMENT}"

# Function to check if table exists
check_table_exists() {
    local table_name=$1
    aws dynamodb describe-table --table-name "${table_name}" --region "${AWS_REGION}" >/dev/null 2>&1
}

# Function to wait for table to be active
wait_for_table_active() {
    local table_name=$1
    echo "Waiting for table ${table_name} to become active..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local status=$(aws dynamodb describe-table \
            --table-name "${table_name}" \
            --query 'Table.TableStatus' \
            --output text \
            --region "${AWS_REGION}" 2>/dev/null || echo "NOT_FOUND")
        
        echo "  Attempt ${attempt}/${max_attempts}: Table status = ${status}"
        
        if [ "$status" = "ACTIVE" ]; then
            echo "  ✅ Table ${table_name} is now active"
            return 0
        elif [ "$status" = "NOT_FOUND" ]; then
            echo "  ❌ Table ${table_name} not found"
            return 1
        elif [ "$status" = "CREATING" ]; then
            echo "  ⏳ Table ${table_name} is still creating..."
        else
            echo "  ⚠️  Table ${table_name} status: ${status}"
        fi
        
        sleep 10
        ((attempt++))
    done
    
    echo "  ❌ Timeout waiting for table ${table_name} to become active"
    return 1
}

# Create Identities Table
echo ""
echo "Creating identities table: ${IDENTITIES_TABLE}"

if check_table_exists "${IDENTITIES_TABLE}"; then
    echo "✅ Table ${IDENTITIES_TABLE} already exists"
else
    echo "📊 Creating new table ${IDENTITIES_TABLE}..."
    
    aws dynamodb create-table \
        --table-name "${IDENTITIES_TABLE}" \
        --attribute-definitions \
            AttributeName=device_fingerprint,AttributeType=S \
            AttributeName=ip_subnet_hour,AttributeType=S \
            AttributeName=household_id,AttributeType=S \
            AttributeName=identity_id,AttributeType=S \
        --key-schema \
            AttributeName=device_fingerprint,KeyType=HASH \
            AttributeName=ip_subnet_hour,KeyType=RANGE \
        --global-secondary-indexes \
            'IndexName=household-identity-index,KeySchema=[{AttributeName=household_id,KeyType=HASH},{AttributeName=identity_id,KeyType=RANGE}],Projection={ProjectionType=ALL}' \
            'IndexName=identity-lookup-index,KeySchema=[{AttributeName=identity_id,KeyType=HASH}],Projection={ProjectionType=ALL}' \
        --billing-mode PAY_PER_REQUEST \
        --tags \
            Key=Project,Value=evothesis-analytics \
            Key=Environment,Value="${ENVIRONMENT}" \
            Key=Component,Value=identity-resolution \
        --region "${AWS_REGION}"
    
    if [ $? -eq 0 ]; then
        echo "✅ Table creation command succeeded"
    else
        echo "❌ Table creation command failed"
        exit 1
    fi
fi

# Create Sessions Table
echo ""
echo "Creating sessions table: ${SESSIONS_TABLE}"

if check_table_exists "${SESSIONS_TABLE}"; then
    echo "✅ Table ${SESSIONS_TABLE} already exists"
else
    echo "📊 Creating new table ${SESSIONS_TABLE}..."
    
    aws dynamodb create-table \
        --table-name "${SESSIONS_TABLE}" \
        --attribute-definitions \
            AttributeName=identity_id,AttributeType=S \
            AttributeName=session_start,AttributeType=N \
            AttributeName=site_id,AttributeType=S \
            AttributeName=session_id,AttributeType=S \
        --key-schema \
            AttributeName=identity_id,KeyType=HASH \
            AttributeName=session_start,KeyType=RANGE \
        --global-secondary-indexes \
            'IndexName=site-session-index,KeySchema=[{AttributeName=site_id,KeyType=HASH},{AttributeName=session_start,KeyType=RANGE}],Projection={ProjectionType=ALL}' \
            'IndexName=session-lookup-index,KeySchema=[{AttributeName=session_id,KeyType=HASH}],Projection={ProjectionType=ALL}' \
        --billing-mode PAY_PER_REQUEST \
        --tags \
            Key=Project,Value=evothesis-analytics \
            Key=Environment,Value="${ENVIRONMENT}" \
            Key=Component,Value=session-tracking \
        --region "${AWS_REGION}"
    
    if [ $? -eq 0 ]; then
        echo "✅ Table creation command succeeded"
    else
        echo "❌ Table creation command failed"
        exit 1
    fi
fi

# Wait for tables to be active
echo ""
echo "Waiting for tables to become active..."

wait_for_table_active "${IDENTITIES_TABLE}"
IDENTITIES_READY=$?

wait_for_table_active "${SESSIONS_TABLE}"
SESSIONS_READY=$?

if [ $IDENTITIES_READY -ne 0 ] || [ $SESSIONS_READY -ne 0 ]; then
    echo "❌ One or more tables failed to become active"
    echo "Please check AWS Console for details"
    exit 1
fi

# Enable TTL on identities table
echo ""
echo "Enabling TTL on identities table..."
aws dynamodb update-time-to-live \
    --table-name "${IDENTITIES_TABLE}" \
    --time-to-live-specification \
        Enabled=true,AttributeName=ttl \
    --region "${AWS_REGION}" \
    2>/dev/null && echo "✅ TTL enabled on ${IDENTITIES_TABLE}" || echo "⚠️  TTL already enabled on ${IDENTITIES_TABLE}"

# Enable TTL on sessions table
echo "Enabling TTL on sessions table..."
aws dynamodb update-time-to-live \
    --table-name "${SESSIONS_TABLE}" \
    --time-to-live-specification \
        Enabled=true,AttributeName=ttl \
    --region "${AWS_REGION}" \
    2>/dev/null && echo "✅ TTL enabled on ${SESSIONS_TABLE}" || echo "⚠️  TTL already enabled on ${SESSIONS_TABLE}"

# Create S3 bucket for enriched events
ENRICHED_BUCKET="evothesis-analytics-v2-enriched-${ENVIRONMENT}"
echo ""
echo "Creating enriched events bucket: ${ENRICHED_BUCKET}"

if aws s3 ls "s3://${ENRICHED_BUCKET}" >/dev/null 2>&1; then
    echo "✅ Bucket ${ENRICHED_BUCKET} already exists"
else
    aws s3 mb "s3://${ENRICHED_BUCKET}" --region "${AWS_REGION}"
    echo "✅ Created bucket ${ENRICHED_BUCKET}"
fi

# Configure bucket lifecycle policy for enriched events
echo "Configuring lifecycle policy for enriched events bucket..."

cat > /tmp/enriched-lifecycle.json << EOF
{
    "Rules": [
        {
            "ID": "EnrichedEventsLifecycle",
            "Status": "Enabled",
            "Filter": {
                "Prefix": "enriched-events/"
            },
            "Transitions": [
                {
                    "Days": 30,
                    "StorageClass": "STANDARD_IA"
                },
                {
                    "Days": 90,
                    "StorageClass": "GLACIER"
                },
                {
                    "Days": 365,
                    "StorageClass": "DEEP_ARCHIVE"
                }
            ]
        }
    ]
}
EOF

aws s3api put-bucket-lifecycle-configuration \
    --bucket "${ENRICHED_BUCKET}" \
    --lifecycle-configuration file:///tmp/enriched-lifecycle.json \
    --region "${AWS_REGION}"

# Configure bucket policy for security
cat > /tmp/enriched-bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "DenyInsecureConnections",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:*",
            "Resource": [
                "arn:aws:s3:::${ENRICHED_BUCKET}",
                "arn:aws:s3:::${ENRICHED_BUCKET}/*"
            ],
            "Condition": {
                "Bool": {
                    "aws:SecureTransport": "false"
                }
            }
        }
    ]
}
EOF

aws s3api put-bucket-policy \
    --bucket "${ENRICHED_BUCKET}" \
    --policy file:///tmp/enriched-bucket-policy.json \
    --region "${AWS_REGION}"

# Enable bucket encryption
aws s3api put-bucket-encryption \
    --bucket "${ENRICHED_BUCKET}" \
    --server-side-encryption-configuration \
        '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' \
    --region "${AWS_REGION}"

# Block public access
aws s3api put-public-access-block \
    --bucket "${ENRICHED_BUCKET}" \
    --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
    --region "${AWS_REGION}"

# Add bucket tags
aws s3api put-bucket-tagging \
    --bucket "${ENRICHED_BUCKET}" \
    --tagging \
        'TagSet=[{Key=Project,Value=evothesis-analytics},{Key=Environment,Value='${ENVIRONMENT}'},{Key=Component,Value=enriched-storage}]' \
    --region "${AWS_REGION}"

# Clean up temporary files
rm -f /tmp/enriched-lifecycle.json /tmp/enriched-bucket-policy.json

echo ""
echo "✅ Identity resolution infrastructure setup complete!"
echo ""
echo "Created resources:"
echo "  • DynamoDB Tables:"
echo "    - ${IDENTITIES_TABLE} (device fingerprint → identity mapping)"
echo "    - ${SESSIONS_TABLE} (session tracking by identity)"
echo "  • S3 Bucket:"
echo "    - ${ENRICHED_BUCKET} (enriched event storage)"
echo ""

# Verify tables are actually active
echo "🔍 Final verification:"
IDENTITIES_STATUS=$(aws dynamodb describe-table --table-name "${IDENTITIES_TABLE}" --query 'Table.TableStatus' --output text --region "${AWS_REGION}")
SESSIONS_STATUS=$(aws dynamodb describe-table --table-name "${SESSIONS_TABLE}" --query 'Table.TableStatus' --output text --region "${AWS_REGION}")

echo "  • ${IDENTITIES_TABLE}: ${IDENTITIES_STATUS}"
echo "  • ${SESSIONS_TABLE}: ${SESSIONS_STATUS}"

if [ "$IDENTITIES_STATUS" = "ACTIVE" ] && [ "$SESSIONS_STATUS" = "ACTIVE" ]; then
    echo "  ✅ All tables are active and ready!"
else
    echo "  ⚠️  Some tables are not active yet. Check AWS Console."
fi

echo ""
echo "Table ARNs:"
aws dynamodb describe-table --table-name "${IDENTITIES_TABLE}" --query 'Table.TableArn' --output text --region "${AWS_REGION}"
aws dynamodb describe-table --table-name "${SESSIONS_TABLE}" --query 'Table.TableArn' --output text --region "${AWS_REGION}"