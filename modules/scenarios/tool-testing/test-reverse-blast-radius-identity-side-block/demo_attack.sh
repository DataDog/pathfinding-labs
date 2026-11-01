#!/bin/bash

# Demo script for test-reverse-blast-radius-identity-side-block
# This is a detection-validation demo (not an attack). It proves the ground truth
# that a reverse blast radius answer for a bucket must EXCLUDE principals whose
# bucket-read permission is nullified on the identity side: by an explicit Deny or
# by a permissions boundary that excludes S3. Only plain-reader actually reads.

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

# Track commands for summary
ATTACK_COMMANDS=()

show_cmd() {
    local identity="$1"; shift
    echo -e "${DIM}[${identity}] \$ $*${NC}"
}

show_attack_cmd() {
    local identity="$1"; shift
    echo -e "\n${CYAN}[${identity}] \$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration (user names from main.tf)
PLAIN_READER_NAME="pl-prod-rbr-isb-plain-reader"
EXPLICIT_DENY_READER_NAME="pl-prod-rbr-isb-explicit-deny-reader"
BOUNDARY_EXCLUDES_S3_NAME="pl-prod-rbr-isb-boundary-excludes-s3"

# Number of observed results that differ from the expected ground truth
MISMATCHES=0

# Matrix rows: "principal|can_read"
MATRIX_ROWS=()

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Reverse Blast Radius: Identity-Side Access Blocks Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}This scenario tests identity-side access blocks:${NC}"
echo "- plain-reader          Allow s3 read, nothing blocking     -> CAN read (control)"
echo "- explicit-deny-reader  Allow s3 read + inline Deny s3:*     -> CANNOT (deny wins)"
echo "- boundary-excludes-s3  Allow s3 read + EC2-only boundary    -> CANNOT (boundary caps)"
echo ""

# Check required tools
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

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_reverse_blast_radius_identity_side_block.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

PLAIN_READER_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.plain_reader_access_key_id')
PLAIN_READER_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.plain_reader_secret_access_key')
EXPLICIT_DENY_READER_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.explicit_deny_reader_access_key_id')
EXPLICIT_DENY_READER_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.explicit_deny_reader_secret_access_key')
BOUNDARY_EXCLUDES_S3_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.boundary_excludes_s3_access_key_id')
BOUNDARY_EXCLUDES_S3_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.boundary_excludes_s3_secret_access_key')
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_name')

for REQUIRED_VALUE in "$PLAIN_READER_ACCESS_KEY_ID" "$EXPLICIT_DENY_READER_ACCESS_KEY_ID" \
    "$BOUNDARY_EXCLUDES_S3_ACCESS_KEY_ID" "$BUCKET_NAME"; do
    if [ "$REQUIRED_VALUE" == "null" ] || [ -z "$REQUIRED_VALUE" ]; then
        echo -e "${RED}Error: Could not extract all required values from terraform output${NC}"
        exit 1
    fi
done

AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")
if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access keys for 3 candidate users:"
echo "  - plain-reader:         (${PLAIN_READER_ACCESS_KEY_ID:0:10}...)"
echo "  - explicit-deny-reader: (${EXPLICIT_DENY_READER_ACCESS_KEY_ID:0:10}...)"
echo "  - boundary-excludes-s3: (${BOUNDARY_EXCLUDES_S3_ACCESS_KEY_ID:0:10}...)"
echo "  - target bucket: $BUCKET_NAME"
echo "  - region:        $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Source demo permissions library (no-op: scenario has no helpful permissions)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# Set caller credentials for one of the candidate users
set_caller_creds() {
    export AWS_ACCESS_KEY_ID="$1"
    export AWS_SECRET_ACCESS_KEY="$2"
    unset AWS_SESSION_TOKEN
    export AWS_REGION=$AWS_REGION
}

