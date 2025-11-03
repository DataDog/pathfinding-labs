#!/bin/bash

# Cleanup script for iam:PassRole + codebuild:CreateProject + codebuild:StartBuild privilege escalation demo
# This script removes the CodeBuild project and policy attachment created during the demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-cbcpsb-to-admin-starting-user"
CODEBUILD_PROJECT_NAME="pl-privesc-codebuild-demo"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + CodeBuild Demo Cleanup${NC}"
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
echo -e "${YELLOW}Step 2: Detaching AdministratorAccess policy from user${NC}"
echo "User: $STARTING_USER"

# Check if the policy is attached
if aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' \
    --output text | grep -q "AdministratorAccess"; then

    echo "Found AdministratorAccess policy attached to $STARTING_USER"

    # Detach the policy
    aws iam detach-user-policy \
        --user-name $STARTING_USER \
        --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

    echo -e "${GREEN}✓ Detached AdministratorAccess policy from $STARTING_USER${NC}"
else
    echo -e "${YELLOW}AdministratorAccess policy not attached to $STARTING_USER (may already be detached)${NC}"
fi
echo ""

# Step 3: Delete the CodeBuild project
echo -e "${YELLOW}Step 3: Deleting CodeBuild project${NC}"
echo "Project name: $CODEBUILD_PROJECT_NAME"
echo "Region: $CURRENT_REGION"

# Check if the project exists
if aws codebuild batch-get-projects \
    --region $CURRENT_REGION \
    --names "$CODEBUILD_PROJECT_NAME" \
    --query 'projects[0].name' \
    --output text 2>/dev/null | grep -q "$CODEBUILD_PROJECT_NAME"; then

    echo "Found CodeBuild project: $CODEBUILD_PROJECT_NAME"

    # Delete the project
    aws codebuild delete-project \
        --region $CURRENT_REGION \
        --name "$CODEBUILD_PROJECT_NAME"

    echo -e "${GREEN}✓ Deleted CodeBuild project: $CODEBUILD_PROJECT_NAME${NC}"
else
    echo -e "${YELLOW}CodeBuild project $CODEBUILD_PROJECT_NAME not found (may already be deleted)${NC}"
fi
echo ""

# Step 4: Verify cleanup
echo -e "${YELLOW}Step 4: Verifying cleanup${NC}"

# Check that the policy is detached
if aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' \
    --output text | grep -q "AdministratorAccess"; then
    echo -e "${YELLOW}⚠ Warning: AdministratorAccess policy still attached to $STARTING_USER${NC}"
else
    echo -e "${GREEN}✓ AdministratorAccess policy successfully detached${NC}"
fi

# Check that the CodeBuild project no longer exists
if aws codebuild batch-get-projects \
    --region $CURRENT_REGION \
    --names "$CODEBUILD_PROJECT_NAME" \
    --query 'projects[0].name' \
    --output text 2>/dev/null | grep -q "$CODEBUILD_PROJECT_NAME"; then
    echo -e "${YELLOW}⚠ Warning: CodeBuild project $CODEBUILD_PROJECT_NAME still exists${NC}"
else
    echo -e "${GREEN}✓ CodeBuild project successfully deleted${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess policy from: $STARTING_USER"
echo "- Deleted CodeBuild project: $CODEBUILD_PROJECT_NAME"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
