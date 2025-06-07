#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
source "$SCRIPT_DIR/../configs/common.env"
source "$SCRIPT_DIR/../configs/${ENVIRONMENT}.env"

echo "🗄️  Setting up DynamoDB for $ENVIRONMENT..."

# Raw events table (simplified - no GSI for now)
RAW_EVENTS_TABLE="${DYNAMODB_TABLE_PREFIX}-raw-events-${ENVIRONMENT}"

if ! aws dynamodb describe-table --table-name "$RAW_EVENTS_TABLE" &>/dev/null; then
    echo "  🔧 Creating raw events table..."
    
    aws dynamodb create-table \
        --table-name "$RAW_EVENTS_TABLE" \
        --attribute-definitions \
            AttributeName=domain_session,AttributeType=S \
            AttributeName=timestamp,AttributeType=N \
        --key-schema \
            AttributeName=domain_session,KeyType=HASH \
            AttributeName=timestamp,KeyType=RANGE \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Environment,Value="$ENVIRONMENT" Key=Project,Value="$PROJECT_NAME"

    aws dynamodb wait table-exists --table-name "$RAW_EVENTS_TABLE"
    echo "  ✅ Table created: $RAW_EVENTS_TABLE"
else
    echo "  ✅ Table $RAW_EVENTS_TABLE already exists"
fi

# Client config table
CLIENT_CONFIG_TABLE="${DYNAMODB_TABLE_PREFIX}-client-config-${ENVIRONMENT}"

if ! aws dynamodb describe-table --table-name "$CLIENT_CONFIG_TABLE" &>/dev/null; then
    echo "  🔧 Creating client configuration table..."
    
    aws dynamodb create-table \
        --table-name "$CLIENT_CONFIG_TABLE" \
        --attribute-definitions AttributeName=domain,AttributeType=S \
        --key-schema AttributeName=domain,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Environment,Value="$ENVIRONMENT" Key=Project,Value="$PROJECT_NAME"

    aws dynamodb wait table-exists --table-name "$CLIENT_CONFIG_TABLE"
    echo "  ✅ Table created: $CLIENT_CONFIG_TABLE"
else
    echo "  ✅ Table $CLIENT_CONFIG_TABLE already exists"
fi

# Store table names
cat > "/tmp/${PROJECT_NAME}-${ENVIRONMENT}-dynamodb.env" << EOF
export RAW_EVENTS_TABLE='$RAW_EVENTS_TABLE'
export CLIENT_CONFIG_TABLE='$CLIENT_CONFIG_TABLE'
EOF

echo "✅ DynamoDB setup complete for $ENVIRONMENT"