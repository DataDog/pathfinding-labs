#!/bin/bash

# Cleanup script for iam:PassRole + cloudformation:CreateStack privilege escalation demo
# This script deletes the CloudFormation stack and removes the escalated role


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
PROFILE="pl-admin-cleanup-prod"
STACK_NAME="pl-prod-cloudformation-001-to-admin-escalation-stack"
ESCALATED_ROLE_NAME="pl-prod-cloudformation-001-to-admin-escalated-role"
TEMPLATE_FILE="/tmp/cfn-cloudformation-001-escalation-template.yaml"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + CloudFormation Demo Cleanup${NC}"
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
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
echo "Region from Terraform: $CURRENT_REGION"
export AWS_DEFAULT_REGION="$CURRENT_REGION"

# Verify credentials
IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Authenticated as: $IDENTITY"

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"

cd - > /dev/null  # Return to scenario directory
echo ""

# Step 1: Delete CloudFormation stack
echo -e "${YELLOW}Step 1: Deleting CloudFormation stack${NC}"
echo "Stack name: $STACK_NAME"

# Check if stack exists
STACK_STATUS=$(aws cloudformation describe-stacks \
    --region $CURRENT_REGION \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$STACK_STATUS" = "NOT_FOUND" ]; then
    echo -e "${YELLOW}Stack not found (may already be deleted)${NC}"
else
    echo "Current stack status: $STACK_STATUS"

    # Stack exists - delete it (works for ROLLBACK_COMPLETE too)
    echo "Initiating stack deletion..."

    aws cloudformation delete-stack \
        --region $CURRENT_REGION \
        --stack-name $STACK_NAME

    echo -e "${GREEN}✓ Stack deletion initiated${NC}"
    echo ""

    # Wait for deletion to complete
    echo -e "${YELLOW}Waiting for stack deletion to complete${NC}"
    echo "This may take 1-2 minutes..."
    echo ""

    MAX_WAIT=300  # 5 minutes
    WAIT_TIME=0
    DELETION_COMPLETE=false

    while [ $WAIT_TIME -lt $MAX_WAIT ]; do
        STACK_STATUS=$(aws cloudformation describe-stacks \
            --region $CURRENT_REGION \
            --stack-name $STACK_NAME \
            --query 'Stacks[0].StackStatus' \
            --output text 2>/dev/null || echo "DELETED")

        if [ "$STACK_STATUS" = "DELETED" ] || [ "$STACK_STATUS" = "NOT_FOUND" ]; then
            echo -e "${GREEN}✓ Stack deleted successfully${NC}"
            DELETION_COMPLETE=true
            break
        elif [ "$STACK_STATUS" = "DELETE_FAILED" ]; then
            echo -e "${RED}Error: Stack deletion failed${NC}"
            echo "Stack status: $STACK_STATUS"
            aws cloudformation describe-stack-events \
                --region $CURRENT_REGION \
                --stack-name $STACK_NAME \
                --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`]' \
                --output table
            break
        fi

        echo "Stack status: $STACK_STATUS"
        sleep 10
        WAIT_TIME=$((WAIT_TIME + 10))
    done

    if [ "$DELETION_COMPLETE" = false ] && [ "$STACK_STATUS" != "DELETE_FAILED" ]; then
        echo -e "${YELLOW}⚠ Stack deletion may still be in progress${NC}"
        echo "Current status: $STACK_STATUS"
    fi
fi
echo ""

# Step 2: Verify escalated role is deleted
echo -e "${YELLOW}Step 2: Verifying escalated role deletion${NC}"
echo "Checking for role: $ESCALATED_ROLE_NAME"

if aws iam get-role --role-name $ESCALATED_ROLE_NAME &> /dev/null; then
    echo -e "${YELLOW}⚠ Role still exists (CloudFormation should have deleted it)${NC}"
    echo "You may need to wait longer or manually delete the role"
else
    echo -e "${GREEN}✓ Escalated role has been deleted${NC}"
fi
echo ""

# Step 3: Clean up template file
echo -e "${YELLOW}Step 3: Cleaning up temporary files${NC}"

if [ -f "$TEMPLATE_FILE" ]; then
    rm -f "$TEMPLATE_FILE"
    echo -e "${GREEN}✓ Deleted template file: $TEMPLATE_FILE${NC}"
else
    echo -e "${YELLOW}Template file not found (may already be deleted)${NC}"
fi
echo ""

# Step 4: Verify cleanup
echo -e "${YELLOW}Step 4: Verifying cleanup${NC}"

# Check stack status one final time
FINAL_STACK_STATUS=$(aws cloudformation describe-stacks \
    --region $CURRENT_REGION \
    --stack-name $STACK_NAME \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$FINAL_STACK_STATUS" = "NOT_FOUND" ]; then
    echo -e "${GREEN}✓ CloudFormation stack confirmed deleted${NC}"
else
    echo -e "${YELLOW}⚠ Stack status: $FINAL_STACK_STATUS${NC}"
fi

# Check role status one final time
if aws iam get-role --role-name $ESCALATED_ROLE_NAME &> /dev/null; then
    echo -e "${YELLOW}⚠ Escalated role still exists${NC}"
    echo "To manually delete the role, run:"
    echo "  aws iam delete-role --role-name $ESCALATED_ROLE_NAME"
else
    echo -e "${GREEN}✓ Escalated role confirmed deleted${NC}"
fi

# Check for temporary file
if [ -f "$TEMPLATE_FILE" ]; then
    echo -e "${YELLOW}⚠ Template file still exists${NC}"
else
    echo -e "${GREEN}✓ Temporary files removed${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Deleted CloudFormation stack: $STACK_NAME"
echo "- Removed escalated role: $ESCALATED_ROLE_NAME (via stack deletion)"
echo "- Cleaned up temporary template file"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
