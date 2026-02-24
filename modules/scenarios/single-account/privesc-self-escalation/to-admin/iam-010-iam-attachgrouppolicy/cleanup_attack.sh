#!/bin/bash

# Cleanup script for iam:AttachGroupPolicy privilege escalation demo
# This script detaches the AdministratorAccess policy from the group


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
GROUP_NAME="pl-prod-iam-010-to-admin-group"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM AttachGroupPolicy Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials from Terraform output
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

# Get admin cleanup user credentials from root terraform output
ADMIN_ACCESS_KEY=$(OTEL_TRACES_EXPORTER= terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(OTEL_TRACES_EXPORTER= terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

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

# Step 2: List attached managed policies
echo -e "${YELLOW}Step 2: Listing attached managed policies for $GROUP_NAME${NC}"
ATTACHED_POLICIES=$(aws iam list-attached-group-policies --group-name $GROUP_NAME --query 'AttachedPolicies[*].PolicyArn' --output text)

if [ -z "$ATTACHED_POLICIES" ]; then
    echo -e "${GREEN}No managed policies attached to $GROUP_NAME${NC}"
else
    echo "Found attached policies: $ATTACHED_POLICIES"

    # Step 3: Detach the AdministratorAccess policy specifically
    echo -e "${YELLOW}Step 3: Detaching AdministratorAccess policy${NC}"
    ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

    if echo "$ATTACHED_POLICIES" | grep -q "$ADMIN_POLICY_ARN"; then
        echo "Detaching policy: $ADMIN_POLICY_ARN"
        aws iam detach-group-policy \
            --group-name $GROUP_NAME \
            --policy-arn $ADMIN_POLICY_ARN
        echo -e "${GREEN}✓ Detached AdministratorAccess policy${NC}"
    else
        echo -e "${YELLOW}AdministratorAccess policy not attached to group${NC}"
    fi
fi


echo -e "${GREEN}✓ Cleanup complete${NC}\n"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AdministratorAccess policy has been detached from $GROUP_NAME${NC}"
echo -e "${YELLOW}The infrastructure (users and groups) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
