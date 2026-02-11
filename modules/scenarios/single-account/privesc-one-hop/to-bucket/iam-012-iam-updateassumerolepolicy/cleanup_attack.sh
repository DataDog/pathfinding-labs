#!/bin/bash

# Cleanup script for iam:UpdateAssumeRolePolicy to S3 bucket demo
# This script restores the original trust policy on the target role

set -e

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
TARGET_ROLE="pl-prod-iam-012-to-bucket-target-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM UpdateAssumeRolePolicy Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials from Terraform output
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

# Get admin cleanup user credentials from root terraform output
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    echo "Make sure the admin cleanup user is deployed"
    exit 1
fi

# Get account ID from terraform output
ACCOUNT_ID=$(terraform output -raw prod_account_id 2>/dev/null)

# Set admin credentials
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
unset AWS_SESSION_TOKEN

echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

cd - > /dev/null  # Return to scenario directory

# Step 2: Verify admin identity
echo -e "${YELLOW}Step 2: Verifying admin identity${NC}"
ADMIN_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ADMIN_IDENTITY"
echo -e "${GREEN}✓ Verified admin identity${NC}\n"

# Step 3: Restore original trust policy (only root)
echo -e "${YELLOW}Step 3: Restoring original trust policy on $TARGET_ROLE${NC}"
echo "Setting trust policy to only allow root principal..."

# Check if we saved the original trust policy
if [ -f "/tmp/original_trust_policy_iam_012_bucket.json" ]; then
    echo "Using saved original trust policy..."
    ORIGINAL_TRUST_POLICY=$(cat /tmp/original_trust_policy_iam_012_bucket.json)
else
    echo "Creating default trust policy (root only)..."
    ORIGINAL_TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${ACCOUNT_ID}:root"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)
fi

aws iam update-assume-role-policy \
    --role-name $TARGET_ROLE \
    --policy-document "$ORIGINAL_TRUST_POLICY"

echo -e "${GREEN}✓ Restored original trust policy${NC}\n"

# Step 4: Remove local temporary files
echo -e "${YELLOW}Step 4: Removing local temporary files${NC}"
DOWNLOAD_FILE="/tmp/iam-012-sensitive-data.txt"
SAVED_POLICY="/tmp/original_trust_policy_iam_012_bucket.json"

if [ -f "$DOWNLOAD_FILE" ]; then
    rm -f "$DOWNLOAD_FILE"
    echo -e "${GREEN}✓ Deleted $DOWNLOAD_FILE${NC}"
else
    echo -e "${YELLOW}No downloaded file found at $DOWNLOAD_FILE${NC}"
fi

if [ -f "$SAVED_POLICY" ]; then
    rm -f "$SAVED_POLICY"
    echo -e "${GREEN}✓ Deleted $SAVED_POLICY${NC}"
fi

echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}The target role trust policy has been restored${NC}"
echo -e "${YELLOW}The infrastructure (bucket, roles, sensitive-data.txt) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
