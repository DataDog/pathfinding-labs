#!/bin/bash

# Cleanup script for iam:CreateLoginProfile to S3 bucket access demo
# This script removes the login profile created during the attack demonstration


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
HOP1_USER="pl-prod-iam-004-bucket-hop1"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Removing Login Profile${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Extract admin cleanup user credentials from Terraform outputs
echo -e "${YELLOW}Extracting admin cleanup user credentials from Terraform outputs${NC}"
TERRAFORM_DIR="../../../../../.."

# Check if AWS credentials are already set in environment (and they're admin credentials)
if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$CLEANUP_USER_CREDENTIALS" ]; then
    echo "Using existing admin cleanup credentials from environment variables"
else
    # Extract admin cleanup user credentials from Terraform outputs
    pushd $TERRAFORM_DIR > /dev/null

    ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
    SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

    if [ -z "$ACCESS_KEY" ] || [ "$ACCESS_KEY" == "null" ] || [ -z "$SECRET_KEY" ] || [ "$SECRET_KEY" == "null" ]; then
        echo -e "${RED}Error: Could not retrieve admin cleanup user credentials from Terraform outputs${NC}"
        echo "Make sure the base infrastructure is deployed: terraform apply"
        popd > /dev/null
        exit 1
    fi

    popd > /dev/null

    # Export credentials as environment variables
    export AWS_ACCESS_KEY_ID=$ACCESS_KEY
    export AWS_SECRET_ACCESS_KEY=$SECRET_KEY
    unset AWS_SESSION_TOKEN  # Clear any session token

    echo -e "${GREEN}✓ Successfully extracted and configured admin cleanup user credentials${NC}"
fi

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 1: Check if login profile exists
echo -e "${YELLOW}Step 1: Checking if login profile exists for hop1 user${NC}"
echo "Checking for login profile for user: $HOP1_USER"

if aws iam get-login-profile --user-name $HOP1_USER &> /dev/null; then
    echo -e "${GREEN}✓ Found login profile for $HOP1_USER${NC}"
    LOGIN_PROFILE_INFO=$(aws iam get-login-profile --user-name $HOP1_USER --output json)
    CREATED_DATE=$(echo $LOGIN_PROFILE_INFO | jq -r '.LoginProfile.CreateDate')
    echo "Login profile created: $CREATED_DATE"

    # Step 2: Delete the login profile
    echo -e "\n${YELLOW}Step 2: Deleting login profile${NC}"

    aws iam delete-login-profile \
        --user-name $HOP1_USER

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Successfully deleted login profile${NC}"
    else
        echo -e "${RED}Failed to delete login profile${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}No login profile found for $HOP1_USER (may already be deleted)${NC}"
fi
echo ""

# Step 3: Verify login profile is gone
echo -e "${YELLOW}Step 3: Verifying login profile is removed${NC}"

if aws iam get-login-profile --user-name $HOP1_USER &> /dev/null; then
    echo -e "${RED}⚠ Login profile still exists for $HOP1_USER${NC}"
    echo "Cleanup may have failed"
else
    echo -e "${GREEN}✓ Confirmed: Login profile has been removed${NC}"
fi
echo ""

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Deleted login profile for user: $HOP1_USER"
echo "- Console access has been revoked"
echo "- Hop1 user retains S3 access permissions (but no console login)"

echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, bucket) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
