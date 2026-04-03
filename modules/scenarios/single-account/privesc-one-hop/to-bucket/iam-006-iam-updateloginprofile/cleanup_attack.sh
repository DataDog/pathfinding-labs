#!/bin/bash

# Cleanup script for iam:UpdateLoginProfile to S3 bucket access demo
# This script restores the original password for the bucket user and removes artifacts


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Source demo permissions library for safety restore
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Safety: remove any orphaned restriction policies
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# Configuration
BUCKET_USER="pl-prod-iam-006-to-bucket-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Restoring Original Password${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Extract admin cleanup user credentials from Terraform outputs
echo -e "${YELLOW}Extracting admin cleanup user credentials from Terraform outputs${NC}"
TERRAFORM_DIR="../../../../../.."

# Check if AWS credentials are already set in environment (and they're admin credentials)
if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$CLEANUP_USER_CREDENTIALS" ]; then
    echo "Using existing admin cleanup credentials from environment variables"
else
    # Extract admin cleanup user credentials from Terraform outputs
    pushd $TERRAFORM_DIR > /dev/null

    ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
    SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

    if [ -z "$ACCESS_KEY" ] || [ "$ACCESS_KEY" == "null" ] || [ -z "$SECRET_KEY" ] || [ "$SECRET_KEY" == "null" ]; then
        echo -e "${RED}Error: Could not retrieve admin cleanup user credentials from Terraform outputs${NC}"
        echo "Make sure the base infrastructure is deployed: terraform apply"
        popd > /dev/null
        exit 1
    fi

    popd > /dev/null

    # Export credentials as environment variables
    export AWS_ACCESS_KEY_ID=$ACCESS_KEY
    export AWS_SECRET_ACCESS_KEY=$SECRET_KEY
    unset AWS_SESSION_TOKEN  # Clear any session token

    echo -e "${GREEN}✓ Successfully extracted and configured admin cleanup user credentials${NC}"
fi

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 1: Check if we have the original password saved
echo -e "${YELLOW}Step 1: Looking for saved original password${NC}"

if [ -f /tmp/original_password_iam_006_bucket.txt ]; then
    ORIGINAL_PASSWORD=$(cat /tmp/original_password_iam_006_bucket.txt)
    echo -e "${GREEN}✓ Found saved original password${NC}"

    # Step 2: Restore the original password
    echo -e "\n${YELLOW}Step 2: Restoring original password${NC}"

    aws iam update-login-profile \
        --user-name $BUCKET_USER \
        --password "$ORIGINAL_PASSWORD" \
        --no-password-reset-required

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Successfully restored original password${NC}"

        # Clean up temporary file
        rm /tmp/original_password_iam_006_bucket.txt
        echo -e "${GREEN}✓ Removed temporary password file${NC}"
    else
        echo -e "${RED}Failed to restore original password${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}No saved original password found${NC}"
    echo "Note: The password was changed but we don't have the original to restore"
    echo ""

    # Step 2: Get password from Terraform and restore it
    echo -e "${YELLOW}Step 2: Getting original password from Terraform state${NC}"

    pushd $TERRAFORM_DIR > /dev/null

    ORIGINAL_PASSWORD=$(terraform output -raw prod_one_hop_to_bucket_iam_updateloginprofile_original_password 2>/dev/null || echo "")

    popd > /dev/null

    if [ ! -z "$ORIGINAL_PASSWORD" ] && [ "$ORIGINAL_PASSWORD" != "null" ]; then
        echo -e "${GREEN}✓ Retrieved original password from Terraform${NC}"

        echo -e "\n${YELLOW}Step 3: Restoring original password${NC}"

        aws iam update-login-profile \
            --user-name $BUCKET_USER \
            --password "$ORIGINAL_PASSWORD" \
            --no-password-reset-required

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Successfully restored original password${NC}"
        else
            echo -e "${RED}Failed to restore original password${NC}"
            exit 1
        fi
    else
        echo -e "${YELLOW}Unable to retrieve original password from Terraform${NC}"
        echo "The bucket user's password remains changed"
        echo "You may need to manually reset it or run 'terraform apply' to restore the original state"
    fi
fi

# Step 3: Delete any access keys that were created during the demo
echo -e "\n${YELLOW}Step 3: Checking for demo-created access keys${NC}"
ACCESS_KEYS=$(aws iam list-access-keys --user-name $BUCKET_USER --query 'AccessKeyMetadata[*].AccessKeyId' --output text)

if [ -n "$ACCESS_KEYS" ]; then
    echo "Found access keys for $BUCKET_USER"

    # Check if there are more keys than the Terraform-managed one (if any)
    KEY_COUNT=$(echo $ACCESS_KEYS | wc -w)
    echo "Total access keys: $KEY_COUNT"

    # Get the Terraform-managed key (if it exists)
    pushd $TERRAFORM_DIR > /dev/null
    TERRAFORM_KEY=$(terraform output -raw prod_one_hop_to_bucket_iam_updateloginprofile_bucket_user_access_key_id 2>/dev/null || echo "")
    popd > /dev/null

    for KEY in $ACCESS_KEYS; do
        # Skip the Terraform-managed key
        if [ ! -z "$TERRAFORM_KEY" ] && [ "$KEY" == "$TERRAFORM_KEY" ]; then
            echo "Keeping Terraform-managed key: $KEY"
            continue
        fi

        echo "Deleting demo-created access key: $KEY"
        aws iam delete-access-key \
            --user-name $BUCKET_USER \
            --access-key-id $KEY
        echo -e "${GREEN}✓ Deleted access key: $KEY${NC}"
    done
else
    echo -e "${YELLOW}No access keys found for $BUCKET_USER${NC}"
fi
echo ""

# Step 4: Remove local temporary files
echo -e "${YELLOW}Step 4: Removing local temporary files${NC}"
DOWNLOAD_FILE="/tmp/iam-006-bucket-sensitive-data-${ACCOUNT_ID}.txt"

if [ -f "$DOWNLOAD_FILE" ]; then
    rm -f "$DOWNLOAD_FILE"
    echo -e "${GREEN}✓ Deleted $DOWNLOAD_FILE${NC}"
else
    echo "No downloaded file found at $DOWNLOAD_FILE"
fi
echo ""

# Step 5: Verify the user still has a login profile
echo -e "${YELLOW}Step 5: Verifying login profile status${NC}"

if aws iam get-login-profile --user-name $BUCKET_USER &> /dev/null; then
    echo -e "${GREEN}✓ Login profile still exists for $BUCKET_USER${NC}"
    LOGIN_PROFILE_INFO=$(aws iam get-login-profile --user-name $BUCKET_USER --output json)
    MODIFIED_DATE=$(echo $LOGIN_PROFILE_INFO | jq -r '.LoginProfile.CreateDate')
    echo "Login profile last modified: $MODIFIED_DATE"
else
    echo -e "${RED}⚠ Login profile not found for $BUCKET_USER${NC}"
fi

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Restored original password for user: $BUCKET_USER"
echo "- Deleted any demo-created access keys"
echo "- Removed local temporary files"
echo "- Bucket user retains both console and S3 access permissions"
echo "- Login profile remains active"

echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, bucket) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
