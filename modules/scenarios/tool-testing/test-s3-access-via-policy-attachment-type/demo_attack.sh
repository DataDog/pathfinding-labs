#!/bin/bash

# Demo script for test-s3-access-via-policy-attachment-type
# This scenario demonstrates that 4 independent test principals (2 IAM users,
# 2 IAM roles) all have equivalent full read/write access to the same S3
# bucket, granted via two different IAM attachment mechanisms:
#   - Inline policy embedded directly on the principal
#   - Customer-managed policy attached to the principal
#
# Two of the principals are IAM users accessed directly with their own
# access keys. The other two are IAM roles reached by having a shared
# "starting user" perform sts:AssumeRole.
#
# The point of this scenario is NOT bucket misconfiguration - it is to
# validate that a graph/CSPM tool infers identical bucket-access edges for
# all 4 principals regardless of the underlying IAM attachment mechanism.
#
# This is a Tool Testing scenario - there is no CTF flag capture step.
# The demo instead proves read+write access for every principal.


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

# Display a non-attack command with identity context
show_cmd() {
    local identity="$1"; shift
    echo -e "${DIM}[${identity}] \$ $*${NC}"
}

# Display AND record an attack command with identity context
show_attack_cmd() {
    local identity="$1"; shift
    echo -e "\n${CYAN}[${identity}] \$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Track PASS/FAIL results for the final summary
declare -a RESULT_LABELS=()
declare -a RESULT_STATUS=()

record_result() {
    local label="$1"
    local status="$2"
    RESULT_LABELS+=("$label")
    RESULT_STATUS+=("$status")
}

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}S3 Access via Policy Attachment Type${NC}"
echo -e "${GREEN}Tool Testing Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo "This scenario demonstrates that 4 independent test principals all have"
echo "equivalent full read/write access to the same S3 bucket:"
echo "  1. pl-prod-patn-user-inline   - IAM user,  inline policy grant"
echo "  2. pl-prod-patn-user-managed  - IAM user,  managed policy grant"
echo "  3. pl-prod-patn-role-inline   - IAM role,  inline policy grant  (reached via assume-role)"
echo "  4. pl-prod-patn-role-managed  - IAM role,  managed policy grant (reached via assume-role)"
echo ""
echo "A properly configured graph/CSPM tool should detect identical"
echo "bucket-access edges for all 4 principals, regardless of the"
echo "underlying IAM attachment mechanism used to grant that access."
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed or not in PATH${NC}"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed or not in PATH${NC}"
    echo "Please install jq to parse JSON outputs"
    exit 1
fi

# Navigate to the Terraform root directory (4 levels up from scenario directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Step 1: Retrieve credentials and configuration from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd "$TERRAFORM_ROOT"

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_s3_access_via_policy_attachment_type.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials and resource information
STARTING_USER_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_USER_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name')

USER_INLINE_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.user_inline_access_key_id')
USER_INLINE_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.user_inline_secret_access_key')
USER_INLINE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.user_inline_name')

USER_MANAGED_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.user_managed_access_key_id')
USER_MANAGED_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.user_managed_secret_access_key')
USER_MANAGED_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.user_managed_name')

ROLE_INLINE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.role_inline_arn')
ROLE_INLINE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.role_inline_name')

ROLE_MANAGED_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.role_managed_arn')
ROLE_MANAGED_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.role_managed_name')

BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.target_bucket_name')

if [ "$USER_INLINE_ACCESS_KEY_ID" == "null" ] || [ -z "$USER_INLINE_ACCESS_KEY_ID" ]; then
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

