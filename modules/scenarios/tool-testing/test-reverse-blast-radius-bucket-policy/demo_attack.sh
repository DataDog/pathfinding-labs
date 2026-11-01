#!/bin/bash

# Demo script for test-reverse-blast-radius-bucket-policy
# This is a detection-validation demo (not an attack). It proves the ground truth
# that a reverse-blast-radius tool ("who can read/write this bucket?") must
# reproduce when the bucket's RESOURCE policy both grants and denies access:
#   - access GRANTED only by the bucket policy must be found (policy-granted-role)
#   - access DENIED by the bucket policy must be withheld even from an admin
#     (an explicit resource-policy Deny overrides AdministratorAccess)

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
STARTING_USER_NAME="pl-prod-rbr-bp-starting-user"
POLICY_GRANTED_ROLE_NAME="pl-prod-rbr-bp-policy-granted-role"
IDENTITY_READER_NAME="pl-prod-rbr-bp-identity-reader"
DENIED_READER_NAME="pl-prod-rbr-bp-denied-reader"
DENIED_ADMIN_NAME="pl-prod-rbr-bp-denied-admin"

# Object written by the demo (under one prefix so cleanup can remove it)
DEMO_PREFIX="rbr-bp-demo"
PROBE_KEY="$DEMO_PREFIX/probe.txt"
SENSITIVE_KEY="sensitive-data.txt"

# Fixed local body file (cleanup_attack.sh also removes it)
PROBE_BODY_FILE="/tmp/rbr-bp-probe-body.txt"

# Number of observed results that differ from the expected ground truth
MISMATCHES=0

# Matrix rows: "principal|can_read"
MATRIX_ROWS=()

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Reverse Blast Radius: Bucket Policy Grants & Denies Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}This scenario tests reverse blast radius detection against a bucket policy:${NC}"
echo "- Granted only by bucket policy: policy-granted-role (no S3 in identity policy)"
echo "- Granted only by identity policy: identity-reader (bucket policy silent)"
echo "- Reachable at one hop: starting-user (assumes policy-granted-role)"
echo "- Denied by bucket policy despite identity allow: denied-reader"
echo "- Denied by bucket policy despite AdministratorAccess: denied-admin"
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

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_reverse_blast_radius_bucket_policy.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
POLICY_GRANTED_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.policy_granted_role_arn')
IDENTITY_READER_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.identity_reader_access_key_id')
IDENTITY_READER_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.identity_reader_secret_access_key')
DENIED_READER_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.denied_reader_access_key_id')
DENIED_READER_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.denied_reader_secret_access_key')
DENIED_ADMIN_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.denied_admin_access_key_id')
DENIED_ADMIN_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.denied_admin_secret_access_key')
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_name')
BUCKET_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_arn')

for REQUIRED_VALUE in "$STARTING_ACCESS_KEY_ID" "$POLICY_GRANTED_ROLE_ARN" "$IDENTITY_READER_ACCESS_KEY_ID" "$DENIED_READER_ACCESS_KEY_ID" "$DENIED_ADMIN_ACCESS_KEY_ID" "$BUCKET_NAME" "$BUCKET_ARN"; do
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

# Derive account ID from the role ARN (arn:aws:iam::ACCOUNT:role/NAME)
ACCOUNT_ID=$(echo "$POLICY_GRANTED_ROLE_ARN" | cut -d':' -f5)

echo "Retrieved credentials for:"
echo "  - Starting user:      $STARTING_USER_NAME (${STARTING_ACCESS_KEY_ID:0:10}...)"
echo "  - Policy-granted role: $POLICY_GRANTED_ROLE_ARN"
echo "  - Identity reader:    $IDENTITY_READER_NAME (${IDENTITY_READER_ACCESS_KEY_ID:0:10}...)"
echo "  - Denied reader:      $DENIED_READER_NAME (${DENIED_READER_ACCESS_KEY_ID:0:10}...)"
echo "  - Denied admin:       $DENIED_ADMIN_NAME (${DENIED_ADMIN_ACCESS_KEY_ID:0:10}...)"
echo "  - Target bucket:      $BUCKET_NAME"
echo "  - Account ID:         $ACCOUNT_ID"
echo "  - Region:             $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Credential switching helpers. Each helper fully clears any prior credentials
# (including assume-role session tokens) before setting the new ones so session
# creds never leak between steps.
use_starting_creds() {
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    export AWS_ACCESS_KEY_ID="$STARTING_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$STARTING_SECRET_ACCESS_KEY"
    export AWS_REGION=$AWS_REGION
}
use_identity_reader_creds() {
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    export AWS_ACCESS_KEY_ID="$IDENTITY_READER_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$IDENTITY_READER_SECRET_ACCESS_KEY"
    export AWS_REGION=$AWS_REGION
}
use_denied_reader_creds() {
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    export AWS_ACCESS_KEY_ID="$DENIED_READER_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$DENIED_READER_SECRET_ACCESS_KEY"
    export AWS_REGION=$AWS_REGION
}
use_denied_admin_creds() {
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    export AWS_ACCESS_KEY_ID="$DENIED_ADMIN_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$DENIED_ADMIN_SECRET_ACCESS_KEY"
    export AWS_REGION=$AWS_REGION
}

