#!/bin/bash

# Cleanup script for iam-updateassumerolepolicy privilege escalation demo
# This script restores the original trust policy of the target admin role


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
TARGET_ROLE="pl-prod-iam-012-to-admin-target-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: IAM UpdateAssumeRolePolicy Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get admin cleanup user credentials from root terraform output
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    echo "Make sure the admin cleanup user is deployed"
    exit 1
fi

if [ -z "$CURRENT_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    CURRENT_REGION="us-east-1"
fi

# Set admin credentials
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

echo "Region from Terraform: $CURRENT_REGION"
echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Check for saved original trust policy
echo -e "${YELLOW}Step 2: Looking for saved original trust policy${NC}"
if [ ! -f /tmp/original_trust_policy_iam_012.json ]; then
    echo -e "${YELLOW}No saved policy found. Restoring default EC2 service trust policy${NC}"
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
    ORIGINAL_POLICY=$(cat /tmp/original_trust_policy_iam_012.json)
fi

echo "Trust policy to restore:"
echo "$ORIGINAL_POLICY" | jq '.'
echo ""

# Step 3: Get current trust policy
echo -e "${YELLOW}Step 3: Checking current trust policy${NC}"
CURRENT_POLICY=$(aws iam get-role --role-name $TARGET_ROLE --query 'Role.AssumeRolePolicyDocument' --output json 2>/dev/null || echo "")

if [ -z "$CURRENT_POLICY" ]; then
    echo -e "${RED}Error: Could not retrieve current trust policy${NC}"
    echo "The role might not exist or you might not have permissions"
    exit 1
fi

echo "Current trust policy:"
echo "$CURRENT_POLICY" | jq '.'
echo ""

# Step 4: Restore the original trust policy
echo -e "${YELLOW}Step 4: Restoring original trust policy${NC}"
echo "Restoring trust policy on role: $TARGET_ROLE"

aws iam update-assume-role-policy \
    --role-name $TARGET_ROLE \
    --policy-document "$ORIGINAL_POLICY"

echo -e "${GREEN}✓ Successfully restored original trust policy${NC}\n"

# Step 5: Verify the restoration
echo -e "${YELLOW}Step 5: Verifying the restoration${NC}"
RESTORED_POLICY=$(aws iam get-role --role-name $TARGET_ROLE --query 'Role.AssumeRolePolicyDocument' --output json)

echo "Restored trust policy:"
echo "$RESTORED_POLICY" | jq '.'
echo -e "${GREEN}✓ Trust policy verified${NC}\n"

# Step 6: Clean up temporary file
if [ -f /tmp/original_trust_policy_iam_012.json ]; then
    rm /tmp/original_trust_policy_iam_012.json
    echo -e "${GREEN}✓ Removed temporary policy file${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Restored original trust policy on role: $TARGET_ROLE"
echo "- Trust policy now only allows EC2 service to assume the role"

echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
