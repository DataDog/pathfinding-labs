#!/bin/bash

# Cleanup script for iam:AddUserToGroup privilege escalation demo
# This script removes the user from the admin group added during the demo

set -e

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
START_USER="pl-aug-start-user"
ADMIN_GROUP="pl-aug-admin-group"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: IAM AddUserToGroup Demo${NC}"
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
unset AWS_SESSION_TOKEN

echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

cd - > /dev/null  # Return to scenario directory

# Step 2: Check if the user is a member of the admin group
echo -e "${YELLOW}Step 2: Checking group membership for $START_USER${NC}"

# Get user's current groups
USER_GROUPS=$(aws iam list-groups-for-user --user-name $START_USER --query 'Groups[*].GroupName' --output text 2>/dev/null || echo "")

if [[ $USER_GROUPS == *"$ADMIN_GROUP"* ]]; then
    echo "Found: $START_USER is a member of $ADMIN_GROUP"

    # Step 3: Remove the user from the admin group
    echo -e "${YELLOW}Step 3: Removing $START_USER from $ADMIN_GROUP${NC}"
    aws iam remove-user-from-group \
        --group-name $ADMIN_GROUP \
        --user-name $START_USER

    echo -e "${GREEN}✓ Removed $START_USER from $ADMIN_GROUP${NC}"
else
    echo -e "${GREEN}User $START_USER is not a member of $ADMIN_GROUP${NC}"
    echo "The demo may not have been run or was already cleaned up"
fi

# Step 4: Verify cleanup
echo -e "\n${YELLOW}Step 4: Verifying cleanup${NC}"
REMAINING_GROUPS=$(aws iam list-groups-for-user --user-name $START_USER --query 'Groups[*].GroupName' --output text 2>/dev/null || echo "")

if [ -z "$REMAINING_GROUPS" ]; then
    echo -e "${GREEN}✓ User $START_USER is not a member of any groups${NC}"
else
    echo -e "${YELLOW}User's remaining groups: $REMAINING_GROUPS${NC}"
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Removed $START_USER from $ADMIN_GROUP"
echo "- User no longer has escalated privileges via group membership"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, groups, and policies) remains deployed.${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply.${NC}\n"
