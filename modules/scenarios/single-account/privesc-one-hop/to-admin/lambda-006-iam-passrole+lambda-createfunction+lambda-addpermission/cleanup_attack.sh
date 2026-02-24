#!/bin/bash

# Cleanup script for iam:PassRole + lambda:CreateFunction + lambda:AddPermission privilege escalation demo
# This script removes the Lambda function and detaches the admin policy from the starting user


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-lambda-006-to-admin-starting-user"
LAMBDA_FUNCTION_NAME="pl-lambda-006-malicious-function"
ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: PassRole + Lambda CreateFunction + AddPermission${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get admin cleanup user credentials from root terraform output
ADMIN_ACCESS_KEY=$(OTEL_TRACES_EXPORTER= terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(OTEL_TRACES_EXPORTER= terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
CURRENT_REGION=$(OTEL_TRACES_EXPORTER= terraform output -raw aws_region 2>/dev/null || echo "")

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
echo "User: $STARTING_USER"
echo "Policy: $ADMIN_POLICY_ARN"

# Check if the policy is attached
if aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --query "AttachedPolicies[?PolicyArn=='$ADMIN_POLICY_ARN']" \
    --output text | grep -q "$ADMIN_POLICY_ARN"; then

    echo "Found AdministratorAccess attached to user"

    # Detach the policy
    aws iam detach-user-policy \
        --user-name "$STARTING_USER" \
        --policy-arn "$ADMIN_POLICY_ARN"

    echo -e "${GREEN}✓ Detached AdministratorAccess from $STARTING_USER${NC}"
else
    echo -e "${YELLOW}AdministratorAccess not attached to $STARTING_USER (may already be detached)${NC}"
fi
echo ""

# Step 3: Delete the Lambda function
echo -e "${YELLOW}Step 3: Deleting Lambda function${NC}"
echo "Function name: $LAMBDA_FUNCTION_NAME"
echo "Region: $CURRENT_REGION"

# Check if the function exists
if aws lambda get-function \
    --region $CURRENT_REGION \
    --function-name $LAMBDA_FUNCTION_NAME &> /dev/null; then

    echo "Found Lambda function: $LAMBDA_FUNCTION_NAME"

    # Delete the function (this also removes the resource-based policy)
    aws lambda delete-function \
        --region $CURRENT_REGION \
        --function-name $LAMBDA_FUNCTION_NAME

    echo -e "${GREEN}✓ Deleted Lambda function: $LAMBDA_FUNCTION_NAME${NC}"
else
    echo -e "${YELLOW}Lambda function $LAMBDA_FUNCTION_NAME not found (may already be deleted)${NC}"
fi
echo ""

# Step 4: Clean up local temporary files
echo -e "${YELLOW}Step 4: Cleaning up local temporary files${NC}"
LOCAL_FILES=("/tmp/lambda_function.py" "/tmp/lambda_function.zip" "/tmp/response.json")

FILES_DELETED=false
for FILE in "${LOCAL_FILES[@]}"; do
    if [ -f "$FILE" ]; then
        rm -f "$FILE"
        echo "Removed: $FILE"
        FILES_DELETED=true
    fi
done

if [ "$FILES_DELETED" = false ]; then
    echo "No local temporary files found"
fi

echo -e "${GREEN}✓ Cleaned up local files${NC}"
echo ""

# Step 5: Verify cleanup
echo -e "${YELLOW}Step 5: Verifying cleanup${NC}"

# Check that AdministratorAccess is not attached to starting user
if aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --query "AttachedPolicies[?PolicyArn=='$ADMIN_POLICY_ARN']" \
    --output text | grep -q "$ADMIN_POLICY_ARN"; then
    echo -e "${YELLOW}⚠ Warning: AdministratorAccess still attached to $STARTING_USER${NC}"
else
    echo -e "${GREEN}✓ AdministratorAccess successfully detached from starting user${NC}"
fi

# Check that the Lambda function no longer exists
if aws lambda get-function \
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
echo "- Detached AdministratorAccess policy from: $STARTING_USER"
echo "- Deleted Lambda function: $LAMBDA_FUNCTION_NAME"
echo "- Cleaned up local temporary files"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
