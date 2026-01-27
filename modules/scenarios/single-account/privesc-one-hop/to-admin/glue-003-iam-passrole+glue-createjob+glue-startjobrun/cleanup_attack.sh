#!/bin/bash

# Cleanup script for iam:PassRole + glue:CreateJob + glue:StartJobRun privilege escalation demo
# This script removes the AdministratorAccess policy and Glue jobs created during the demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-glue-003-to-admin-starting-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Glue CreateJob + StartJobRun Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials from Terraform
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
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$CURRENT_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    CURRENT_REGION="us-east-1"
fi

echo "Region from Terraform: $CURRENT_REGION"

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"

cd - > /dev/null  # Return to scenario directory
echo ""

# Step 2: Detach AdministratorAccess policy from starting user
echo -e "${YELLOW}Step 2: Detaching AdministratorAccess policy from starting user${NC}"
echo "User: $STARTING_USER"

# Check if the policy is attached
if aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' \
    --output text | grep -q "AdministratorAccess"; then

    echo "Found AdministratorAccess policy attached to user"
    aws iam detach-user-policy \
        --user-name "$STARTING_USER" \
        --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

    echo -e "${GREEN}✓ Detached AdministratorAccess policy from $STARTING_USER${NC}"
else
    echo -e "${YELLOW}AdministratorAccess policy not attached to user (may already be detached)${NC}"
fi
echo ""

# Step 3: Find and delete Glue jobs created by the demo
echo -e "${YELLOW}Step 3: Finding and deleting demo Glue jobs${NC}"
DEMO_JOB_PREFIX="pl-glue-003-demo-job-"

echo "Searching for Glue jobs with prefix: $DEMO_JOB_PREFIX"
echo "Region: $CURRENT_REGION"

# List all jobs matching our prefix
GLUE_JOBS=$(aws glue get-jobs \
    --region $CURRENT_REGION \
    --query "Jobs[?starts_with(Name, '${DEMO_JOB_PREFIX}')].Name" \
    --output text)

if [ -n "$GLUE_JOBS" ]; then
    echo "Found Glue jobs to delete:"
    echo "$GLUE_JOBS"
    echo ""

    # Delete each job
    for JOB_NAME in $GLUE_JOBS; do
        echo "Deleting Glue job: $JOB_NAME"
        aws glue delete-job \
            --region $CURRENT_REGION \
            --job-name "$JOB_NAME"
        echo -e "${GREEN}✓ Deleted job: $JOB_NAME${NC}"
    done
else
    echo -e "${YELLOW}No demo Glue jobs found (may already be deleted)${NC}"
fi
echo ""

# Step 4: Verify cleanup
echo -e "${YELLOW}Step 4: Verifying cleanup${NC}"

# Check that AdministratorAccess is detached
if aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' \
    --output text | grep -q "AdministratorAccess"; then
    echo -e "${YELLOW}⚠ Warning: AdministratorAccess still attached to $STARTING_USER${NC}"
else
    echo -e "${GREEN}✓ AdministratorAccess successfully detached from user${NC}"
fi

# Check for remaining Glue jobs
REMAINING_JOBS=$(aws glue get-jobs \
    --region $CURRENT_REGION \
    --query "Jobs[?starts_with(Name, '${DEMO_JOB_PREFIX}')].Name" \
    --output text)

if [ -n "$REMAINING_JOBS" ]; then
    echo -e "${YELLOW}⚠ Warning: Some Glue jobs still exist: $REMAINING_JOBS${NC}"
else
    echo -e "${GREEN}✓ All demo Glue jobs deleted${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess policy from starting user"
echo "- Deleted Glue jobs with prefix: $DEMO_JOB_PREFIX"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
