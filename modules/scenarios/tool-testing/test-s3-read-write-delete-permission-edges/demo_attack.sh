#!/bin/bash

# Demo script for test-s3-read-write-delete-permission-edges
#
# This scenario grants 8 independent test principals (4 permission tiers x
# IAM user/role) a precise, non-overlapping subset of s3:GetObject /
# s3:PutObject / s3:DeleteObject on the same S3 bucket:
#   - Read-Only          : GetObject + ListBucket only
#   - Write-Only         : PutObject only
#   - Delete-Only        : DeleteObject only
#   - Read+Write+Delete  : GetObject + PutObject + DeleteObject + ListBucket
#
# The bucket already contains one pre-seeded object (created by Terraform)
# that every principal attempts to read. Each principal also attempts to
# put a new test object and delete an object.
#
# The point of this scenario is NOT privilege escalation - it is to
# validate that a graph/CSPM tool generates can_read/can_write/can_delete
# edges that EXACTLY match each principal's granted tier, with no
# over-inference (false positive edges) or under-inference (false
# negative edges).
#
# This is a Tool Testing scenario - there is no CTF flag capture step.
# The demo instead proves the exact Get/Put/Delete outcome for all 8
# principals and prints a PASS/FAIL matrix at the end.


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

# Matrix tracking arrays (Bash 3.2 compatible - no associative arrays)
MATRIX_LABELS=()
MATRIX_GET=()
MATRIX_PUT=()
MATRIX_DELETE=()
MISMATCH_COUNT=0

# Record one cell result. Prints a colored line and tracks whether the
# actual outcome matched what the granted permission tier should produce.
# Args: identity_label, operation_name ("GetObject"|"PutObject"|"DeleteObject"), expected ("ALLOW"|"DENY"), actual ("ALLOW"|"DENY")
record_cell() {
    local label="$1" op="$2" expected="$3" actual="$4"
    if [ "$expected" == "$actual" ]; then
        echo -e "  ${GREEN}✓${NC} $op: ${actual} (expected ${expected}) - correct"
    else
        echo -e "  ${RED}✗${NC} $op: ${actual} (expected ${expected}) - ${RED}MISMATCH${NC}"
        MISMATCH_COUNT=$((MISMATCH_COUNT + 1))
    fi
}

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}S3 Read/Write/Delete Permission Edge Granularity${NC}"
echo -e "${GREEN}Tool Testing Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo "This scenario tests 8 independent principals, each granted an exact,"
echo "non-overlapping subset of s3:GetObject / s3:PutObject / s3:DeleteObject"
echo "on the same bucket:"
echo "  1. pl-prod-rwd-user-read-only          - GetObject + ListBucket only"
echo "  2. pl-prod-rwd-role-read-only           - GetObject + ListBucket only (via assume-role)"
echo "  3. pl-prod-rwd-user-write-only          - PutObject only"
echo "  4. pl-prod-rwd-role-write-only          - PutObject only (via assume-role)"
echo "  5. pl-prod-rwd-user-delete-only         - DeleteObject only"
echo "  6. pl-prod-rwd-role-delete-only         - DeleteObject only (via assume-role)"
echo "  7. pl-prod-rwd-user-read-write-delete   - Get + Put + Delete + ListBucket"
echo "  8. pl-prod-rwd-role-read-write-delete   - Get + Put + Delete + ListBucket (via assume-role)"
echo ""
echo "A properly configured graph/CSPM tool should generate can_read,"
echo "can_write, and can_delete edges for each principal that EXACTLY"
echo "match its granted tier - no more, no less."
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Step 1: Retrieve credentials and configuration from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd "$TERRAFORM_ROOT"

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_s3_read_write_delete_permission_edges.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Starting user (assumes the 4 role-based test principals)
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name')

# Read-only tier
USER_READ_ONLY_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.user_read_only_name')
USER_READ_ONLY_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.user_read_only_access_key_id')
USER_READ_ONLY_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.user_read_only_secret_access_key')
ROLE_READ_ONLY_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.role_read_only_name')
ROLE_READ_ONLY_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.role_read_only_arn')

# Write-only tier
USER_WRITE_ONLY_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.user_write_only_name')
USER_WRITE_ONLY_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.user_write_only_access_key_id')
USER_WRITE_ONLY_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.user_write_only_secret_access_key')
ROLE_WRITE_ONLY_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.role_write_only_name')
ROLE_WRITE_ONLY_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.role_write_only_arn')

