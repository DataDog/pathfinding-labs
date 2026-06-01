#!/bin/bash

# Cleanup script for PassRole + EventBridge Scheduler privilege escalation demo
# Removes all out-of-band mutations made by demo_attack.sh:
#   - Deletes the EventBridge Scheduler schedule (if it still exists)
#   - Detaches AdministratorAccess from the starting user

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
SCHEDULE_NAME="pl-scheduler-001-escalation"
ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: PassRole + EventBridge Scheduler${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin cleanup credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

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

# Get the starting user name from the scenario module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_scheduler_001.value // empty')
STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name // empty')

if [ -z "$STARTING_USER_NAME" ]; then
    # Fall back to the known static name if the module output is unavailable
    STARTING_USER_NAME="pl-prod-scheduler-001-to-admin-starting-user"
    echo -e "${YELLOW}Warning: Could not read starting_user_name from module output, using default: $STARTING_USER_NAME${NC}"
fi

# Set admin credentials
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
export AWS_DEFAULT_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

echo "Region: $CURRENT_REGION"
echo "Starting user: $STARTING_USER_NAME"
echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Safety restore: ensure helpful permissions deny policy is removed
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# Disable exit-on-error for idempotent cleanup steps
set +e

# Step 2: Delete the EventBridge Scheduler schedule
echo -e "${YELLOW}Step 2: Deleting EventBridge Scheduler schedule${NC}"
echo "Schedule name: $SCHEDULE_NAME"
echo "Region: $CURRENT_REGION"

if aws scheduler delete-schedule \
    --name "$SCHEDULE_NAME" \
    --region "$CURRENT_REGION" 2>/dev/null; then
    echo -e "${GREEN}✓ Deleted schedule: $SCHEDULE_NAME${NC}"
else
    echo -e "${YELLOW}Schedule '$SCHEDULE_NAME' not found (may have already been deleted by --action-after-completion DELETE, or was never created)${NC}"
fi
echo ""

# Step 3: Detach AdministratorAccess from the starting user
echo -e "${YELLOW}Step 3: Detaching AdministratorAccess from starting user${NC}"
echo "User: $STARTING_USER_NAME"
echo "Policy: $ADMIN_POLICY_ARN"

if aws iam detach-user-policy \
    --user-name "$STARTING_USER_NAME" \
    --policy-arn "$ADMIN_POLICY_ARN" 2>/dev/null; then
    echo -e "${GREEN}✓ Detached AdministratorAccess from $STARTING_USER_NAME${NC}"
else
    echo -e "${YELLOW}AdministratorAccess was not attached to $STARTING_USER_NAME (or was never attached)${NC}"
fi
echo ""

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Deleted schedule '$SCHEDULE_NAME' (or confirmed already gone)"
echo "- Detached AdministratorAccess from $STARTING_USER_NAME (or confirmed not attached)"
echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed.${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply.${NC}\n"
