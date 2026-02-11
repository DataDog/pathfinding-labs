#!/bin/bash

# Cleanup script for iam-putrolepolicy+sts-assumerole privilege escalation demo
# This script removes the inline admin policy from the target role

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
TARGET_ROLE="pl-prod-iam-017-to-admin-target-role"
INLINE_POLICY_NAME="admin-escalation"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: iam:PutRolePolicy + sts:AssumeRole${NC}"
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

# Step 2: Check current inline policies on target role
echo -e "${YELLOW}Step 2: Checking current inline policies on target role${NC}"
echo "Target role: $TARGET_ROLE"
echo ""

echo "Current inline policies:"
INLINE_POLICIES=$(aws iam list-role-policies \
    --role-name $TARGET_ROLE \
    --query 'PolicyNames' \
    --output text 2>/dev/null || echo "None")

if [ -z "$INLINE_POLICIES" ] || [ "$INLINE_POLICIES" == "None" ]; then
    echo "  (No inline policies)"
else
    echo "  $INLINE_POLICIES"
fi
echo ""

# Step 3: Delete inline admin policy from target role
echo -e "${YELLOW}Step 3: Removing inline admin policy from target role${NC}"

# Check if the policy exists before trying to delete
if aws iam get-role-policy \
    --role-name $TARGET_ROLE \
    --policy-name $INLINE_POLICY_NAME &> /dev/null; then

    aws iam delete-role-policy \
        --role-name $TARGET_ROLE \
        --policy-name $INLINE_POLICY_NAME

    echo -e "${GREEN}✓ Deleted inline policy '$INLINE_POLICY_NAME' from $TARGET_ROLE${NC}"
else
    echo -e "${YELLOW}Inline policy '$INLINE_POLICY_NAME' not found (may already be cleaned up)${NC}"
fi
echo ""

# Step 4: Verify cleanup
echo -e "${YELLOW}Step 4: Verifying cleanup${NC}"
echo "Inline policies after cleanup:"
FINAL_POLICIES=$(aws iam list-role-policies \
    --role-name $TARGET_ROLE \
    --query 'PolicyNames' \
    --output text 2>/dev/null || echo "None")

if [ -z "$FINAL_POLICIES" ] || [ "$FINAL_POLICIES" == "None" ]; then
    echo "  (No inline policies)"
else
    echo "  $FINAL_POLICIES"
fi

# Verify the specific policy is gone
if echo "$FINAL_POLICIES" | grep -q "$INLINE_POLICY_NAME"; then
    echo -e "${RED}✗ Warning: Policy '$INLINE_POLICY_NAME' still exists${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Verified target role no longer has admin inline policy${NC}"
fi
echo ""

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Removed inline policy '$INLINE_POLICY_NAME' from target role"
echo "- Target role restored to original permissions"
echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