# Delete-only tier
USER_DELETE_ONLY_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.user_delete_only_name')
USER_DELETE_ONLY_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.user_delete_only_access_key_id')
USER_DELETE_ONLY_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.user_delete_only_secret_access_key')
ROLE_DELETE_ONLY_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.role_delete_only_name')
ROLE_DELETE_ONLY_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.role_delete_only_arn')

# Read+write+delete tier
USER_RWD_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.user_read_write_delete_name')
USER_RWD_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.user_read_write_delete_access_key_id')
USER_RWD_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.user_read_write_delete_secret_access_key')
ROLE_RWD_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.role_read_write_delete_name')
ROLE_RWD_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.role_read_write_delete_arn')

BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.target_bucket_name')
SEED_OBJECT_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.seed_object_key')

if [ "$USER_READ_ONLY_ACCESS_KEY_ID" == "null" ] || [ -z "$USER_READ_ONLY_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

if [ -z "$BUCKET_NAME" ] || [ "$BUCKET_NAME" == "null" ] || [ -z "$SEED_OBJECT_KEY" ] || [ "$SEED_OBJECT_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not extract bucket name or seed object key from terraform output${NC}"
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
echo "  - Starting user:        $STARTING_USER_NAME (assume-role only)"
echo "  - Read-only user/role:  $USER_READ_ONLY_NAME / $ROLE_READ_ONLY_NAME"
echo "  - Write-only user/role: $USER_WRITE_ONLY_NAME / $ROLE_WRITE_ONLY_NAME"
echo "  - Delete-only user/role:$USER_DELETE_ONLY_NAME / $ROLE_DELETE_ONLY_NAME"
echo "  - RWD user/role:        $USER_RWD_NAME / $ROLE_RWD_NAME"
echo "  - Bucket:               $BUCKET_NAME"
echo "  - Seed object key:      $SEED_OBJECT_KEY"
echo "  - Region:               $AWS_REGION"
echo "  ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
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
use_user_read_only_creds() {
    export AWS_ACCESS_KEY_ID="$USER_READ_ONLY_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$USER_READ_ONLY_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
}
use_user_write_only_creds() {
    export AWS_ACCESS_KEY_ID="$USER_WRITE_ONLY_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$USER_WRITE_ONLY_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
}
use_user_delete_only_creds() {
    export AWS_ACCESS_KEY_ID="$USER_DELETE_ONLY_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$USER_DELETE_ONLY_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
}
use_user_rwd_creds() {
    export AWS_ACCESS_KEY_ID="$USER_RWD_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$USER_RWD_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
}

# Assume a role with the starting user's credentials and export the
# resulting temporary credentials. Args: role_arn, role_label
assume_test_role() {
    local role_arn="$1" role_label="$2"

    use_starting_creds
    export AWS_REGION=$AWS_REGION
    export AWS_DEFAULT_REGION="$AWS_REGION"

    show_cmd "starting-user" "aws sts get-caller-identity --query 'Arn' --output text"
    CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
    echo "Current identity: $CURRENT_USER"

    show_attack_cmd "starting-user" "aws sts assume-role --role-arn $role_arn --role-session-name demo-session --query 'Credentials' --output json"
    CREDENTIALS=$(aws sts assume-role \
        --role-arn "$role_arn" \
        --role-session-name demo-session \
        --query 'Credentials' \
        --output json)

    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Failed to assume $role_label${NC}"
        exit 1
    fi

    export AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS" | jq -r '.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS" | jq -r '.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo "$CREDENTIALS" | jq -r '.SessionToken')
    export AWS_REGION=$AWS_REGION
    export AWS_DEFAULT_REGION="$AWS_REGION"

    show_cmd "$role_label" "aws sts get-caller-identity --query 'Arn' --output text"
    ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
    echo "Current identity: $ROLE_IDENTITY"
    echo -e "${GREEN}✓ Successfully assumed $role_label${NC}\n"
}

# Source demo permissions library for validation restriction
source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# Run the 3-operation test suite (GetObject on the seed object, PutObject of
# a unique test object, DeleteObject of a delete-target object) against
# whichever credentials are currently active, and record the results into
# the matrix arrays.
#
# Args:
#   label            - display label for this principal (e.g. "read-only (user)")
#   expect_get       - "ALLOW" or "DENY"
#   expect_put       - "ALLOW" or "DENY"
#   expect_delete    - "ALLOW" or "DENY"
#   delete_target    - S3 key to attempt to delete. If empty, defaults to the
#                       object this principal just put (self-delete, used by
#                       the read-write-delete tier). Tiers expected to be
#                       denied on delete target the untouched seed object
#                       (safe no-op since the call fails). The delete-only
#                       tier targets a throwaway object staged in advance by
#                       a write-capable principal.
#
# Returns via global PUT_KEY_USED (key that was actually put, for staging
# reuse by the caller if needed).
run_permission_tests() {
    local label="$1" expect_get="$2" expect_put="$3" expect_delete="$4" delete_target="$5"

    local slug
    slug=$(echo "$label" | tr -c 'a-zA-Z0-9' '-' | tr -s '-')
    local put_key="rwd-test/put-test-${slug}.txt"
    local downloaded_file="/tmp/rwd-get-${slug}.txt"
    local upload_file
    upload_file=$(mktemp "/tmp/rwd-upload-${slug}.XXXXXX")
    echo "rwd-test-marker-${slug}-$(date +%s)" > "$upload_file"

    echo -e "${BLUE}--- Testing: $label ---${NC}"

    # GetObject test - always targets the pre-seeded object
    show_attack_cmd "$label" "aws s3 cp s3://$BUCKET_NAME/$SEED_OBJECT_KEY $downloaded_file"
    if aws s3 cp "s3://$BUCKET_NAME/$SEED_OBJECT_KEY" "$downloaded_file" > /dev/null 2>&1; then
        get_actual="ALLOW"
    else
        get_actual="DENY"
    fi
    record_cell "$label" "GetObject" "$expect_get" "$get_actual"

    # PutObject test - always targets a unique key for this principal
    show_attack_cmd "$label" "aws s3 cp $upload_file s3://$BUCKET_NAME/$put_key"
    if aws s3 cp "$upload_file" "s3://$BUCKET_NAME/$put_key" > /dev/null 2>&1; then
        put_actual="ALLOW"
    else
        put_actual="DENY"
    fi
    record_cell "$label" "PutObject" "$expect_put" "$put_actual"

    # DeleteObject test
    local target="$delete_target"
    if [ -z "$target" ]; then
        target="$put_key"
    fi
    show_attack_cmd "$label" "aws s3 rm s3://$BUCKET_NAME/$target"
    if aws s3 rm "s3://$BUCKET_NAME/$target" > /dev/null 2>&1; then
        delete_actual="ALLOW"
    else
        delete_actual="DENY"
    fi
    record_cell "$label" "DeleteObject" "$expect_delete" "$delete_actual"

    MATRIX_LABELS+=("$label")
    MATRIX_GET+=("$get_actual")
    MATRIX_PUT+=("$put_actual")
    MATRIX_DELETE+=("$delete_actual")

    PUT_KEY_USED="$put_key"

    rm -f "$upload_file"
    echo ""
}

# [OBSERVATION] Step 2: Get account ID and confirm the seed object exists
echo -e "${YELLOW}Step 2: Getting account ID and confirming seed object exists${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"

show_cmd "ReadOnly" "aws s3 ls s3://$BUCKET_NAME/$SEED_OBJECT_KEY"
aws s3 ls "s3://$BUCKET_NAME/$SEED_OBJECT_KEY" || {
    echo -e "${RED}Error: Seed object not found at s3://$BUCKET_NAME/$SEED_OBJECT_KEY${NC}"
    echo "Run terraform apply to ensure the scenario infrastructure is fully deployed."
    exit 1
}
echo -e "${GREEN}✓ Seed object present${NC}\n"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}TIER 1: READ-ONLY${NC}"
echo -e "${BLUE}(GetObject + ListBucket only - Put/Delete must be denied)${NC}"
echo -e "${BLUE}========================================${NC}\n"

# [EXPLOIT] Step 3: Test read-only user
echo -e "${YELLOW}Step 3: Testing $USER_READ_ONLY_NAME${NC}"
use_user_read_only_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"
run_permission_tests "read-only (user)" "ALLOW" "DENY" "DENY" "$SEED_OBJECT_KEY"

# [EXPLOIT] Step 4: Test read-only role
echo -e "${YELLOW}Step 4: Testing $ROLE_READ_ONLY_NAME${NC}"
assume_test_role "$ROLE_READ_ONLY_ARN" "read-only-role"
run_permission_tests "read-only (role)" "ALLOW" "DENY" "DENY" "$SEED_OBJECT_KEY"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}TIER 2: WRITE-ONLY${NC}"
echo -e "${BLUE}(PutObject only - Get/Delete must be denied)${NC}"
echo -e "${BLUE}========================================${NC}\n"

