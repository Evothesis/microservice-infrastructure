#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
source "$SCRIPT_DIR/../configs/common.env"
source "$SCRIPT_DIR/../configs/${ENVIRONMENT}.env"

echo "🔧 Setting up IAM roles for $ENVIRONMENT..."

# Lambda execution role
LAMBDA_ROLE_NAME="${PROJECT_NAME}-lambda-role-${ENVIRONMENT}"

# Check if role exists
if aws iam get-role --role-name "$LAMBDA_ROLE_NAME" &>/dev/null; then
    echo "  ✅ Lambda role $LAMBDA_ROLE_NAME already exists"
else
    echo "  🔧 Creating Lambda execution role..."
    
    # Trust policy for Lambda
    cat > /tmp/lambda-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    aws iam create-role \
        --role-name "$LAMBDA_ROLE_NAME" \
        --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
        --tags Key=Environment,Value="$ENVIRONMENT" Key=Project,Value="$PROJECT_NAME"

    # Attach basic Lambda execution policy
    aws iam attach-role-policy \
        --role-name "$LAMBDA_ROLE_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"

    echo "  ✅ Lambda role created: $LAMBDA_ROLE_NAME"
fi

# Create custom policy for DynamoDB and S3 access
POLICY_NAME="${PROJECT_NAME}-lambda-policy-${ENVIRONMENT}"

if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}" &>/dev/null; then
    echo "  ✅ Custom policy $POLICY_NAME already exists"
else
    echo "  🔧 Creating custom Lambda policy..."
    
    cat > /tmp/lambda-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:UpdateItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:Scan"
      ],
      "Resource": [
        "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${DYNAMODB_TABLE_PREFIX}-*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET_PREFIX}-*/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${S3_BUCKET_PREFIX}-*"
      ]
    }
  ]
}
EOF

    aws iam create-policy \
        --policy-name "$POLICY_NAME" \
        --policy-document file:///tmp/lambda-policy.json \
        --tags Key=Environment,Value="$ENVIRONMENT" Key=Project,Value="$PROJECT_NAME"

    echo "  ✅ Custom policy created: $POLICY_NAME"
fi

# Attach custom policy to Lambda role
aws iam attach-role-policy \
    --role-name "$LAMBDA_ROLE_NAME" \
    --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"

# Store role ARN for other scripts
LAMBDA_ROLE_ARN=$(aws iam get-role --role-name "$LAMBDA_ROLE_NAME" --query 'Role.Arn' --output text)
echo "export LAMBDA_ROLE_ARN='$LAMBDA_ROLE_ARN'" > "/tmp/${PROJECT_NAME}-${ENVIRONMENT}-iam.env"

echo "✅ IAM setup complete for $ENVIRONMENT"