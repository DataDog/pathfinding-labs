#!/bin/bash

# Prints credentials and target information for the implicit admin access
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
cd "$(dirname "$0")/../../../.."

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_reverse_blast_radius_implicit_admin_access.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")

ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_arn')
ACCOUNT_ID=$(echo "$ADMIN_ROLE_ARN" | cut -d':' -f5)
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_name')
BUCKET_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_arn')

if [ "$ADMIN_ROLE_ARN" == "null" ] || [ -z "$ADMIN_ROLE_ARN" ]; then
    echo -e "${RED}Error: Could not extract values from terraform output${NC}"
    exit 1
fi

print_user() {
    local label="$1"
    local prefix="$2"
    local name arn key secret
    name=$(echo "$MODULE_OUTPUT" | jq -r ".${prefix}_user_name")
    arn=$(echo "$MODULE_OUTPUT" | jq -r ".${prefix}_user_arn")
    key=$(echo "$MODULE_OUTPUT" | jq -r ".${prefix}_user_access_key_id")
    secret=$(echo "$MODULE_OUTPUT" | jq -r ".${prefix}_user_secret_access_key")
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

print_user "Reader user (explicit read)" "reader"
print_user "Writer user (explicit write)" "writer"
print_user "Admin user (implicit access via AdministratorAccess)" "admin"
print_user "No-access user (negative control)" "no_access"

echo -e "${YELLOW}Admin role (implicit access via Action:* Resource:*, trust: ec2.amazonaws.com only):${NC}"
echo "ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_name')"
echo "ROLE_ARN=$ADMIN_ROLE_ARN"
echo ""

echo -e "${YELLOW}Target Bucket:${NC}"
echo "BUCKET_NAME=$BUCKET_NAME"
echo "BUCKET_ARN=$BUCKET_ARN"
echo ""

echo -e "${BLUE}Expected reverse blast radius for the bucket:${NC}"
echo "can_read  = reader-user, admin-user, admin-role"
echo "can_write = writer-user, admin-user, admin-role"
echo "neither   = no-access-user"
echo "Note: admin-user and admin-role have no S3-specific statement; access is implicit."
echo ""