# [EXPLOIT] Step 5: Test write-only user
echo -e "${YELLOW}Step 5: Testing $USER_WRITE_ONLY_NAME${NC}"
use_user_write_only_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"
run_permission_tests "write-only (user)" "DENY" "ALLOW" "DENY" "$SEED_OBJECT_KEY"

# Stage a throwaway object for the delete-only USER test using this
# principal's PutObject access (write-only has no Get/Delete, so it cannot
# verify or clean this up itself - that happens in the delete-only test and
# in cleanup_attack.sh).
DELETE_ONLY_USER_STAGE_KEY="rwd-test/delete-target-delete-only-user.txt"
STAGE_FILE=$(mktemp /tmp/rwd-stage.XXXXXX)
echo "rwd-test-delete-target-for-delete-only-user" > "$STAGE_FILE"
show_attack_cmd "write-only (user)" "aws s3 cp $STAGE_FILE s3://$BUCKET_NAME/$DELETE_ONLY_USER_STAGE_KEY"
aws s3 cp "$STAGE_FILE" "s3://$BUCKET_NAME/$DELETE_ONLY_USER_STAGE_KEY" > /dev/null 2>&1
rm -f "$STAGE_FILE"
echo -e "${GREEN}✓ Staged delete-target object for the delete-only user test${NC}\n"

