#!/bin/bash

# Cleanup script for iam:UpdateLoginProfile privilege escalation demo
# This script restores the original password for the admin user

set -e

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ADMIN_USER="pl-prod-ulp-to-admin-target-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM UpdateLoginProfile Demo Cleanup${NC}"
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

# Get the original password from terraform output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_updateloginprofile.value // empty')
ORIGINAL_PASSWORD=$(echo "$MODULE_OUTPUT" | jq -r '.original_password')

# Also check if we saved it locally during the attack
if [ -f "/tmp/ulp_original_password.txt" ]; then
    SAVED_PASSWORD=$(cat /tmp/ulp_original_password.txt)
    if [ -n "$SAVED_PASSWORD" ]; then
        ORIGINAL_PASSWORD="$SAVED_PASSWORD"
    fi
fi

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

# Step 3: Restore original password
echo -e "${YELLOW}Step 3: Restoring original password for $ADMIN_USER${NC}"

if [ -z "$ORIGINAL_PASSWORD" ] || [ "$ORIGINAL_PASSWORD" == "null" ]; then
    echo -e "${RED}Error: Could not retrieve original password${NC}"
    echo -e "${YELLOW}You may need to manually reset the password or redeploy the scenario${NC}"
    exit 1
fi

aws iam update-login-profile \
    --user-name $ADMIN_USER \
    --password "$ORIGINAL_PASSWORD" \
    --no-password-reset-required

echo -e "${GREEN}✓ Successfully restored original password${NC}\n"

# Step 4: Remove local temporary files
echo -e "${YELLOW}Step 4: Removing local temporary files${NC}"
SAVED_PASSWORD_FILE="/tmp/ulp_original_password.txt"

if [ -f "$SAVED_PASSWORD_FILE" ]; then
    rm -f "$SAVED_PASSWORD_FILE"
    echo -e "${GREEN}✓ Deleted $SAVED_PASSWORD_FILE${NC}"
else
    echo -e "${YELLOW}No saved password file found${NC}"
fi

echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}The original password has been restored${NC}"
echo -e "${YELLOW}The infrastructure (users, roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
