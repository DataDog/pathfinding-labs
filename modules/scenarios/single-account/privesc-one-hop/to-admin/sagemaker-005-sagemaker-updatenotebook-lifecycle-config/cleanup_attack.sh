#!/bin/bash

# Cleanup script for SageMaker UpdateNotebook Lifecycle Config privilege escalation demo
# This script removes the admin policy from the starting user and cleans up the lifecycle config

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-sagemaker-005-to-admin-starting-user"
LIFECYCLE_CONFIG_NAME="pl-malicious-lifecycle-config"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: SageMaker UpdateNotebook Lifecycle Config${NC}"
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

# Get scenario details from grouped output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_sagemaker_005_sagemaker_updatenotebook_lifecycle_config.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output for scenario${NC}"
    echo "The scenario may not be deployed"
    exit 1
fi

NOTEBOOK_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.notebook_instance_name')

# Navigate back to scenario directory
cd - > /dev/null

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo "Notebook: $NOTEBOOK_NAME"
echo ""

# Step 2: Remove AdministratorAccess policy from starting user
echo -e "${YELLOW}Step 2: Removing AdministratorAccess policy from starting user${NC}"
echo "Checking if AdministratorAccess is attached to: $STARTING_USER"

ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`].PolicyArn' \
    --output text)

if [ -n "$ATTACHED_POLICIES" ]; then
    echo "Found AdministratorAccess policy attached"
    echo "Detaching policy..."
    aws iam detach-user-policy \
        --user-name $STARTING_USER \
        --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
    echo -e "${GREEN}✓ Detached AdministratorAccess from $STARTING_USER${NC}"
else
    echo -e "${YELLOW}AdministratorAccess not attached (may already be cleaned up)${NC}"
fi
echo ""

# Step 3: Remove lifecycle config from notebook (if stopped)
echo -e "${YELLOW}Step 3: Checking notebook status${NC}"
NOTEBOOK_STATUS=$(aws sagemaker describe-notebook-instance \
    --notebook-instance-name $NOTEBOOK_NAME \
    --region $CURRENT_REGION \
    --query 'NotebookInstanceStatus' \
    --output text 2>/dev/null || echo "NOT_FOUND")

echo "Notebook status: $NOTEBOOK_STATUS"

if [ "$NOTEBOOK_STATUS" == "Stopped" ]; then
    echo "Notebook is stopped, checking for lifecycle config..."
    CURRENT_LIFECYCLE=$(aws sagemaker describe-notebook-instance \
        --notebook-instance-name $NOTEBOOK_NAME \
        --region $CURRENT_REGION \
        --query 'NotebookInstanceLifecycleConfigName' \
        --output text 2>/dev/null || echo "None")

    if [ "$CURRENT_LIFECYCLE" != "None" ] && [ "$CURRENT_LIFECYCLE" == "$LIFECYCLE_CONFIG_NAME" ]; then
        echo "Removing lifecycle config from notebook..."
        aws sagemaker update-notebook-instance \
            --notebook-instance-name $NOTEBOOK_NAME \
            --disassociate-lifecycle-config \
            --region $CURRENT_REGION \
            --output json > /dev/null
        echo -e "${GREEN}✓ Removed lifecycle config from notebook${NC}"
    else
        echo -e "${YELLOW}Malicious lifecycle config not attached to notebook${NC}"
    fi
elif [ "$NOTEBOOK_STATUS" == "InService" ]; then
    echo -e "${YELLOW}Notebook is running. The lifecycle config can be removed by Terraform cleanup.${NC}"
    echo -e "${YELLOW}Or you can stop the notebook and run this cleanup script again.${NC}"
elif [ "$NOTEBOOK_STATUS" == "NOT_FOUND" ]; then
    echo -e "${YELLOW}Notebook not found (may have been deleted)${NC}"
else
    echo -e "${YELLOW}Notebook is in $NOTEBOOK_STATUS state${NC}"
fi
echo ""

# Step 4: Delete malicious lifecycle configuration
echo -e "${YELLOW}Step 4: Deleting malicious lifecycle configuration${NC}"
echo "Attempting to delete lifecycle config: $LIFECYCLE_CONFIG_NAME"

if aws sagemaker describe-notebook-instance-lifecycle-config \
    --notebook-instance-lifecycle-config-name $LIFECYCLE_CONFIG_NAME \
    --region $CURRENT_REGION &> /dev/null; then

    aws sagemaker delete-notebook-instance-lifecycle-config \
        --notebook-instance-lifecycle-config-name $LIFECYCLE_CONFIG_NAME \
        --region $CURRENT_REGION

    echo -e "${GREEN}✓ Deleted lifecycle config: $LIFECYCLE_CONFIG_NAME${NC}"
else
    echo -e "${YELLOW}Lifecycle config $LIFECYCLE_CONFIG_NAME not found (may already be deleted)${NC}"
fi
echo ""

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Removed AdministratorAccess policy from $STARTING_USER"
echo "- Removed lifecycle config from notebook (if stopped)"
echo "- Deleted malicious lifecycle configuration: $LIFECYCLE_CONFIG_NAME"
echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, notebook) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