# [EXPLOIT] Step 6: Test write-only role
echo -e "${YELLOW}Step 6: Testing $ROLE_WRITE_ONLY_NAME${NC}"
assume_test_role "$ROLE_WRITE_ONLY_ARN" "write-only-role"
run_permission_tests "write-only (role)" "DENY" "ALLOW" "DENY" "$SEED_OBJECT_KEY"

# Stage a throwaway object for the delete-only ROLE test using this
# principal's PutObject access.
DELETE_ONLY_ROLE_STAGE_KEY="rwd-test/delete-target-delete-only-role.txt"
STAGE_FILE=$(mktemp /tmp/rwd-stage.XXXXXX)
echo "rwd-test-delete-target-for-delete-only-role" > "$STAGE_FILE"
show_attack_cmd "write-only (role)" "aws s3 cp $STAGE_FILE s3://$BUCKET_NAME/$DELETE_ONLY_ROLE_STAGE_KEY"
aws s3 cp "$STAGE_FILE" "s3://$BUCKET_NAME/$DELETE_ONLY_ROLE_STAGE_KEY" > /dev/null 2>&1
rm -f "$STAGE_FILE"
echo -e "${GREEN}✓ Staged delete-target object for the delete-only role test${NC}\n"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}TIER 3: DELETE-ONLY${NC}"
echo -e "${BLUE}(DeleteObject only - Get/Put must be denied)${NC}"
echo -e "${BLUE}========================================${NC}\n"

# [EXPLOIT] Step 7: Test delete-only user (deletes the object staged above)
echo -e "${YELLOW}Step 7: Testing $USER_DELETE_ONLY_NAME${NC}"
use_user_delete_only_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"
run_permission_tests "delete-only (user)" "DENY" "DENY" "ALLOW" "$DELETE_ONLY_USER_STAGE_KEY"

# [EXPLOIT] Step 8: Test delete-only role (deletes the object staged above)
echo -e "${YELLOW}Step 8: Testing $ROLE_DELETE_ONLY_NAME${NC}"
assume_test_role "$ROLE_DELETE_ONLY_ARN" "delete-only-role"
run_permission_tests "delete-only (role)" "DENY" "DENY" "ALLOW" "$DELETE_ONLY_ROLE_STAGE_KEY"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}TIER 4: READ + WRITE + DELETE${NC}"
echo -e "${BLUE}(Full CRUD - all three must succeed)${NC}"
echo -e "${BLUE}========================================${NC}\n"

