#!/bin/bash

# Comprehensive Effective Permissions Evaluation Test Suite
# Tests 40 principals (15 isAdmin, 24 notAdmin, 1 starting user)


# Disable AWS CLI paging
export AWS_PAGER=""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Dim color for command display
DIM='\033[2m'

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

echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}Effective Permissions Evaluation Test (40 Principals)${NC}"
echo -e "${CYAN}================================================================${NC}"
echo ""
echo -e "${BLUE}This scenario tests 40 IAM principals with varying configurations:${NC}"
echo -e "${BLUE}  - 15 isAdmin (9 users + 6 roles)${NC}"
echo -e "${BLUE}  - 24 notAdmin (12 users + 12 roles)${NC}"
echo -e "${BLUE}  - 1 starting user${NC}"
echo ""
echo -e "${BLUE}Admin Definition: You have * on * without any IAM denies${NC}"
echo ""

# Navigate to project root
cd ../../../..

echo -e "${YELLOW}[INFO]${NC} Retrieving credentials from Terraform outputs..."

# Get module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_effective_permissions_evaluation.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}[ERROR]${NC} Could not retrieve Terraform outputs. Ensure scenario is deployed."
    exit 1
fi

# Get AWS region
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
export AWS_REGION

# Extract bucket info
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.target_bucket_name')

# Extract starting user credentials
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}[ERROR]${NC} Could not extract starting user credentials from terraform output"
    exit 1
fi

# Extract readonly credentials for observation/polling steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

echo -e "${GREEN}[SUCCESS]${NC} Retrieved configuration"
echo -e "${YELLOW}[INFO]${NC} Target bucket: $BUCKET_NAME"
echo -e "${YELLOW}[INFO]${NC} Starting Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo -e "${YELLOW}[INFO]${NC} ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo ""

# Results tracking (using simple counters for Bash 3.2+ compatibility)
TOTAL_TESTS=39
TEST_NUM=0
ISADMIN_PASS=0
ISADMIN_FAIL=0
NOTADMIN_PASS=0
NOTADMIN_FAIL=0

# Return to scenario directory
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

# Source demo permissions library for validation restriction
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# Test function for users
test_user() {
    local user_name=$1
    local access_key=$2
    local secret_key=$3
    local expected=$4  # "admin" or "not-admin"

    TEST_NUM=$((TEST_NUM + 1))
    echo -e "${CYAN}[TEST $TEST_NUM/$TOTAL_TESTS]${NC} Testing user: ${YELLOW}$user_name${NC} (expecting: $expected)"

    export AWS_ACCESS_KEY_ID="$access_key"
    export AWS_SECRET_ACCESS_KEY="$secret_key"
    export AWS_REGION
    unset AWS_SESSION_TOKEN

    # Wait for IAM propagation
    sleep 1

    # Test S3 access
    if aws s3 ls s3://$BUCKET_NAME/ > /dev/null 2>&1; then
        s3_result="PASS"
    else
        s3_result="FAIL"
    fi

    # Test IAM access
    if aws iam list-users --max-items 1 > /dev/null 2>&1; then
        iam_result="PASS"
    else
        iam_result="FAIL"
    fi

    # Determine if admin (has both S3 and IAM)
    if [ "$s3_result" = "PASS" ] && [ "$iam_result" = "PASS" ]; then
        actual="admin"
        echo -e "  S3: ${GREEN}✓${NC}  IAM: ${GREEN}✓${NC}  → ${GREEN}ADMIN${NC}"
    elif [ "$s3_result" = "FAIL" ] && [ "$iam_result" = "FAIL" ]; then
        actual="not-admin"
        echo -e "  S3: ${RED}✗${NC}  IAM: ${RED}✗${NC}  → ${RED}NOT ADMIN${NC}"
    else
        actual="partial"
        echo -e "  S3: $([ "$s3_result" = "PASS" ] && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}")  IAM: $([ "$iam_result" = "PASS" ] && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}")  → ${YELLOW}PARTIAL${NC}"
    fi

    # Check if result matches expectation
    if [ "$expected" = "admin" ]; then
        if [ "$actual" = "admin" ]; then
            echo -e "  ${GREEN}✓ CORRECT${NC} - Properly identified as admin"
            ISADMIN_PASS=$((ISADMIN_PASS + 1))
        else
            echo -e "  ${RED}✗ INCORRECT${NC} - Should be admin but detected as $actual"
            ISADMIN_FAIL=$((ISADMIN_FAIL + 1))
        fi
    else
        if [ "$actual" != "admin" ]; then
            echo -e "  ${GREEN}✓ CORRECT${NC} - Properly blocked from admin"
            NOTADMIN_PASS=$((NOTADMIN_PASS + 1))
        else
            echo -e "  ${RED}✗ INCORRECT${NC} - Should be blocked but has admin"
            NOTADMIN_FAIL=$((NOTADMIN_FAIL + 1))
        fi
    fi

    echo ""
}

