#!/bin/bash

# Cleanup script for codedeploy-001 - CodeDeploy CreateDeployment to Admin
# Removes artifacts created by demo_attack.sh:
#   - AdministratorAccess policy detached from starting user
#   - Legacy inline policy removed if present (from older research agent versions)

set -e

export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: CodeDeploy CreateDeployment to Admin (codedeploy-001)${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd "$(dirname "$0")/../../../../../.."  # Navigate to root of terraform project

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

# Get starting user name from grouped output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_codedeploy_001_codedeploy_createdeployment.value // empty')
STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name // empty')

echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Safety restore: ensure helpful permissions deny policy is removed
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"

# Fall back to the well-known name if the grouped output didn't return it
if [ -z "$STARTING_USER_NAME" ] || [ "$STARTING_USER_NAME" = "null" ]; then
    STARTING_USER_NAME="pl-prod-codedeploy-001-to-admin-starting-user"
    echo -e "${YELLOW}Warning: Could not read starting_user_name from Terraform output, using default: $STARTING_USER_NAME${NC}"
fi

echo "Starting user: $STARTING_USER_NAME"
echo ""

# Step 2: Detach AdministratorAccess managed policy from starting user
echo -e "${YELLOW}Step 2: Detaching AdministratorAccess from starting user${NC}"
POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

if aws iam list-attached-user-policies \
        --user-name "$STARTING_USER_NAME" \
        --query "AttachedPolicies[?PolicyArn=='$POLICY_ARN'].PolicyArn" \
        --output text 2>/dev/null | grep -q "$POLICY_ARN"; then
    aws iam detach-user-policy \
        --user-name "$STARTING_USER_NAME" \
        --policy-arn "$POLICY_ARN"
    echo -e "${GREEN}✓ Detached AdministratorAccess from $STARTING_USER_NAME${NC}"
else
    echo -e "${YELLOW}AdministratorAccess not attached to $STARTING_USER_NAME (may already be cleaned up)${NC}"
fi
echo ""

# Step 3: Remove legacy inline policy if present
# Older research agent versions used an inline policy named pra-escalate-codedeploy-001
# instead of the managed AdministratorAccess attachment. Remove it as a safety measure.
echo -e "${YELLOW}Step 3: Removing legacy inline policy (pra-escalate-codedeploy-001) if present${NC}"
LEGACY_POLICY_NAME="pra-escalate-codedeploy-001"

if aws iam get-user-policy \
        --user-name "$STARTING_USER_NAME" \
        --policy-name "$LEGACY_POLICY_NAME" \
        &>/dev/null; then
    aws iam delete-user-policy \
        --user-name "$STARTING_USER_NAME" \
        --policy-name "$LEGACY_POLICY_NAME"
    echo -e "${GREEN}✓ Removed legacy inline policy $LEGACY_POLICY_NAME from $STARTING_USER_NAME${NC}"
else
    echo -e "${YELLOW}Legacy inline policy $LEGACY_POLICY_NAME not found (expected — only present if an older hook version ran)${NC}"
fi
echo ""

# Step 4: Remove .demo_active marker
echo -e "${YELLOW}Step 4: Removing demo active marker${NC}"
DEMO_ACTIVE_FILE="$(dirname "$0")/.demo_active"
if [ -f "$DEMO_ACTIVE_FILE" ]; then
    rm -f "$DEMO_ACTIVE_FILE"
    echo -e "${GREEN}✓ Removed .demo_active marker${NC}"
else
    echo -e "${YELLOW}.demo_active not found (already cleaned up)${NC}"
fi
echo ""

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess from $STARTING_USER_NAME (if present)"
echo "- Removed legacy inline policy pra-escalate-codedeploy-001 (if present)"
echo "- Restored helpful permissions deny policy"
echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, CodeDeploy app, EC2 instance) remains deployed.${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply.${NC}\n"
