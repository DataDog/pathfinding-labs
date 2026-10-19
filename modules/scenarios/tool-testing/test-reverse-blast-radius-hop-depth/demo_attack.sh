#!/bin/bash

# Demo script for test-reverse-blast-radius-hop-depth
# Tool-testing scenario: this is a detection-validation demo, not an attack.
# It proves, with real AWS calls, which principals can read one S3 bucket at
# each hop depth, then prints the expected-results table a graph tool's
# reverse blast radius output should be compared against.
#
#   depth 0: user-a, role-r1   (S3 read permissions directly)
#   depth 1: user-b -> role-r1, role-r2 -> role-r1
#   depth 2: user-c -> role-r2 -> role-r1
#
# The demo only reads from the bucket. Exits non-zero if any observed result
# differs from the expectation.

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

# Temp file used for read-only object downloads (removed by cleanup_attack.sh)
DOWNLOAD_FILE="/tmp/rbr-hd-sensitive.txt"

# Number of observations that differed from the expectation
MISMATCHES=0

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Reverse Blast Radius Test Demo${NC}"
echo -e "${GREEN}Hop Depth to S3 Bucket${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo "This scenario places five principals at different hop depths from one bucket:"
echo "  Depth 0: user-a, role-r1 (direct S3 read permissions)"
echo "  Depth 1: user-b -> role-r1 ; role-r2 -> role-r1"
echo "  Depth 2: user-c -> role-r2 -> role-r1"
echo ""

if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed or not in PATH${NC}"
    exit 1
fi
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed or not in PATH${NC}"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd "$TERRAFORM_ROOT"

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_reverse_blast_radius_hop_depth.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

USER_A_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.user_a_name')
USER_A_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.user_a_access_key_id')
USER_A_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.user_a_secret_access_key')

USER_B_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.user_b_name')
USER_B_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.user_b_access_key_id')
USER_B_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.user_b_secret_access_key')

USER_C_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.user_c_name')
USER_C_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.user_c_access_key_id')
USER_C_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.user_c_secret_access_key')

ROLE_R1_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.role_r1_name')
ROLE_R1_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.role_r1_arn')
ROLE_R2_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.role_r2_name')
ROLE_R2_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.role_r2_arn')

BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_name')

for REQUIRED_VALUE in "$USER_A_ACCESS_KEY_ID" "$USER_B_ACCESS_KEY_ID" "$USER_C_ACCESS_KEY_ID" \
                      "$ROLE_R1_ARN" "$ROLE_R2_ARN" "$BUCKET_NAME"; do
    if [ "$REQUIRED_VALUE" == "null" ] || [ -z "$REQUIRED_VALUE" ]; then
        echo -e "${RED}Error: Could not extract all required values from terraform output${NC}"
        exit 1
    fi
done

# Readonly credentials for observation steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")
if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved credentials for:"
echo "  - $USER_A_NAME (depth 0, direct)"
echo "  - $USER_B_NAME"
echo "  - $USER_C_NAME"
echo "  - $ROLE_R1_NAME (depth 0, direct)"
echo "  - $ROLE_R2_NAME"
echo "  - Bucket: $BUCKET_NAME"
echo "  - Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

cd - > /dev/null

# Credential helpers. Every switch clears all three variables first so an
# assume-role session token can never leak into the next principal.
clear_creds() {
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
}
set_creds() {
    # usage: set_creds ACCESS_KEY SECRET_KEY [SESSION_TOKEN]
    clear_creds
    export AWS_ACCESS_KEY_ID="$1"
    export AWS_SECRET_ACCESS_KEY="$2"
    if [ -n "$3" ]; then
        export AWS_SESSION_TOKEN="$3"
    fi
    export AWS_REGION="$AWS_REGION"
    export AWS_DEFAULT_REGION="$AWS_REGION"
}
use_readonly_creds() { set_creds "$READONLY_ACCESS_KEY" "$READONLY_SECRET_KEY"; }
use_user_a_creds()   { set_creds "$USER_A_ACCESS_KEY_ID" "$USER_A_SECRET_ACCESS_KEY"; }
use_user_b_creds()   { set_creds "$USER_B_ACCESS_KEY_ID" "$USER_B_SECRET_ACCESS_KEY"; }
use_user_c_creds()   { set_creds "$USER_C_ACCESS_KEY_ID" "$USER_C_SECRET_ACCESS_KEY"; }

