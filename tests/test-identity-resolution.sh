#!/bin/bash

# Identity Resolution Testing Script
# Tests the complete enrichment pipeline with realistic data

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
source "${SCRIPT_DIR}/../deploy/configs/common.env"
source "${SCRIPT_DIR}/../deploy/configs/${ENVIRONMENT}.env"

echo "🧪 Testing Identity Resolution Pipeline for ${ENVIRONMENT}"
echo "=================================================="

# Get API Gateway URL from existing deployment
API_ID=$(aws apigateway get-rest-apis \
    --query "items[?name=='evothesis-analytics-api-v2-${ENVIRONMENT}'].id" \
    --output text \
    --region "${AWS_REGION}")

if [ -z "$API_ID" ]; then
    echo "❌ API Gateway not found. Please deploy the main infrastructure first."
    exit 1
fi

ENDPOINT="https://${API_ID}.execute-api.${AWS_REGION}.amazonaws.com/${ENVIRONMENT}/collect"
echo "📡 API Endpoint: ${ENDPOINT}"

# Test data for different identity scenarios
echo ""
echo "🔍 Test Scenario 1: New Visitor - Desktop Chrome"
echo "------------------------------------------------"

VISITOR_1_SESSION_1="sess_$(openssl rand -hex 8)"
VISITOR_1_ID="vis_$(openssl rand -hex 8)"

# Pageview event
echo "📄 Sending pageview event..."
curl -s -X POST "${ENDPOINT}" \
    -H "Content-Type: application/json" \
    -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
    -d "{
        \"eventType\": \"pageview\",
        \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",
        \"sessionId\": \"${VISITOR_1_SESSION_1}\",
        \"visitorId\": \"${VISITOR_1_ID}\",
        \"siteId\": \"test-site-com\",
        \"url\": \"https://test-site.com/products/widget\",
        \"path\": \"/products/widget\",
        \"page\": {
            \"title\": \"Amazing Widget - Product Page\",
            \"referrer\": \"https://google.com/search?q=widget\",
            \"queryParams\": \"?utm_source=google&utm_medium=cpc&utm_campaign=summer-sale\",
            \"hash\": \"\"
        },
        \"attribution\": {
            \"firstTouch\": {
                \"source\": \"google\",
                \"medium\": \"cpc\",
                \"campaign\": \"summer-sale\",
                \"category\": \"paid_search\",
                \"utmParams\": {
                    \"utm_source\": \"google\",
                    \"utm_medium\": \"cpc\",
                    \"utm_campaign\": \"summer-sale\",
                    \"utm_content\": \"widget-ad\",
                    \"utm_term\": \"best-widget\"
                }
            },
            \"currentTouch\": {
                \"source\": \"google\",
                \"medium\": \"cpc\",
                \"category\": \"paid_search\"
            },
            \"touchCount\": 1
        },
        \"browser\": {
            \"userAgent\": \"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36\",
            \"language\": \"en-US\",
            \"screenWidth\": 1920,
            \"screenHeight\": 1080,
            \"viewportWidth\": 1440,
            \"viewportHeight\": 900,
            \"devicePixelRatio\": 2,
            \"timezone\": \"America/Los_Angeles\"
        },
        \"scroll\": {
            \"maxScrollPercentage\": 0,
            \"milestonesReached\": []
        }
    }"

echo "✅ Sent pageview event for new visitor (Desktop Chrome)"

# Wait for processing
echo "⏳ Waiting 5 seconds for enrichment processing..."
sleep 5

# Batch events for same visitor
echo ""
echo "🔍 Test Scenario 2: Same Visitor - Interaction Events"
echo "---------------------------------------------------"

