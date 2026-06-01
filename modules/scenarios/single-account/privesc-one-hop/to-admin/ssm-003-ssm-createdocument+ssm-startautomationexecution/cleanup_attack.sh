#!/bin/bash
set -e

# Cleanup script for ssm:CreateDocument + ssm:StartAutomationExecution privilege escalation demo
# Removes two artifacts created during the demo:
#   1. AdministratorAccess managed policy attached to the starting user
#   2. The SSM Automation document pl-ssm-003-escalation-doc

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER_NAME="pl-prod-ssm-003-to-admin-starting-user"
SSM_DOC_NAME="pl-ssm-003-escalation-doc"
ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

# Source demo permissions library for safety restore
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Safety: remove any orphaned restriction policies
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: SSM CreateDocument + StartAutomationExecution Demo${NC}"
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

# Step 2: Detach AdministratorAccess from the starting user
echo -e "${YELLOW}Step 2: Detaching AdministratorAccess from starting user${NC}"
echo "Checking if AdministratorAccess is attached to: $STARTING_USER_NAME"

ATTACHED=$(aws iam list-attached-user-policies \
    --user-name "$STARTING_USER_NAME" \
    --query "AttachedPolicies[?PolicyArn=='$ADMIN_POLICY_ARN'].PolicyArn" \
    --output text 2>/dev/null || echo "")

if [ -n "$ATTACHED" ] && [ "$ATTACHED" != "None" ]; then
    aws iam detach-user-policy \
        --user-name "$STARTING_USER_NAME" \
        --policy-arn "$ADMIN_POLICY_ARN"
    echo -e "${GREEN}✓ Detached AdministratorAccess from $STARTING_USER_NAME${NC}"
else
    echo -e "${YELLOW}AdministratorAccess not attached to $STARTING_USER_NAME (may already be detached)${NC}"
fi
echo ""

# Step 3: Delete the SSM Automation document
echo -e "${YELLOW}Step 3: Deleting SSM Automation document: $SSM_DOC_NAME${NC}"

if aws ssm describe-document \
    --name "$SSM_DOC_NAME" \
    --region "$CURRENT_REGION" &>/dev/null; then
    aws ssm delete-document \
        --name "$SSM_DOC_NAME" \
        --region "$CURRENT_REGION"
    echo -e "${GREEN}✓ Deleted SSM document: $SSM_DOC_NAME${NC}"
else
    echo -e "${YELLOW}SSM document $SSM_DOC_NAME not found (may already be deleted)${NC}"
fi
echo ""

# Step 4: Clean up environment variables
echo -e "${YELLOW}Step 4: Cleaning up environment variables${NC}"
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
unset AWS_REGION
echo -e "${GREEN}✓ Cleared AWS environment variables${NC}"
echo ""

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess from: $STARTING_USER_NAME"
echo "- Deleted SSM Automation document: $SSM_DOC_NAME"
echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (IAM users, roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}"
echo ""

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
