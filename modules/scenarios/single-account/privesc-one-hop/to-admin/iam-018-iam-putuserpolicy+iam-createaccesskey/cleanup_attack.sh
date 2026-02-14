#!/bin/bash

# Cleanup script for iam:PutUserPolicy + iam:CreateAccessKey privilege escalation demo
# This script removes the admin policy and access keys created during the demo


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
TARGET_USER="pl-prod-iam-018-to-admin-target-user"
ADMIN_POLICY_NAME="admin-escalation"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: PutUserPolicy + CreateAccessKey Demo${NC}"
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

# Step 2: Delete access keys created during demo
echo -e "${YELLOW}Step 2: Deleting access keys for target user${NC}"
echo "Checking for access keys on: $TARGET_USER"

# List all access keys for the target user
ACCESS_KEYS=$(aws iam list-access-keys --user-name $TARGET_USER --query 'AccessKeyMetadata[*].AccessKeyId' --output text)

if [ -z "$ACCESS_KEYS" ]; then
    echo -e "${YELLOW}No access keys found for $TARGET_USER (may already be deleted)${NC}"
else
    echo "Found access keys: $ACCESS_KEYS"

    # Delete each access key
    for KEY_ID in $ACCESS_KEYS; do
        echo "Deleting access key: $KEY_ID"
        aws iam delete-access-key \
            --user-name $TARGET_USER \
            --access-key-id $KEY_ID
        echo -e "${GREEN}✓ Deleted access key: $KEY_ID${NC}"
    done
fi
echo ""

# Step 3: Remove admin inline policy from target user
echo -e "${YELLOW}Step 3: Removing admin inline policy from target user${NC}"
echo "Checking for policy: $ADMIN_POLICY_NAME"

if aws iam get-user-policy --user-name $TARGET_USER --policy-name $ADMIN_POLICY_NAME &> /dev/null; then
    aws iam delete-user-policy \
        --user-name $TARGET_USER \
        --policy-name $ADMIN_POLICY_NAME
    echo -e "${GREEN}✓ Removed policy: $ADMIN_POLICY_NAME${NC}"
else
    echo -e "${YELLOW}Policy $ADMIN_POLICY_NAME not found (may already be deleted)${NC}"
fi
echo ""

# Step 4: Clean up temporary files
echo -e "${YELLOW}Step 4: Cleaning up temporary files${NC}"
POLICY_FILE="/tmp/admin-escalation-policy.json"
if [ -f "$POLICY_FILE" ]; then
    rm -f $POLICY_FILE
    echo -e "${GREEN}✓ Removed temporary policy file: $POLICY_FILE${NC}"
else
    echo -e "${YELLOW}Temporary policy file not found${NC}"
fi
echo ""

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Deleted all access keys for $TARGET_USER"
echo "- Removed admin inline policy '$ADMIN_POLICY_NAME' from $TARGET_USER"
echo "- Cleaned up temporary policy file"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
