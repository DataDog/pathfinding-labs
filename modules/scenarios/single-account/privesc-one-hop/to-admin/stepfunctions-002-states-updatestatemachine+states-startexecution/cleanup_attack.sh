#!/bin/bash

# Cleanup script for stepfunctions-002 privilege escalation demo
# Detaches AdministratorAccess from the starting user and restores the state
# machine to its benign initial definition.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-stepfunctions-002-to-admin-starting-user"
ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: stepfunctions-002 (UpdateStateMachine + StartExecution)${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials and region from Terraform
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

# Get the state machine ARN from the scenario module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_stepfunctions_002_states_updatestatemachine_states_startexecution.value // empty')
STATE_MACHINE_ARN=""
if [ -n "$MODULE_OUTPUT" ]; then
    STATE_MACHINE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.state_machine_arn // empty')
fi

# Set admin credentials
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

echo "Region from Terraform: $CURRENT_REGION"
if [ -n "$STATE_MACHINE_ARN" ]; then
    echo "State machine ARN: $STATE_MACHINE_ARN"
fi
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
echo ""

# Step 2: Detach AdministratorAccess from the starting user
echo -e "${YELLOW}Step 2: Detaching AdministratorAccess from starting user${NC}"
echo "User: $STARTING_USER"
echo "Policy: $ADMIN_POLICY_ARN"

# Check if the policy is attached before attempting detach
ATTACHED=$(aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --query "AttachedPolicies[?PolicyArn=='$ADMIN_POLICY_ARN'].PolicyArn" \
    --output text 2>/dev/null || true)

if [ -n "$ATTACHED" ]; then
    aws iam detach-user-policy \
        --user-name "$STARTING_USER" \
        --policy-arn "$ADMIN_POLICY_ARN"
    echo -e "${GREEN}✓ Detached AdministratorAccess from $STARTING_USER${NC}"
else
    echo -e "${YELLOW}AdministratorAccess was not attached (may already be cleaned up)${NC}"
fi
echo ""

# Step 3: Restore the state machine to its benign definition
echo -e "${YELLOW}Step 3: Restoring state machine to benign definition${NC}"

if [ -n "$STATE_MACHINE_ARN" ]; then
    echo "State machine: $STATE_MACHINE_ARN"
    BENIGN_DEFINITION='{"Comment":"Benign initial definition","StartAt":"Done","States":{"Done":{"Type":"Pass","Result":"ok","End":true}}}'
    if aws stepfunctions update-state-machine \
        --state-machine-arn "$STATE_MACHINE_ARN" \
        --definition "$BENIGN_DEFINITION" \
        --region "$CURRENT_REGION" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Restored state machine to benign definition${NC}"
    else
        echo -e "${YELLOW}Could not restore state machine definition (may not be deployed or already benign)${NC}"
    fi
else
    echo -e "${YELLOW}State machine ARN not available — skipping definition restore${NC}"
fi
echo ""

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess from: $STARTING_USER"
echo "- Restored state machine to benign Pass definition"
echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, state machine) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Remove demo active marker
rm -f "$(dirname "$0")/.demo_active"