echo "📊 Sending batch interaction events..."
curl -s -X POST "${ENDPOINT}" \
    -H "Content-Type: application/json" \
    -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
    -d "{
        \"eventType\": \"batch\",
        \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",
        \"sessionId\": \"${VISITOR_1_SESSION_1}\",
        \"visitorId\": \"${VISITOR_1_ID}\",
        \"siteId\": \"test-site-com\",
        \"batchMetadata\": {
            \"eventCount\": 3,
            \"batchStartTime\": \"$(date -u -v-30S +%Y-%m-%dT%H:%M:%S.000Z)\",
            \"batchEndTime\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",
            \"activityDuration\": 30000,
            \"sentOnExit\": false
        },
        \"events\": [
            {
                \"eventType\": \"click\",
                \"timestamp\": \"$(date -u -v-25S +%Y-%m-%dT%H:%M:%S.000Z)\",
                \"eventData\": {
                    \"tagName\": \"button\",
                    \"classes\": \"btn btn-primary add-to-cart\",
                    \"id\": \"add-cart-btn\",
                    \"text\": \"Add to Cart\",
                    \"href\": \"\",
                    \"position\": {\"x\": 456, \"y\": 234}
                }
            },
            {
                \"eventType\": \"scroll\",
                \"timestamp\": \"$(date -u -v-15S +%Y-%m-%dT%H:%M:%S.000Z)\",
                \"eventData\": {
                    \"scrollPercentage\": 65,
                    \"scrollTop\": 1200,
                    \"documentHeight\": 2400,
                    \"windowHeight\": 900
                }
            },
            {
                \"eventType\": \"scroll_depth\",
                \"timestamp\": \"$(date -u -v-5S +%Y-%m-%dT%H:%M:%S.000Z)\",
                \"eventData\": {
                    \"milestone\": 75,
                    \"timeToMilestone\": 55000,
                    \"scrollPercentage\": 76,
                    \"scrollTop\": 1450,
                    \"documentHeight\": 2400,
                    \"windowHeight\": 900
                }
            }
        ]
    }"

echo "✅ Sent batch events for same visitor"

# Wait for processing
echo "⏳ Waiting 5 seconds for enrichment processing..."
sleep 5

# Test Scenario 3: Same visitor, new session (return visit)
echo ""
echo "🔍 Test Scenario 3: Return Visitor - New Session"
echo "-----------------------------------------------"

VISITOR_1_SESSION_2="sess_$(openssl rand -hex 8)"

echo "📄 Sending return visit pageview..."
curl -s -X POST "${ENDPOINT}" \
    -H "Content-Type: application/json" \
    -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
    -d "{
        \"eventType\": \"pageview\",
        \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",
        \"sessionId\": \"${VISITOR_1_SESSION_2}\",
        \"visitorId\": \"${VISITOR_1_ID}\",
        \"siteId\": \"test-site-com\",
        \"url\": \"https://test-site.com/\",
        \"path\": \"/\",
        \"page\": {
            \"title\": \"Test Site - Homepage\",
            \"referrer\": \"direct\",
            \"queryParams\": \"\",
            \"hash\": \"\"
        },
        \"attribution\": {
            \"firstTouch\": {
                \"source\": \"google\",
                \"medium\": \"cpc\",
                \"campaign\": \"summer-sale\",
                \"category\": \"paid_search\"
            },
            \"currentTouch\": {
                \"source\": \"direct\",
                \"medium\": \"none\",
                \"category\": \"direct\"
            },
            \"touchCount\": 2
        },
        \"browser\": {
            \"userAgent\": \"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36\",
            \"language\": \"en-US\",
            \"screenWidth\": 1920,
            \"screenHeight\": 1080,
            \"viewportWidth\": 1440,
            \"viewportHeight\": 900,
            \"devicePixelRatio\": 2,
            \"timezone\": \"America/Los_Angeles\"
        }
    }"

echo "✅ Sent return visit pageview"

# Wait for processing
echo "⏳ Waiting 5 seconds for enrichment processing..."
sleep 5

# Test Scenario 4: Different device, same household (mobile)
echo ""
echo "🔍 Test Scenario 4: Different Device - Same Household (Mobile)"
echo "------------------------------------------------------------"

VISITOR_2_SESSION_1="sess_$(openssl rand -hex 8)"
VISITOR_2_ID="vis_$(openssl rand -hex 8)"

