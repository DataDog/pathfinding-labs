#!/bin/bash

# Demo script for test-reverse-blast-radius-direct-and-indirect-to-bucket
# This scenario demonstrates two distinct access paths to the same S3 bucket:
# Path 1: user1 → (direct S3 access) → bucket
# Path 2: user2 → (sts:AssumeRole) → role3 → (S3 access) → bucket
#
# This is designed to test reverse blast radius queries in security tools:
# "Which principals have access to this sensitive bucket?"

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Reverse Blast Radius Test Demo${NC}"
echo -e "${GREEN}Direct and Indirect S3 Access Paths${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo "This scenario demonstrates two distinct paths to access a sensitive S3 bucket:"
echo "  Path 1 (Direct):   user1 → S3 bucket"
echo "  Path 2 (Indirect): user2 → role3 → S3 bucket"
echo ""
echo "A properly configured security tool should detect BOTH principals"
echo "when performing a reverse blast radius query on the bucket."
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed or not in PATH${NC}"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed or not in PATH${NC}"
    echo "Please install jq to parse JSON outputs"
    exit 1
fi

# Navigate to the Terraform root directory (4 levels up from scenario directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Step 1: Retrieve credentials and configuration from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd "$TERRAFORM_ROOT"

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_reverse_blast_radius_direct_and_indirect_to_bucket.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials and resource information
USER1_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.user1_access_key_id')
USER1_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.user1_secret_access_key')
USER1_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.user1_name')

USER2_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.user2_access_key_id')
USER2_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.user2_secret_access_key')
USER2_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.user2_name')

ROLE3_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.role3_arn')
ROLE3_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.role3_name')

BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_name')

