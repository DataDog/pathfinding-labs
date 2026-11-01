#!/bin/bash

# Demo script for test-reverse-blast-radius-implicit-admin-access
# This is a detection-validation demo (not an attack). It proves the ground truth
# that a security tool's reverse blast radius query ("who can read/write this
# bucket?") must reproduce, including administrators whose access to the bucket is
# purely implicit (AdministratorAccess / Action:* with no S3-specific statement).

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
READER_USER_NAME="pl-prod-rbr-ia-reader-user"
WRITER_USER_NAME="pl-prod-rbr-ia-writer-user"
ADMIN_USER_NAME="pl-prod-rbr-ia-admin-user"
NO_ACCESS_USER_NAME="pl-prod-rbr-ia-no-access-user"
ADMIN_ROLE_NAME="pl-prod-rbr-ia-admin-role"

# Objects written by the demo (all under one prefix so cleanup can remove them)
DEMO_PREFIX="rbr-ia-demo"
WRITER_KEY="$DEMO_PREFIX/writer-probe.txt"
ADMIN_KEY="$DEMO_PREFIX/admin-probe.txt"
NO_ACCESS_KEY="$DEMO_PREFIX/no-access-probe.txt"

# Fixed local body file (cleanup_attack.sh also removes it)
PROBE_BODY_FILE="/tmp/rbr-ia-probe-body.txt"

# Number of observed results that differ from the expected ground truth
MISMATCHES=0

# Matrix rows: "principal|can_read|can_write"
MATRIX_ROWS=()

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Reverse Blast Radius: Implicit Admin Access Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}This scenario tests reverse blast radius detection:${NC}"
echo "- Explicit access: reader-user (read), writer-user (write)"
echo "- Implicit access: admin-user and admin-role (no S3 statements, only admin)"
echo "- Negative control: no-access-user"
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

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../..  # Navigate to root of terraform project

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_reverse_blast_radius_implicit_admin_access.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

READER_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.reader_user_access_key_id')
READER_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.reader_user_secret_access_key')
WRITER_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.writer_user_access_key_id')
WRITER_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.writer_user_secret_access_key')
ADMIN_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.admin_user_access_key_id')
ADMIN_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.admin_user_secret_access_key')
NO_ACCESS_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.no_access_user_access_key_id')
NO_ACCESS_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.no_access_user_secret_access_key')
ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_arn')
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_name')
BUCKET_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_arn')

for REQUIRED_VALUE in "$READER_ACCESS_KEY_ID" "$WRITER_ACCESS_KEY_ID" "$ADMIN_ACCESS_KEY_ID" "$NO_ACCESS_ACCESS_KEY_ID" "$ADMIN_ROLE_ARN" "$BUCKET_NAME" "$BUCKET_ARN"; do
    if [ "$REQUIRED_VALUE" == "null" ] || [ -z "$REQUIRED_VALUE" ]; then
        echo -e "${RED}Error: Could not extract all required values from terraform output${NC}"
        exit 1
    fi
done

# Cleanup-admin credentials are used ONLY for iam:SimulatePrincipalPolicy on the
# admin role (the role cannot be assumed here: its trust policy only allows EC2)
CLEANUP_ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
CLEANUP_ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

