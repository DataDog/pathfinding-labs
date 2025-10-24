#!/bin/bash

# Cleanup script for iam:UpdateAssumeRolePolicy privilege escalation demo
# This script restores the original trust policy of the target role

set -e

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
TARGET_ROLE="pl-prod-uar-to-admin-target-role"

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

# Set admin credentials
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"

echo -e "${GREEN}✓ Retrieved admin cleanup credentials${NC}\n"

cd - > /dev/null  # Return to scenario directory

# Step 2: Verify admin access
echo -e "${YELLOW}Step 2: Verifying admin access${NC}"
ADMIN_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ADMIN_IDENTITY"
echo -e "${GREEN}✓ Verified admin access${NC}\n"

# Step 3: Check for saved original policy
echo -e "${YELLOW}Step 3: Looking for saved original trust policy${NC}"
if [ ! -f /tmp/original_trust_policy_uar.json ]; then
    echo -e "${YELLOW}No saved policy found. Setting default EC2 service trust policy${NC}"
    # Use the original Terraform-defined trust policy
    ORIGINAL_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)
else
    echo -e "${GREEN}✓ Found saved original trust policy${NC}"
    ORIGINAL_POLICY=$(cat /tmp/original_trust_policy_uar.json)
fi

echo "Trust policy to restore:"
echo "$ORIGINAL_POLICY" | jq '.'
echo ""

# Step 4: Get current trust policy
echo -e "${YELLOW}Step 4: Checking current trust policy${NC}"
CURRENT_POLICY=$(aws iam get-role --role-name $TARGET_ROLE --query 'Role.AssumeRolePolicyDocument' --output json 2>/dev/null || echo "")

if [ -z "$CURRENT_POLICY" ]; then
    echo -e "${RED}Error: Could not retrieve current trust policy${NC}"
    echo "The role might not exist or you might not have permissions"
    exit 1
fi

echo "Current trust policy:"
echo "$CURRENT_POLICY" | jq '.'
echo ""

# Step 5: Restore the original trust policy
echo -e "${YELLOW}Step 5: Restoring original trust policy${NC}"

aws iam update-assume-role-policy \
    --role-name $TARGET_ROLE \
    --policy-document "$ORIGINAL_POLICY"

echo -e "${GREEN}✓ Successfully restored original trust policy${NC}\n"

# Step 6: Verify the restoration
echo -e "${YELLOW}Step 6: Verifying the restoration${NC}"
RESTORED_POLICY=$(aws iam get-role --role-name $TARGET_ROLE --query 'Role.AssumeRolePolicyDocument' --output json)

echo "Restored trust policy:"
echo "$RESTORED_POLICY" | jq '.'

# Step 7: Clean up temporary file
if [ -f /tmp/original_trust_policy_uar.json ]; then
    rm /tmp/original_trust_policy_uar.json
    echo -e "\n${GREEN}✓ Removed temporary policy file${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo "The target role $TARGET_ROLE has been restored to its original trust policy"
echo ""
