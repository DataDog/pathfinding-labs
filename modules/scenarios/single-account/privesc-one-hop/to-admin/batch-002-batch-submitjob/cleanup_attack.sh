#!/bin/bash

# Cleanup script for batch-002-batch-submitjob privilege escalation demo
# This script detaches the AdministratorAccess policy from the starting user
# that was attached during the demo by the Batch job container.

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER_NAME="pl-prod-batch-002-to-admin-starting-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Batch SubmitJob to Admin${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd "$(dirname "$0")/../../../../../.."

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
echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Safety restore: ensure helpful permissions deny policy is removed in case demo exited early
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Detach AdministratorAccess from starting user if attached
echo -e "${YELLOW}Step 2: Detaching AdministratorAccess from starting user${NC}"
echo "Checking attached policies for: $STARTING_USER_NAME"

ATTACHED=$(aws iam list-attached-user-policies \
    --user-name "$STARTING_USER_NAME" \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`].PolicyArn' \
    --output text 2>/dev/null || echo "")

if [ -n "$ATTACHED" ]; then
    aws iam detach-user-policy \
        --user-name "$STARTING_USER_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"
    echo -e "${GREEN}✓ Detached AdministratorAccess from $STARTING_USER_NAME${NC}"
else
    echo -e "${YELLOW}AdministratorAccess not attached to $STARTING_USER_NAME (may already be cleaned up)${NC}"
fi
echo ""

# Step 3: Remove any lingering inline policies
echo -e "${YELLOW}Step 3: Checking for inline policies on starting user${NC}"
INLINE_POLICIES=$(aws iam list-user-policies \
    --user-name "$STARTING_USER_NAME" \
    --query 'PolicyNames' \
    --output text 2>/dev/null || echo "")

if [ -n "$INLINE_POLICIES" ] && [ "$INLINE_POLICIES" != "None" ]; then
    for POLICY_NAME in $INLINE_POLICIES; do
        echo "Removing inline policy: $POLICY_NAME"
        aws iam delete-user-policy \
            --user-name "$STARTING_USER_NAME" \
            --policy-name "$POLICY_NAME"
        echo -e "${GREEN}✓ Removed inline policy: $POLICY_NAME${NC}"
    done
else
    echo -e "${YELLOW}No inline policies found on $STARTING_USER_NAME${NC}"
fi
echo ""

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess from: $STARTING_USER_NAME"
echo "- Removed any lingering inline policies from: $STARTING_USER_NAME"
echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, Batch resources) remains deployed.${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply.${NC}\n"