# Test function for roles
test_role() {
    local role_name=$1
    local role_arn=$2
    local expected=$3  # "admin" or "not-admin"

    TEST_NUM=$((TEST_NUM + 1))
    echo -e "${CYAN}[TEST $TEST_NUM/$TOTAL_TESTS]${NC} Testing role: ${YELLOW}$role_name${NC} (expecting: $expected)"

    # Switch to starting user credentials for role assumption
    use_starting_creds
    export AWS_REGION

    # Wait for IAM propagation
    sleep 1

    # Assume role
    ASSUMED=$(aws sts assume-role --role-arn "$role_arn" --role-session-name "test-session" 2>/dev/null || echo "FAIL")

    if [ "$ASSUMED" = "FAIL" ]; then
        echo -e "  ${RED}✗ FAILED${NC} to assume role"
        if [ "$expected" = "admin" ]; then
            ISADMIN_FAIL=$((ISADMIN_FAIL + 1))
        else
            NOTADMIN_FAIL=$((NOTADMIN_FAIL + 1))
        fi
        echo ""
        return
    fi

    TEMP_ACCESS_KEY=$(echo "$ASSUMED" | jq -r '.Credentials.AccessKeyId')
    TEMP_SECRET_KEY=$(echo "$ASSUMED" | jq -r '.Credentials.SecretAccessKey')
    TEMP_SESSION_TOKEN=$(echo "$ASSUMED" | jq -r '.Credentials.SessionToken')

    export AWS_ACCESS_KEY_ID="$TEMP_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$TEMP_SECRET_KEY"
    export AWS_SESSION_TOKEN="$TEMP_SESSION_TOKEN"
    export AWS_REGION

    # Test S3 access
    if aws s3 ls s3://$BUCKET_NAME/ > /dev/null 2>&1; then
        s3_result="PASS"
    else
        s3_result="FAIL"
    fi

    # Test IAM access
    if aws iam list-users --max-items 1 > /dev/null 2>&1; then
        iam_result="PASS"
    else
        iam_result="FAIL"
    fi

    # Determine if admin
    if [ "$s3_result" = "PASS" ] && [ "$iam_result" = "PASS" ]; then
        actual="admin"
        echo -e "  S3: ${GREEN}✓${NC}  IAM: ${GREEN}✓${NC}  → ${GREEN}ADMIN${NC}"
    elif [ "$s3_result" = "FAIL" ] && [ "$iam_result" = "FAIL" ]; then
        actual="not-admin"
        echo -e "  S3: ${RED}✗${NC}  IAM: ${RED}✗${NC}  → ${RED}NOT ADMIN${NC}"
    else
        actual="partial"
        echo -e "  S3: $([ "$s3_result" = "PASS" ] && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}")  IAM: $([ "$iam_result" = "PASS" ] && echo -e "${GREEN}✓${NC}" || echo -e "${RED}✗${NC}")  → ${YELLOW}PARTIAL${NC}"
    fi

    # Check if result matches expectation
    if [ "$expected" = "admin" ]; then
        if [ "$actual" = "admin" ]; then
            echo -e "  ${GREEN}✓ CORRECT${NC} - Properly identified as admin"
            ISADMIN_PASS=$((ISADMIN_PASS + 1))
        else
            echo -e "  ${RED}✗ INCORRECT${NC} - Should be admin but detected as $actual"
            ISADMIN_FAIL=$((ISADMIN_FAIL + 1))
        fi
    else
        if [ "$actual" != "admin" ]; then
            echo -e "  ${GREEN}✓ CORRECT${NC} - Properly blocked from admin"
            NOTADMIN_PASS=$((NOTADMIN_PASS + 1))
        else
            echo -e "  ${RED}✗ INCORRECT${NC} - Should be blocked but has admin"
            NOTADMIN_FAIL=$((NOTADMIN_FAIL + 1))
        fi
    fi

    echo ""
}

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}TESTING ISADMIN USERS (9 users)${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# isAdmin Users - Single Policy (3)
test_user "isAdmin-awsmanaged" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_isadmin_awsmanaged_access_key_id')" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_isadmin_awsmanaged_secret_access_key')" \
    "admin"