if [ "$USER1_ACCESS_KEY_ID" == "null" ] || [ -z "$USER1_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

# Get region from Terraform
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved credentials for:"
echo "  - User 1: $USER1_NAME"
echo "  - User 2: $USER2_NAME"
echo "  - Role 3: $ROLE3_NAME"
echo "  - Bucket: $BUCKET_NAME"
echo "  - Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Get account ID (we'll use user1's credentials initially)
export AWS_ACCESS_KEY_ID=$USER1_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$USER1_SECRET_ACCESS_KEY
export AWS_REGION=$AWS_REGION
unset AWS_SESSION_TOKEN

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}PATH 1: Direct S3 Access (user1)${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Step 2: Verify user1 identity
echo -e "${YELLOW}Step 2: Verifying user1 identity${NC}"
export AWS_ACCESS_KEY_ID=$USER1_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$USER1_SECRET_ACCESS_KEY
export AWS_REGION=$AWS_REGION
unset AWS_SESSION_TOKEN

CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$USER1_NAME"* ]]; then
    echo -e "${RED}Error: Not running as $USER1_NAME${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified user1 identity${NC}\n"

# Step 3: List S3 buckets with user1
echo -e "${YELLOW}Step 3: Listing S3 buckets with user1 (direct access)${NC}"
echo "Attempting to list all S3 buckets..."

if aws s3 ls 2>/dev/null | head -5; then
    echo -e "${GREEN}✓ Successfully listed buckets${NC}"
else
    echo -e "${YELLOW}Note: Could not list all buckets (may not have s3:ListAllMyBuckets)${NC}"
fi
echo ""

# Step 4: Access the sensitive bucket directly with user1
echo -e "${YELLOW}Step 4: Accessing sensitive bucket with user1 (direct access)${NC}"
echo "Bucket: $BUCKET_NAME"
echo ""

echo "Listing objects in the sensitive bucket..."
if aws s3 ls "s3://$BUCKET_NAME/" 2>/dev/null; then
    echo -e "${GREEN}✓ Successfully listed objects in bucket${NC}"
else
    echo -e "${RED}✗ Failed to list objects${NC}"
    exit 1
fi
echo ""

echo "Downloading sensitive-data.txt..."
if aws s3 cp "s3://$BUCKET_NAME/sensitive-data.txt" /tmp/sensitive-user1.txt 2>/dev/null; then
    echo -e "${GREEN}✓ Successfully downloaded file${NC}"
    echo ""
    echo "Content preview:"
    head -3 /tmp/sensitive-user1.txt
    echo ""
else
    echo -e "${RED}✗ Failed to download file${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Path 1 Complete: user1 has direct access to bucket${NC}\n"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}PATH 2: Indirect S3 Access (user2 → role3)${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Step 5: Switch to user2 and verify identity
echo -e "${YELLOW}Step 5: Switching to user2 credentials${NC}"
export AWS_ACCESS_KEY_ID=$USER2_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$USER2_SECRET_ACCESS_KEY
export AWS_REGION=$AWS_REGION
unset AWS_SESSION_TOKEN

CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$USER2_NAME"* ]]; then
    echo -e "${RED}Error: Not running as $USER2_NAME${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified user2 identity${NC}\n"

# Step 6: Verify user2 lacks direct bucket access
echo -e "${YELLOW}Step 6: Verifying user2 lacks direct bucket access${NC}"
echo "Attempting to access bucket directly (should fail)..."

if aws s3 ls "s3://$BUCKET_NAME/" 2>/dev/null; then
    echo -e "${RED}⚠ Unexpectedly have direct bucket access${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot access bucket directly (as expected)${NC}"
fi
echo ""

# Step 7: Assume role3 with user2
echo -e "${YELLOW}Step 7: Assuming role3 with user2 credentials${NC}"
echo "Role ARN: $ROLE3_ARN"

CREDENTIALS=$(aws sts assume-role \
    --role-arn $ROLE3_ARN \
    --role-session-name demo-session \
    --query 'Credentials' \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Failed to assume role${NC}"
    exit 1
fi

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')
export AWS_REGION=$AWS_REGION

# Verify we assumed the role
ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ROLE_IDENTITY"
echo -e "${GREEN}✓ Successfully assumed role3${NC}\n"

# Step 8: Access bucket with role3
echo -e "${YELLOW}Step 8: Accessing sensitive bucket with role3 (indirect access)${NC}"
echo "Bucket: $BUCKET_NAME"
echo ""

echo "Listing objects in the sensitive bucket..."
if aws s3 ls "s3://$BUCKET_NAME/" 2>/dev/null; then
    echo -e "${GREEN}✓ Successfully listed objects in bucket${NC}"
else
    echo -e "${RED}✗ Failed to list objects${NC}"
    exit 1
fi
echo ""

echo "Downloading sensitive-data.txt..."
if aws s3 cp "s3://$BUCKET_NAME/sensitive-data.txt" /tmp/sensitive-role3.txt 2>/dev/null; then
    echo -e "${GREEN}✓ Successfully downloaded file${NC}"
    echo ""
    echo "Content preview:"
    head -3 /tmp/sensitive-role3.txt
    echo ""
else
    echo -e "${RED}✗ Failed to download file${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Path 2 Complete: user2 can access bucket via role3${NC}\n"

# Final summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ DEMONSTRATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Summary of Access Paths:${NC}"
echo "1. Direct Path:"
echo "   └─ $USER1_NAME → S3 bucket"
echo ""
echo "2. Indirect Path:"
echo "   └─ $USER2_NAME → role3 → S3 bucket"
echo ""
echo -e "${YELLOW}Reverse Blast Radius Query Test:${NC}"
echo "A security tool performing a reverse blast radius query on the bucket:"
echo "  \"Which principals can access s3://$BUCKET_NAME?\""
echo ""
echo "Should detect BOTH principals:"
echo "  ✓ $USER1_NAME (direct IAM permissions)"
echo "  ✓ $USER2_NAME (indirect via role3)"
echo ""
echo -e "${YELLOW}Artifacts Created:${NC}"
echo "  - /tmp/sensitive-user1.txt (downloaded by user1)"
echo "  - /tmp/sensitive-role3.txt (downloaded by role3)"
echo ""
echo -e "${YELLOW}To clean up artifacts:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Clean up credentials from environment
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
