#!/bin/bash

# Cleanup script for iam-passrole+sagemaker-createtrainingjob privilege escalation demo
# This script removes the AdministratorAccess policy from the starting user,
# deletes the exploit script from S3, and cleans up local files


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Source demo permissions library for safety restore
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Safety: remove any orphaned restriction policies
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# Configuration
STARTING_USER="pl-prod-sagemaker-002-to-admin-starting-user"
EXPLOIT_SCRIPT="exploit.py"
TRAINING_JOB_PREFIX="pl-demo-training-"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: SageMaker CreateTrainingJob${NC}"
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

# Get the bucket name from the scenario output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_sagemaker_002_iam_passrole_sagemaker_createtrainingjob.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "The scenario may not be deployed"
    exit 1
fi

BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_name')

if [ "$BUCKET_NAME" == "null" ] || [ -z "$BUCKET_NAME" ]; then
    echo -e "${RED}Error: Could not extract bucket name from terraform output${NC}"
    exit 1
fi

echo "S3 Bucket: $BUCKET_NAME"
echo ""

# Navigate back to scenario directory
cd - > /dev/null

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Check and stop any running training jobs
echo -e "${YELLOW}Step 2: Checking for running training jobs${NC}"
echo "Searching for training jobs with prefix: $TRAINING_JOB_PREFIX"
echo ""

# List all training jobs (InProgress status)
RUNNING_JOBS=$(aws sagemaker list-training-jobs \
    --region $CURRENT_REGION \
    --status-equals InProgress \
    --name-contains $TRAINING_JOB_PREFIX \
    --query 'TrainingJobSummaries[*].TrainingJobName' \
    --output text 2>/dev/null || echo "")

if [ -n "$RUNNING_JOBS" ]; then
    echo "Found running training jobs:"
    for JOB_NAME in $RUNNING_JOBS; do
        echo "  - $JOB_NAME"
        echo "Stopping training job: $JOB_NAME"
        aws sagemaker stop-training-job \
            --region $CURRENT_REGION \
            --training-job-name $JOB_NAME 2>/dev/null || true
        echo -e "${GREEN}✓ Stopped training job: $JOB_NAME${NC}"
    done
else
    echo -e "${YELLOW}No running demo training jobs found${NC}"
fi
echo ""

# Step 3: Detach AdministratorAccess policy from starting user
echo -e "${YELLOW}Step 3: Detaching AdministratorAccess policy from starting user${NC}"
echo "Checking if AdministratorAccess is attached to: $STARTING_USER"

# Check if the policy is attached
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`].PolicyArn' \
    --output text 2>/dev/null || echo "")

if [ -n "$ATTACHED_POLICIES" ]; then
    echo "Detaching AdministratorAccess policy..."
    aws iam detach-user-policy \
        --user-name $STARTING_USER \
        --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"
    echo -e "${GREEN}✓ Detached AdministratorAccess policy${NC}"
else
    echo -e "${YELLOW}AdministratorAccess policy not attached (may already be cleaned up)${NC}"
fi
echo ""

# Step 4: Delete exploit script and packaged tar.gz from S3
echo -e "${YELLOW}Step 4: Deleting exploit script from S3${NC}"

# Delete the raw exploit script (if it exists from old runs)
if aws s3 ls s3://$BUCKET_NAME/$EXPLOIT_SCRIPT &> /dev/null; then
    echo "Deleting exploit script: s3://$BUCKET_NAME/$EXPLOIT_SCRIPT"
    aws s3 rm s3://$BUCKET_NAME/$EXPLOIT_SCRIPT
    echo -e "${GREEN}✓ Deleted exploit script${NC}"
fi

# Delete the packaged tar.gz file
if aws s3 ls s3://$BUCKET_NAME/sourcedir.tar.gz &> /dev/null; then
    echo "Deleting packaged script: s3://$BUCKET_NAME/sourcedir.tar.gz"
    aws s3 rm s3://$BUCKET_NAME/sourcedir.tar.gz
    echo -e "${GREEN}✓ Deleted packaged script${NC}"
else
    echo -e "${YELLOW}Packaged script not found in S3 (may already be deleted)${NC}"
fi
echo ""

# Step 5: Clean up output directory in S3 (if it exists)
echo -e "${YELLOW}Step 5: Cleaning up training job outputs from S3${NC}"
echo "Checking for: s3://$BUCKET_NAME/output/"

# Check if output directory exists and has objects
OUTPUT_COUNT=$(aws s3 ls s3://$BUCKET_NAME/output/ 2>/dev/null | wc -l || echo "0")

if [ "$OUTPUT_COUNT" -gt 0 ]; then
    echo "Deleting training job outputs..."
    aws s3 rm s3://$BUCKET_NAME/output/ --recursive
    echo -e "${GREEN}✓ Deleted training job outputs from S3${NC}"
else
    echo -e "${YELLOW}No training job outputs found in S3${NC}"
fi
echo ""

# Step 6: Clean up local files
echo -e "${YELLOW}Step 6: Cleaning up local files${NC}"

if [ -f "/tmp/$EXPLOIT_SCRIPT" ]; then
    rm -f /tmp/$EXPLOIT_SCRIPT
    echo -e "${GREEN}✓ Deleted local exploit script${NC}"
else
    echo -e "${YELLOW}Local exploit script not found (may already be deleted)${NC}"
fi
echo ""

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Stopped any running demo training jobs"
echo "- Detached AdministratorAccess policy from $STARTING_USER"
echo "- Deleted exploit script from S3"
echo "- Cleaned up training job outputs from S3"
echo "- Deleted local exploit script"

echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, bucket) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

echo -e "${BLUE}Note: Completed training jobs are automatically cleaned up by AWS${NC}"
echo -e "${BLUE}and do not need manual deletion.${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
