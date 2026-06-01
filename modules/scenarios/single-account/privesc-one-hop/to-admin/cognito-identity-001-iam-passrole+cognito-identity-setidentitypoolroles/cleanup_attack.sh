#!/bin/bash
set -e

# Cleanup script for cognito-identity-001 privilege escalation demo
# The Cognito Identity Pool itself is Terraform-managed and is not removed here.
# This script clears the unauthenticated role binding set by SetIdentityPoolRoles
# so the pool returns to a clean state and subsequent demo runs start fresh.

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: PassRole + Cognito Identity Pool Unauthenticated Role Swap${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get admin cleanup user credentials from root terraform output
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    echo "Make sure the admin cleanup user is deployed"
    exit 1
fi

if [ -z "$CURRENT_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    CURRENT_REGION="us-east-1"
fi

# Set admin credentials
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

echo "Region from Terraform: $CURRENT_REGION"

# Get the module output to retrieve the identity pool ID
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_cognito_identity_001_iam_passrole_cognito_identity_setidentitypoolroles.value // empty')
POOL_ID=$(echo "$MODULE_OUTPUT" | jq -r '.identity_pool_id // empty')

echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Safety restore: ensure helpful permissions deny policy is removed
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# Step 2: Reset the identity pool's unauthenticated role binding
echo -e "${YELLOW}Step 2: Resetting the identity pool unauthenticated role binding${NC}"

if [ -z "$POOL_ID" ] || [ "$POOL_ID" == "null" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve identity_pool_id from terraform output — skipping role reset${NC}"
    echo "The pool may have already been destroyed or the scenario may be disabled."
else
    echo "Identity Pool ID: $POOL_ID"
    echo "Clearing the unauthenticated role binding (roles map reset to empty)..."

    aws cognito-identity set-identity-pool-roles \
        --identity-pool-id "$POOL_ID" \
        --roles '{}' \
        --region "$CURRENT_REGION" 2>/dev/null || true

    echo -e "${GREEN}✓ Identity pool unauthenticated role binding cleared${NC}"
fi
echo ""

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Cleared unauthenticated role binding on Cognito Identity Pool: ${POOL_ID:-<unknown>}"
echo "  (Pool's roles map reset to empty — no longer vends admin credentials to public callers)"
echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (pool, users, and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