# Get region from Terraform
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved credentials for:"
echo "  - Starting user: $STARTING_USER_NAME (assume-role only)"
echo "  - User (inline):  $USER_INLINE_NAME"
echo "  - User (managed): $USER_MANAGED_NAME"
echo "  - Role (inline):  $ROLE_INLINE_NAME"
echo "  - Role (managed): $ROLE_MANAGED_NAME"
echo "  - Bucket: $BUCKET_NAME"
echo "  - Region: $AWS_REGION"
echo "  ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Credential switching helpers
use_starting_user_creds() {
    export AWS_ACCESS_KEY_ID="$STARTING_USER_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$STARTING_USER_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
}
use_user_inline_creds() {
    export AWS_ACCESS_KEY_ID="$USER_INLINE_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$USER_INLINE_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
}
use_user_managed_creds() {
    export AWS_ACCESS_KEY_ID="$USER_MANAGED_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$USER_MANAGED_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
}
use_readonly_creds() {
    export AWS_ACCESS_KEY_ID="$READONLY_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$READONLY_SECRET_KEY"
    unset AWS_SESSION_TOKEN
}

# Source demo permissions library for validation restriction
source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# Helper: put a small test object, get it back, verify content, print PASS/FAIL
# Args: identity_label, s3_key, downloaded_file_path
demo_put_get_verify() {
    local identity_label="$1"
    local s3_key="$2"
    local downloaded_file="$3"

    local upload_file
    upload_file=$(mktemp /tmp/patn-upload.XXXXXX)
    local marker="patn-test-write-by-${s3_key//\//-}-$(date +%s)"
    echo "$marker" > "$upload_file"

    echo "Writing test object: s3://$BUCKET_NAME/$s3_key"
    show_attack_cmd "$identity_label" "aws s3 cp $upload_file s3://$BUCKET_NAME/$s3_key"
    if ! aws s3 cp "$upload_file" "s3://$BUCKET_NAME/$s3_key" > /dev/null 2>&1; then
        echo -e "${RED}✗ FAIL: $identity_label could not write to bucket${NC}\n"
        rm -f "$upload_file"
        record_result "$identity_label - write (PutObject)" "FAIL"
        record_result "$identity_label - read (GetObject)" "SKIPPED"
        return 1
    fi
    echo -e "${GREEN}✓ Write succeeded${NC}"
    record_result "$identity_label - write (PutObject)" "PASS"

    echo "Reading test object back: s3://$BUCKET_NAME/$s3_key"
    show_attack_cmd "$identity_label" "aws s3 cp s3://$BUCKET_NAME/$s3_key $downloaded_file"
    if ! aws s3 cp "s3://$BUCKET_NAME/$s3_key" "$downloaded_file" > /dev/null 2>&1; then
        echo -e "${RED}✗ FAIL: $identity_label could not read from bucket${NC}\n"
        rm -f "$upload_file"
        record_result "$identity_label - read (GetObject)" "FAIL"
        return 1
    fi

    if [ "$(cat "$downloaded_file")" == "$marker" ]; then
        echo -e "${GREEN}✓ Read succeeded and content matches${NC}"
        record_result "$identity_label - read (GetObject)" "PASS"
    else
        echo -e "${RED}✗ FAIL: downloaded content does not match uploaded content${NC}"
        record_result "$identity_label - read (GetObject)" "FAIL"
        rm -f "$upload_file"
        return 1
    fi

    rm -f "$upload_file"
    echo -e "${GREEN}✅ PASS: $identity_label has full read+write access to bucket${NC}\n"
    return 0
}

# [OBSERVATION] Step 2: Get account ID using readonly credentials
echo -e "${YELLOW}Step 2: Getting account ID${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}PRINCIPAL 1: IAM User - Inline Policy${NC}"
echo -e "${BLUE}========================================${NC}\n"

# [EXPLOIT] Step 3: Verify user_inline identity
echo -e "${YELLOW}Step 3: Verifying $USER_INLINE_NAME identity${NC}"
use_user_inline_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

show_cmd "user-inline" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$USER_INLINE_NAME"* ]]; then
    echo -e "${RED}Error: Not running as $USER_INLINE_NAME${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified $USER_INLINE_NAME identity${NC}\n"

