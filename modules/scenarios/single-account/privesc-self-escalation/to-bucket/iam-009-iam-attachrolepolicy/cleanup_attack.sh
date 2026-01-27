#!/bin/bash

# Cleanup script for iam:AttachRolePolicy to S3 bucket demo
# This script detaches the escalated S3 access policy from the starting role

set -e

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_ROLE="pl-prod-iam-009-to-bucket-starting-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM AttachRolePolicy Demo Cleanup${NC}"
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

# Get the bucket access policy ARN from module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_self_escalation_to_bucket_iam_009_iam_attachrolepolicy.value // empty')
BUCKET_ACCESS_POLICY_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_access_policy_arn')

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

# Step 3: Detach the escalated S3 policy
echo -e "${YELLOW}Step 3: Detaching escalated S3 policy from $STARTING_ROLE${NC}"
echo "Policy ARN: $BUCKET_ACCESS_POLICY_ARN"

# Check if the policy is attached first
if aws iam list-attached-role-policies --role-name "$STARTING_ROLE" --query "AttachedPolicies[?PolicyArn=='${BUCKET_ACCESS_POLICY_ARN}']" --output text | grep -q .; then
    aws iam detach-role-policy \
        --role-name "$STARTING_ROLE" \
        --policy-arn "$BUCKET_ACCESS_POLICY_ARN"
    echo -e "${GREEN}✓ Successfully detached escalated policy${NC}\n"
else
    echo -e "${YELLOW}Policy not found attached to $STARTING_ROLE (may have been already cleaned up)${NC}\n"
fi

# Step 4: Remove local temporary files
echo -e "${YELLOW}Step 4: Removing local temporary files${NC}"
DOWNLOAD_FILE="/tmp/iam-009-sensitive-data.txt"

if [ -f "$DOWNLOAD_FILE" ]; then
    rm -f "$DOWNLOAD_FILE"
    echo -e "${GREEN}✓ Deleted $DOWNLOAD_FILE${NC}"
else
    echo -e "${YELLOW}No downloaded file found at $DOWNLOAD_FILE${NC}"
fi

echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}The escalated S3 access policy has been detached${NC}"
echo -e "${YELLOW}The infrastructure (bucket, roles, sensitive-data.txt) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
