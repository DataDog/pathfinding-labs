#!/bin/bash

# Cleanup script for iam:PassRole + glue:UpdateJob + glue:CreateTrigger privilege escalation demo
# This script removes the trigger, restores the Glue job to its original configuration,
# and detaches AdministratorAccess from the starting user

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-guj-ct-to-admin-starting-user"
INITIAL_ROLE="pl-prod-guj-ct-to-admin-initial-role"
TRIGGER_PREFIX="pl-guj-ct-demo-trigger-"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Glue UpdateJob + CreateTrigger Privilege Escalation${NC}"
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

# Get module output for job details
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_createtrigger.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output for this scenario${NC}"
    echo "Cleanup will continue with best effort..."
    GLUE_JOB_NAME=""
    BENIGN_SCRIPT_S3_PATH=""
else
    GLUE_JOB_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.glue_job_name // empty')
    BENIGN_SCRIPT_S3_PATH=$(echo "$MODULE_OUTPUT" | jq -r '.benign_script_s3_path // empty')
fi

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

# Step 3: Restore Glue job to original configuration
echo -e "${YELLOW}Step 3: Restoring Glue job to original configuration${NC}"

if [ -z "$GLUE_JOB_NAME" ] || [ -z "$BENIGN_SCRIPT_S3_PATH" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve job details from Terraform${NC}"
    echo "Skipping job restoration (job may need manual restoration)"
else
    echo "Job name: $GLUE_JOB_NAME"
    echo "Restoring to initial role: $INITIAL_ROLE"
    echo "Restoring to benign script: $BENIGN_SCRIPT_S3_PATH"

    INITIAL_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${INITIAL_ROLE}"

    # Get current job configuration to verify it exists
    if aws glue get-job \
        --region $CURRENT_REGION \
        --job-name "$GLUE_JOB_NAME" &> /dev/null; then

        # Update job back to original configuration
        aws glue update-job \
            --region $CURRENT_REGION \
            --job-name "$GLUE_JOB_NAME" \
            --job-update "Role=${INITIAL_ROLE_ARN},Command={Name=pythonshell,ScriptLocation=${BENIGN_SCRIPT_S3_PATH},PythonVersion=3.9}" \
            --output json > /dev/null

        echo -e "${GREEN}✓ Restored job to original configuration${NC}"
        echo "  → Role: $INITIAL_ROLE"
        echo "  → Script: $BENIGN_SCRIPT_S3_PATH"
    else
        echo -e "${YELLOW}Job $GLUE_JOB_NAME not found (may have been deleted)${NC}"
    fi
fi
echo ""

# Step 4: Detach AdministratorAccess from starting user
echo -e "${YELLOW}Step 4: Detaching AdministratorAccess from starting user${NC}"
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

# Check job configuration (if we have the job name)
if [ -n "$GLUE_JOB_NAME" ]; then
    CURRENT_JOB_CONFIG=$(aws glue get-job \
        --region $CURRENT_REGION \
        --job-name "$GLUE_JOB_NAME" \
        --output json 2>/dev/null || echo "")

    if [ -n "$CURRENT_JOB_CONFIG" ]; then
        CURRENT_ROLE=$(echo "$CURRENT_JOB_CONFIG" | jq -r '.Job.Role')
        CURRENT_SCRIPT=$(echo "$CURRENT_JOB_CONFIG" | jq -r '.Job.Command.ScriptLocation')

        if [[ "$CURRENT_ROLE" == *"$INITIAL_ROLE"* ]]; then
            echo -e "${GREEN}✓ Glue job restored to initial role${NC}"
        else
            echo -e "${YELLOW}⚠ Warning: Glue job may not be fully restored${NC}"
            echo "  Current role: $CURRENT_ROLE"
        fi

        if [[ "$CURRENT_SCRIPT" == *"benign_script"* ]]; then
            echo -e "${GREEN}✓ Glue job restored to benign script${NC}"
        else
            echo -e "${YELLOW}⚠ Warning: Glue job script may not be restored${NC}"
            echo "  Current script: $CURRENT_SCRIPT"
        fi
    fi
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
echo "- Restored Glue job to original configuration (initial role and benign script)"
echo "- Detached AdministratorAccess from starting user: $STARTING_USER"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, and Glue job) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
