#!/bin/bash

# Cleanup script for bedrockagentcore-invokeagentcommand privilege escalation demo (bedrock-004)
# This script removes the local temporary Python script created during the demo.
# The victim AgentCore Runtime is managed by Terraform and is NOT deleted here.
# The demo makes no IAM mutations, so no IAM cleanup is required.

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Source demo permissions library for safety restore
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Safety: remove any orphaned restriction policies left by an interrupted demo
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# Configuration
PYTHON_SCRIPT="/tmp/extract_bedrock_004_creds.py"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: AgentCore Runtime Command Injection (bedrock-004)${NC}"
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

if [ -z "$CURRENT_REGION" ] || [ "$CURRENT_REGION" == "null" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    CURRENT_REGION="us-east-1"
fi

export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
export AWS_DEFAULT_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

echo "Region from Terraform: $CURRENT_REGION"
echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

cd - > /dev/null

# Get account ID for reference
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Remove the local Python credential extraction script
echo -e "${YELLOW}Step 2: Cleaning up local temporary files${NC}"

if [ -f "$PYTHON_SCRIPT" ]; then
    rm -f "$PYTHON_SCRIPT"
    echo -e "${GREEN}✓ Removed: $PYTHON_SCRIPT${NC}"
else
    echo -e "${YELLOW}File not found (may already be cleaned up): $PYTHON_SCRIPT${NC}"
fi
echo ""

# Step 3: Verify local cleanup
echo -e "${YELLOW}Step 3: Verifying cleanup${NC}"

if [ -f "$PYTHON_SCRIPT" ]; then
    echo -e "${YELLOW}⚠ Warning: $PYTHON_SCRIPT still exists${NC}"
else
    echo -e "${GREEN}✓ Local temporary files cleaned up${NC}"
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Removed local Python script: $PYTHON_SCRIPT"
echo "- No IAM mutations were made during the demo — nothing to revert"
echo ""
echo -e "${BLUE}Note: The AgentCore Runtime is managed by Terraform and remains deployed.${NC}"
echo -e "${BLUE}The stolen temporary credentials have already expired (max 1–12 hours).${NC}"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (user, role, and runtime) remains deployed.${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
