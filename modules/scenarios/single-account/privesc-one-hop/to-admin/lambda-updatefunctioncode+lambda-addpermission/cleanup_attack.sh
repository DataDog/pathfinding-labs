#!/bin/bash

# Cleanup script for lambda:UpdateFunctionCode + lambda:AddPermission privilege escalation demo
# This script removes the attack artifacts and restores the Lambda function

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-lufclap-to-admin-starting-user"
TARGET_LAMBDA="pl-prod-lufclap-to-admin-target-lambda"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Lambda UpdateFunctionCode + AddPermission${NC}"
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
echo "Checking if AdministratorAccess is attached to $STARTING_USER..."

# Check if the policy is attached
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`].PolicyArn' \
    --output text)

if [ -n "$ATTACHED_POLICIES" ]; then
    echo "Detaching AdministratorAccess policy..."
    aws iam detach-user-policy \
        --user-name $STARTING_USER \
        --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"
    echo -e "${GREEN}✓ Detached AdministratorAccess policy${NC}"
else
    echo -e "${YELLOW}AdministratorAccess policy not attached (may already be cleaned)${NC}"
fi
echo ""

# Step 3: Remove resource-based permissions from Lambda function
echo -e "${YELLOW}Step 3: Removing resource-based permissions from Lambda function${NC}"
echo "Checking Lambda function policy for permissions to remove..."

# Get the current policy
POLICY=$(aws lambda get-policy \
    --region $CURRENT_REGION \
    --function-name $TARGET_LAMBDA \
    --query 'Policy' \
    --output text 2>/dev/null || echo "")

if [ -n "$POLICY" ]; then
    # Extract statement IDs that contain "AllowStartingUserInvoke"
    STATEMENT_IDS=$(echo "$POLICY" | jq -r '.Statement[] | select(.Sid | startswith("AllowStartingUserInvoke")) | .Sid' 2>/dev/null || echo "")

    if [ -n "$STATEMENT_IDS" ]; then
        echo "Found resource-based permissions to remove:"
        echo "$STATEMENT_IDS"
        echo ""

        # Remove each statement
        while IFS= read -r STATEMENT_ID; do
            if [ -n "$STATEMENT_ID" ]; then
                echo "Removing permission: $STATEMENT_ID"
                aws lambda remove-permission \
                    --region $CURRENT_REGION \
                    --function-name $TARGET_LAMBDA \
                    --statement-id "$STATEMENT_ID" 2>/dev/null || true
                echo -e "${GREEN}✓ Removed permission: $STATEMENT_ID${NC}"
            fi
        done <<< "$STATEMENT_IDS"
    else
        echo -e "${YELLOW}No matching resource-based permissions found${NC}"
    fi
else
    echo -e "${YELLOW}No resource policy found on Lambda function${NC}"
fi
echo ""

# Step 4: Restore original Lambda function code
echo -e "${YELLOW}Step 4: Restoring original Lambda function code${NC}"
echo "Redeploying original Lambda function code from Terraform..."

# Get the module output to find the original code
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_lambda_updatefunctioncode_lambda_addpermission.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${YELLOW}Warning: Could not get original Lambda code from Terraform${NC}"
    echo "Restoring with basic hello world function..."

    # Create original hello world function
    cat > /tmp/lambda_function_restore.py << 'EOF'
import json

def lambda_handler(event, context):
    """
    Original benign Lambda function
    """
    return {
        'statusCode': 200,
        'body': json.dumps('Hello from Lambda!')
    }
EOF

    # Create zip file
    cd /tmp
    zip -q lambda_function_restore.zip lambda_function_restore.py
    cd - > /dev/null

    # Update Lambda function with original code
    aws lambda update-function-code \
        --region $CURRENT_REGION \
        --function-name $TARGET_LAMBDA \
        --zip-file fileb:///tmp/lambda_function_restore.zip \
        --output text > /dev/null

    echo -e "${GREEN}✓ Restored Lambda function to original code${NC}"
    rm -f /tmp/lambda_function_restore.py /tmp/lambda_function_restore.zip
else
    echo -e "${GREEN}✓ Lambda function code will be restored by Terraform${NC}"
fi
echo ""

# Step 5: Clean up temporary files
echo -e "${YELLOW}Step 5: Cleaning up temporary files${NC}"
rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/response.json /tmp/original_lambda_url.txt
echo -e "${GREEN}✓ Cleaned up temporary files${NC}"
echo ""

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess policy from $STARTING_USER"
echo "- Removed resource-based permissions from Lambda function"
echo "- Restored original Lambda function code"
echo "- Cleaned up temporary files"
echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
