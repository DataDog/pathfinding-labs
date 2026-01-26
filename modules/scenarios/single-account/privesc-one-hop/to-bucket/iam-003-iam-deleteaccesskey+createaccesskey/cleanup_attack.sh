#!/bin/bash

# Cleanup script for iam:DeleteAccessKey + iam:CreateAccessKey demo
# This script removes the newly created access key and ensures the target user
# has 2 access keys again (restoring the original scenario state)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
TARGET_USER="pl-prod-iam-003-to-bucket-target-user"
STARTING_USER="pl-prod-iam-003-to-bucket-starting-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: IAM DeleteAccessKey + CreateAccessKey Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get admin cleanup user credentials from root terraform output
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    echo "Make sure the admin cleanup user is deployed"
    exit 1
fi

# Set admin credentials
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
unset AWS_SESSION_TOKEN

echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Check current state of target user's access keys
echo -e "${YELLOW}Step 2: Checking current state of target user's access keys${NC}"
echo "Target user: $TARGET_USER"
echo ""

CURRENT_KEYS=$(aws iam list-access-keys --user-name $TARGET_USER --query 'AccessKeyMetadata[].AccessKeyId' --output text)
CURRENT_KEY_COUNT=$(echo "$CURRENT_KEYS" | wc -w | xargs)

echo "Current access keys for $TARGET_USER:"
aws iam list-access-keys --user-name $TARGET_USER --output table
echo ""
echo "Total keys: $CURRENT_KEY_COUNT"
echo ""

# Step 3: Delete the newly created access key
echo -e "${YELLOW}Step 3: Deleting the newly created access key${NC}"

# Check if we have the created key ID saved
CREATED_KEY_FILE="/tmp/iam-003-created-key-id-${ACCOUNT_ID}.txt"
if [ -f "$CREATED_KEY_FILE" ]; then
    CREATED_KEY_ID=$(cat "$CREATED_KEY_FILE")
    echo "Found created key ID from demo: $CREATED_KEY_ID"

    if aws iam get-access-key-last-used --access-key-id $CREATED_KEY_ID &> /dev/null; then
        echo "Deleting access key: $CREATED_KEY_ID"
        aws iam delete-access-key \
            --user-name $TARGET_USER \
            --access-key-id $CREATED_KEY_ID
        echo -e "${GREEN}✓ Deleted created access key${NC}"
        rm -f "$CREATED_KEY_FILE"
    else
        echo -e "${YELLOW}Access key $CREATED_KEY_ID not found (may already be deleted)${NC}"
        rm -f "$CREATED_KEY_FILE"
    fi
else
    echo -e "${YELLOW}No record of created key ID found${NC}"
    echo "This is expected if the demo didn't complete or was run previously"
fi
echo ""

# Step 4: Ensure target user has exactly 2 access keys
echo -e "${YELLOW}Step 4: Ensuring target user has 2 access keys${NC}"

# Recount keys after deletion
UPDATED_KEYS=$(aws iam list-access-keys --user-name $TARGET_USER --query 'AccessKeyMetadata[].AccessKeyId' --output text)
UPDATED_KEY_COUNT=$(echo "$UPDATED_KEYS" | wc -w | xargs)

echo "Current key count after cleanup: $UPDATED_KEY_COUNT"

if [ "$UPDATED_KEY_COUNT" -lt 2 ]; then
    KEYS_NEEDED=$((2 - UPDATED_KEY_COUNT))
    echo "Need to create $KEYS_NEEDED additional key(s) to restore the 2-key limit scenario"

    for i in $(seq 1 $KEYS_NEEDED); do
        echo "Creating replacement access key $i..."
        NEW_KEY=$(aws iam create-access-key --user-name $TARGET_USER --output json)
        NEW_KEY_ID=$(echo "$NEW_KEY" | jq -r '.AccessKey.AccessKeyId')
        echo "Created new key: $NEW_KEY_ID"
    done

    echo -e "${GREEN}✓ Restored target user to 2-key limit${NC}"
elif [ "$UPDATED_KEY_COUNT" -eq 2 ]; then
    echo -e "${GREEN}✓ Target user already has 2 keys${NC}"
elif [ "$UPDATED_KEY_COUNT" -gt 2 ]; then
    echo -e "${YELLOW}Warning: Target user has more than 2 keys ($UPDATED_KEY_COUNT)${NC}"
    echo "This shouldn't happen - AWS limit is 2 keys per user"
fi
echo ""

# Step 5: Verify final state
echo -e "${YELLOW}Step 5: Verifying final state${NC}"
echo "Final access keys for $TARGET_USER:"
aws iam list-access-keys --user-name $TARGET_USER --output table
FINAL_KEY_COUNT=$(aws iam list-access-keys --user-name $TARGET_USER --query 'AccessKeyMetadata[].AccessKeyId' --output text | wc -w | xargs)
echo "Total keys: $FINAL_KEY_COUNT"

if [ "$FINAL_KEY_COUNT" -eq 2 ]; then
    echo -e "${GREEN}✓ Target user has exactly 2 access keys (at AWS limit)${NC}"
else
    echo -e "${YELLOW}Warning: Expected 2 keys but found $FINAL_KEY_COUNT${NC}"
fi
echo ""

# Step 6: Remove local temporary files
echo -e "${YELLOW}Step 6: Removing local temporary files${NC}"

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