test_user "isAdmin-customermanaged" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_isadmin_customermanaged_access_key_id')" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_isadmin_customermanaged_secret_access_key')" \
    "admin"

test_user "isAdmin-inline" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_isadmin_inline_access_key_id')" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_isadmin_inline_secret_access_key')" \
    "admin"

# isAdmin Users - Group Membership (3)
test_user "isAdmin-via-group-awsmanaged" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_isadmin_via_group_awsmanaged_access_key_id')" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_isadmin_via_group_awsmanaged_secret_access_key')" \
    "admin"

test_user "isAdmin-via-group-customermanaged" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_isadmin_via_group_customermanaged_access_key_id')" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_isadmin_via_group_customermanaged_secret_access_key')" \
    "admin"

test_user "isAdmin-via-group-inline" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_isadmin_via_group_inline_access_key_id')" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_isadmin_via_group_inline_secret_access_key')" \
    "admin"

# isAdmin Users - Multi-Policy (3)
test_user "isAdmin-split-iam-and-notiam" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_isadmin_split_iam_and_notiam_access_key_id')" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_isadmin_split_iam_and_notiam_secret_access_key')" \
    "admin"

test_user "isAdmin-split-s3-and-nots3" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_isadmin_split_s3_and_nots3_access_key_id')" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_isadmin_split_s3_and_nots3_secret_access_key')" \
    "admin"

test_user "isAdmin-many-services-combined" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_isadmin_many_services_combined_access_key_id')" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_isadmin_many_services_combined_secret_access_key')" \
    "admin"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}TESTING NOTADMIN USERS (12 users)${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# notAdmin Users - Single Deny (3)
test_user "notAdmin-adminpolicy-plus-denyall" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_adminpolicy_plus_denyall_access_key_id')" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_adminpolicy_plus_denyall_secret_access_key')" \
    "not-admin"

test_user "notAdmin-adminpolicy-plus-denynotaction" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_adminpolicy_plus_denynotaction_access_key_id')" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_adminpolicy_plus_denynotaction_secret_access_key')" \
    "not-admin"

test_user "notAdmin-admin-plus-denynotaction-ec2only" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_adminpolicy_plus_denynotaction_ec2only_access_key_id')" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_adminpolicy_plus_denynotaction_ec2only_secret_access_key')" \
    "not-admin"

# notAdmin Users - Multi-Deny (3)
test_user "notAdmin-adminpolicy-plus-deny-split-iam-notiam" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_adminpolicy_plus_deny_split_iam_notiam_access_key_id')" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_adminpolicy_plus_deny_split_iam_notiam_secret_access_key')" \
    "not-admin"

test_user "notAdmin-adminpolicy-plus-deny-incremental" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_adminpolicy_plus_deny_incremental_access_key_id')" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_adminpolicy_plus_deny_incremental_secret_access_key')" \
    "not-admin"

test_user "notAdmin-split-allow-plus-denyall" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_split_allow_plus_denyall_access_key_id')" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_split_allow_plus_denyall_secret_access_key')" \
    "not-admin"

# notAdmin Users - Single Boundary (3)
test_user "notAdmin-admin-plus-boundary-allows-nothing" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_adminpolicy_plus_boundary_allows_nothing_access_key_id')" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_adminpolicy_plus_boundary_allows_nothing_secret_access_key')" \
    "not-admin"

test_user "notAdmin-adminpolicy-plus-boundary-ec2only" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_adminpolicy_plus_boundary_ec2only_access_key_id')" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_adminpolicy_plus_boundary_ec2only_secret_access_key')" \
    "not-admin"

test_user "notAdmin-admin-plus-boundary-na-ec2only" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_adminpolicy_plus_boundary_notaction_ec2only_access_key_id')" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_adminpolicy_plus_boundary_notaction_ec2only_secret_access_key')" \
    "not-admin"

# notAdmin Users - Multi-Policy with Boundary (3)
test_user "notAdmin-split-allow-boundary-allows-nothing" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_split_allow_boundary_allows_nothing_access_key_id')" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_split_allow_boundary_allows_nothing_secret_access_key')" \
    "not-admin"

test_user "notAdmin-split-allow-boundary-ec2only" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_split_allow_boundary_ec2only_access_key_id')" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_split_allow_boundary_ec2only_secret_access_key')" \
    "not-admin"

test_user "notAdmin-split-boundary-mismatch" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_split_boundary_mismatch_access_key_id')" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.user_notadmin_split_boundary_mismatch_secret_access_key')" \
    "not-admin"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}TESTING ISADMIN ROLES (6 roles)${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# isAdmin Roles - Single Policy (3)
