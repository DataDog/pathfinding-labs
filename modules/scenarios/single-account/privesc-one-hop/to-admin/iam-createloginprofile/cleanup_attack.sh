#!/bin/bash

# Cleanup script for iam:CreateLoginProfile privilege escalation demo
# This script removes the login profile created during the attack

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROFILE="pl-admin-user-for-cleanup-scripts-prod"
ADMIN_USER="pl-clp-admin"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Removing Login Profile${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Check if login profile exists
echo -e "${YELLOW}Step 1: Checking if login profile exists for $ADMIN_USER${NC}"

if aws iam get-login-profile --user-name $ADMIN_USER --profile $PROFILE &> /dev/null; then
    echo -e "${GREEN}✓ Login profile found for $ADMIN_USER${NC}"

    # Step 2: Delete the login profile
    echo -e "\n${YELLOW}Step 2: Deleting login profile${NC}"

    aws iam delete-login-profile \
        --user-name $ADMIN_USER \
        --profile $PROFILE

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Successfully deleted login profile${NC}"
    else
        echo -e "${RED}Failed to delete login profile${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}No login profile exists for $ADMIN_USER (nothing to clean up)${NC}"
fi

# Step 3: Verify cleanup
echo -e "\n${YELLOW}Step 3: Verifying cleanup${NC}"

if aws iam get-login-profile --user-name $ADMIN_USER --profile $PROFILE &> /dev/null; then
    echo -e "${RED}⚠ Login profile still exists!${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Confirmed: Login profile has been removed${NC}"
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Removed login profile for user: $ADMIN_USER"
echo "- Console access has been revoked"
echo "- Admin user still has API access via access keys"

echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo "The admin user no longer has console access but retains API access."