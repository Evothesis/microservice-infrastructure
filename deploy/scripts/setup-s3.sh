#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load configuration
source "$SCRIPT_DIR/../configs/common.env"
source "$SCRIPT_DIR/../configs/${ENVIRONMENT}.env"

echo "🪣 Setting up S3 buckets for $ENVIRONMENT..."

# Function to create bucket with proper configuration
create_bucket() {
    local bucket_name=$1
    local bucket_purpose=$2
    
    if aws s3api head-bucket --bucket "$bucket_name" &>/dev/null; then
        echo "  ✅ Bucket $bucket_name already exists"
    else
        echo "  🔧 Creating $bucket_purpose bucket: $bucket_name"
        
        # Create bucket (us-west-1 requires location constraint)
        aws s3api create-bucket \
            --bucket "$bucket_name" \
            --region "$AWS_REGION" \
            --create-bucket-configuration LocationConstraint="$AWS_REGION"
        
        # Block public access
        aws s3api put-public-access-block \
            --bucket "$bucket_name" \
            --public-access-block-configuration \
                BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
        
        # Add tags
        aws s3api put-bucket-tagging \
            --bucket "$bucket_name" \
            --tagging "TagSet=[{Key=Environment,Value=$ENVIRONMENT},{Key=Project,Value=$PROJECT_NAME},{Key=Purpose,Value=$bucket_purpose}]"
        
        # Enable versioning for data protection
        aws s3api put-bucket-versioning \
            --bucket "$bucket_name" \
            --versioning-configuration Status=Enabled
        
        # Set lifecycle policy for cost optimization
        cat > /tmp/lifecycle-policy.json << EOF
{
  "Rules": [
    {
      "ID": "ArchiveOldVersions",
      "Status": "Enabled",
      "Filter": {},
      "Transitions": [
        {
          "Days": 30,
          "StorageClass": "STANDARD_IA"
        },
        {
          "Days": 90,
          "StorageClass": "GLACIER"
        }
      ],
      "NoncurrentVersionTransitions": [
        {
          "NoncurrentDays": 30,
          "StorageClass": "STANDARD_IA"
        }
      ],
      "NoncurrentVersionExpiration": {
        "NoncurrentDays": 365
      }
    }
  ]
}
EOF
        
        aws s3api put-bucket-lifecycle-configuration \
            --bucket "$bucket_name" \
            --lifecycle-configuration file:///tmp/lifecycle-policy.json
        
        echo "  ✅ Bucket created: $bucket_name"
    fi
}

# Create buckets
create_bucket "$S3_ARCHIVE_BUCKET" "archive"
create_bucket "$S3_EXPORT_BUCKET" "export"
create_bucket "$S3_INTERNAL_BUCKET" "internal"

# Set up CORS for internal bucket (for Retool access)
echo "  🔧 Setting up CORS for internal bucket..."
cat > /tmp/cors-policy.json << EOF
{
  "CORSRules": [
    {
      "AllowedHeaders": ["*"],
      "AllowedMethods": ["GET", "PUT", "POST", "DELETE", "HEAD"],
      "AllowedOrigins": ["*"],
      "ExposeHeaders": ["ETag"],
      "MaxAgeSeconds": 3000
    }
  ]
}
EOF

aws s3api put-bucket-cors \
    --bucket "$S3_INTERNAL_BUCKET" \
    --cors-configuration file:///tmp/cors-policy.json

# Store bucket names for other scripts
cat > "/tmp/${PROJECT_NAME}-${ENVIRONMENT}-s3.env" << EOF
export S3_ARCHIVE_BUCKET='$S3_ARCHIVE_BUCKET'
export S3_EXPORT_BUCKET='$S3_EXPORT_BUCKET'
export S3_INTERNAL_BUCKET='$S3_INTERNAL_BUCKET'
EOF

echo "✅ S3 setup complete for $ENVIRONMENT"