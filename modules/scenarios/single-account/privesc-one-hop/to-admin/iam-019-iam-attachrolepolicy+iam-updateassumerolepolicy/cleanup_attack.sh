#!/bin/bash

# Cleanup script for iam-attachrolepolicy+iam-updateassumerolepolicy privilege escalation demo
# This script detaches the AdministratorAccess policy and restores the original trust policy

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
TARGET_ROLE="pl-prod-iam-019-to-admin-target-role"
ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: iam:AttachRolePolicy + iam:UpdateAssumeRolePolicy${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get admin cleanup user credentials from root terraform output
ADMIN_ACCESS_KEY=$(OTEL_TRACES_EXPORTER= terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(OTEL_TRACES_EXPORTER= terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
CURRENT_REGION=$(OTEL_TRACES_EXPORTER= terraform output -raw aws_region 2>/dev/null || echo "")

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

# Step 2: Check current attached policies
echo -e "${YELLOW}Step 2: Checking current policies on target role${NC}"
echo "Target role: $TARGET_ROLE"
echo ""

echo "Current attached policies:"
ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
    --role-name $TARGET_ROLE \
    --query 'AttachedPolicies[*].[PolicyName,PolicyArn]' \
    --output table 2>/dev/null || echo "None")

echo "$ATTACHED_POLICIES"
echo ""

# Step 3: Detach AdministratorAccess policy from target role
echo -e "${YELLOW}Step 3: Detaching AdministratorAccess policy from target role${NC}"

# Check if the policy is attached before trying to detach
if aws iam list-attached-role-policies \
    --role-name $TARGET_ROLE \
    --query "AttachedPolicies[?PolicyArn=='$ADMIN_POLICY_ARN']" \
    --output text | grep -q "AdministratorAccess"; then

    aws iam detach-role-policy \
        --role-name $TARGET_ROLE \
        --policy-arn $ADMIN_POLICY_ARN

    echo -e "${GREEN}✓ Detached AdministratorAccess policy from $TARGET_ROLE${NC}"
else
    echo -e "${YELLOW}AdministratorAccess policy not attached (may already be cleaned up)${NC}"
fi
echo ""

# Step 4: Restore the original trust policy
echo -e "${YELLOW}Step 4: Restoring original trust policy${NC}"
echo "Resetting trust policy to trust account root..."

# Create the original trust policy (trusts :root as defined in main.tf)
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

aws iam update-assume-role-policy \
    --role-name $TARGET_ROLE \
    --policy-document "$ORIGINAL_TRUST_POLICY"

echo -e "${GREEN}✓ Restored original trust policy${NC}"
echo ""

# Step 5: Verify cleanup
echo -e "${YELLOW}Step 5: Verifying cleanup${NC}"

echo "Attached policies after cleanup:"
aws iam list-attached-role-policies \
    --role-name $TARGET_ROLE \
    --query 'AttachedPolicies[*].[PolicyName,PolicyArn]' \
    --output table 2>/dev/null || echo "  (No managed policies attached)"

echo ""
echo "Trust policy after cleanup:"
aws iam get-role \
    --role-name $TARGET_ROLE \
    --query 'Role.AssumeRolePolicyDocument' \
    --output json | jq '.'

echo -e "${GREEN}✓ Verified target role restored to original state${NC}"
echo ""

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess policy from target role"
echo "- Restored original trust policy (trusts account root)"
echo "- Target role restored to original permissions"
echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
