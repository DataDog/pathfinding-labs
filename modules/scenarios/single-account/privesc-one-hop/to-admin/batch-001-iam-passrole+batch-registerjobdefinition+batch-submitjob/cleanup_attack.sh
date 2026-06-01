#!/bin/bash
set -e

# Cleanup script for iam:PassRole + batch:RegisterJobDefinition + batch:SubmitJob privilege escalation demo
# This script detaches AdministratorAccess from the starting user and deregisters the job definition

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-batch-001-to-admin-starting-user"
JOB_DEF_NAME="pl-prod-batch-001-to-admin-privesc-job-def"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: PassRole + Batch RegisterJobDefinition + SubmitJob${NC}"
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

# Source demo permissions library and remove any orphaned restriction policies
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Detach AdministratorAccess from the starting user
echo -e "${YELLOW}Step 2: Detaching AdministratorAccess from starting user${NC}"
ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

if aws iam list-attached-user-policies --user-name "$STARTING_USER" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null | grep -q "AdministratorAccess"; then
    aws iam detach-user-policy \
        --user-name "$STARTING_USER" \
        --policy-arn "$ADMIN_POLICY_ARN"
    echo -e "${GREEN}✓ Detached AdministratorAccess from $STARTING_USER${NC}"
else
    echo -e "${YELLOW}AdministratorAccess not attached to $STARTING_USER (may already be detached)${NC}"
fi
echo ""

# Step 3: Deregister the Batch job definition
echo -e "${YELLOW}Step 3: Deregistering Batch job definition${NC}"
echo "Job Definition Name: $JOB_DEF_NAME"
echo "Region: $CURRENT_REGION"

# List all active revisions of the job definition
JOB_DEF_REVISIONS=$(aws batch describe-job-definitions \
    --region $CURRENT_REGION \
    --job-definition-name "$JOB_DEF_NAME" \
    --status ACTIVE \
    --query 'jobDefinitions[*].jobDefinitionArn' \
    --output text 2>/dev/null)

if [ -n "$JOB_DEF_REVISIONS" ] && [ "$JOB_DEF_REVISIONS" != "None" ]; then
    for JOB_DEF_ARN in $JOB_DEF_REVISIONS; do
        echo "Deregistering: $JOB_DEF_ARN"
        aws batch deregister-job-definition \
            --region $CURRENT_REGION \
            --job-definition "$JOB_DEF_ARN"
        echo -e "${GREEN}✓ Deregistered: $JOB_DEF_ARN${NC}"
    done
else
    echo -e "${YELLOW}No active job definition revisions found for $JOB_DEF_NAME (may already be deregistered)${NC}"
fi
echo ""

# Step 4: Verify cleanup
echo -e "${YELLOW}Step 4: Verifying cleanup${NC}"

# Check that AdministratorAccess is detached
if aws iam list-attached-user-policies --user-name "$STARTING_USER" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null | grep -q "AdministratorAccess"; then
    echo -e "${YELLOW}⚠ Warning: AdministratorAccess still attached to $STARTING_USER${NC}"
else
    echo -e "${GREEN}✓ AdministratorAccess successfully detached from $STARTING_USER${NC}"
fi

# Check that job definitions are deregistered
REMAINING_DEFS=$(aws batch describe-job-definitions \
    --region $CURRENT_REGION \
    --job-definition-name "$JOB_DEF_NAME" \
    --status ACTIVE \
    --query 'jobDefinitions | length(@)' \
    --output text 2>/dev/null)

if [ "$REMAINING_DEFS" == "0" ] || [ -z "$REMAINING_DEFS" ]; then
    echo -e "${GREEN}✓ All job definition revisions deregistered${NC}"
else
    echo -e "${YELLOW}⚠ Warning: $REMAINING_DEFS active job definition revision(s) remain${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess from $STARTING_USER"
echo "- Deregistered Batch job definition: $JOB_DEF_NAME"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, compute environment, job queue) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
