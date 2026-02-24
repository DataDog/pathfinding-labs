#!/bin/bash

# Cleanup script for lambda:UpdateFunctionCode + lambda:InvokeFunction privilege escalation demo
# This script restores the original Lambda function code and removes the AdministratorAccess policy


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-lambda-004-to-admin-starting-user"
TARGET_LAMBDA="pl-prod-lambda-004-to-admin-target-lambda"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Lambda UpdateFunctionCode + InvokeFunction${NC}"
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

# Step 2: Detach AdministratorAccess policy from starting user
echo -e "${YELLOW}Step 2: Detaching AdministratorAccess policy from starting user${NC}"
POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

# Check if policy is attached
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[?PolicyArn==`'$POLICY_ARN'`].PolicyArn' \
    --output text)

if [ -n "$ATTACHED_POLICIES" ]; then
    echo "Found AdministratorAccess policy attached to $STARTING_USER"
    aws iam detach-user-policy \
        --user-name $STARTING_USER \
        --policy-arn $POLICY_ARN
    echo -e "${GREEN}✓ Detached AdministratorAccess policy${NC}"
else
    echo -e "${YELLOW}AdministratorAccess policy not attached (may already be removed)${NC}"
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
    echo "  2. Run: terraform apply -replace='module.single_account_privesc_one_hop_to_admin_lambda_004_lambda_updatefunctioncode_lambda_invokefunction[0].aws_lambda_function.target_lambda'"
fi
echo ""

# Step 4: Wait for Lambda to process the update
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

# Verify policy is detached
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[?PolicyArn==`'$POLICY_ARN'`].PolicyArn' \
    --output text)

if [ -z "$ATTACHED_POLICIES" ]; then
    echo -e "${GREEN}✓ AdministratorAccess policy successfully detached${NC}"
else
    echo -e "${YELLOW}⚠ Warning: AdministratorAccess policy still attached to $STARTING_USER${NC}"
fi

# Verify Lambda function exists
if aws lambda get-function \
    --region $CURRENT_REGION \
    --function-name $TARGET_LAMBDA &> /dev/null; then
    echo -e "${GREEN}✓ Lambda function still exists (as expected)${NC}"
else
    echo -e "${RED}⚠ Warning: Lambda function $TARGET_LAMBDA not found${NC}"
fi

# Check that local files are cleaned up
FILES_REMAINING=false
for FILE in "${LOCAL_FILES[@]}"; do
    if [ -f "$FILE" ]; then
        echo -e "${YELLOW}⚠ Warning: Local file still exists: $FILE${NC}"
        FILES_REMAINING=true
    fi
done

if [ "$FILES_REMAINING" = false ]; then
    echo -e "${GREEN}✓ All local temporary files cleaned up${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess policy from $STARTING_USER"
echo "- Restored original Lambda function code (if backup was available)"
echo "- Cleaned up local temporary files"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, and Lambda function) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
