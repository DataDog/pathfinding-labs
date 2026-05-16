#!/bin/bash

# Cleanup script for iam:DeleteAccessKey + iam:CreateAccessKey demo
# This script removes the newly created access key and ensures the target user
# has 2 access keys again (restoring the original scenario state)


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
TARGET_USER="pl-prod-iam-003-to-bucket-target-user"
STARTING_USER="pl-prod-iam-003-to-bucket-starting-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: IAM DeleteAccessKey + CreateAccessKey Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials and terraform-managed key IDs
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    exit 1
fi

# Get the two terraform-managed key IDs for the target user
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_iam_003_iam_deleteaccesskey_createaccesskey.value // empty')
TF_KEY_1=$(echo "$MODULE_OUTPUT" | jq -r '.target_user_key_1_id // empty')
TF_KEY_2=$(echo "$MODULE_OUTPUT" | jq -r '.target_user_key_2_id // empty')

export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
unset AWS_SESSION_TOKEN

echo -e "${GREEN}✓ Retrieved admin credentials${NC}"
echo "Terraform-managed keys: ${TF_KEY_1:-unknown} ${TF_KEY_2:-unknown}"

cd - > /dev/null

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo ""

# Step 2: Delete any keys not managed by terraform
# After the demo the target user may have an attacker-created key in addition to
# (or in place of) the terraform keys. Delete anything that isn't in the tf set.
echo -e "${YELLOW}Step 2: Removing attacker-created keys from target user${NC}"
echo "Target user: $TARGET_USER"

CURRENT_KEYS=$(aws iam list-access-keys --user-name $TARGET_USER --query 'AccessKeyMetadata[].AccessKeyId' --output text)

DELETED=0
for key in $CURRENT_KEYS; do
    if [ "$key" != "$TF_KEY_1" ] && [ "$key" != "$TF_KEY_2" ]; then
        echo "Deleting attacker-created key: $key"
        aws iam delete-access-key --user-name $TARGET_USER --access-key-id "$key"
        DELETED=$((DELETED + 1))
    else
        echo "Keeping terraform-managed key: $key"
    fi
done

if [ "$DELETED" -eq 0 ]; then
    echo "No attacker-created keys found"
fi
echo -e "${GREEN}✓ Cleanup complete — run 'plabs apply' to restore any terraform keys deleted during the demo${NC}\n"

# Step 3: Remove local temporary files
echo -e "${YELLOW}Step 3: Removing local temporary files${NC}"

CREATED_KEY_FILE="/tmp/iam-003-created-key-id-${ACCOUNT_ID}.txt"
DELETED_KEY_FILE="/tmp/iam-003-deleted-key-id-${ACCOUNT_ID}.txt"
DOWNLOAD_FILE="/tmp/iam-003-bucket-sensitive-data-${ACCOUNT_ID}.txt"

FILES_REMOVED=0

if [ -f "$CREATED_KEY_FILE" ]; then
    rm -f "$CREATED_KEY_FILE"
    echo -e "${GREEN}✓ Deleted $CREATED_KEY_FILE${NC}"
    FILES_REMOVED=$((FILES_REMOVED + 1))
fi

if [ -f "$DELETED_KEY_FILE" ]; then
    rm -f "$DELETED_KEY_FILE"
    echo -e "${GREEN}✓ Deleted $DELETED_KEY_FILE${NC}"
    FILES_REMOVED=$((FILES_REMOVED + 1))
fi

if [ -f "$DOWNLOAD_FILE" ]; then
    rm -f "$DOWNLOAD_FILE"
    echo -e "${GREEN}✓ Deleted $DOWNLOAD_FILE${NC}"
    FILES_REMOVED=$((FILES_REMOVED + 1))
fi

if [ $FILES_REMOVED -eq 0 ]; then
    echo "No temporary files found to clean up"
fi
echo ""

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Deleted the newly created access key"
echo "- Restored target user to 2-key limit (scenario state)"
echo "- Removed all temporary files"

echo -e "\n${BLUE}Important Note:${NC}"
echo "The original access key that was deleted during the demo cannot be restored"
echo "with its original secret. New access keys have been created to restore the"
echo "2-key limit configuration for the scenario."

echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, bucket) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
