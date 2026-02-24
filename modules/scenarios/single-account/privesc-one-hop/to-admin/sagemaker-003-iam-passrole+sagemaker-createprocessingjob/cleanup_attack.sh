#!/bin/bash

# Cleanup script for iam-passrole+sagemaker-createprocessingjob privilege escalation demo
# This script removes attack artifacts created during the demonstration


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-sagemaker-003-to-admin-starting-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: PassRole + SageMaker CreateProcessingJob${NC}"
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

# Get the bucket name from terraform output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_sagemaker_003_iam_passrole_sagemaker_createprocessingjob.value // empty')
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_name')

if [ -z "$BUCKET_NAME" ] || [ "$BUCKET_NAME" == "null" ]; then
    echo -e "${RED}Error: Could not find bucket name from terraform output${NC}"
    exit 1
fi

echo "Bucket: $BUCKET_NAME"

# Navigate back to scenario directory
cd - > /dev/null

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Stop any running processing jobs
echo -e "${YELLOW}Step 2: Checking for running processing jobs${NC}"
DEMO_JOB_PREFIX="pl-demo-processing-"

echo "Searching for processing jobs with prefix: $DEMO_JOB_PREFIX"
echo ""

# List all processing jobs (in progress or completed recently)
PROCESSING_JOBS=$(aws sagemaker list-processing-jobs \
    --region $CURRENT_REGION \
    --max-results 100 \
    --query "ProcessingJobSummaries[?starts_with(ProcessingJobName, '$DEMO_JOB_PREFIX')].{Name:ProcessingJobName,Status:ProcessingJobStatus}" \
    --output json)

if [ "$PROCESSING_JOBS" == "[]" ] || [ -z "$PROCESSING_JOBS" ]; then
    echo -e "${YELLOW}No demo processing jobs found${NC}"
else
    echo "Found processing jobs:"
    echo "$PROCESSING_JOBS" | jq -r '.[] | "  - \(.Name) (\(.Status))"'
    echo ""

    # Stop any InProgress jobs
    INPROGRESS_JOBS=$(echo "$PROCESSING_JOBS" | jq -r '.[] | select(.Status == "InProgress") | .Name')

    if [ -n "$INPROGRESS_JOBS" ]; then
        echo "Stopping InProgress jobs..."
        for JOB_NAME in $INPROGRESS_JOBS; do
            echo "Stopping job: $JOB_NAME"
            aws sagemaker stop-processing-job \
                --region $CURRENT_REGION \
                --processing-job-name "$JOB_NAME" 2>/dev/null || true
            echo -e "${GREEN}✓ Stopped job: $JOB_NAME${NC}"
        done
        echo ""
    fi
fi

echo -e "${GREEN}✓ Checked processing jobs${NC}"
echo -e "${YELLOW}Note: Processing jobs are automatically deleted by SageMaker after completion${NC}\n"

# Step 3: Remove AdministratorAccess policy from starting user
echo -e "${YELLOW}Step 3: Removing AdministratorAccess policy from starting user${NC}"

# Check if the policy is attached
if aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query "AttachedPolicies[?PolicyArn=='arn:aws:iam::aws:policy/AdministratorAccess']" \
    --output text | grep -q "AdministratorAccess"; then

    echo "Detaching AdministratorAccess policy from $STARTING_USER..."
    aws iam detach-user-policy \
        --user-name $STARTING_USER \
        --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"
    echo -e "${GREEN}✓ Detached AdministratorAccess policy${NC}"
else
    echo -e "${YELLOW}AdministratorAccess policy not attached (may already be removed)${NC}"
fi
echo ""

# Step 4: Delete exploit script from S3
echo -e "${YELLOW}Step 4: Cleaning up S3 artifacts${NC}"

# Delete the exploit script
if aws s3 ls s3://$BUCKET_NAME/scripts/exploit.py &> /dev/null; then
    echo "Deleting s3://$BUCKET_NAME/scripts/exploit.py"
    aws s3 rm s3://$BUCKET_NAME/scripts/exploit.py
    echo -e "${GREEN}✓ Deleted exploit script${NC}"
else
    echo -e "${YELLOW}Exploit script not found (may already be deleted)${NC}"
fi

# Clean up output directory if it exists
if aws s3 ls s3://$BUCKET_NAME/output/ &> /dev/null; then
    echo "Cleaning up output directory..."
    aws s3 rm s3://$BUCKET_NAME/output/ --recursive
    echo -e "${GREEN}✓ Cleaned output directory${NC}"
fi

# Clean up scripts directory if empty
SCRIPT_COUNT=$(aws s3 ls s3://$BUCKET_NAME/scripts/ 2>/dev/null | wc -l)
if [ "$SCRIPT_COUNT" -eq 0 ]; then
    aws s3api delete-object --bucket $BUCKET_NAME --key scripts/ 2>/dev/null || true
fi

echo ""

# Step 5: Clean up local temporary files
echo -e "${YELLOW}Step 5: Cleaning up local temporary files${NC}"
rm -f /tmp/exploit.py
echo -e "${GREEN}✓ Cleaned up local files${NC}\n"

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Stopped any running demo processing jobs"
echo "- Removed AdministratorAccess policy from $STARTING_USER"
echo "- Deleted exploit script from S3 bucket"
echo "- Cleaned up local temporary files"

echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (user, role, bucket) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
