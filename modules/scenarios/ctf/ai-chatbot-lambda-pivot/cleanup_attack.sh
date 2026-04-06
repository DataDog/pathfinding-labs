#!/bin/bash

# Cleanup script for CTF-002: AI Chatbot Prompt Injection → Lambda Pivot → Admin
#
# The ctf-002 attack modifies the target Lambda's code (pl-prod-ctf-002-acme-data-processor).
# This script restores the original benign code from the committed zip.

export AWS_PAGER=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_LAMBDA="pl-prod-ctf-002-acme-data-processor"

# Source demo permissions library
source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: CTF-002 AI Chatbot Lambda Pivot${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd "../../../../" || exit 1

ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    echo "Make sure the admin cleanup user is deployed"
    exit 1
fi

export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

echo -e "${GREEN}Retrieved admin credentials (region: $CURRENT_REGION)${NC}\n"
cd - > /dev/null

# Step 2: Restore target Lambda's original code
echo -e "${YELLOW}Step 2: Restoring target Lambda function code${NC}"
echo "Target: $TARGET_LAMBDA"

ORIGINAL_ZIP="$SCRIPT_DIR/lambda/target/target.zip"

if [ ! -f "$ORIGINAL_ZIP" ]; then
    echo -e "${RED}Error: Original zip not found at $ORIGINAL_ZIP${NC}"
    echo "Run: cd $SCRIPT_DIR/lambda/target && zip target.zip index.js package.json"
    exit 1
fi

# Check if the function exists before trying to update it
if ! aws lambda get-function \
    --region "$CURRENT_REGION" \
    --function-name "$TARGET_LAMBDA" &>/dev/null; then
    echo -e "${YELLOW}Target Lambda not found - may already be cleaned up${NC}"
else
    aws lambda update-function-code \
        --region "$CURRENT_REGION" \
        --function-name "$TARGET_LAMBDA" \
        --zip-file "fileb://$ORIGINAL_ZIP" \
        --output json > /dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Target Lambda code restored to original benign version${NC}"
        echo "Waiting for Lambda to process the update..."
        sleep 5
    else
        echo -e "${RED}Error restoring Lambda code - may need manual restore via:${NC}"
        echo "  terraform apply -replace='module.ctf_ai_chatbot_lambda_pivot[0].aws_lambda_function.target'"
    fi
fi
echo ""

# Step 3: Clean up local temporary files
echo -e "${YELLOW}Step 3: Cleaning up local temporary files${NC}"
LOCAL_FILES=(
    "/tmp/malicious_lambda.js"
    "/tmp/malicious_lambda.zip"
    "/tmp/ctf_creds.env"
    "/tmp/ctf002_creds"
    "/tmp/target_response.json"
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
    echo -e "${GREEN}Cleaned up $CLEANED_COUNT local file(s)${NC}"
else
    echo "No local temporary files found"
fi
echo ""

# Step 4: Verify cleanup
echo -e "${YELLOW}Step 4: Verifying cleanup${NC}"

# Verify chatbot is intact
if aws lambda get-function \
    --region "$CURRENT_REGION" \
    --function-name pl-prod-ctf-002-acmebot &>/dev/null; then
    echo -e "${GREEN}Chatbot Lambda is intact${NC}"
fi

# Verify target is restored
if aws lambda get-function \
    --region "$CURRENT_REGION" \
    --function-name "$TARGET_LAMBDA" &>/dev/null; then
    echo -e "${GREEN}Target Lambda exists and has been restored${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "- Restored $TARGET_LAMBDA to original benign code"
echo "- Cleaned up local temporary files"
echo "- Infrastructure remains deployed and ready for another attempt"
echo ""
echo -e "${YELLOW}To remove all infrastructure:${NC}"
echo "  Set enable_ctf_ai_chatbot_lambda_pivot = false in terraform.tfvars and run terraform apply"
echo ""

rm -f "$(dirname "$0")/.demo_active"
