#!/bin/bash

# Cleanup script for iam:PutGroupPolicy privilege escalation demo
# This script removes the inline policy added to the group during the demo


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
TARGET_GROUP="pl-prod-iam-011-to-admin-escalation-group"
POLICY_NAME="EscalatedAdminAccess"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: IAM PutGroupPolicy Demo${NC}"
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

# Step 2: Check if the inline policy exists
echo -e "${YELLOW}Step 2: Checking for inline policy on group $TARGET_GROUP${NC}"

# List group policies
GROUP_POLICIES=$(aws iam list-group-policies --group-name $TARGET_GROUP --query 'PolicyNames' --output text 2>/dev/null || echo "")

if [[ $GROUP_POLICIES == *"$POLICY_NAME"* ]]; then
    echo "Found inline policy: $POLICY_NAME"
    
    # Step 3: Delete the inline policy
    echo -e "${YELLOW}Step 3: Deleting inline policy${NC}"
    aws iam delete-group-policy \
        --group-name $TARGET_GROUP \
        --policy-name $POLICY_NAME
    
    echo -e "${GREEN}✓ Deleted inline policy: $POLICY_NAME${NC}"
else
    echo -e "${GREEN}No inline policy '$POLICY_NAME' found on group $TARGET_GROUP${NC}"
    echo "The demo may not have been run or was already cleaned up"
fi

# Step 3: Verify cleanup
echo -e "\n${YELLOW}Step 3: Verifying cleanup${NC}"
REMAINING_POLICIES=$(aws iam list-group-policies --group-name $TARGET_GROUP --query 'PolicyNames' --output text 2>/dev/null || echo "")

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

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