# [EXPLOIT] Step 9: Test read-write-delete user (deletes the object it just put)
echo -e "${YELLOW}Step 9: Testing $USER_RWD_NAME${NC}"
use_user_rwd_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"
run_permission_tests "read-write-delete (user)" "ALLOW" "ALLOW" "ALLOW" ""

# [EXPLOIT] Step 10: Test read-write-delete role (deletes the object it just put)
echo -e "${YELLOW}Step 10: Testing $ROLE_RWD_NAME${NC}"
assume_test_role "$ROLE_RWD_ARN" "read-write-delete-role"
run_permission_tests "read-write-delete (role)" "ALLOW" "ALLOW" "ALLOW" ""

# Restore helpful permissions before printing summary
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "${GREEN}========================================${NC}"
if [ "$MISMATCH_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✅ DEMONSTRATION SUCCESSFUL - ALL 8 PRINCIPALS MATCH EXPECTED TIER${NC}"
else
    echo -e "${RED}⚠ DEMONSTRATION FOUND $MISMATCH_COUNT MISMATCH(ES)${NC}"
fi
echo -e "${GREEN}========================================${NC}\n"

echo -e "${YELLOW}Permission Edge Matrix (measured actual outcome):${NC}"
printf "%-32s %-12s %-12s %-12s\n" "Principal" "GetObject" "PutObject" "DeleteObject"
printf "%-32s %-12s %-12s %-12s\n" "--------------------------------" "------------" "------------" "------------"
for i in "${!MATRIX_LABELS[@]}"; do
    label="${MATRIX_LABELS[$i]}"
    g="${MATRIX_GET[$i]}"
    p="${MATRIX_PUT[$i]}"
    d="${MATRIX_DELETE[$i]}"
    printf "%-32s %-12s %-12s %-12s\n" "$label" "$g" "$p" "$d"
done
echo ""

echo -e "${YELLOW}Expected Matrix (ground truth for detection tooling):${NC}"
printf "%-32s %-12s %-12s %-12s\n" "Principal" "GetObject" "PutObject" "DeleteObject"
printf "%-32s %-12s %-12s %-12s\n" "--------------------------------" "------------" "------------" "------------"
printf "%-32s %-12s %-12s %-12s\n" "read-only (user)"           "ALLOW" "DENY"  "DENY"
printf "%-32s %-12s %-12s %-12s\n" "read-only (role)"           "ALLOW" "DENY"  "DENY"
printf "%-32s %-12s %-12s %-12s\n" "write-only (user)"          "DENY"  "ALLOW" "DENY"
printf "%-32s %-12s %-12s %-12s\n" "write-only (role)"          "DENY"  "ALLOW" "DENY"
printf "%-32s %-12s %-12s %-12s\n" "delete-only (user)"         "DENY"  "DENY"  "ALLOW"
printf "%-32s %-12s %-12s %-12s\n" "delete-only (role)"         "DENY"  "DENY"  "ALLOW"
printf "%-32s %-12s %-12s %-12s\n" "read-write-delete (user)"   "ALLOW" "ALLOW" "ALLOW"
printf "%-32s %-12s %-12s %-12s\n" "read-write-delete (role)"   "ALLOW" "ALLOW" "ALLOW"
echo ""

echo -e "${YELLOW}Reverse Blast Radius / Tool Testing Objective:${NC}"
echo "A graph/CSPM tool inspecting s3://$BUCKET_NAME must generate"
echo "can_read/can_write/can_delete edges that exactly match the Expected"
echo "Matrix above for all 8 principals - no false positive edges (e.g. a"
echo "can_write edge on a read-only principal) and no false negative edges"
echo "(e.g. a missing can_delete edge on the read-write-delete principal)."
echo ""

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
    echo ""
fi

echo -e "${YELLOW}Attack Artifacts:${NC}"
echo "  - s3://$BUCKET_NAME/rwd-test/ (put-test objects and staged delete-target objects)"
echo "  - /tmp/rwd-get-*.txt (downloaded objects)"
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

if [ "$MISMATCH_COUNT" -ne 0 ]; then
    exit 1
fi
