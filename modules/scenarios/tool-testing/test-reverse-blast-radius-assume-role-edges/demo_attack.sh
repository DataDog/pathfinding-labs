#!/bin/bash

# Demo script for test-reverse-blast-radius-assume-role-edges
# This is a detection-validation demo (not an attack). It proves the ground truth
# that a security tool's "who can reach this bucket via one assume-role hop" answer
# must draw the can-assume edge only when BOTH the caller's identity policy AND the
# role trust policy allow the assumption. A role trusting the account root defers
# the decision entirely to identity policies.
#
# Five candidate users differ only in which half of the assume-role requirement
# they satisfy. Only are-both (identity + explicit trust) and are-root-with-identity
# (identity + root trust) can assume a target role and read the bucket.

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
ARE_BOTH_NAME="pl-prod-rbr-are-both"
ARE_IDENTITY_ONLY_NAME="pl-prod-rbr-are-identity-only"
ARE_TRUST_ONLY_NAME="pl-prod-rbr-are-trust-only"
ARE_ROOT_WITH_IDENTITY_NAME="pl-prod-rbr-are-root-with-identity"
ARE_ROOT_NO_IDENTITY_NAME="pl-prod-rbr-are-root-no-identity"

# Number of observed results that differ from the expected ground truth
MISMATCHES=0

# Matrix rows: "principal|can_assume|can_read"
MATRIX_ROWS=()

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Reverse Blast Radius: Assume-Role Edge Correctness Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}This scenario tests assume-role edge correctness:${NC}"
echo "- are-both               identity AssumeRole + trust names it      -> CAN assume + read"
echo "- are-root-with-identity identity AssumeRole + root trust defers    -> CAN assume + read"
echo "- are-identity-only      identity AssumeRole, trust does NOT name it -> CANNOT"
echo "- are-trust-only         trust names it, NO identity AssumeRole      -> CANNOT"
echo "- are-root-no-identity   root trust, identity silent on AssumeRole   -> CANNOT"
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

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_reverse_blast_radius_assume_role_edges.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

ARE_BOTH_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.are_both_access_key_id')
ARE_BOTH_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.are_both_secret_access_key')
ARE_IDENTITY_ONLY_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.are_identity_only_access_key_id')
ARE_IDENTITY_ONLY_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.are_identity_only_secret_access_key')
ARE_TRUST_ONLY_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.are_trust_only_access_key_id')
ARE_TRUST_ONLY_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.are_trust_only_secret_access_key')
ARE_ROOT_WITH_IDENTITY_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.are_root_with_identity_access_key_id')
ARE_ROOT_WITH_IDENTITY_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.are_root_with_identity_secret_access_key')
ARE_ROOT_NO_IDENTITY_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.are_root_no_identity_access_key_id')
ARE_ROOT_NO_IDENTITY_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.are_root_no_identity_secret_access_key')
TARGET_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.target_role_arn')
TARGET_ROLE_ROOT_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.target_role_root_arn')
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_name')

for REQUIRED_VALUE in "$ARE_BOTH_ACCESS_KEY_ID" "$ARE_IDENTITY_ONLY_ACCESS_KEY_ID" \
    "$ARE_TRUST_ONLY_ACCESS_KEY_ID" "$ARE_ROOT_WITH_IDENTITY_ACCESS_KEY_ID" \
    "$ARE_ROOT_NO_IDENTITY_ACCESS_KEY_ID" "$TARGET_ROLE_ARN" "$TARGET_ROLE_ROOT_ARN" "$BUCKET_NAME"; do
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

echo "Retrieved access keys for 5 candidate users:"
echo "  - are-both:               (${ARE_BOTH_ACCESS_KEY_ID:0:10}...)"
echo "  - are-identity-only:      (${ARE_IDENTITY_ONLY_ACCESS_KEY_ID:0:10}...)"
echo "  - are-trust-only:         (${ARE_TRUST_ONLY_ACCESS_KEY_ID:0:10}...)"
echo "  - are-root-with-identity: (${ARE_ROOT_WITH_IDENTITY_ACCESS_KEY_ID:0:10}...)"
echo "  - are-root-no-identity:   (${ARE_ROOT_NO_IDENTITY_ACCESS_KEY_ID:0:10}...)"
echo "  - target role:      $TARGET_ROLE_ARN"
echo "  - target role root: $TARGET_ROLE_ROOT_ARN"
echo "  - target bucket:    $BUCKET_NAME"
echo "  - region:           $AWS_REGION"
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

# Verify the identity of the currently configured credentials contains the given name
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
#   $1 = expectation ("allow" or "deny"), $2 = description, remaining = command
# A deny expectation is only met when the error is an authorization failure.
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