test_role "isAdmin-awsmanaged" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.role_isadmin_awsmanaged_arn')" \
    "admin"

test_role "isAdmin-customermanaged" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.role_isadmin_customermanaged_arn')" \
    "admin"

test_role "isAdmin-inline" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.role_isadmin_inline_arn')" \
    "admin"

# isAdmin Roles - Multi-Policy (3)
test_role "isAdmin-split-iam-and-notiam" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.role_isadmin_split_iam_and_notiam_arn')" \
    "admin"

test_role "isAdmin-split-s3-and-nots3" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.role_isadmin_split_s3_and_nots3_arn')" \
    "admin"

test_role "isAdmin-many-services-combined" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.role_isadmin_many_services_combined_arn')" \
    "admin"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}TESTING NOTADMIN ROLES (12 roles)${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# notAdmin Roles - Single Deny (3)
test_role "notAdmin-adminpolicy-plus-denyall" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.role_notadmin_adminpolicy_plus_denyall_arn')" \
    "not-admin"

test_role "notAdmin-adminpolicy-plus-denynotaction" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.role_notadmin_adminpolicy_plus_denynotaction_arn')" \
    "not-admin"

test_role "notAdmin-adminpolicy-plus-denynotaction-ec2only" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.role_notadmin_adminpolicy_plus_denynotaction_ec2only_arn')" \
    "not-admin"

# notAdmin Roles - Multi-Deny (3)
test_role "notAdmin-adminpolicy-plus-deny-split-iam-notiam" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.role_notadmin_adminpolicy_plus_deny_split_iam_notiam_arn')" \
    "not-admin"

test_role "notAdmin-adminpolicy-plus-deny-incremental" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.role_notadmin_adminpolicy_plus_deny_incremental_arn')" \
    "not-admin"

test_role "notAdmin-split-allow-plus-denyall" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.role_notadmin_split_allow_plus_denyall_arn')" \
    "not-admin"

# notAdmin Roles - Single Boundary (3)
test_role "notAdmin-admin-plus-boundary-allows-nothing" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.role_notadmin_adminpolicy_plus_boundary_allows_nothing_arn')" \
    "not-admin"

test_role "notAdmin-adminpolicy-plus-boundary-ec2only" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.role_notadmin_adminpolicy_plus_boundary_ec2only_arn')" \
    "not-admin"

test_role "notAdmin-admin-plus-boundary-na-ec2only" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.role_notadmin_adminpolicy_plus_boundary_notaction_ec2only_arn')" \
    "not-admin"

# notAdmin Roles - Multi-Policy with Boundary (3)
test_role "notAdmin-split-allow-boundary-allows-nothing" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.role_notadmin_split_allow_boundary_allows_nothing_arn')" \
    "not-admin"

test_role "notAdmin-split-allow-boundary-ec2only" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.role_notadmin_split_allow_boundary_ec2only_arn')" \
    "not-admin"

test_role "notAdmin-split-boundary-mismatch" \
    "$(echo "$MODULE_OUTPUT" | jq -r '.role_notadmin_split_boundary_mismatch_arn')" \
    "not-admin"

# Final Summary
echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}TEST SUMMARY${NC}"
echo -e "${CYAN}================================================================${NC}"
echo ""
echo -e "${BLUE}Total Tests: $TOTAL_TESTS${NC}"
echo ""
echo -e "${GREEN}isAdmin Results:${NC}"
echo -e "  Correct: $ISADMIN_PASS / 15"
echo -e "  Incorrect: $ISADMIN_FAIL / 15"
echo ""
echo -e "${GREEN}notAdmin Results:${NC}"
echo -e "  Correct: $NOTADMIN_PASS / 24"
echo -e "  Incorrect: $NOTADMIN_FAIL / 24"
echo ""

TOTAL_PASS=$((ISADMIN_PASS + NOTADMIN_PASS))
TOTAL_FAIL=$((ISADMIN_FAIL + NOTADMIN_FAIL))

if [ $TOTAL_FAIL -eq 0 ]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED${NC} ($TOTAL_PASS/$TOTAL_TESTS)"
    echo -e "${GREEN}Your CSPM tool correctly evaluates all effective permissions!${NC}"
else
    echo -e "${YELLOW}⚠ SOME TESTS FAILED${NC} ($TOTAL_FAIL failed, $TOTAL_PASS passed)"
    echo -e "${YELLOW}Your CSPM tool needs improvement in effective permissions evaluation.${NC}"
fi

echo ""
echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}Admin Definition: You have * on * without any IAM denies${NC}"
echo -e "${CYAN}================================================================${NC}"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
