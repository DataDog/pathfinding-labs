#!/bin/bash

# Cleanup script for iam:PutRolePolicy privilege escalation demo
# This script removes the self-admin-policy inline policy attached during the demo


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
STARTING_ROLE="pl-prod-iam-005-to-admin-starting-role"
POLICY_NAME="self-admin-policy"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PutRolePolicy Demo Cleanup${NC}"
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

# Step 4: Check if self-admin-policy exists
echo -e "${YELLOW}Step 4: Checking for $POLICY_NAME${NC}"
if aws iam get-role-policy --role-name "$STARTING_ROLE" --policy-name "$POLICY_NAME" &> /dev/null; then
    echo "Found $POLICY_NAME, removing it..."

    # Delete the self-admin-policy
    aws iam delete-role-policy \
        --role-name "$STARTING_ROLE" \
        --policy-name "$POLICY_NAME"

    echo -e "${GREEN}✓ Successfully removed $POLICY_NAME${NC}\n"
else
    echo -e "${GREEN}✓ No $POLICY_NAME found (already clean)${NC}\n"
fi

# Step 5: Verify cleanup
echo -e "${YELLOW}Step 5: Verifying cleanup${NC}"
INLINE_POLICIES=$(aws iam list-role-policies --role-name "$STARTING_ROLE" --query 'PolicyNames' --output text)

if echo "$INLINE_POLICIES" | grep -q "self-admin-policy"; then
    echo -e "${RED}✗ Warning: self-admin-policy still exists${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Confirmed self-admin-policy removed${NC}\n"
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo "The role $STARTING_ROLE has been restored to its original permissions"
echo ""

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
