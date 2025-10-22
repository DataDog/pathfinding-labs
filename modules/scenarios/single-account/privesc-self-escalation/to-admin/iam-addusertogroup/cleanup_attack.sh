#!/bin/bash

# Cleanup script for iam:AddUserToGroup privilege escalation demo
# This script removes the user from the admin group added during the demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROFILE="pl-admin-cleanup-prod"
START_USER="pl-aug-start-user"
ADMIN_GROUP="pl-aug-admin-group"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: IAM AddUserToGroup Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Check if the user is a member of the admin group
echo -e "${YELLOW}Step 1: Checking group membership for $START_USER${NC}"

# Get user's current groups
USER_GROUPS=$(aws iam list-groups-for-user --user-name $START_USER --profile $PROFILE --query 'Groups[*].GroupName' --output text 2>/dev/null || echo "")

if [[ $USER_GROUPS == *"$ADMIN_GROUP"* ]]; then
    echo "Found: $START_USER is a member of $ADMIN_GROUP"

    # Step 2: Remove the user from the admin group
    echo -e "${YELLOW}Step 2: Removing $START_USER from $ADMIN_GROUP${NC}"
    aws iam remove-user-from-group \
        --group-name $ADMIN_GROUP \
        --user-name $START_USER \
        --profile $PROFILE

    echo -e "${GREEN}✓ Removed $START_USER from $ADMIN_GROUP${NC}"
else
    echo -e "${GREEN}User $START_USER is not a member of $ADMIN_GROUP${NC}"
    echo "The demo may not have been run or was already cleaned up"
fi

# Step 3: Verify cleanup
echo -e "\n${YELLOW}Step 3: Verifying cleanup${NC}"
REMAINING_GROUPS=$(aws iam list-groups-for-user --user-name $START_USER --profile $PROFILE --query 'Groups[*].GroupName' --output text 2>/dev/null || echo "")

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
