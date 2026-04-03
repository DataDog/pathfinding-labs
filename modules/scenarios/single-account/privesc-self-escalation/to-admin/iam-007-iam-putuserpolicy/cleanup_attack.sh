#!/bin/bash

# Cleanup script for iam:PutUserPolicy privilege escalation demo
# This script removes the inline policy attached during the demo


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
STARTING_USER="pl-prod-iam-007-to-admin-starting-user"
INLINE_POLICY_NAME="EscalatedAdminPolicy"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PutUserPolicy Demo Cleanup${NC}"
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

# Step 3: Check if inline policy exists
echo -e "${YELLOW}Step 3: Checking for inline policy $INLINE_POLICY_NAME${NC}"

# List inline policies for the user
POLICIES=$(aws iam list-user-policies --user-name $STARTING_USER --query 'PolicyNames' --output text 2>/dev/null || echo "")

if [ -z "$POLICIES" ]; then
    echo -e "${GREEN}✓ No inline policies found (already clean)${NC}\n"
    echo -e "${GREEN}Cleanup complete - nothing to do${NC}"
    exit 0
fi

echo "Found inline policies: $POLICIES"

# Check specifically for our escalation policy
if echo "$POLICIES" | grep -q "$INLINE_POLICY_NAME"; then
    echo -e "${GREEN}✓ Found $INLINE_POLICY_NAME${NC}\n"
else
    echo -e "${YELLOW}⚠ Policy $INLINE_POLICY_NAME not found (already removed)${NC}\n"
    echo -e "${GREEN}Cleanup complete - nothing to do${NC}"
    exit 0
fi

# Step 4: Remove the inline policy
echo -e "${YELLOW}Step 4: Removing inline policy: $INLINE_POLICY_NAME${NC}"
aws iam delete-user-policy \
    --user-name $STARTING_USER \
    --policy-name $INLINE_POLICY_NAME

echo -e "${GREEN}✓ Successfully deleted inline policy${NC}\n"

# Step 5: Verify cleanup
echo -e "${YELLOW}Step 5: Verifying cleanup${NC}"
REMAINING_POLICIES=$(aws iam list-user-policies --user-name $STARTING_USER --query 'PolicyNames' --output text 2>/dev/null || echo "")

if echo "$REMAINING_POLICIES" | grep -q "$INLINE_POLICY_NAME"; then
    echo -e "${RED}✗ Warning: Policy still exists${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Confirmed policy removed${NC}\n"
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Complete${NC}"
echo -e "${GREEN}========================================${NC}"
echo "The user $STARTING_USER has been restored to its original permissions"
echo ""

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
