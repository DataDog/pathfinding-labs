#!/bin/bash
set -e

# Cleanup script for iam:PassRole + lambda:CreateFunction + lambda:CreateEventSourceMapping (DynamoDB) to S3 bucket demo
# This script removes the Lambda function and event source mapping created during the demo.
# The exfil DynamoDB table item written by Lambda is left in place (it is cleaned by terraform destroy).

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
LAMBDA_FUNCTION_NAME="pl-lambda-002-to-bucket-escalation-fn"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: IAM PassRole + Lambda CreateFunction + CreateEventSourceMapping (DynamoDB) to Bucket${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

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

export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
export AWS_DEFAULT_REGION="$AWS_REGION"
unset AWS_SESSION_TOKEN

echo "Region from Terraform: $CURRENT_REGION"
echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Safety restore: ensure helpful permissions deny policy is removed
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Find and delete event source mappings for the Lambda function
echo -e "${YELLOW}Step 2: Deleting event source mappings${NC}"
echo "Searching for event source mappings for function: $LAMBDA_FUNCTION_NAME"

if aws lambda get-function \
    --region $CURRENT_REGION \
    --function-name $LAMBDA_FUNCTION_NAME &> /dev/null; then

    echo "Lambda function exists, checking for event source mappings..."

    EVENT_SOURCE_MAPPINGS=$(aws lambda list-event-source-mappings \
        --region $CURRENT_REGION \
        --function-name $LAMBDA_FUNCTION_NAME \
        --query 'EventSourceMappings[*].UUID' \
        --output text)

    if [ -n "$EVENT_SOURCE_MAPPINGS" ]; then
        echo "Found event source mappings to delete"
        for UUID in $EVENT_SOURCE_MAPPINGS; do
            echo "Deleting event source mapping: $UUID"
            aws lambda delete-event-source-mapping \
                --region $CURRENT_REGION \
                --uuid $UUID \
                --output json > /dev/null
            echo -e "${GREEN}✓ Deleted event source mapping: $UUID${NC}"
        done
    else
        echo -e "${YELLOW}No event source mappings found (may already be deleted)${NC}"
    fi
else
    echo -e "${YELLOW}Lambda function not found, skipping event source mapping deletion${NC}"
    EVENT_SOURCE_MAPPINGS=""
fi
echo ""

# Step 3: Brief wait for ESM deletion to propagate before deleting the function
if [ -n "$EVENT_SOURCE_MAPPINGS" ]; then
    echo -e "${YELLOW}Step 3: Allowing event source mapping deletion to propagate${NC}"
    sleep 10
    echo -e "${GREEN}✓ Done${NC}\n"
fi

# Step 4: Delete the Lambda function
echo -e "${YELLOW}Step 4: Deleting Lambda function${NC}"
echo "Function name: $LAMBDA_FUNCTION_NAME"
echo "Region: $CURRENT_REGION"

if aws lambda get-function \
    --region $CURRENT_REGION \
    --function-name $LAMBDA_FUNCTION_NAME &> /dev/null; then

    aws lambda delete-function \
        --region $CURRENT_REGION \
        --function-name $LAMBDA_FUNCTION_NAME

    echo -e "${GREEN}✓ Deleted Lambda function: $LAMBDA_FUNCTION_NAME${NC}"
else
    echo -e "${YELLOW}Lambda function $LAMBDA_FUNCTION_NAME not found (may already be deleted)${NC}"
fi
echo ""

# Step 5: Clean up local temporary files
echo -e "${YELLOW}Step 5: Cleaning up local temporary files${NC}"
LOCAL_FILES=("/tmp/lambda_function.py" "/tmp/lambda_function.zip")

for FILE in "${LOCAL_FILES[@]}"; do
    if [ -f "$FILE" ]; then
        rm -f "$FILE"
        echo "Removed: $FILE"
    fi
done

echo -e "${GREEN}✓ Cleaned up local files${NC}"
echo ""

# Step 6: Verify cleanup
echo -e "${YELLOW}Step 6: Verifying cleanup${NC}"

if aws lambda get-function \
    --region $CURRENT_REGION \
    --function-name $LAMBDA_FUNCTION_NAME &> /dev/null; then
    echo -e "${YELLOW}⚠ Warning: Lambda function $LAMBDA_FUNCTION_NAME still exists${NC}"
else
    echo -e "${GREEN}✓ Lambda function successfully deleted${NC}"
fi

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
echo "- Deleted event source mappings linking Lambda to DynamoDB stream"
echo "- Deleted Lambda function: $LAMBDA_FUNCTION_NAME"
echo "- Cleaned up local temporary files"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, DynamoDB tables, and S3 bucket) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