# Assume a role using the CURRENT credentials and switch to the resulting
# session. Returns non-zero (and leaves current creds untouched) on failure.
assume_role_and_switch() {
    local role_arn="$1"
    local session_name="$2"
    local identity_label="$3"
    local creds
    show_attack_cmd "$identity_label" "aws sts assume-role --role-arn $role_arn --role-session-name $session_name --query 'Credentials' --output json"
    creds=$(aws sts assume-role \
        --role-arn "$role_arn" \
        --role-session-name "$session_name" \
        --query 'Credentials' \
        --output json)
    if [ $? -ne 0 ] || [ -z "$creds" ]; then
        return 1
    fi
    set_creds \
        "$(echo "$creds" | jq -r '.AccessKeyId')" \
        "$(echo "$creds" | jq -r '.SecretAccessKey')" \
        "$(echo "$creds" | jq -r '.SessionToken')"
    return 0
}

# Attempt to list and read the bucket with the CURRENT credentials.
# Returns 0 if both list and get succeed, 1 otherwise.
can_read_bucket() {
    local identity_label="$1"
    show_cmd "$identity_label" "aws s3 ls s3://$BUCKET_NAME/ --region $AWS_REGION"
    aws s3 ls "s3://$BUCKET_NAME/" --region "$AWS_REGION" > /dev/null 2>&1 || return 1
    show_cmd "$identity_label" "aws s3 cp s3://$BUCKET_NAME/sensitive-data.txt $DOWNLOAD_FILE --region $AWS_REGION"
    aws s3 cp "s3://$BUCKET_NAME/sensitive-data.txt" "$DOWNLOAD_FILE" --region "$AWS_REGION" > /dev/null 2>&1 || return 1
    return 0
}

# Compare observed read result with expectation and record mismatches.
# usage: expect_read "<label>" "<identity label>" <allow|deny>
expect_read() {
    local description="$1"
    local identity_label="$2"
    local expectation="$3"
    local observed
    if can_read_bucket "$identity_label"; then observed="allow"; else observed="deny"; fi
    if [ "$observed" == "$expectation" ]; then
        if [ "$observed" == "allow" ]; then
            echo -e "${GREEN}✓ $description: read SUCCEEDED (expected)${NC}"
        else
            echo -e "${GREEN}✓ $description: read DENIED (expected)${NC}"
        fi
        return 0
    fi
    echo -e "${RED}✗ $description: read was $observed but expected $expectation${NC}"
    MISMATCHES=$((MISMATCHES + 1))
    return 1
}

# Print the identity for the current creds and verify it contains a substring
verify_identity() {
    local identity_label="$1"
    local expected_fragment="$2"
    local arn
    show_cmd "$identity_label" "aws sts get-caller-identity --query 'Arn' --output text"
    arn=$(aws sts get-caller-identity --query 'Arn' --output text 2>/dev/null)
    echo "Current identity: $arn"
    if [[ "$arn" != *"$expected_fragment"* ]]; then
        echo -e "${RED}✗ Expected identity containing '$expected_fragment'${NC}"
        MISMATCHES=$((MISMATCHES + 1))
        return 1
    fi
    return 0
}

# Source demo permissions library for validation restriction
source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# [OBSERVATION] Step 2: Account ID
echo -e "${YELLOW}Step 2: Getting account ID${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Observed hop depth per principal (set only when the full proof sequence passes)
DEPTH_USER_A="?"
DEPTH_ROLE_R1="?"
DEPTH_USER_B="?"
DEPTH_ROLE_R2="?"
DEPTH_USER_C="?"

