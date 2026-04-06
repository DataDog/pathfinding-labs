#!/bin/bash

# Demo script for test-reverse-blast-radius-direct-and-indirect-through-admin
# This scenario demonstrates direct S3 access and indirect access via admin role
# to validate reverse blast radius detection of administrative permissions


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
USER1_NAME="pl-prod-rbr-admin-user1"
USER2_NAME="pl-prod-rbr-admin-user2"
ROLE3_NAME="pl-prod-rbr-admin-role3"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Reverse Blast Radius: Direct and Indirect Access Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}This scenario tests reverse blast radius detection:${NC}"
echo "- Path 1: user1 → (direct S3 access) → bucket"
echo "- Path 2: user2 → role3 (admin) → (S3 access via admin) → bucket"
echo ""

# Check if required tools are installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed or not in PATH${NC}"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed or not in PATH${NC}"
    exit 1
fi

# Step 1: Retrieve credentials from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
USER1_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.user1_access_key_id')
USER1_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.user1_secret_access_key')
USER2_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.user2_access_key_id')
USER2_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.user2_secret_access_key')
ROLE3_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.role3_arn')
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_name')

if [ "$USER1_ACCESS_KEY_ID" == "null" ] || [ -z "$USER1_ACCESS_KEY_ID" ]; then
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

echo "Retrieved access keys for:"
echo "  - User1: $USER1_NAME (Access Key: ${USER1_ACCESS_KEY_ID:0:10}...)"
echo "  - User2: $USER2_NAME (Access Key: ${USER2_ACCESS_KEY_ID:0:10}...)"
echo "  - ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo "  - Role3: $ROLE3_NAME ($ROLE3_ARN)"
echo "  - Target Bucket: $BUCKET_NAME"
echo "  - Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Credential switching helpers
use_user1_creds() {
    export AWS_ACCESS_KEY_ID="$USER1_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$USER1_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
}
use_user2_creds() {
    export AWS_ACCESS_KEY_ID="$USER2_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$USER2_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
}
use_readonly_creds() {
    export AWS_ACCESS_KEY_ID="$READONLY_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$READONLY_SECRET_KEY"
    unset AWS_SESSION_TOKEN
}

# Source demo permissions library for validation restriction
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# =============================================================================
# PATH 1: Direct S3 Access (user1)
# =============================================================================

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}PATH 1: Direct S3 Access (user1)${NC}"
echo -e "${GREEN}========================================${NC}\n"

# [EXPLOIT] Step 2: Configure AWS credentials with user1
echo -e "${YELLOW}Step 2: Configuring AWS CLI with user1 credentials${NC}"
use_user1_creds
export AWS_REGION=$AWS_REGION

echo "Using region: $AWS_REGION"

# Verify user1 identity
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$USER1_NAME"* ]]; then
    echo -e "${RED}Error: Not running as $USER1_NAME${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified user1 identity${NC}\n"

# [OBSERVATION] Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [EXPLOIT] Step 4: List all S3 buckets
echo -e "${YELLOW}Step 4: Listing all S3 buckets with user1${NC}"
echo "User1 has direct S3 permissions..."
use_user1_creds
show_attack_cmd "Attacker" "aws s3api list-buckets --query 'Buckets[*].Name' --output text"
BUCKETS=$(aws s3api list-buckets --query 'Buckets[*].Name' --output text)
echo "Found buckets:"
for bucket in $BUCKETS; do
    if [[ "$bucket" == *"rbr-admin"* ]]; then
        echo -e "  - ${GREEN}$bucket${NC} (target bucket)"
    else
        echo "  - $bucket"
    fi
done
echo -e "${GREEN}✓ Successfully listed buckets${NC}\n"

# [EXPLOIT] Step 5: Access the target bucket directly
echo -e "${YELLOW}Step 5: Accessing target bucket directly with user1${NC}"
echo "Target bucket: $BUCKET_NAME"

