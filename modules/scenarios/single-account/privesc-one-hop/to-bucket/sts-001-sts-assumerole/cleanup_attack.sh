#!/bin/bash

# Cleanup script for sts:AssumeRole to S3 bucket access demo
# This script removes temporary files and test objects created during the demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}STS AssumeRole Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Disable paging for AWS CLI
export AWS_PAGER=""

# Navigate to the Terraform root directory (6 levels up from scenario directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

echo "🔍 Retrieving admin credentials from Terraform outputs..."
cd "$TERRAFORM_ROOT"

# Get admin credentials from Terraform outputs
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

if [ -z "$ADMIN_ACCESS_KEY" ] || [ -z "$ADMIN_SECRET_KEY" ]; then
    echo -e "${RED}❌ Error: Could not retrieve admin credentials from Terraform outputs.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Retrieved admin credentials from Terraform${NC}"

# Set environment variables for admin user
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_DEFAULT_REGION="us-west-2"

# Step 1: Get account ID and bucket name
echo -e "${YELLOW}Step 1: Getting account ID and bucket information${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"

# Get bucket name from Terraform outputs
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_sts_001_sts_assumerole.value // empty')
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.target_bucket_name')
echo "Target bucket: $BUCKET_NAME"
echo -e "${GREEN}✓ Retrieved account information${NC}\n"

# Step 2: Remove local temporary files
echo -e "${YELLOW}Step 2: Removing local temporary files${NC}"
DOWNLOAD_FILE="/tmp/sensitive-data-${ACCOUNT_ID}.txt"
TEST_FILE="/tmp/test-write-${ACCOUNT_ID}.txt"

if [ -f "$DOWNLOAD_FILE" ]; then
    rm -f "$DOWNLOAD_FILE"
    echo -e "${GREEN}✓ Deleted $DOWNLOAD_FILE${NC}"
else
    echo "No downloaded file found at $DOWNLOAD_FILE"
fi

if [ -f "$TEST_FILE" ]; then
    rm -f "$TEST_FILE"
    echo -e "${GREEN}✓ Deleted $TEST_FILE${NC}"
else
    echo "No test file found at $TEST_FILE"
fi
echo ""

# Step 3: Clean up S3 test objects using admin credentials
echo -e "${YELLOW}Step 3: Cleaning up S3 test objects${NC}"
echo "Using admin credentials to clean up bucket objects"
echo -e "${GREEN}✓ Ready to clean up S3 objects${NC}\n"

# Step 4: Verify bucket exists
echo -e "${YELLOW}Step 4: Verifying target bucket${NC}"
echo "Target bucket: $BUCKET_NAME"

if [ -z "$BUCKET_NAME" ] || [ "$BUCKET_NAME" == "null" ]; then
    echo -e "${RED}Error: Could not find target bucket${NC}"
    exit 1
fi

echo "Target bucket: $BUCKET_NAME"
echo -e "${GREEN}✓ Found target bucket${NC}\n"

# Step 5: Remove test file from S3
echo -e "${YELLOW}Step 5: Removing test objects from S3 bucket${NC}"
if aws s3 ls s3://$BUCKET_NAME/demo-test-file.txt 2>/dev/null; then
    aws s3 rm s3://$BUCKET_NAME/demo-test-file.txt
    echo -e "${GREEN}✓ Deleted demo-test-file.txt from bucket${NC}"
else
    echo "No demo-test-file.txt found in bucket"
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}All temporary files and test objects have been removed${NC}"
echo -e "${YELLOW}The infrastructure (bucket, role, sensitive-data.txt) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