# [EXPLOIT] Step 4: Prove read+write access via inline policy on the user
echo -e "${YELLOW}Step 4: Demonstrating S3 access for $USER_INLINE_NAME (inline policy)${NC}"
demo_put_get_verify "user-inline ($USER_INLINE_NAME)" "patn-test/user-inline.txt" "/tmp/patn-download-user-inline.txt"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}PRINCIPAL 2: IAM User - Managed Policy${NC}"
echo -e "${BLUE}========================================${NC}\n"

# [EXPLOIT] Step 5: Verify user_managed identity
echo -e "${YELLOW}Step 5: Verifying $USER_MANAGED_NAME identity${NC}"
use_user_managed_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

show_cmd "user-managed" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$USER_MANAGED_NAME"* ]]; then
    echo -e "${RED}Error: Not running as $USER_MANAGED_NAME${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified $USER_MANAGED_NAME identity${NC}\n"

# [EXPLOIT] Step 6: Prove read+write access via managed policy on the user
echo -e "${YELLOW}Step 6: Demonstrating S3 access for $USER_MANAGED_NAME (managed policy)${NC}"
demo_put_get_verify "user-managed ($USER_MANAGED_NAME)" "patn-test/user-managed.txt" "/tmp/patn-download-user-managed.txt"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}PRINCIPAL 3: IAM Role - Inline Policy${NC}"
echo -e "${BLUE}(reached via starting-user assume-role)${NC}"
echo -e "${BLUE}========================================${NC}\n"

# [EXPLOIT] Step 7: Verify starting user identity
echo -e "${YELLOW}Step 7: Switching to $STARTING_USER_NAME credentials${NC}"
use_starting_user_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

show_cmd "starting-user" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER_NAME"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER_NAME${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified $STARTING_USER_NAME identity${NC}\n"

# [EXPLOIT] Step 8: Assume role_inline with the starting user
echo -e "${YELLOW}Step 8: Assuming $ROLE_INLINE_NAME with $STARTING_USER_NAME credentials${NC}"
use_starting_user_creds
echo "Role ARN: $ROLE_INLINE_ARN"

show_attack_cmd "starting-user" "aws sts assume-role --role-arn $ROLE_INLINE_ARN --role-session-name demo-session --query 'Credentials' --output json"
CREDENTIALS=$(aws sts assume-role \
    --role-arn "$ROLE_INLINE_ARN" \
    --role-session-name demo-session \
    --query 'Credentials' \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Failed to assume $ROLE_INLINE_NAME${NC}"
    exit 1
fi

export AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS" | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS" | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$CREDENTIALS" | jq -r '.SessionToken')
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

show_cmd "role-inline" "aws sts get-caller-identity --query 'Arn' --output text"
ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ROLE_IDENTITY"
echo -e "${GREEN}✓ Successfully assumed $ROLE_INLINE_NAME${NC}\n"

# [EXPLOIT] Step 9: Prove read+write access via inline policy on the role
echo -e "${YELLOW}Step 9: Demonstrating S3 access for $ROLE_INLINE_NAME (inline policy)${NC}"
demo_put_get_verify "role-inline ($ROLE_INLINE_NAME)" "patn-test/role-inline.txt" "/tmp/patn-download-role-inline.txt"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}PRINCIPAL 4: IAM Role - Managed Policy${NC}"
echo -e "${BLUE}(reached via starting-user assume-role)${NC}"
echo -e "${BLUE}========================================${NC}\n"

# [EXPLOIT] Step 10: Switch back to starting user to assume role_managed
echo -e "${YELLOW}Step 10: Switching back to $STARTING_USER_NAME credentials${NC}"
use_starting_user_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

show_cmd "starting-user" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"
echo -e "${GREEN}✓ Verified $STARTING_USER_NAME identity${NC}\n"