echo "📱 Sending mobile device pageview..."
curl -s -X POST "${ENDPOINT}" \
    -H "Content-Type: application/json" \
    -H "User-Agent: Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" \
    -d "{
        \"eventType\": \"pageview\",
        \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\",
        \"sessionId\": \"${VISITOR_2_SESSION_1}\",
        \"visitorId\": \"${VISITOR_2_ID}\",
        \"siteId\": \"test-site-com\",
        \"url\": \"https://test-site.com/products/widget\",
        \"path\": \"/products/widget\",
        \"page\": {
            \"title\": \"Amazing Widget - Product Page\",
            \"referrer\": \"https://facebook.com\",
            \"queryParams\": \"?utm_source=facebook&utm_medium=social\",
            \"hash\": \"\"
        },
        \"attribution\": {
            \"firstTouch\": {
                \"source\": \"facebook\",
                \"medium\": \"social\",
                \"category\": \"organic_social\",
                \"utmParams\": {
                    \"utm_source\": \"facebook\",
                    \"utm_medium\": \"social\"
                }
            },
            \"currentTouch\": {
                \"source\": \"facebook\",
                \"medium\": \"social\",
                \"category\": \"organic_social\"
            },
            \"touchCount\": 1
        },
        \"browser\": {
            \"userAgent\": \"Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1\",
            \"language\": \"en-US\",
            \"screenWidth\": 390,
            \"screenHeight\": 844,
            \"viewportWidth\": 390,
            \"viewportHeight\": 664,
            \"devicePixelRatio\": 3,
            \"timezone\": \"America/Los_Angeles\"
        }
    }"

echo "✅ Sent mobile device pageview"

# Wait for final processing
echo "⏳ Waiting 10 seconds for final enrichment processing..."
sleep 10

# Verification phase
echo ""
echo "🔍 Pipeline Verification"
echo "========================"

# Check raw events in DynamoDB
echo ""
echo "1️⃣ Checking raw events in DynamoDB..."
RAW_EVENTS_COUNT=$(aws dynamodb scan \
    --table-name "evothesis-v2-raw-events-${ENVIRONMENT}" \
    --select COUNT \
    --query 'Count' \
    --output text \
    --region "${AWS_REGION}")

echo "   📊 Raw events in DynamoDB: ${RAW_EVENTS_COUNT}"

# Check identity records
echo ""
echo "2️⃣ Checking identity resolution results..."
IDENTITY_COUNT=$(aws dynamodb scan \
    --table-name "evothesis-v2-identities-${ENVIRONMENT}" \
    --select COUNT \
    --query 'Count' \
    --output text \
    --region "${AWS_REGION}" 2>/dev/null || echo "0")

echo "   👤 Identity records created: ${IDENTITY_COUNT}"

if [ "$IDENTITY_COUNT" -gt "0" ]; then
    echo "   🔍 Sample identity record:"
    aws dynamodb scan \
        --table-name "evothesis-v2-identities-${ENVIRONMENT}" \
        --limit 1 \
        --query 'Items[0]' \
        --region "${AWS_REGION}" 2>/dev/null || echo "   ❌ Error retrieving identity record"
fi

# Check session records
echo ""
echo "3️⃣ Checking session tracking..."
SESSION_COUNT=$(aws dynamodb scan \
    --table-name "evothesis-v2-sessions-${ENVIRONMENT}" \
    --select COUNT \
    --query 'Count' \
    --output text \
    --region "${AWS_REGION}" 2>/dev/null || echo "0")

echo "   📝 Session records created: ${SESSION_COUNT}"

# Check enriched events in S3
echo ""
echo "4️⃣ Checking enriched events in S3..."
S3_OBJECTS=$(aws s3 ls "s3://evothesis-analytics-v2-enriched-${ENVIRONMENT}/enriched-events/" \
    --recursive \
    --region "${AWS_REGION}" 2>/dev/null | wc -l || echo "0")

echo "   📦 Enriched event files in S3: ${S3_OBJECTS}"

if [ "$S3_OBJECTS" -gt "0" ]; then
    echo "   📂 Sample S3 files:"
    aws s3 ls "s3://evothesis-analytics-v2-enriched-${ENVIRONMENT}/enriched-events/" \
        --recursive \
        --region "${AWS_REGION}" 2>/dev/null | head -3 || echo "   ❌ Error listing S3 files"
fi

