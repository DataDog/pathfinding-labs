#!/bin/bash

# Cleanup script for SageMaker CreatePresignedNotebookInstanceUrl privilege escalation demo
# This script removes the AdministratorAccess policy attached during the demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-sagemaker-004-to-admin-starting-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: SageMaker CreatePresignedNotebookInstanceUrl${NC}"
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
ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

# Check if the policy is attached
if aws iam list-attached-user-policies --user-name $STARTING_USER --query "AttachedPolicies[?PolicyArn=='$ADMIN_POLICY_ARN'].PolicyArn" --output text | grep -q "$ADMIN_POLICY_ARN"; then
    echo "Detaching AdministratorAccess from user: $STARTING_USER"
    aws iam detach-user-policy \
        --user-name $STARTING_USER \
        --policy-arn $ADMIN_POLICY_ARN
    echo -e "${GREEN}✓ Detached AdministratorAccess policy${NC}"
else
    echo -e "${YELLOW}AdministratorAccess not attached to $STARTING_USER (may already be cleaned up)${NC}"
fi
echo ""

# Step 3: Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess policy from: $STARTING_USER"
echo "- Notebook instance remains running (managed by Terraform)"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, and notebook) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