# Source demo permissions library for validation restriction
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run (helpful: [] here, so no-op)
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# Remove the local probe body file on every exit path (normal, error, Ctrl+C).
# Wraps the demo_permissions EXIT handler (only installed when restriction is on)
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

# Small body file uploaded by the put-object probe
echo "reverse blast radius bucket-policy probe object" > "$PROBE_BODY_FILE"

# Run a command expecting success or an access denial.
#   $1 = expectation ("allow" or "deny")
#   $2 = human description
#   remaining = command to run
# Sets LAST_RESULT to "allowed", "denied" or "error". A deny expectation only
# counts as met if the error is an authorization failure (AccessDenied/Forbidden);
# any other error is a mismatch.
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
# Step 2: identity-reader reads via its OWN identity policy (bucket policy silent)
# =============================================================================
echo -e "${YELLOW}Step 2: identity-reader (reads via identity policy, expected ALLOW)${NC}"
use_identity_reader_creds
verify_identity "$IDENTITY_READER_NAME"

show_attack_cmd "IdentityReader" "aws s3 ls s3://$BUCKET_NAME/ --region $AWS_REGION"
check_access allow "identity-reader list bucket" \
    aws s3 ls "s3://$BUCKET_NAME/" --region "$AWS_REGION"

show_attack_cmd "IdentityReader" "aws s3api get-object --region $AWS_REGION --bucket $BUCKET_NAME --key $SENSITIVE_KEY /dev/null"
check_access allow "identity-reader get-object" \
    aws s3api get-object --region "$AWS_REGION" --bucket "$BUCKET_NAME" --key "$SENSITIVE_KEY" /dev/null
IDENTITY_READER_CAN_READ=$LAST_RESULT
MATRIX_ROWS+=("identity-reader|$IDENTITY_READER_CAN_READ")
echo ""

# =============================================================================
# Step 3: starting-user assumes policy-granted-role, then reads/writes the bucket.
# The role has NO S3 statement in its identity policy; all bucket access comes
# from the bucket policy grant. This is the one-hop case.
# =============================================================================
echo -e "${YELLOW}Step 3: starting-user -> assume policy-granted-role -> access via bucket policy${NC}"
use_starting_creds
verify_identity "$STARTING_USER_NAME"

echo "Assuming the policy-granted role (one hop)..."
show_attack_cmd "StartingUser" "aws sts assume-role --role-arn $POLICY_GRANTED_ROLE_ARN --role-session-name rbr-bp-demo --query 'Credentials' --output json"
ASSUME_OUTPUT=$(aws sts assume-role \
    --role-arn "$POLICY_GRANTED_ROLE_ARN" \
    --role-session-name rbr-bp-demo \
    --query 'Credentials' \
    --output json 2>&1)
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Failed to assume policy-granted-role: $ASSUME_OUTPUT${NC}"
    MISMATCHES=$((MISMATCHES + 1))
else
    echo -e "${GREEN}✓ Assumed policy-granted-role${NC}"
    # Export the returned temporary session credentials for the role
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
    export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_OUTPUT" | jq -r '.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_OUTPUT" | jq -r '.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo "$ASSUME_OUTPUT" | jq -r '.SessionToken')
    export AWS_REGION=$AWS_REGION

    show_cmd "PolicyGrantedRole" "aws sts get-caller-identity --query 'Arn' --output text"
    ROLE_ARN_OBSERVED=$(aws sts get-caller-identity --query 'Arn' --output text)
    echo "Current identity: $ROLE_ARN_OBSERVED"

    show_attack_cmd "PolicyGrantedRole" "aws s3 ls s3://$BUCKET_NAME/ --region $AWS_REGION"
    check_access allow "policy-granted-role list bucket (via bucket policy)" \
        aws s3 ls "s3://$BUCKET_NAME/" --region "$AWS_REGION"

    show_attack_cmd "PolicyGrantedRole" "aws s3api get-object --region $AWS_REGION --bucket $BUCKET_NAME --key $SENSITIVE_KEY /dev/null"
    check_access allow "policy-granted-role get-object (via bucket policy)" \
        aws s3api get-object --region "$AWS_REGION" --bucket "$BUCKET_NAME" --key "$SENSITIVE_KEY" /dev/null
    ROLE_CAN_READ=$LAST_RESULT

    echo "Writing a probe object (bucket policy grants PutObject)..."
    show_attack_cmd "PolicyGrantedRole" "aws s3api put-object --region $AWS_REGION --bucket $BUCKET_NAME --key $PROBE_KEY --body $PROBE_BODY_FILE"
    check_access allow "policy-granted-role put-object (via bucket policy)" \
        aws s3api put-object --region "$AWS_REGION" --bucket "$BUCKET_NAME" --key "$PROBE_KEY" --body "$PROBE_BODY_FILE"

    MATRIX_ROWS+=("policy-granted-role (via assume)|$ROLE_CAN_READ")
    MATRIX_ROWS+=("starting-user (1 hop)|$ROLE_CAN_READ")
