#!/bin/bash

# Cleanup script for lambda:UpdateFunctionCode + lambda:AddPermission to S3 bucket access demo
# This script removes attack artifacts: restores original Lambda code, removes the injected
# environment variable, and removes the resource policy statement added by AddPermission.

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
STARTING_USER="pl-prod-lambda-005-to-bucket-starting-user"
TARGET_LAMBDA="pl-prod-lambda-005-to-bucket-target-lambda"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Lambda UpdateFunctionCode + AddPermission (to-bucket)${NC}"
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
export AWS_DEFAULT_REGION="$AWS_REGION"
unset AWS_SESSION_TOKEN

echo "Region from Terraform: $CURRENT_REGION"
echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Remove resource-based permissions added by AddPermission during the demo
echo -e "${YELLOW}Step 2: Removing resource-based permissions from Lambda function${NC}"
echo "Checking Lambda function policy for statements added during the demo..."

# Get the current policy
POLICY=$(aws lambda get-policy \
    --region $CURRENT_REGION \
    --function-name $TARGET_LAMBDA \
    --query 'Policy' \
    --output text 2>/dev/null || echo "")

if [ -n "$POLICY" ]; then
    # Extract statement IDs that match the pattern added by the demo script
    STATEMENT_IDS=$(echo "$POLICY" | jq -r '.Statement[] | select(.Sid | startswith("AllowStartingUserInvoke")) | .Sid' 2>/dev/null || echo "")

    if [ -n "$STATEMENT_IDS" ]; then
        echo "Found resource-based permissions to remove:"
        echo "$STATEMENT_IDS"
        echo ""

        while IFS= read -r STATEMENT_ID; do
            if [ -n "$STATEMENT_ID" ]; then
                echo "Removing permission statement: $STATEMENT_ID"
                aws lambda remove-permission \
                    --region $CURRENT_REGION \
                    --function-name $TARGET_LAMBDA \
                    --statement-id "$STATEMENT_ID" 2>/dev/null || true
                echo -e "${GREEN}✓ Removed permission: $STATEMENT_ID${NC}"
            fi
        done <<< "$STATEMENT_IDS"
    else
        echo -e "${YELLOW}No matching resource-based permissions found (may already be cleaned)${NC}"
    fi
else
    echo -e "${YELLOW}No resource policy found on Lambda function${NC}"
fi
echo ""

# Step 3: Restore original Lambda function code
echo -e "${YELLOW}Step 3: Restoring original Lambda function code${NC}"
echo "Redeploying the original benign function code..."

# Recreate the original benign function code. The handler is lambda_function.lambda_handler,
# so the file inside the zip must be named lambda_function.py.
cat > /tmp/lambda_function.py << 'EOF'
def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'body': 'Hello from Lambda!'
    }
EOF

# Create zip file (must contain lambda_function.py to match the handler)
cd /tmp
zip -q lambda_function_restore.zip lambda_function.py
cd - > /dev/null

# Update Lambda function with the restored code
aws lambda update-function-code \
    --region $CURRENT_REGION \
    --function-name $TARGET_LAMBDA \
    --zip-file fileb:///tmp/lambda_function_restore.zip \
    --output text > /dev/null

echo -e "${GREEN}✓ Restored Lambda function to original code${NC}\n"

# Step 4: Clean up temporary files
echo -e "${YELLOW}Step 4: Cleaning up temporary files${NC}"
rm -f /tmp/lambda_function.py \
      /tmp/lambda_function.zip \
      /tmp/lambda_function_restore.zip \
      /tmp/response.json \
      /tmp/preflight_response.json
echo -e "${GREEN}✓ Cleaned up temporary files${NC}"
echo ""

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Removed resource-based permission statements from Lambda function"
echo "- Restored original Lambda function code"
echo "- Cleaned up temporary files"
echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, Lambda, and S3 bucket) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
