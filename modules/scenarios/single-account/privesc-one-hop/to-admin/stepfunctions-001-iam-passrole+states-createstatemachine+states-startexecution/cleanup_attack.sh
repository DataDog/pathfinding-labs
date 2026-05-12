#!/bin/bash

# Cleanup script for iam:PassRole + states:CreateStateMachine + states:StartExecution demo
# This script detaches the AdministratorAccess policy from the starting user
# and deletes the state machine created during the demo

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STATE_MACHINE_NAME="pl-prod-stepfunctions-001-to-admin-privesc-sfn"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Step Functions Privilege Escalation Demo Cleanup${NC}"
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

# Get starting user name from grouped output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_stepfunctions_001_iam_passrole_states_createstatemachine_states_startexecution.value // empty')
STARTING_USER_NAME=""
if [ -n "$MODULE_OUTPUT" ]; then
    STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name // empty')
fi

if [ -z "$STARTING_USER_NAME" ]; then
    STARTING_USER_NAME="pl-prod-stepfunctions-001-to-admin-starting-user"
    echo -e "${YELLOW}Warning: Could not get starting user name from terraform, using default: $STARTING_USER_NAME${NC}"
fi

# Set admin credentials
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

echo "Region from Terraform: $CURRENT_REGION"
echo "Starting user: $STARTING_USER_NAME"
echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Verify credentials
IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Authenticated as: $IDENTITY"

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Detach AdministratorAccess from starting user
echo -e "${YELLOW}Step 2: Detaching AdministratorAccess policy from starting user${NC}"
echo "User: $STARTING_USER_NAME"

if aws iam list-attached-user-policies --user-name "$STARTING_USER_NAME" --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' --output text 2>/dev/null | grep -q "AdministratorAccess"; then
    aws iam detach-user-policy \
        --user-name "$STARTING_USER_NAME" \
        --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"
    echo -e "${GREEN}✓ Detached AdministratorAccess from $STARTING_USER_NAME${NC}"
else
    echo -e "${YELLOW}AdministratorAccess not attached to user (may already be detached)${NC}"
fi
echo ""

# Step 3: Delete the state machine
echo -e "${YELLOW}Step 3: Deleting Step Functions state machine${NC}"
echo "Looking for state machine: $STATE_MACHINE_NAME"

# Find the state machine ARN by listing and filtering
STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines \
    --region $CURRENT_REGION \
    --query "stateMachines[?name=='${STATE_MACHINE_NAME}'].stateMachineArn" \
    --output text 2>/dev/null)

if [ -n "$STATE_MACHINE_ARN" ] && [ "$STATE_MACHINE_ARN" != "None" ]; then
    echo "Found state machine ARN: $STATE_MACHINE_ARN"
    aws stepfunctions delete-state-machine \
        --region $CURRENT_REGION \
        --state-machine-arn "$STATE_MACHINE_ARN"
    echo -e "${GREEN}✓ Deleted state machine: $STATE_MACHINE_NAME${NC}"
else
    echo -e "${YELLOW}State machine not found (may already be deleted)${NC}"
fi
echo ""

# Step 4: Verify cleanup
echo -e "${YELLOW}Step 4: Verifying cleanup${NC}"

# Check that AdministratorAccess is detached
ATTACHED=$(aws iam list-attached-user-policies \
    --user-name "$STARTING_USER_NAME" \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' \
    --output text 2>/dev/null)

if [ -z "$ATTACHED" ]; then
    echo -e "${GREEN}✓ AdministratorAccess confirmed detached from user${NC}"
else
    echo -e "${YELLOW}⚠ AdministratorAccess may still be attached${NC}"
fi

# Check that state machine is deleted
REMAINING_ARN=$(aws stepfunctions list-state-machines \
    --region $CURRENT_REGION \
    --query "stateMachines[?name=='${STATE_MACHINE_NAME}'].stateMachineArn" \
    --output text 2>/dev/null)

if [ -z "$REMAINING_ARN" ] || [ "$REMAINING_ARN" == "None" ]; then
    echo -e "${GREEN}✓ State machine confirmed deleted${NC}"
else
    echo -e "${YELLOW}⚠ State machine may still exist (Step Functions deletes are eventually consistent)${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess from: $STARTING_USER_NAME"
echo "- Deleted state machine: $STATE_MACHINE_NAME"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