echo "Listing objects in bucket..."
show_attack_cmd "Attacker" "aws s3 ls s3://$BUCKET_NAME/"
aws s3 ls s3://$BUCKET_NAME/
echo -e "${GREEN}✓ Successfully listed bucket contents${NC}\n"

# [EXPLOIT] Step 6: Download and read sensitive data
echo -e "${YELLOW}Step 6: Reading sensitive data with user1${NC}"
echo "Downloading sensitive-data.txt..."

TEMP_FILE="/tmp/user1-sensitive-data.txt"
show_attack_cmd "Attacker" "aws s3 cp s3://$BUCKET_NAME/sensitive-data.txt $TEMP_FILE"
aws s3 cp s3://$BUCKET_NAME/sensitive-data.txt $TEMP_FILE

echo -e "${GREEN}✓ Successfully downloaded file${NC}"
echo -e "\n${BLUE}File contents:${NC}"
cat $TEMP_FILE
echo ""

# Clean up temp file
rm -f $TEMP_FILE

echo -e "${GREEN}✓ Path 1 Complete: user1 has direct S3 access to bucket${NC}\n"

# =============================================================================
# PATH 2: Indirect Access via Admin Role (user2 → role3)
# =============================================================================

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}PATH 2: Indirect Access via Admin (user2 → role3)${NC}"
echo -e "${GREEN}========================================${NC}\n"

# [EXPLOIT] Step 7: Switch to user2 credentials
echo -e "${YELLOW}Step 7: Configuring AWS CLI with user2 credentials${NC}"
use_user2_creds
export AWS_REGION=$AWS_REGION

# Verify user2 identity
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$USER2_NAME"* ]]; then
    echo -e "${RED}Error: Not running as $USER2_NAME${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified user2 identity${NC}\n"

# [EXPLOIT] Step 8: Verify user2 doesn't have direct S3 access
echo -e "${YELLOW}Step 8: Verifying user2 doesn't have direct S3 access${NC}"
echo "Attempting to list buckets with user2..."

show_cmd "Attacker" "aws s3api list-buckets --output text"
if aws s3api list-buckets --output text &> /dev/null; then
    echo -e "${YELLOW}⚠ Unexpectedly can list buckets (user2 may have some S3 permissions)${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list buckets directly (as expected)${NC}"
fi

echo "Attempting to access target bucket directly..."
show_cmd "Attacker" "aws s3 ls s3://$BUCKET_NAME/"
if aws s3 ls s3://$BUCKET_NAME/ &> /dev/null; then
    echo -e "${YELLOW}⚠ Unexpectedly can access bucket (user2 may have direct access)${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot access bucket directly (as expected)${NC}"
fi
echo ""

# [EXPLOIT] Step 9: Assume role3 (admin role)
echo -e "${YELLOW}Step 9: Assuming role3 (admin role)${NC}"
echo "Role ARN: $ROLE3_ARN"
echo "This role has AdministratorAccess..."

