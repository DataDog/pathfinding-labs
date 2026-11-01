#!/bin/bash

# Prints credentials and target information for the assume-role-edge
# reverse blast radius tool-testing scenario.

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Starting Information${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Navigate to root of terraform project (scenario dir is 4 levels deep)
cd "$(dirname "${BASH_SOURCE[0]}")/../../../.."

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_reverse_blast_radius_assume_role_edges.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")

TARGET_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.target_role_arn')
TARGET_ROLE_ROOT_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.target_role_root_arn')
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_name')
BUCKET_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_arn')
ACCOUNT_ID=$(echo "$TARGET_ROLE_ARN" | cut -d':' -f5)

if [ "$TARGET_ROLE_ARN" == "null" ] || [ -z "$TARGET_ROLE_ARN" ]; then
    echo -e "${RED}Error: Could not extract values from terraform output${NC}"
    exit 1
fi

print_user() {
    local label="$1"
    local prefix="$2"
    local name arn key secret
    name=$(echo "$MODULE_OUTPUT" | jq -r ".${prefix}_name")
    arn=$(echo "$MODULE_OUTPUT" | jq -r ".${prefix}_arn")
    key=$(echo "$MODULE_OUTPUT" | jq -r ".${prefix}_access_key_id")
    secret=$(echo "$MODULE_OUTPUT" | jq -r ".${prefix}_secret_access_key")
    echo -e "${YELLOW}${label}:${NC}"
    echo "USER_NAME=$name"
    echo "USER_ARN=$arn"
    echo "AWS_ACCESS_KEY_ID=$key"
    echo "AWS_SECRET_ACCESS_KEY=$secret"
    echo ""
}

echo -e "${YELLOW}AWS Configuration:${NC}"
echo "AWS_REGION=$AWS_REGION"
echo "ACCOUNT_ID=$ACCOUNT_ID"
echo ""

print_user "are-both (identity AssumeRole + explicit trust -> CAN)"             "are_both"
print_user "are-identity-only (identity AssumeRole, trust excludes -> CANNOT)"  "are_identity_only"
print_user "are-trust-only (trust names it, no identity AssumeRole -> CANNOT)"  "are_trust_only"
print_user "are-root-with-identity (identity AssumeRole + root trust -> CAN)"   "are_root_with_identity"
print_user "are-root-no-identity (root trust, identity silent -> CANNOT)"       "are_root_no_identity"

echo -e "${YELLOW}Target roles (read the bucket):${NC}"
echo "TARGET_ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.target_role_name')"
echo "TARGET_ROLE_ARN=$TARGET_ROLE_ARN"
echo "TARGET_ROLE_ROOT_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.target_role_root_name')"
echo "TARGET_ROLE_ROOT_ARN=$TARGET_ROLE_ROOT_ARN"
echo ""

echo -e "${YELLOW}Target Bucket:${NC}"
echo "BUCKET_NAME=$BUCKET_NAME"
echo "BUCKET_ARN=$BUCKET_ARN"
echo ""

echo -e "${BLUE}Expected reverse blast radius for the bucket (one assume-role hop):${NC}"
echo "can_reach = are-both, are-root-with-identity"
echo "cannot    = are-identity-only, are-trust-only, are-root-no-identity"
echo "Note: a same-account AssumeRole needs BOTH an identity permission AND trust;"
echo "      a role trusting the account root defers entirely to identity policies."
echo ""