# [EXPLOIT] Step 11: Assume role_managed with the starting user
echo -e "${YELLOW}Step 11: Assuming $ROLE_MANAGED_NAME with $STARTING_USER_NAME credentials${NC}"
use_starting_user_creds
echo "Role ARN: $ROLE_MANAGED_ARN"

show_attack_cmd "starting-user" "aws sts assume-role --role-arn $ROLE_MANAGED_ARN --role-session-name demo-session --query 'Credentials' --output json"
CREDENTIALS=$(aws sts assume-role \
    --role-arn "$ROLE_MANAGED_ARN" \
    --role-session-name demo-session \
    --query 'Credentials' \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Failed to assume $ROLE_MANAGED_NAME${NC}"
    exit 1
fi

export AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS" | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS" | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$CREDENTIALS" | jq -r '.SessionToken')
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

show_cmd "role-managed" "aws sts get-caller-identity --query 'Arn' --output text"
ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ROLE_IDENTITY"
echo -e "${GREEN}✓ Successfully assumed $ROLE_MANAGED_NAME${NC}\n"

# [EXPLOIT] Step 12: Prove read+write access via managed policy on the role
echo -e "${YELLOW}Step 12: Demonstrating S3 access for $ROLE_MANAGED_NAME (managed policy)${NC}"
demo_put_get_verify "role-managed ($ROLE_MANAGED_NAME)" "patn-test/role-managed.txt" "/tmp/patn-download-role-managed.txt"

# Restore helpful permissions before printing summary
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ DEMONSTRATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Test Principal Results (PASS/FAIL):${NC}"
for i in "${!RESULT_LABELS[@]}"; do
    status="${RESULT_STATUS[$i]}"
    label="${RESULT_LABELS[$i]}"
    if [ "$status" == "PASS" ]; then
        echo -e "  ${GREEN}✓ PASS${NC} - $label"
    elif [ "$status" == "SKIPPED" ]; then
        echo -e "  ${YELLOW}- SKIPPED${NC} - $label"
    else
        echo -e "  ${RED}✗ FAIL${NC} - $label"
    fi
done
echo ""

echo -e "${YELLOW}Attack Paths Demonstrated:${NC}"
echo "1. $USER_INLINE_NAME  → (inline user policy)   → S3 bucket"
echo "2. $USER_MANAGED_NAME → (managed policy)        → S3 bucket"
echo "3. $STARTING_USER_NAME → (sts:AssumeRole) → $ROLE_INLINE_NAME  → (inline role policy)   → S3 bucket"
echo "4. $STARTING_USER_NAME → (sts:AssumeRole) → $ROLE_MANAGED_NAME → (managed policy)        → S3 bucket"
echo ""

echo -e "${YELLOW}Reverse Blast Radius / Tool Testing Objective:${NC}"
echo "A graph/CSPM tool inspecting s3://$BUCKET_NAME should report all 4"
echo "principals below as having equivalent full read/write access,"
echo "regardless of the IAM attachment mechanism used:"
echo "  ✓ $USER_INLINE_NAME (inline policy on user)"
echo "  ✓ $USER_MANAGED_NAME (managed policy on user)"
echo "  ✓ $ROLE_INLINE_NAME (inline policy on role)"
echo "  ✓ $ROLE_MANAGED_NAME (managed policy on role)"
echo ""

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
    echo ""
fi

echo -e "${YELLOW}Attack Artifacts:${NC}"
echo "  - s3://$BUCKET_NAME/patn-test/user-inline.txt"
echo "  - s3://$BUCKET_NAME/patn-test/user-managed.txt"
echo "  - s3://$BUCKET_NAME/patn-test/role-inline.txt"
echo "  - s3://$BUCKET_NAME/patn-test/role-managed.txt"
echo "  - /tmp/patn-download-user-inline.txt"
echo "  - /tmp/patn-download-user-managed.txt"
echo "  - /tmp/patn-download-role-inline.txt"
echo "  - /tmp/patn-download-role-managed.txt"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Clean up credentials from environment
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
