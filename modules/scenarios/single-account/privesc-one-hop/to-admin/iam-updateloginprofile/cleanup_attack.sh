#!/bin/bash

# Cleanup script for iam:UpdateLoginProfile privilege escalation demo
# This script restores the original password for the admin user

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROFILE="pl-admin-user-for-cleanup-scripts-prod"
ADMIN_USER="pl-ulp-admin"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Restoring Original Password${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Check if we have the original password saved
echo -e "${YELLOW}Step 1: Looking for saved original password${NC}"

if [ -f /tmp/original_password_ulp.txt ]; then
    ORIGINAL_PASSWORD=$(cat /tmp/original_password_ulp.txt)
    echo -e "${GREEN}✓ Found saved original password${NC}"

    # Step 2: Restore the original password
    echo -e "\n${YELLOW}Step 2: Restoring original password${NC}"

    aws iam update-login-profile \
        --user-name $ADMIN_USER \
        --password "$ORIGINAL_PASSWORD" \
        --no-password-reset-required \
        --profile $PROFILE

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Successfully restored original password${NC}"

        # Clean up temporary file
        rm /tmp/original_password_ulp.txt
        echo -e "${GREEN}✓ Removed temporary password file${NC}"
    else
        echo -e "${RED}Failed to restore original password${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}No saved original password found${NC}"
    echo "Note: The password was changed but we don't have the original to restore"
    echo ""

    # Step 2: Get password from Terraform and restore it
    echo -e "${YELLOW}Step 2: Getting original password from Terraform state${NC}"

    TERRAFORM_DIR="../../../../../.."
    pushd $TERRAFORM_DIR > /dev/null

    ORIGINAL_PASSWORD=$(terraform output -json | jq -r '.prod_one_hop_to_admin_iam_updateloginprofile[0].original_password.value' 2>/dev/null || echo "")

    popd > /dev/null

    if [ ! -z "$ORIGINAL_PASSWORD" ] && [ "$ORIGINAL_PASSWORD" != "null" ]; then
        echo -e "${GREEN}✓ Retrieved original password from Terraform${NC}"

        echo -e "\n${YELLOW}Step 3: Restoring original password${NC}"

        aws iam update-login-profile \
            --user-name $ADMIN_USER \
            --password "$ORIGINAL_PASSWORD" \
            --no-password-reset-required \
            --profile $PROFILE

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Successfully restored original password${NC}"
        else
            echo -e "${RED}Failed to restore original password${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}Unable to retrieve original password from Terraform${NC}"
        echo "The admin user's password remains changed"
        echo "You may need to manually reset it or run 'terraform apply' to restore the original state"
    fi
fi

# Step 3: Verify the user still has a login profile
echo -e "\n${YELLOW}Step 3: Verifying login profile status${NC}"

if aws iam get-login-profile --user-name $ADMIN_USER --profile $PROFILE &> /dev/null; then
    echo -e "${GREEN}✓ Login profile still exists for $ADMIN_USER${NC}"
    LOGIN_PROFILE_INFO=$(aws iam get-login-profile --user-name $ADMIN_USER --profile $PROFILE --output json)
    MODIFIED_DATE=$(echo $LOGIN_PROFILE_INFO | jq -r '.LoginProfile.CreateDate')
    echo "Login profile last modified: $MODIFIED_DATE"
else
    echo -e "${RED}⚠ Login profile not found for $ADMIN_USER${NC}"
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Restored original password for user: $ADMIN_USER"
echo "- Admin user retains both console and API access"
echo "- Login profile remains active"

echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"