show_attack_cmd "Attacker" "aws sts assume-role --role-arn $ROLE3_ARN --role-session-name demo-admin-session --query 'Credentials' --output json"
CREDENTIALS=$(aws sts assume-role \
    --role-arn $ROLE3_ARN \
    --role-session-name demo-admin-session \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')
# Keep region consistent
export AWS_REGION=$AWS_REGION

# Verify we assumed the role
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ROLE_IDENTITY"

if [[ ! $ROLE_IDENTITY == *"$ROLE3_NAME"* ]]; then
    echo -e "${RED}Error: Failed to assume role3${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Successfully assumed role3 (admin role)${NC}\n"

# [OBSERVATION] Step 10: Verify admin permissions
echo -e "${YELLOW}Step 10: Verifying admin permissions${NC}"
echo "Testing administrative access with IAM ListUsers..."

show_cmd "Attacker" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list IAM users${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 11: List all S3 buckets as admin
echo -e "${YELLOW}Step 11: Listing all S3 buckets as admin${NC}"
echo "Admin role has full S3 access via AdministratorAccess..."

show_attack_cmd "Attacker" "aws s3api list-buckets --query 'Buckets[*].Name' --output text"
BUCKETS=$(aws s3api list-buckets --query 'Buckets[*].Name' --output text)
echo "Found buckets:"
for bucket in $BUCKETS; do
    if [[ "$bucket" == *"rbr-admin"* ]]; then
        echo -e "  - ${GREEN}$bucket${NC} (target bucket)"
    else
        echo "  - $bucket"
    fi
done
echo -e "${GREEN}✓ Successfully listed buckets as admin${NC}\n"

# [EXPLOIT] Step 12: Access the target bucket via admin role
echo -e "${YELLOW}Step 12: Accessing target bucket via admin role${NC}"
echo "Target bucket: $BUCKET_NAME"
echo "Access is granted through AdministratorAccess policy..."

echo "Listing objects in bucket..."
show_attack_cmd "Attacker" "aws s3 ls s3://$BUCKET_NAME/"
aws s3 ls s3://$BUCKET_NAME/
echo -e "${GREEN}✓ Successfully listed bucket contents${NC}\n"

# [EXPLOIT] Step 13: Download and read sensitive data via admin role
echo -e "${YELLOW}Step 13: Reading sensitive data via admin role${NC}"
echo "Downloading sensitive-data.txt..."

TEMP_FILE="/tmp/admin-sensitive-data.txt"
show_attack_cmd "Attacker" "aws s3 cp s3://$BUCKET_NAME/sensitive-data.txt $TEMP_FILE"
aws s3 cp s3://$BUCKET_NAME/sensitive-data.txt $TEMP_FILE

echo -e "${GREEN}✓ Successfully downloaded file via admin role${NC}"
echo -e "\n${BLUE}File contents:${NC}"
cat $TEMP_FILE
echo ""

# Clean up temp file
rm -f $TEMP_FILE

echo -e "${GREEN}✓ Path 2 Complete: user2 → role3 (admin) → bucket access${NC}\n"

# =============================================================================
# Final Summary
# =============================================================================

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ REVERSE BLAST RADIUS TEST COMPLETE!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo ""
echo -e "${BLUE}PATH 1 - Direct Access:${NC}"
echo "  1. Started as: $USER1_NAME"
echo "  2. Direct S3 permissions: ListBucket, GetObject"
echo "  3. Successfully accessed: $BUCKET_NAME"
echo ""
echo -e "${BLUE}PATH 2 - Indirect Access via Admin:${NC}"
echo "  1. Started as: $USER2_NAME"
echo "  2. Assumed role: $ROLE3_NAME (AdministratorAccess)"
echo "  3. Admin role grants full S3 access"
echo "  4. Successfully accessed: $BUCKET_NAME"
echo ""
echo -e "${YELLOW}Reverse Blast Radius Detection:${NC}"
echo "A proper security tool should detect:"
echo "  ✓ user1 has direct access to the sensitive bucket"
echo "  ✓ user2 has indirect access via admin role assumption"
echo "  ✓ role3 has AdministratorAccess (broad permissions)"
echo "  ✓ Both principals can access the same sensitive resource"
echo ""

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}MITRE ATT&CK Mapping:${NC}"
echo "  - T1078: Valid Accounts"
echo "  - T1098: Account Manipulation"
echo "  - T1530: Data from Cloud Storage Object"
echo ""
echo -e "${RED}⚠ Important:${NC}"
echo "This scenario demonstrates reverse blast radius analysis:"
echo "- Starting from a sensitive resource (S3 bucket)"
echo "- Identifying all principals that can access it"
echo "- Direct paths and indirect paths through privilege escalation"
echo ""
echo -e "${YELLOW}No cleanup required - this scenario only reads data.${NC}"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
