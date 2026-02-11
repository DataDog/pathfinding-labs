#!/bin/bash

# Cleanup script for Lambda UpdateFunctionCode + IAM CreateAccessKey multi-hop privilege escalation demo
# This script restores the original Lambda function code and deletes access keys created during the attack

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
TARGET_LAMBDA="pl-prod-lambda-004-to-iam-002-target-function"
ADMIN_USER="pl-prod-lambda-004-to-iam-002-admin-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Lambda-004 to IAM-002 Multi-Hop${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get admin cleanup user credentials from root terraform output
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    echo "Make sure the admin cleanup user is deployed"
    exit 1
fi

if [ -z "$CURRENT_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    CURRENT_REGION="us-east-1"
fi

# Set admin credentials
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

echo "Region from Terraform: $CURRENT_REGION"
echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Delete access keys created for admin user during demo
echo -e "${YELLOW}Step 2: Deleting access keys for $ADMIN_USER${NC}"

# List all access keys for the admin user
ACCESS_KEYS=$(aws iam list-access-keys --user-name $ADMIN_USER --query 'AccessKeyMetadata[*].AccessKeyId' --output text 2>/dev/null || echo "")

if [ -z "$ACCESS_KEYS" ]; then
    echo -e "${YELLOW}No access keys found for $ADMIN_USER (may already be deleted or user has no keys)${NC}"
else
    echo "Found access keys to delete:"
    for KEY_ID in $ACCESS_KEYS; do
        echo "  - $KEY_ID"
    done
    echo ""

    # Delete each access key
    for KEY_ID in $ACCESS_KEYS; do
        echo "Deleting access key: $KEY_ID"
        aws iam delete-access-key \
            --user-name $ADMIN_USER \
            --access-key-id $KEY_ID 2>/dev/null || echo -e "${YELLOW}Could not delete key $KEY_ID (may already be deleted)${NC}"
        echo -e "${GREEN}✓ Deleted access key: $KEY_ID${NC}"
    done
fi
echo ""

# Step 3: Restore original Lambda function code
echo -e "${YELLOW}Step 3: Restoring original Lambda function code${NC}"
echo "Target Lambda function: $TARGET_LAMBDA"

# Check if backup exists
if [ -f /tmp/original_lambda_backup.zip ]; then
    echo "Found backup of original code at /tmp/original_lambda_backup.zip"
    echo "Restoring original Lambda function code..."

    UPDATE_RESULT=$(aws lambda update-function-code \
        --region $CURRENT_REGION \
        --function-name $TARGET_LAMBDA \
        --zip-file fileb:///tmp/original_lambda_backup.zip \
        --output json 2>&1)

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Successfully restored original Lambda function code${NC}"
    else
        echo -e "${RED}Error: Failed to restore Lambda function code${NC}"
        echo "$UPDATE_RESULT"
    fi
else
    echo -e "${YELLOW}Backup file not found at /tmp/original_lambda_backup.zip${NC}"
    echo -e "${YELLOW}The Lambda function code may need to be restored manually or via Terraform${NC}"
    echo ""
    echo -e "${BLUE}To restore via Terraform:${NC}"
    echo "  1. Navigate to project root"
    echo "  2. Run: terraform apply -replace='module.single_account_privesc_multi_hop_to_admin_lambda_004_to_iam_002[0].aws_lambda_function.target_function'"
fi
echo ""

# Step 4: Wait for Lambda to process the update (if restored)
if [ -f /tmp/original_lambda_backup.zip ]; then
    echo -e "${YELLOW}Step 4: Waiting for Lambda to process code restoration${NC}"
    echo "Allowing time for Lambda to deploy the original code..."
    sleep 10
    echo -e "${GREEN}✓ Lambda function restored${NC}\n"
fi

# Step 5: Clean up local temporary files
echo -e "${YELLOW}Step 5: Cleaning up local temporary files${NC}"
LOCAL_FILES=(
    "/tmp/lambda_function.py"
    "/tmp/lambda_function.zip"
    "/tmp/response.json"
    "/tmp/original_lambda_backup.zip"
)

CLEANED_COUNT=0
for FILE in "${LOCAL_FILES[@]}"; do
    if [ -f "$FILE" ]; then
        rm -f "$FILE"
        echo "Removed: $FILE"
        CLEANED_COUNT=$((CLEANED_COUNT + 1))
    fi
done

if [ $CLEANED_COUNT -gt 0 ]; then
    echo -e "${GREEN}✓ Cleaned up $CLEANED_COUNT local file(s)${NC}"
else
    echo -e "${YELLOW}No local temporary files found${NC}"
fi
echo ""

# Step 6: Verify cleanup
echo -e "${YELLOW}Step 6: Verifying cleanup${NC}"

# Verify access keys are deleted
REMAINING_KEYS=$(aws iam list-access-keys --user-name $ADMIN_USER --query 'AccessKeyMetadata[*].AccessKeyId' --output text 2>/dev/null || echo "")
if [ -z "$REMAINING_KEYS" ]; then
    echo -e "${GREEN}✓ All access keys deleted for $ADMIN_USER${NC}"
else
    echo -e "${YELLOW}Warning: Some access keys may still exist for $ADMIN_USER: $REMAINING_KEYS${NC}"
fi

# Verify Lambda function exists
if aws lambda get-function \
    --region $CURRENT_REGION \
    --function-name $TARGET_LAMBDA &> /dev/null; then
    echo -e "${GREEN}✓ Lambda function still exists (as expected)${NC}"
else
    echo -e "${RED}Warning: Lambda function $TARGET_LAMBDA not found${NC}"
fi

# Check that local files are cleaned up
FILES_REMAINING=false
for FILE in "${LOCAL_FILES[@]}"; do
    if [ -f "$FILE" ]; then
        echo -e "${YELLOW}Warning: Local file still exists: $FILE${NC}"
        FILES_REMAINING=true
    fi
done

if [ "$FILES_REMAINING" = false ]; then
    echo -e "${GREEN}✓ All local temporary files cleaned up${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Deleted all access keys for $ADMIN_USER"
echo "- Restored original Lambda function code (if backup was available)"
echo "- Cleaned up local temporary files"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, and Lambda function) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
