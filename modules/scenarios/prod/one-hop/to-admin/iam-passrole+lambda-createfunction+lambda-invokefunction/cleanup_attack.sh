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

# Step 0: Get region from Terraform
echo -e "${YELLOW}Retrieving region from Terraform configuration${NC}"
cd ../../../../../..  # Navigate to root of terraform project

CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$CURRENT_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    CURRENT_REGION="us-east-1"
fi

echo "Region from Terraform: $CURRENT_REGION"

# Navigate back to scenario directory
cd - > /dev/null
echo ""

# Try to use the admin cleanup profile, but fall back to default credentials if not available
echo "Checking AWS credentials..."
if aws sts get-caller-identity --profile $PROFILE &> /dev/null; then
    echo "Using AWS profile: $PROFILE"
    AWS_PROFILE_FLAG="--profile $PROFILE"
elif [ -n "$AWS_ACCESS_KEY_ID" ]; then
    echo "Using AWS credentials from environment variables"
    AWS_PROFILE_FLAG=""
else
    echo -e "${RED}Error: No AWS credentials available${NC}"
    echo "Either configure the '$PROFILE' profile or set AWS environment variables"
    exit 1
fi

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity $AWS_PROFILE_FLAG --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 1: Delete the Lambda function
echo -e "${YELLOW}Step 1: Deleting Lambda function${NC}"
echo "Function name: $LAMBDA_FUNCTION_NAME"
echo "Region: $CURRENT_REGION"

# Check if the function exists
if aws lambda get-function \
    $AWS_PROFILE_FLAG \
    --region $CURRENT_REGION \
    --function-name $LAMBDA_FUNCTION_NAME &> /dev/null; then

    echo "Found Lambda function: $LAMBDA_FUNCTION_NAME"

    # Delete the function
    aws lambda delete-function \
        $AWS_PROFILE_FLAG \
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
    $AWS_PROFILE_FLAG \
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