# Check enrichment Lambda logs
echo ""
echo "5️⃣ Checking enrichment Lambda execution..."
LAMBDA_LOG_STREAMS=$(aws logs describe-log-streams \
    --log-group-name "/aws/lambda/evothesis-v2-enrichment-${ENVIRONMENT}" \
    --order-by LastEventTime \
    --descending \
    --max-items 1 \
    --query 'logStreams[0].logStreamName' \
    --output text \
    --region "${AWS_REGION}" 2>/dev/null || echo "")

if [ -n "$LAMBDA_LOG_STREAMS" ] && [ "$LAMBDA_LOG_STREAMS" != "None" ]; then
    echo "   ⚡ Recent Lambda executions found"
    echo "   📋 Latest log entries:"
    aws logs get-log-events \
        --log-group-name "/aws/lambda/evothesis-v2-enrichment-${ENVIRONMENT}" \
        --log-stream-name "$LAMBDA_LOG_STREAMS" \
        --limit 5 \
        --query 'events[*].message' \
        --output text \
        --region "${AWS_REGION}" 2>/dev/null || echo "   ❌ Error retrieving logs"
else
    echo "   ❌ No recent Lambda executions found"
fi

# Summary
echo ""
echo "📊 Test Results Summary"
echo "======================"

# Determine overall status
TOTAL_ISSUES=0

if [ "$RAW_EVENTS_COUNT" -lt "4" ]; then
    echo "❌ Issue: Expected at least 4 raw events, found ${RAW_EVENTS_COUNT}"
    ((TOTAL_ISSUES++))
else
    echo "✅ Raw event collection: WORKING"
fi

if [ "$IDENTITY_COUNT" -lt "1" ]; then
    echo "❌ Issue: No identity records found - enrichment may not be working"
    ((TOTAL_ISSUES++))
else
    echo "✅ Identity resolution: WORKING"
fi

if [ "$SESSION_COUNT" -lt "1" ]; then
    echo "❌ Issue: No session records found - session tracking may not be working"
    ((TOTAL_ISSUES++))
else
    echo "✅ Session tracking: WORKING"
fi

if [ "$S3_OBJECTS" -lt "1" ]; then
    echo "❌ Issue: No enriched events in S3 - enrichment pipeline may not be working"
    ((TOTAL_ISSUES++))
else
    echo "✅ S3 enriched storage: WORKING"
fi

if [ -z "$LAMBDA_LOG_STREAMS" ] || [ "$LAMBDA_LOG_STREAMS" = "None" ]; then
    echo "❌ Issue: No Lambda execution logs found - enrichment function may not be triggered"
    ((TOTAL_ISSUES++))
else
    echo "✅ Enrichment Lambda execution: WORKING"
fi

echo ""
if [ "$TOTAL_ISSUES" -eq "0" ]; then
    echo "🎉 ALL TESTS PASSED! Identity resolution pipeline is working correctly."
    echo ""
    echo "🔗 Next steps:"
    echo "  1. Set up CSV export automation"
    echo "  2. Configure Retool dashboard"
    echo "  3. Test with production traffic"
    echo "  4. Set up monitoring and alerts"
else
    echo "⚠️  Found ${TOTAL_ISSUES} issues. Check the individual results above."
    echo ""
    echo "🔧 Debugging commands:"
    echo "  • Check Lambda logs: aws logs tail /aws/lambda/evothesis-v2-enrichment-${ENVIRONMENT} --follow"
    echo "  • Check DynamoDB streams: aws dynamodb describe-table --table-name evothesis-v2-raw-events-${ENVIRONMENT}"
    echo "  • Manual Lambda test: aws lambda invoke --function-name evothesis-v2-enrichment-${ENVIRONMENT} --payload '{}' response.json"
fi

echo ""
echo "🔍 Manual verification commands:"
echo "  aws dynamodb scan --table-name evothesis-v2-identities-${ENVIRONMENT} --limit 5"
echo "  aws s3 ls s3://evothesis-analytics-v2-enriched-${ENVIRONMENT}/enriched-events/ --recursive"
echo "  aws logs tail /aws/lambda/evothesis-v2-enrichment-${ENVIRONMENT} --since 10m"