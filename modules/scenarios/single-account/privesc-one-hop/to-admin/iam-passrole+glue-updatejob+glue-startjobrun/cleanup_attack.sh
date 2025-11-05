#!/bin/bash

# Cleanup script for iam:PassRole + glue:UpdateJob + glue:StartJobRun privilege escalation demo
# This script restores the Glue job to original configuration and removes AdministratorAccess policy

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-guj-sjr-to-admin-starting-user"
INITIAL_ROLE="pl-prod-guj-sjr-to-admin-initial-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Glue UpdateJob + StartJobRun Demo Cleanup${NC}"
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

# Get the module output for job details
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_startjobrun.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Get job name and original configuration from Terraform
GLUE_JOB_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.glue_job_name')
BENIGN_SCRIPT_PATH=$(echo "$MODULE_OUTPUT" | jq -r '.benign_script_s3_path')
INITIAL_ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.initial_role_name')

if [ "$GLUE_JOB_NAME" == "null" ] || [ -z "$GLUE_JOB_NAME" ]; then
    echo -e "${RED}Error: Could not retrieve job name from terraform output${NC}"
    exit 1
fi

echo "Glue Job Name: $GLUE_JOB_NAME"
echo "Initial Role: $INITIAL_ROLE_NAME"
echo "Benign Script: $BENIGN_SCRIPT_PATH"

cd - > /dev/null  # Return to scenario directory
echo ""

# Step 2: Restore Glue job to original configuration
echo -e "${YELLOW}Step 2: Restoring Glue job to original configuration${NC}"
echo "Job: $GLUE_JOB_NAME"

# Check if job exists
if aws glue get-job --region $CURRENT_REGION --job-name "$GLUE_JOB_NAME" &> /dev/null; then
    echo "Found Glue job: $GLUE_JOB_NAME"

    # Restore original role and script
    INITIAL_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${INITIAL_ROLE_NAME}"

    echo "Restoring job configuration:"
    echo "  Role: $INITIAL_ROLE_ARN (initial non-privileged role)"
    echo "  Script: $BENIGN_SCRIPT_PATH (benign script)"
    echo ""

    aws glue update-job \
        --region $CURRENT_REGION \
        --job-name "$GLUE_JOB_NAME" \
        --job-update "Role=${INITIAL_ROLE_ARN},Command={Name=pythonshell,ScriptLocation=${BENIGN_SCRIPT_PATH},PythonVersion=3.9},DefaultArguments={--job-language=python},MaxCapacity=0.0625,Timeout=5" \
        --output json > /dev/null

    echo -e "${GREEN}✓ Restored Glue job to original configuration${NC}"
else
    echo -e "${YELLOW}Glue job $GLUE_JOB_NAME not found (may not be deployed)${NC}"
fi
echo ""

# Step 3: Detach AdministratorAccess policy from starting user
echo -e "${YELLOW}Step 3: Detaching AdministratorAccess policy from starting user${NC}"
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

# Verify job configuration is restored
if aws glue get-job --region $CURRENT_REGION --job-name "$GLUE_JOB_NAME" &> /dev/null; then
    CURRENT_ROLE=$(aws glue get-job \
        --region $CURRENT_REGION \
        --job-name "$GLUE_JOB_NAME" \
        --query 'Job.Role' \
        --output text)

    CURRENT_SCRIPT=$(aws glue get-job \
        --region $CURRENT_REGION \
        --job-name "$GLUE_JOB_NAME" \
        --query 'Job.Command.ScriptLocation' \
        --output text)

    INITIAL_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${INITIAL_ROLE_NAME}"

    if [ "$CURRENT_ROLE" = "$INITIAL_ROLE_ARN" ] && [ "$CURRENT_SCRIPT" = "$BENIGN_SCRIPT_PATH" ]; then
        echo -e "${GREEN}✓ Glue job successfully restored to original configuration${NC}"
        echo "  Current role: $CURRENT_ROLE"
        echo "  Current script: $CURRENT_SCRIPT"
    else
        echo -e "${YELLOW}⚠ Warning: Glue job configuration may not be fully restored${NC}"
        echo "  Current role: $CURRENT_ROLE"
        echo "  Expected role: $INITIAL_ROLE_ARN"
        echo "  Current script: $CURRENT_SCRIPT"
        echo "  Expected script: $BENIGN_SCRIPT_PATH"
    fi
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Restored Glue job to original configuration (initial role and benign script)"
echo "- Detached AdministratorAccess policy from starting user"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, and Glue job) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