# ---------------------------------------------------------------------------
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}DEPTH 0: user-a (direct S3 permissions)${NC}"
echo -e "${BLUE}========================================${NC}\n"

# [EXPLOIT] Step 3: user-a reads the bucket directly
echo -e "${YELLOW}Step 3: user-a reads the bucket directly${NC}"
use_user_a_creds
verify_identity "Attacker" "$USER_A_NAME"
if expect_read "user-a direct" "Attacker" allow; then DEPTH_USER_A=0; fi
echo ""

# ---------------------------------------------------------------------------
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}DEPTH 1: user-b -> role-r1${NC}"
echo -e "${BLUE}========================================${NC}\n"

# [EXPLOIT] Step 4: user-b direct read fails, then hops to role-r1
echo -e "${YELLOW}Step 4: user-b has no direct access (expected to fail)${NC}"
use_user_b_creds
verify_identity "Attacker" "$USER_B_NAME"
USER_B_DIRECT_OK=0
expect_read "user-b direct" "Attacker" deny && USER_B_DIRECT_OK=1
echo ""

echo -e "${YELLOW}Step 5: user-b assumes role-r1 (1 hop) and reads the bucket${NC}"
USER_B_HOP_OK=0
if assume_role_and_switch "$ROLE_R1_ARN" "rbr-hd-user-b" "Attacker"; then
    verify_identity "Attacker" "$ROLE_R1_NAME"
    # Wait is not needed for assume-role sessions; the role policy is pre-provisioned
    if expect_read "user-b via role-r1" "Attacker" allow; then
        USER_B_HOP_OK=1
        # role-r1 reached via user-b reads the bucket directly (no further hop)
        DEPTH_ROLE_R1=0
    fi
else
    echo -e "${RED}✗ user-b failed to assume role-r1${NC}"
    MISMATCHES=$((MISMATCHES + 1))
fi
if [ "$USER_B_DIRECT_OK" == "1" ] && [ "$USER_B_HOP_OK" == "1" ]; then DEPTH_USER_B=1; fi
echo ""

# ---------------------------------------------------------------------------
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}DEPTH 2: user-c -> role-r2 -> role-r1${NC}"
echo -e "${BLUE}========================================${NC}\n"

# [EXPLOIT] Step 6: user-c direct read fails
echo -e "${YELLOW}Step 6: user-c has no direct access (expected to fail)${NC}"
use_user_c_creds
verify_identity "Attacker" "$USER_C_NAME"
USER_C_DIRECT_OK=0
expect_read "user-c direct" "Attacker" deny && USER_C_DIRECT_OK=1
echo ""

# [EXPLOIT] Step 7: user-c assumes role-r2 (hop 1); role-r2 has no direct access
echo -e "${YELLOW}Step 7: user-c assumes role-r2 (hop 1); role-r2 has no direct access${NC}"
USER_C_HOP1_OK=0
R2_DIRECT_OK=0
R2_HOP_OK=0
if assume_role_and_switch "$ROLE_R2_ARN" "rbr-hd-user-c" "Attacker"; then
    USER_C_HOP1_OK=1
    verify_identity "Attacker" "$ROLE_R2_NAME"
    expect_read "role-r2 direct" "Attacker" deny && R2_DIRECT_OK=1
    echo ""

    # [EXPLOIT] Step 8: role-r2 credentials chain into role-r1 (hop 2 from user-c)
    echo -e "${YELLOW}Step 8: role-r2 assumes role-r1 (chained hop) and reads the bucket${NC}"
    # Current creds are role-r2's session, which is what the chained call needs
    if assume_role_and_switch "$ROLE_R1_ARN" "rbr-hd-user-c-chain" "Attacker (as role-r2)"; then
        verify_identity "Attacker" "$ROLE_R1_NAME"
        expect_read "role-r2 via role-r1" "Attacker" allow && R2_HOP_OK=1
    else
        echo -e "${RED}✗ role-r2 failed to assume role-r1${NC}"
        MISMATCHES=$((MISMATCHES + 1))
    fi