fi
echo ""

# =============================================================================
# Step 4: denied-reader (identity policy allows, but bucket policy Denies its ARN)
# =============================================================================
echo -e "${YELLOW}Step 4: denied-reader (identity allows read, bucket policy DENIES, expected DENY)${NC}"
use_denied_reader_creds
verify_identity "$DENIED_READER_NAME"

show_attack_cmd "DeniedReader" "aws s3 ls s3://$BUCKET_NAME/ --region $AWS_REGION"
check_access deny "denied-reader list bucket" \
    aws s3 ls "s3://$BUCKET_NAME/" --region "$AWS_REGION"

show_attack_cmd "DeniedReader" "aws s3api get-object --region $AWS_REGION --bucket $BUCKET_NAME --key $SENSITIVE_KEY /dev/null"
check_access deny "denied-reader get-object" \
    aws s3api get-object --region "$AWS_REGION" --bucket "$BUCKET_NAME" --key "$SENSITIVE_KEY" /dev/null
DENIED_READER_CAN_READ=$LAST_RESULT
MATRIX_ROWS+=("denied-reader|$DENIED_READER_CAN_READ")
echo ""

# =============================================================================
# Step 5: denied-admin (AdministratorAccess, but bucket policy Denies its ARN).
# An explicit resource-policy Deny overrides admin. Prove the principal really is
# admin by running a non-denied admin action (iam:ListUsers) that succeeds.
# =============================================================================
echo -e "${YELLOW}Step 5: denied-admin (AdministratorAccess, bucket policy DENIES this bucket)${NC}"
use_denied_admin_creds
verify_identity "$DENIED_ADMIN_NAME"

show_attack_cmd "DeniedAdmin" "aws s3 ls s3://$BUCKET_NAME/ --region $AWS_REGION"
check_access deny "denied-admin list bucket" \
    aws s3 ls "s3://$BUCKET_NAME/" --region "$AWS_REGION"

show_attack_cmd "DeniedAdmin" "aws s3api get-object --region $AWS_REGION --bucket $BUCKET_NAME --key $SENSITIVE_KEY /dev/null"
check_access deny "denied-admin get-object" \
    aws s3api get-object --region "$AWS_REGION" --bucket "$BUCKET_NAME" --key "$SENSITIVE_KEY" /dev/null
DENIED_ADMIN_CAN_READ=$LAST_RESULT
MATRIX_ROWS+=("denied-admin|$DENIED_ADMIN_CAN_READ")

echo "Proving denied-admin really is an administrator (non-denied action)..."
show_cmd "DeniedAdmin" "aws iam list-users --max-items 1"
check_access allow "denied-admin iam:list-users (proves admin)" \
    aws iam list-users --max-items 1
echo ""

# Restore helpful permissions before printing the summary
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# =============================================================================
# Observed matrix
# =============================================================================
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Observed Access Matrix for bucket: $BUCKET_NAME${NC}"
echo -e "${GREEN}========================================${NC}"
printf "  %-32s %-10s\n" "PRINCIPAL" "CAN_READ"
for ROW in "${MATRIX_ROWS[@]}"; do
    IFS='|' read -r ROW_PRINCIPAL ROW_READ <<< "$ROW"
    printf "  %-32s %-10s\n" "$ROW_PRINCIPAL" "$ROW_READ"
done
echo ""

echo -e "${YELLOW}Expected results (compare your reverse-blast-radius tool against these):${NC}"
echo "  can_read bucket = policy-granted-role (via bucket policy, assumed),"
echo "                    identity-reader (via identity policy),"
echo "                    starting-user at 1 hop (assumes policy-granted-role)"
echo "  NO access       = denied-reader (identity allows, bucket policy Denies its ARN)"
echo "                    denied-admin  (AdministratorAccess, bucket policy Denies its ARN)"
echo ""
echo -e "${RED}⚠ denied-admin holds AdministratorAccess yet CANNOT read this bucket.${NC}"
echo "  An explicit resource-policy Deny overrides an identity-based admin allow."
echo "  A tool that only reasons over identity policies will wrongly include"
echo "  denied-reader and denied-admin, and wrongly exclude policy-granted-role"
echo "  (whose access exists only in the bucket policy)."
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
echo "  - Probe object at s3://$BUCKET_NAME/$PROBE_KEY"
echo "  - To remove it: ./cleanup_attack.sh"
echo ""

if [ "$MISMATCHES" -ne 0 ]; then
    echo -e "${RED}✗ $MISMATCHES observed result(s) differed from the expected ground truth${NC}"
    # Still mark active so cleanup of the uploaded probe object is offered
    touch "$(dirname "$0")/.demo_active"
    exit 1
fi

echo -e "${GREEN}✅ All observed results match the expected ground truth${NC}"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