# Test one candidate user: assume the role, then (if assumed) read the bucket.
#   $1 label, $2 username, $3 access_key, $4 secret_key,
#   $5 assume expectation (allow|deny), $6 role_arn
test_user() {
    local label="$1" uname="$2" ak="$3" sk="$4" assume_expect="$5" role_arn="$6"
    echo -e "${YELLOW}Testing $label (assume $role_arn)${NC}"

    set_caller_creds "$ak" "$sk"
    verify_identity "$uname"

    show_attack_cmd "$label" "aws sts assume-role --role-arn $role_arn --role-session-name rbr-are-demo --region $AWS_REGION"
    local assume_output assume_rc
    assume_output=$(aws sts assume-role \
        --role-arn "$role_arn" \
        --role-session-name rbr-are-demo \
        --region "$AWS_REGION" \
        --output json 2>&1)
    assume_rc=$?

    local can_assume can_read="n/a"
    if [ $assume_rc -eq 0 ]; then
        LAST_RESULT="allowed"
    elif echo "$assume_output" | grep -qiE "AccessDenied|Access Denied|not authorized|Forbidden|403"; then
        LAST_RESULT="denied"
    else
        LAST_RESULT="error"
        echo -e "${RED}  Unexpected non-authorization error: $assume_output${NC}"
    fi

    if { [ "$assume_expect" == "allow" ] && [ "$LAST_RESULT" == "allowed" ]; } || \
       { [ "$assume_expect" == "deny" ] && [ "$LAST_RESULT" == "denied" ]; }; then
        if [ "$LAST_RESULT" == "allowed" ]; then
            echo -e "  ${GREEN}✓ $label assume-role: ALLOWED (expected)${NC}"
        else
            echo -e "  ${GREEN}✓ $label assume-role: ACCESS DENIED (expected)${NC}"
        fi
    else
        echo -e "  ${RED}✗ $label assume-role: observed ${LAST_RESULT}, expected ${assume_expect}${NC}"
        MISMATCHES=$((MISMATCHES + 1))
    fi
    can_assume=$LAST_RESULT

    if [ "$LAST_RESULT" == "allowed" ]; then
        # Export the assumed-role credentials and read the bucket
        export AWS_ACCESS_KEY_ID=$(echo "$assume_output" | jq -r '.Credentials.AccessKeyId')
        export AWS_SECRET_ACCESS_KEY=$(echo "$assume_output" | jq -r '.Credentials.SecretAccessKey')
        export AWS_SESSION_TOKEN=$(echo "$assume_output" | jq -r '.Credentials.SessionToken')
        export AWS_REGION=$AWS_REGION

        show_attack_cmd "$label (assumed)" "aws s3api get-object --region $AWS_REGION --bucket $BUCKET_NAME --key sensitive-data.txt /dev/null"
        check_result allow "$label read bucket" \
            aws s3api get-object --region "$AWS_REGION" --bucket "$BUCKET_NAME" --key "sensitive-data.txt" /dev/null
        can_read=$LAST_RESULT
        unset AWS_SESSION_TOKEN
    else
        echo -e "  ${DIM}(no assumed credentials, skipping bucket read)${NC}"
    fi

    MATRIX_ROWS+=("$label|$can_assume|$can_read")
    echo ""
}

# =============================================================================
# Run the five candidate users
# =============================================================================
test_user "are-both"               "$ARE_BOTH_NAME"               "$ARE_BOTH_ACCESS_KEY_ID"               "$ARE_BOTH_SECRET_ACCESS_KEY"               allow "$TARGET_ROLE_ARN"
test_user "are-root-with-identity" "$ARE_ROOT_WITH_IDENTITY_NAME" "$ARE_ROOT_WITH_IDENTITY_ACCESS_KEY_ID" "$ARE_ROOT_WITH_IDENTITY_SECRET_ACCESS_KEY" allow "$TARGET_ROLE_ROOT_ARN"
test_user "are-identity-only"      "$ARE_IDENTITY_ONLY_NAME"      "$ARE_IDENTITY_ONLY_ACCESS_KEY_ID"      "$ARE_IDENTITY_ONLY_SECRET_ACCESS_KEY"      deny  "$TARGET_ROLE_ARN"
test_user "are-trust-only"         "$ARE_TRUST_ONLY_NAME"         "$ARE_TRUST_ONLY_ACCESS_KEY_ID"         "$ARE_TRUST_ONLY_SECRET_ACCESS_KEY"         deny  "$TARGET_ROLE_ARN"
test_user "are-root-no-identity"   "$ARE_ROOT_NO_IDENTITY_NAME"   "$ARE_ROOT_NO_IDENTITY_ACCESS_KEY_ID"   "$ARE_ROOT_NO_IDENTITY_SECRET_ACCESS_KEY"   deny  "$TARGET_ROLE_ROOT_ARN"

# Restore helpful permissions before printing the summary (no-op)
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# =============================================================================
# Observed matrix
# =============================================================================
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Observed Assume+Read Matrix for bucket: $BUCKET_NAME${NC}"
echo -e "${GREEN}========================================${NC}"
printf "  %-26s %-14s %-10s\n" "PRINCIPAL" "CAN_ASSUME" "CAN_READ"
for ROW in "${MATRIX_ROWS[@]}"; do
    IFS='|' read -r ROW_PRINCIPAL ROW_ASSUME ROW_READ <<< "$ROW"
    printf "  %-26s %-14s %-10s\n" "$ROW_PRINCIPAL" "$ROW_ASSUME" "$ROW_READ"
done
echo ""

echo -e "${YELLOW}Expected results (compare your graph tool against these):${NC}"
echo "  can reach bucket via one assume-role hop = are-both, are-root-with-identity"
echo "  cannot                                   = are-identity-only, are-trust-only, are-root-no-identity"
echo ""
echo -e "${RED}⚠ A same-account AssumeRole requires BOTH an identity permission AND trust.${NC}"
echo "  are-identity-only is a false positive for tools that read only identity policies."
echo "  are-trust-only is a false positive for tools that read only trust policies."
echo "  are-root-no-identity is a false positive for tools that treat root trust as 'anyone'."
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