else
    echo -e "${RED}✗ user-c failed to assume role-r2${NC}"
    MISMATCHES=$((MISMATCHES + 1))
fi
if [ "$R2_DIRECT_OK" == "1" ] && [ "$R2_HOP_OK" == "1" ]; then DEPTH_ROLE_R2=1; fi
if [ "$USER_C_DIRECT_OK" == "1" ] && [ "$USER_C_HOP1_OK" == "1" ] && [ "$R2_DIRECT_OK" == "1" ] && [ "$R2_HOP_OK" == "1" ]; then
    DEPTH_USER_C=2
fi
echo ""

# Drop all session credentials before printing results
clear_creds

# Restore helpful permissions before printing summary
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Compare observed depths with expectations
check_depth() {
    local label="$1" observed="$2" expected="$3"
    if [ "$observed" != "$expected" ]; then
        echo -e "${RED}✗ $label observed at depth '$observed', expected $expected${NC}"
        MISMATCHES=$((MISMATCHES + 1))
    fi
}
check_depth "user-a"  "$DEPTH_USER_A"  0
check_depth "role-r1" "$DEPTH_ROLE_R1" 0
check_depth "user-b"  "$DEPTH_USER_B"  1
check_depth "role-r2" "$DEPTH_ROLE_R2" 1
check_depth "user-c"  "$DEPTH_USER_C"  2

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Observed Hop Depth (proven with real calls)${NC}"
echo -e "${GREEN}========================================${NC}"
printf "  %-10s %s\n" "PRINCIPAL" "HOPS TO BUCKET"
printf "  %-10s %s\n" "user-a"  "$DEPTH_USER_A"
printf "  %-10s %s\n" "role-r1" "$DEPTH_ROLE_R1"
printf "  %-10s %s\n" "user-b"  "$DEPTH_USER_B"
printf "  %-10s %s\n" "role-r2" "$DEPTH_ROLE_R2"
printf "  %-10s %s\n" "user-c"  "$DEPTH_USER_C"
echo ""

echo -e "${YELLOW}Expected Results: compare your graph tool against these${NC}"
echo "Query: \"Who can read s3://$BUCKET_NAME?\""
echo ""
echo "  Exactly 0 hops:  user-a, role-r1"
echo "  Exactly 1 hop:   user-b, role-r2"
echo "  Exactly 2 hops:  user-c"
echo ""
echo "  Cumulative <= 0 hops:  user-a, role-r1"
echo "  Cumulative <= 1 hop:   user-a, role-r1, user-b, role-r2"
echo "  Cumulative <= 2 hops:  user-a, role-r1, user-b, role-r2, user-c  (all five)"
echo ""
echo -e "${YELLOW}Point for the team:${NC}"
echo "  A query run at a single depth misses principals at every other depth."
echo "  For example, a 1-hop-only query omits user-a and role-r1 even though they"
echo "  can read the bucket (they have access directly), and omits user-c, which"
echo "  needs 2 hops. The tool must either return all depths together, or the"
echo "  user must union the results of multiple queries (0, 1 and 2 hops)."
echo ""

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
    echo ""
fi

echo -e "${YELLOW}Artifacts Created:${NC}"
echo "  - $DOWNLOAD_FILE (local temp file; the demo only reads from the bucket)"
echo ""

if [ "$MISMATCHES" -ne 0 ]; then
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}✗ DEMONSTRATION FAILED: $MISMATCHES observation(s) differed from expectation${NC}"
    echo -e "${RED}========================================${NC}"
    echo -e "${YELLOW}To clean up artifacts:${NC} ./cleanup_attack.sh"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ DEMONSTRATION SUCCESSFUL: all observations matched expectations${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}To clean up artifacts:${NC}"
echo "  run plabs cleanup or use the plabs TUI/CLI"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
