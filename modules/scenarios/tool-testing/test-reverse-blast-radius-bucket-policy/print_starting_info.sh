#!/bin/bash

# Prints credentials and target information for the reverse-blast-radius
# bucket-policy tool-testing scenario.

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

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_reverse_blast_radius_bucket_policy.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")

POLICY_GRANTED_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.policy_granted_role_arn')
ACCOUNT_ID=$(echo "$POLICY_GRANTED_ROLE_ARN" | cut -d':' -f5)
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_name')
BUCKET_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_arn')

if [ "$POLICY_GRANTED_ROLE_ARN" == "null" ] || [ -z "$POLICY_GRANTED_ROLE_ARN" ]; then
    echo -e "${RED}Error: Could not extract values from terraform output${NC}"
    exit 1
fi

# Print a user principal (name/arn/access key/secret) from the grouped output
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

print_user "Starting user (assumes policy-granted-role, 1 hop to bucket)" "starting_user"
print_user "Identity reader (reads via its identity policy)" "identity_reader"
print_user "Denied reader (identity allows, bucket policy Denies its ARN)" "denied_reader"
print_user "Denied admin (AdministratorAccess, bucket policy Denies its ARN)" "denied_admin"

echo -e "${YELLOW}Policy-granted role (NO S3 in identity policy; access via bucket policy only):${NC}"
echo "ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.policy_granted_role_name')"
echo "ROLE_ARN=$POLICY_GRANTED_ROLE_ARN"
echo ""

echo -e "${YELLOW}Target Bucket:${NC}"
echo "BUCKET_NAME=$BUCKET_NAME"
echo "BUCKET_ARN=$BUCKET_ARN"
echo ""

echo -e "${BLUE}Expected reverse blast radius for the bucket (can_read):${NC}"
echo "can_read = policy-granted-role (via bucket policy),"
echo "           identity-reader (via identity policy),"
echo "           starting-user at 1 hop (assumes policy-granted-role)"
echo "NO access = denied-reader (identity allows, bucket policy Denies its ARN)"
echo "           denied-admin  (AdministratorAccess, bucket policy Denies its ARN)"
echo "Note: an explicit bucket-policy Deny overrides an identity-based admin allow,"
echo "      and the bucket policy grant gives the role access with no S3 in its"
echo "      identity policy."
echo ""