verify_identity() {
    local expected_name="$1"
    show_cmd "$expected_name" "aws sts get-caller-identity --query 'Arn' --output text --region $AWS_REGION"
    local arn
    arn=$(aws sts get-caller-identity --query 'Arn' --output text --region "$AWS_REGION")
    echo "Current identity: $arn"
    if [[ ! "$arn" == *"$expected_name"* ]]; then
        echo -e "${RED}Error: Not running as $expected_name${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Verified identity${NC}"
}

# Classify a command's result as allowed/denied/error and compare to expectation.
check_result() {
    local expectation="$1"; shift
    local description="$1"; shift
    local output rc
    output=$("$@" 2>&1); rc=$?

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

# Test one candidate user: s3 ls (list) + s3api get-object (read).
#   $1 label, $2 username, $3 access_key, $4 secret_key, $5 expectation (allow|deny)
test_user() {
    local label="$1" uname="$2" ak="$3" sk="$4" expectation="$5"
    echo -e "${YELLOW}Testing $label${NC}"

    set_caller_creds "$ak" "$sk"
    verify_identity "$uname"

    show_attack_cmd "$label" "aws s3 ls s3://$BUCKET_NAME/ --region $AWS_REGION"
    check_result "$expectation" "$label list bucket" \
        aws s3 ls "s3://$BUCKET_NAME/" --region "$AWS_REGION"

    show_attack_cmd "$label" "aws s3api get-object --region $AWS_REGION --bucket $BUCKET_NAME --key sensitive-data.txt /dev/null"
    check_result "$expectation" "$label get-object" \
        aws s3api get-object --region "$AWS_REGION" --bucket "$BUCKET_NAME" --key "sensitive-data.txt" /dev/null
    MATRIX_ROWS+=("$label|$LAST_RESULT")
    echo ""
}

# =============================================================================
# Run the three candidate users
# =============================================================================
test_user "plain-reader"         "$PLAIN_READER_NAME"         "$PLAIN_READER_ACCESS_KEY_ID"         "$PLAIN_READER_SECRET_ACCESS_KEY"         allow
test_user "explicit-deny-reader" "$EXPLICIT_DENY_READER_NAME" "$EXPLICIT_DENY_READER_ACCESS_KEY_ID" "$EXPLICIT_DENY_READER_SECRET_ACCESS_KEY" deny
test_user "boundary-excludes-s3" "$BOUNDARY_EXCLUDES_S3_NAME" "$BOUNDARY_EXCLUDES_S3_ACCESS_KEY_ID" "$BOUNDARY_EXCLUDES_S3_SECRET_ACCESS_KEY" deny

# Restore helpful permissions before printing the summary (no-op)
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# =============================================================================
# Observed matrix
# =============================================================================
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Observed Read Matrix for bucket: $BUCKET_NAME${NC}"
echo -e "${GREEN}========================================${NC}"
printf "  %-26s %-10s\n" "PRINCIPAL" "CAN_READ"
for ROW in "${MATRIX_ROWS[@]}"; do
    IFS='|' read -r ROW_PRINCIPAL ROW_READ <<< "$ROW"
    printf "  %-26s %-10s\n" "$ROW_PRINCIPAL" "$ROW_READ"
done
echo ""

echo -e "${YELLOW}Expected results (compare your graph tool against these):${NC}"
echo "  can_read bucket = plain-reader"
echo "  cannot          = explicit-deny-reader, boundary-excludes-s3"
echo ""
echo -e "${RED}⚠ explicit-deny-reader and boundary-excludes-s3 both have an S3-read Allow.${NC}"
echo "  explicit-deny-reader is nullified by an inline Deny on s3:* (deny always wins)."
echo "  boundary-excludes-s3 is capped by an EC2-only permissions boundary."
echo "  A tool that only reads the Allow statement will wrongly include them in can_read."
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
echo "  - None (this demo makes no lasting changes)"
echo ""

if [ "$MISMATCHES" -ne 0 ]; then
    echo -e "${RED}✗ $MISMATCHES observed result(s) differed from the expected ground truth${NC}"
    touch "$(dirname "$0")/.demo_active"
    exit 1
fi

echo -e "${GREEN}✅ All observed results match the expected ground truth${NC}"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
