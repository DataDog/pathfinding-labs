#!/bin/bash

# Cleanup script for iam:PassRole + lambda:CreateFunction + lambda:InvokeFunction privilege escalation demo
# This script removes the Lambda function created during the demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROFILE="pl-admin-cleanup-prod"
LAMBDA_FUNCTION_NAME="pl-plcflif-credential-extractor"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Lambda CreateFunction + InvokeFunction Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 0: Get admin credentials from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

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

# Get region from Terraform
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$CURRENT_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    CURRENT_REGION="us-east-1"
fi

echo "Region from Terraform: $CURRENT_REGION"

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"

cd - > /dev/null  # Return to scenario directory
echo ""

# Step 1: Delete the Lambda function
echo -e "${YELLOW}Step 1: Deleting Lambda function${NC}"
echo "Function name: $LAMBDA_FUNCTION_NAME"
echo "Region: $CURRENT_REGION"

# Check if the function exists
if aws lambda get-function \
     \
    --region $CURRENT_REGION \
    --function-name $LAMBDA_FUNCTION_NAME &> /dev/null; then

    echo "Found Lambda function: $LAMBDA_FUNCTION_NAME"

    # Delete the function
    aws lambda delete-function \
         \
        --region $CURRENT_REGION \
        --function-name $LAMBDA_FUNCTION_NAME

    echo -e "${GREEN}✓ Deleted Lambda function: $LAMBDA_FUNCTION_NAME${NC}"
else
    echo -e "${YELLOW}Lambda function $LAMBDA_FUNCTION_NAME not found (may already be deleted)${NC}"
fi
echo ""

# Step 2: Clean up local temporary files
echo -e "${YELLOW}Step 2: Cleaning up local temporary files${NC}"
LOCAL_FILES=("/tmp/lambda_function.py" "/tmp/lambda_function.zip" "/tmp/response.json")

for FILE in "${LOCAL_FILES[@]}"; do
    if [ -f "$FILE" ]; then
        rm -f "$FILE"
        echo "Removed: $FILE"
    fi
done

echo -e "${GREEN}✓ Cleaned up local files${NC}"
echo ""

# Step 3: Verify cleanup
echo -e "${YELLOW}Step 3: Verifying cleanup${NC}"

# Check that the Lambda function no longer exists
if aws lambda get-function \
     \
    --region $CURRENT_REGION \
    --function-name $LAMBDA_FUNCTION_NAME &> /dev/null; then
    echo -e "${YELLOW}⚠ Warning: Lambda function $LAMBDA_FUNCTION_NAME still exists${NC}"
else
    echo -e "${GREEN}✓ Lambda function successfully deleted${NC}"
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
echo "- Deleted Lambda function: $LAMBDA_FUNCTION_NAME"
echo "- Cleaned up local temporary files"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
