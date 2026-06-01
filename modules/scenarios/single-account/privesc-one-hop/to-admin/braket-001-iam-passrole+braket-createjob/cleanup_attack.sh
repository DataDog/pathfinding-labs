#!/bin/bash
set -e

# Cleanup script for iam:PassRole + braket:CreateJob privilege escalation demo
# This script detaches the AdministratorAccess policy from the starting user
# and cancels any running Braket jobs.

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-braket-001-to-admin-starting-user"
JOB_NAME="pl-prod-braket-001-to-admin-privesc-job"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Braket CreateJob Privilege Escalation${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get admin cleanup user credentials from root terraform output
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null)

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    echo "Make sure the admin cleanup user is deployed"
    exit 1
fi

if [ -z "$CURRENT_REGION" ] || [ "$CURRENT_REGION" == "null" ]; then
    echo -e "${RED}Error: Could not retrieve region from Terraform output${NC}"
    exit 1
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

# Source demo permissions library
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Safety: remove any orphaned restriction policies from an interrupted demo run
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Detach AdministratorAccess policy from starting user
echo -e "${YELLOW}Step 2: Detaching AdministratorAccess policy from starting user${NC}"
POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

# Check if policy is attached
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[?PolicyArn==`'$POLICY_ARN'`].PolicyArn' \
    --output text)

if [ -n "$ATTACHED_POLICIES" ]; then
    echo "Found AdministratorAccess policy attached to $STARTING_USER"
    aws iam detach-user-policy \
        --user-name $STARTING_USER \
        --policy-arn $POLICY_ARN
    echo -e "${GREEN}✓ Detached AdministratorAccess policy${NC}"
else
    echo -e "${YELLOW}AdministratorAccess policy not attached (may already be removed)${NC}"
fi
echo ""

# Step 3: Cancel any running Braket jobs
echo -e "${YELLOW}Step 3: Checking for running Braket jobs${NC}"

# Search for jobs created by this scenario
RUNNING_JOBS=$(aws braket search-jobs \
    --region $CURRENT_REGION \
    --filters '[{"name":"creationDateAfter","operator":"Gt","values":["2020-01-01T00:00:00Z"]}]' \
    --query 'jobs[?jobName==`'"$JOB_NAME"'` && (status==`QUEUED` || status==`RUNNING`)].jobArn' \
    --output text 2>/dev/null)

if [ -n "$RUNNING_JOBS" ] && [ "$RUNNING_JOBS" != "None" ]; then
    for JOB_ARN in $RUNNING_JOBS; do
        echo "Cancelling job: $JOB_ARN"
        aws braket cancel-job \
            --job-arn "$JOB_ARN" \
            --region $CURRENT_REGION 2>/dev/null
        echo -e "${GREEN}✓ Cancelled job: $JOB_ARN${NC}"
    done
else
    echo -e "${YELLOW}No running Braket jobs found (may already be completed or cancelled)${NC}"
fi
echo ""

# Step 4: Verify cleanup
echo -e "${YELLOW}Step 4: Verifying cleanup${NC}"

# Verify policy is detached
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[?PolicyArn==`'$POLICY_ARN'`].PolicyArn' \
    --output text)

if [ -z "$ATTACHED_POLICIES" ]; then
    echo -e "${GREEN}✓ AdministratorAccess policy successfully detached${NC}"
else
    echo -e "${YELLOW}⚠ Warning: AdministratorAccess policy still attached to $STARTING_USER${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess policy from $STARTING_USER"
echo "- Cancelled any running Braket jobs"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, and S3 bucket) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