if [ -z "$CLEANUP_ADMIN_ACCESS_KEY" ] || [ "$CLEANUP_ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    exit 1
fi

AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

# Derive account ID from the admin role ARN (arn:aws:iam::ACCOUNT:role/NAME)
ACCOUNT_ID=$(echo "$ADMIN_ROLE_ARN" | cut -d':' -f5)

echo "Retrieved access keys for:"
echo "  - Reader:    $READER_USER_NAME (${READER_ACCESS_KEY_ID:0:10}...)"
echo "  - Writer:    $WRITER_USER_NAME (${WRITER_ACCESS_KEY_ID:0:10}...)"
echo "  - Admin:     $ADMIN_USER_NAME (${ADMIN_ACCESS_KEY_ID:0:10}...)"
echo "  - No access: $NO_ACCESS_USER_NAME (${NO_ACCESS_ACCESS_KEY_ID:0:10}...)"
echo "  - Admin role: $ADMIN_ROLE_ARN"
echo "  - Target bucket: $BUCKET_NAME"
echo "  - Account ID: $ACCOUNT_ID"
echo "  - Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Credential switching helpers
use_reader_creds() {
    export AWS_ACCESS_KEY_ID="$READER_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$READER_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
    export AWS_REGION=$AWS_REGION
}
use_writer_creds() {
    export AWS_ACCESS_KEY_ID="$WRITER_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$WRITER_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
    export AWS_REGION=$AWS_REGION
}
use_admin_user_creds() {
    export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
    export AWS_REGION=$AWS_REGION
}
use_no_access_creds() {
    export AWS_ACCESS_KEY_ID="$NO_ACCESS_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$NO_ACCESS_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
    export AWS_REGION=$AWS_REGION
}
use_cleanup_admin_creds() {
    export AWS_ACCESS_KEY_ID="$CLEANUP_ADMIN_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$CLEANUP_ADMIN_SECRET_KEY"
    unset AWS_SESSION_TOKEN
    export AWS_REGION=$AWS_REGION
}

# Source demo permissions library for validation restriction
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# Remove the local probe body file on every exit path (normal, error, Ctrl+C).
# This wraps the demo_permissions EXIT handler (only installed when restriction is on)
# so both the temp file removal and the permission restore still run.
rbr_exit_handler() {
    rm -f "$PROBE_BODY_FILE"
    if [ "${PL_RESTRICT_PERMISSIONS:-0}" == "1" ] && declare -F _dp_exit_handler > /dev/null; then
        _dp_exit_handler
    fi
}
if [ "${PL_RESTRICT_PERMISSIONS:-0}" != "1" ]; then
    # Without the library's interrupt trap, turn INT/TERM into an exit so EXIT fires
    trap 'exit 130' INT TERM
fi
trap 'rbr_exit_handler' EXIT

# Small body file uploaded by put-object probes
echo "reverse blast radius probe object" > "$PROBE_BODY_FILE"

# Run a command expecting success or an access denial.
#   $1 = expectation ("allow" or "deny")
#   $2 = human description
#   remaining = command to run
# Sets LAST_RESULT to "allowed", "denied" or "error". A deny expectation only counts
# as met if the error is an authorization failure (not, say, a typo or missing bucket).
check_access() {
    local expectation="$1"; shift
    local description="$1"; shift
    local output
    output=$("$@" 2>&1)
    local rc=$?

    if [ $rc -eq 0 ]; then
        LAST_RESULT="allowed"
    elif echo "$output" | grep -qiE "AccessDenied|Access Denied|not authorized|Forbidden|403"; then
        LAST_RESULT="denied"
    else
        LAST_RESULT="error"
        echo -e "${RED}  Unexpected non-authorization error: $output${NC}"
    fi

    if { [ "$expectation" == "allow" ] && [ "$LAST_RESULT" == "allowed" ]; } || \
       { [ "$expectation" == "deny" ] && [ "$LAST_RESULT" == "denied" ]; }; then
        if [ "$LAST_RESULT" == "allowed" ]; then
            echo -e "  ${GREEN}✓ $description: ALLOWED (expected)${NC}"
        else
            echo -e "  ${GREEN}✓ $description: ACCESS DENIED (expected)${NC}"
        fi
    else
        echo -e "  ${RED}✗ $description: observed ${LAST_RESULT}, expected ${expectation}${NC}"
        MISMATCHES=$((MISMATCHES + 1))
    fi
}

# Verify the identity of the currently configured credentials contains the given name
verify_identity() {
    local expected_name="$1"
    show_cmd "$expected_name" "aws sts get-caller-identity --query 'Arn' --output text"
    local arn
    arn=$(aws sts get-caller-identity --query 'Arn' --output text)
    echo "Current identity: $arn"
    if [[ ! "$arn" == *"$expected_name"* ]]; then
        echo -e "${RED}Error: Not running as $expected_name${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Verified identity${NC}"
}

# =============================================================================
# Step 2: reader-user identity
# =============================================================================
echo -e "${YELLOW}Step 2: reader-user (explicit s3:GetObject / s3:ListBucket)${NC}"
use_reader_creds
verify_identity "$READER_USER_NAME"
echo ""

# =============================================================================
# Step 3: writer-user writes first so a probe object exists for the read tests
# =============================================================================
echo -e "${YELLOW}Step 3: writer-user (explicit s3:PutObject only)${NC}"
use_writer_creds
verify_identity "$WRITER_USER_NAME"

echo "Writing probe object (expected to succeed)..."
show_attack_cmd "Writer" "aws s3api put-object --region $AWS_REGION --bucket $BUCKET_NAME --key $WRITER_KEY --body $PROBE_BODY_FILE"
check_access allow "writer-user put-object" \
    aws s3api put-object --region "$AWS_REGION" --bucket "$BUCKET_NAME" --key "$WRITER_KEY" --body "$PROBE_BODY_FILE"
WRITER_CAN_WRITE=$LAST_RESULT

echo "Reading the object back (expected to be denied)..."
show_attack_cmd "Writer" "aws s3api get-object --region $AWS_REGION --bucket $BUCKET_NAME --key $WRITER_KEY /dev/null"
check_access deny "writer-user get-object" \
    aws s3api get-object --region "$AWS_REGION" --bucket "$BUCKET_NAME" --key "$WRITER_KEY" /dev/null
WRITER_CAN_READ=$LAST_RESULT
MATRIX_ROWS+=("writer-user|$WRITER_CAN_READ|$WRITER_CAN_WRITE")
echo ""

# =============================================================================
# Step 4: reader-user tests
# =============================================================================
echo -e "${YELLOW}Step 4: Testing reader-user access to the bucket${NC}"
use_reader_creds

show_attack_cmd "Reader" "aws s3 ls s3://$BUCKET_NAME/$DEMO_PREFIX/ --region $AWS_REGION"
check_access allow "reader-user list bucket" \
    aws s3 ls "s3://$BUCKET_NAME/$DEMO_PREFIX/" --region "$AWS_REGION"

show_attack_cmd "Reader" "aws s3api get-object --region $AWS_REGION --bucket $BUCKET_NAME --key $WRITER_KEY /dev/null"
check_access allow "reader-user get-object" \
    aws s3api get-object --region "$AWS_REGION" --bucket "$BUCKET_NAME" --key "$WRITER_KEY" /dev/null
READER_CAN_READ=$LAST_RESULT

show_attack_cmd "Reader" "aws s3api put-object --region $AWS_REGION --bucket $BUCKET_NAME --key $DEMO_PREFIX/reader-probe.txt --body $PROBE_BODY_FILE"
check_access deny "reader-user put-object" \
    aws s3api put-object --region "$AWS_REGION" --bucket "$BUCKET_NAME" --key "$DEMO_PREFIX/reader-probe.txt" --body "$PROBE_BODY_FILE"
READER_CAN_WRITE=$LAST_RESULT
MATRIX_ROWS+=("reader-user|$READER_CAN_READ|$READER_CAN_WRITE")
echo ""

# =============================================================================
# Step 5: admin-user (implicit access through AdministratorAccess)
# =============================================================================
echo -e "${YELLOW}Step 5: admin-user (AdministratorAccess only, NO S3-specific statement)${NC}"
use_admin_user_creds
verify_identity "$ADMIN_USER_NAME"

show_attack_cmd "AdminUser" "aws s3api get-object --region $AWS_REGION --bucket $BUCKET_NAME --key $WRITER_KEY /dev/null"
check_access allow "admin-user get-object" \
    aws s3api get-object --region "$AWS_REGION" --bucket "$BUCKET_NAME" --key "$WRITER_KEY" /dev/null
ADMIN_CAN_READ=$LAST_RESULT

show_attack_cmd "AdminUser" "aws s3api put-object --region $AWS_REGION --bucket $BUCKET_NAME --key $ADMIN_KEY --body $PROBE_BODY_FILE"
check_access allow "admin-user put-object" \
    aws s3api put-object --region "$AWS_REGION" --bucket "$BUCKET_NAME" --key "$ADMIN_KEY" --body "$PROBE_BODY_FILE"
ADMIN_CAN_WRITE=$LAST_RESULT
MATRIX_ROWS+=("admin-user|$ADMIN_CAN_READ|$ADMIN_CAN_WRITE")
echo ""

# =============================================================================
# Step 6: no-access-user (negative control)
# =============================================================================
echo -e "${YELLOW}Step 6: no-access-user (negative control, no S3 permissions)${NC}"
use_no_access_creds
verify_identity "$NO_ACCESS_USER_NAME"

show_attack_cmd "NoAccess" "aws s3 ls s3://$BUCKET_NAME/$DEMO_PREFIX/ --region $AWS_REGION"
check_access deny "no-access-user list bucket" \
    aws s3 ls "s3://$BUCKET_NAME/$DEMO_PREFIX/" --region "$AWS_REGION"

show_attack_cmd "NoAccess" "aws s3api get-object --region $AWS_REGION --bucket $BUCKET_NAME --key $WRITER_KEY /dev/null"
check_access deny "no-access-user get-object" \
    aws s3api get-object --region "$AWS_REGION" --bucket "$BUCKET_NAME" --key "$WRITER_KEY" /dev/null
NO_ACCESS_CAN_READ=$LAST_RESULT

show_attack_cmd "NoAccess" "aws s3api put-object --region $AWS_REGION --bucket $BUCKET_NAME --key $NO_ACCESS_KEY --body $PROBE_BODY_FILE"
check_access deny "no-access-user put-object" \
    aws s3api put-object --region "$AWS_REGION" --bucket "$BUCKET_NAME" --key "$NO_ACCESS_KEY" --body "$PROBE_BODY_FILE"
NO_ACCESS_CAN_WRITE=$LAST_RESULT
MATRIX_ROWS+=("no-access-user|$NO_ACCESS_CAN_READ|$NO_ACCESS_CAN_WRITE")
echo ""

# =============================================================================
# Step 7: admin-role (cannot be assumed here; evaluate effective access instead)
# =============================================================================
echo -e "${YELLOW}Step 7: admin-role (inline Action:* Resource:*, trust policy only allows ec2.amazonaws.com)${NC}"
echo "The role cannot be assumed by these users, so its effective access is evaluated"
echo "with iam:SimulatePrincipalPolicy using the cleanup admin credentials."
use_cleanup_admin_creds

simulate_role_action() {
    local action="$1"
    local resource="$2"
    show_attack_cmd "CleanupAdmin" "aws iam simulate-principal-policy --policy-source-arn $ADMIN_ROLE_ARN --action-names $action --resource-arns $resource --query 'EvaluationResults[0].EvalDecision' --output text"
    SIM_DECISION=$(aws iam simulate-principal-policy \
        --policy-source-arn "$ADMIN_ROLE_ARN" \
        --action-names "$action" \
        --resource-arns "$resource" \
        --query 'EvaluationResults[0].EvalDecision' \
        --output text 2>&1)
    if [ "$SIM_DECISION" == "allowed" ]; then
        echo -e "  ${GREEN}✓ admin-role $action on $resource: allowed (expected)${NC}"
    else
        echo -e "  ${RED}✗ admin-role $action on $resource: observed '$SIM_DECISION', expected allowed${NC}"
        MISMATCHES=$((MISMATCHES + 1))
    fi
}

simulate_role_action "s3:GetObject" "$BUCKET_ARN/$WRITER_KEY"
ROLE_CAN_READ=$([ "$SIM_DECISION" == "allowed" ] && echo "allowed" || echo "denied")
simulate_role_action "s3:PutObject" "$BUCKET_ARN/$ADMIN_KEY"
ROLE_CAN_WRITE=$([ "$SIM_DECISION" == "allowed" ] && echo "allowed" || echo "denied")
MATRIX_ROWS+=("admin-role (simulated)|$ROLE_CAN_READ|$ROLE_CAN_WRITE")
echo ""

rm -f "$PROBE_BODY_FILE"

# Restore helpful permissions before printing the summary
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# =============================================================================
# Observed matrix
# =============================================================================
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Observed Access Matrix for bucket: $BUCKET_NAME${NC}"
echo -e "${GREEN}========================================${NC}"
printf "  %-26s %-10s %-10s\n" "PRINCIPAL" "READ" "WRITE"
for ROW in "${MATRIX_ROWS[@]}"; do
    IFS='|' read -r ROW_PRINCIPAL ROW_READ ROW_WRITE <<< "$ROW"
    printf "  %-26s %-10s %-10s\n" "$ROW_PRINCIPAL" "$ROW_READ" "$ROW_WRITE"
done
echo ""

echo -e "${YELLOW}Expected results (compare your graph tool against these):${NC}"
echo "  can_read  bucket = reader-user, admin-user, admin-role"
echo "  can_write bucket = writer-user, admin-user, admin-role"
echo "  neither          = no-access-user"
echo ""
echo -e "${RED}⚠ admin-user and admin-role have NO S3 edge in IAM policy terms.${NC}"
echo "  Their access comes only from AdministratorAccess / Action:* on Resource:*."
echo "  A tool that only follows explicit resource edges (statements naming the bucket)"
echo "  will wrongly omit them from both can_read and can_write."
echo ""

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Commands Executed:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
    echo ""
fi

echo -e "${YELLOW}MITRE ATT&CK Mapping:${NC}"
echo "  - T1530: Data from Cloud Storage Object"
echo ""
echo -e "${YELLOW}Artifacts:${NC}"
echo "  - Probe objects under s3://$BUCKET_NAME/$DEMO_PREFIX/"
echo "  - To remove them: ./cleanup_attack.sh"
echo ""

if [ "$MISMATCHES" -ne 0 ]; then
    echo -e "${RED}✗ $MISMATCHES observed result(s) differed from the expected ground truth${NC}"
    # Still mark active so cleanup of the uploaded probe objects is offered
    touch "$(dirname "$0")/.demo_active"
    exit 1
fi

echo -e "${GREEN}✅ All observed results match the expected ground truth${NC}"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
