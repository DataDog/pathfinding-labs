#!/bin/bash

# Cleanup script for iam:PutGroupPolicy privilege escalation demo
# This script removes the inline policy added to the group during the demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROFILE="pl-admin-cleanup-prod"
TARGET_GROUP="pl-pgp-escalation-group"
POLICY_NAME="EscalatedAdminAccess"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: IAM PutGroupPolicy Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Check if the inline policy exists
echo -e "${YELLOW}Step 1: Checking for inline policy on group $TARGET_GROUP${NC}"

# List group policies
GROUP_POLICIES=$(aws iam list-group-policies --group-name $TARGET_GROUP --profile $PROFILE --query 'PolicyNames' --output text 2>/dev/null || echo "")

if [[ $GROUP_POLICIES == *"$POLICY_NAME"* ]]; then
    echo "Found inline policy: $POLICY_NAME"
    
    # Step 2: Delete the inline policy
    echo -e "${YELLOW}Step 2: Deleting inline policy${NC}"
    aws iam delete-group-policy \
        --group-name $TARGET_GROUP \
        --policy-name $POLICY_NAME \
        --profile $PROFILE
    
    echo -e "${GREEN}✓ Deleted inline policy: $POLICY_NAME${NC}"
else
    echo -e "${GREEN}No inline policy '$POLICY_NAME' found on group $TARGET_GROUP${NC}"
    echo "The demo may not have been run or was already cleaned up"
fi

# Step 3: Verify cleanup
echo -e "\n${YELLOW}Step 3: Verifying cleanup${NC}"
REMAINING_POLICIES=$(aws iam list-group-policies --group-name $TARGET_GROUP --profile $PROFILE --query 'PolicyNames' --output text 2>/dev/null || echo "")

if [ -z "$REMAINING_POLICIES" ]; then
    echo -e "${GREEN}✓ No inline policies remain on group $TARGET_GROUP${NC}"
else
    echo -e "${YELLOW}Remaining inline policies on group: $REMAINING_POLICIES${NC}"
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Removed inline policy '$POLICY_NAME' from group $TARGET_GROUP"
echo "- Starting user no longer has escalated privileges via group membership"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (roles, groups, and memberships) remains deployed.${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply.${NC}\n"
