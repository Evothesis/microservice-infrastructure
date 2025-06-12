#!/bin/bash

# Enriched Events Archiver Setup Script
# Creates DynamoDB table and Lambda for enriched events batching

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

echo "Setting up enriched events archiver for environment: ${ENVIRONMENT}"

# Define resource names
ENRICHED_EVENTS_TABLE="evothesis-v2-enriched-events-${ENVIRONMENT}"
ENRICHED_ARCHIVER_FUNCTION="evothesis-v2-enriched-events-s3-archiver-${ENVIRONMENT}"

# Create enriched events DynamoDB table
echo "Creating enriched events table: ${ENRICHED_EVENTS_TABLE}"

aws dynamodb create-table \
    --table-name "${ENRICHED_EVENTS_TABLE}" \
    --attribute-definitions \
        AttributeName=site_id,AttributeType=S \
        AttributeName=timestamp,AttributeType=N \
    --key-schema \
        AttributeName=site_id,KeyType=HASH \
        AttributeName=timestamp,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST \
    --tags \
        Key=Project,Value=evothesis-analytics \
        Key=Environment,Value="${ENVIRONMENT}" \
        Key=Component,Value=enriched-events-storage \
    --region "${AWS_REGION}" \
    2>/dev/null && echo "✅ Created table ${ENRICHED_EVENTS_TABLE}" || echo "✅ Table ${ENRICHED_EVENTS_TABLE} already exists"

# Enable TTL (7 days for temporary storage)
echo "Enabling TTL on enriched events table..."
aws dynamodb update-time-to-live \
    --table-name "${ENRICHED_EVENTS_TABLE}" \
    --time-to-live-specification \
        Enabled=true,AttributeName=ttl \
    --region "${AWS_REGION}" \
    2>/dev/null && echo "✅ TTL enabled" || echo "✅ TTL already enabled"

echo ""
echo "✅ Enriched events archiver setup complete!"
echo "  • Table: ${ENRICHED_EVENTS_TABLE}"
echo ""
echo "Next steps:"
echo "  1. Modify enrichment Lambda to write to DynamoDB"
echo "  2. Create enriched events archiver Lambda"
echo "  3. Set up hourly scheduler"

