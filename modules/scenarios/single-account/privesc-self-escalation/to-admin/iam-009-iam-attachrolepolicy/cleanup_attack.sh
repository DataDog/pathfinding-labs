#!/bin/bash

# Cleanup script for iam:AttachRolePolicy privilege escalation demo
# This script removes the AdministratorAccess policy attached during the demo


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Source demo permissions library for safety restore
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Safety: remove any orphaned restriction policies
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# Configuration
STARTING_ROLE="pl-prod-iam-009-to-admin-starting-role"
MANAGED_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM AttachRolePolicy Demo Cleanup${NC}"
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

echo -e "${GREEN}✓ Retrieved admin cleanup credentials${NC}\n"

cd - > /dev/null  # Return to scenario directory

# Step 2: Verify admin access
echo -e "${YELLOW}Step 2: Verifying admin access${NC}"
ADMIN_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ADMIN_IDENTITY"
echo -e "${GREEN}✓ Verified admin access${NC}\n"

# Step 3: Check if role exists
echo -e "${YELLOW}Step 3: Checking if role exists${NC}"
if aws iam get-role --role-name "$STARTING_ROLE" &> /dev/null; then
    echo -e "${GREEN}✓ Role $STARTING_ROLE exists${NC}\n"
else
    echo -e "${RED}✗ Role $STARTING_ROLE not found. Nothing to clean up.${NC}"
    exit 0
fi

# Step 4: Check if AdministratorAccess policy is attached
echo -e "${YELLOW}Step 4: Checking for attached AdministratorAccess policy${NC}"
ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name $STARTING_ROLE --query 'AttachedPolicies[?PolicyArn==`'$MANAGED_POLICY_ARN'`].PolicyName' --output text)

if [ -z "$ATTACHED_POLICIES" ]; then
    echo -e "${GREEN}✓ No AdministratorAccess policy attached (already clean)${NC}\n"
    echo -e "${GREEN}Cleanup complete - nothing to do${NC}"
    exit 0
fi

echo "Found attached policy: $ATTACHED_POLICIES"
echo -e "${GREEN}✓ Policy found${NC}\n"

# Step 5: Detach the policy
echo -e "${YELLOW}Step 5: Detaching AdministratorAccess policy from $STARTING_ROLE${NC}"
aws iam detach-role-policy \
    --role-name $STARTING_ROLE \
    --policy-arn $MANAGED_POLICY_ARN

echo -e "${GREEN}✓ Successfully detached AdministratorAccess policy${NC}\n"

# Step 6: Verify cleanup
echo -e "${YELLOW}Step 6: Verifying cleanup${NC}"
REMAINING_POLICIES=$(aws iam list-attached-role-policies --role-name $STARTING_ROLE --query 'AttachedPolicies[*].PolicyName' --output text)

if echo "$REMAINING_POLICIES" | grep -q "AdministratorAccess"; then
    echo -e "${RED}✗ Warning: AdministratorAccess policy still attached${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Confirmed policy removed${NC}\n"
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo "The role $STARTING_ROLE has been restored to its original permissions"
echo ""

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
