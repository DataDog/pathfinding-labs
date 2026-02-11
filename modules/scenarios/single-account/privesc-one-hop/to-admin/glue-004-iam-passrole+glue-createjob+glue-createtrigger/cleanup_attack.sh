#!/bin/bash

# Cleanup script for iam:PassRole + glue:CreateJob + glue:CreateTrigger privilege escalation demo
# This script removes the trigger and detaches AdministratorAccess from the starting user

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-glue-004-to-admin-starting-user"
TRIGGER_PREFIX="pl-glue-004-demo-trigger-"
JOB_PREFIX="pl-glue-004-demo-job-"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Glue CreateJob + CreateTrigger Privilege Escalation${NC}"
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

# Step 2: Find and delete demo triggers
echo -e "${YELLOW}Step 2: Finding and deleting demo triggers${NC}"
echo "Searching for triggers starting with: $TRIGGER_PREFIX"

# List all triggers and filter for our demo triggers
ALL_TRIGGERS=$(aws glue get-triggers \
    --region $CURRENT_REGION \
    --output json 2>/dev/null | jq -r '.Triggers[].Name' | grep "^${TRIGGER_PREFIX}" || true)

if [ -n "$ALL_TRIGGERS" ]; then
    echo "Found demo triggers:"
    echo "$ALL_TRIGGERS"
    echo ""

    # Delete each trigger (stop first if activated)
    while IFS= read -r TRIGGER_NAME; do
        if [ -n "$TRIGGER_NAME" ]; then
            echo "Stopping and deleting trigger: $TRIGGER_NAME"

            # Stop the trigger first (ignore errors if already stopped)
            aws glue stop-trigger \
                --region $CURRENT_REGION \
                --name "$TRIGGER_NAME" 2>/dev/null || true

            # Wait a moment for the stop to take effect
            sleep 2

            # Delete the trigger
            aws glue delete-trigger \
                --region $CURRENT_REGION \
                --name "$TRIGGER_NAME" 2>/dev/null || true
            echo -e "${GREEN}✓ Deleted trigger: $TRIGGER_NAME${NC}"
        fi
    done <<< "$ALL_TRIGGERS"
else
    echo -e "${YELLOW}No demo triggers found (may already be deleted)${NC}"
fi
echo ""

# Step 3: Detach AdministratorAccess from starting user
echo -e "${YELLOW}Step 3: Detaching AdministratorAccess from starting user${NC}"
echo "User: $STARTING_USER"

# Check if AdministratorAccess is attached
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`].PolicyArn' \
    --output text 2>/dev/null || true)

if [ -n "$ATTACHED_POLICIES" ]; then
    echo "Found AdministratorAccess attached to user"

    aws iam detach-user-policy \
        --user-name $STARTING_USER \
        --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

    echo -e "${GREEN}✓ Detached AdministratorAccess from $STARTING_USER${NC}"
else
    echo -e "${YELLOW}AdministratorAccess not attached to user (may already be detached)${NC}"
fi
echo ""

# Step 4: Find and delete demo Glue jobs
echo -e "${YELLOW}Step 4: Finding and deleting demo Glue jobs${NC}"
echo "Searching for jobs starting with: $JOB_PREFIX"

DEMO_JOBS=$(aws glue get-jobs \
    --region $CURRENT_REGION \
    --output json 2>/dev/null | jq -r '.Jobs[].Name' | grep "^${JOB_PREFIX}" || true)

if [ -n "$DEMO_JOBS" ]; then
    echo "Found demo jobs:"
    echo "$DEMO_JOBS"
    echo ""

    # Delete each job
    while IFS= read -r JOB_NAME; do
        if [ -n "$JOB_NAME" ]; then
            echo "Deleting Glue job: $JOB_NAME"
            aws glue delete-job \
                --region $CURRENT_REGION \
                --job-name "$JOB_NAME" 2>/dev/null || true
            echo -e "${GREEN}✓ Deleted job: $JOB_NAME${NC}"
        fi
    done <<< "$DEMO_JOBS"
else
    echo -e "${YELLOW}No demo jobs found (may already be deleted)${NC}"
fi
echo ""

# Step 5: Verify cleanup
echo -e "${YELLOW}Step 5: Verifying cleanup${NC}"

# Check triggers
REMAINING_TRIGGERS=$(aws glue get-triggers \
    --region $CURRENT_REGION \
    --output json 2>/dev/null | jq -r '.Triggers[].Name' | grep "^${TRIGGER_PREFIX}" || true)

if [ -z "$REMAINING_TRIGGERS" ]; then
    echo -e "${GREEN}✓ All demo triggers have been deleted${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Some demo triggers still exist:${NC}"
    echo "$REMAINING_TRIGGERS"
fi

# Check jobs
REMAINING_JOBS=$(aws glue get-jobs \
    --region $CURRENT_REGION \
    --output json 2>/dev/null | jq -r '.Jobs[].Name' | grep "^${JOB_PREFIX}" || true)

if [ -z "$REMAINING_JOBS" ]; then
    echo -e "${GREEN}✓ All demo Glue jobs have been deleted${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Some demo Glue jobs still exist:${NC}"
    echo "$REMAINING_JOBS"
fi

# Check AdministratorAccess
STILL_ATTACHED=$(aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`].PolicyArn' \
    --output text 2>/dev/null || true)

if [ -z "$STILL_ATTACHED" ]; then
    echo -e "${GREEN}✓ AdministratorAccess successfully detached from starting user${NC}"
else
    echo -e "${YELLOW}⚠ Warning: AdministratorAccess still attached to starting user${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Deleted all demo triggers matching pattern: $TRIGGER_PREFIX*"
echo "- Deleted all demo Glue jobs matching pattern: $JOB_PREFIX*"
echo "- Detached AdministratorAccess from starting user: $STARTING_USER"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
