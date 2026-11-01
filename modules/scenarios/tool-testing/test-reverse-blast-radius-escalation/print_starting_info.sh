#!/bin/bash

# Prints credentials and target information for the escalation-aware
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

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_reverse_blast_radius_escalation.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")

BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_name')
BUCKET_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_arn')
BUCKET_READER_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_reader_arn')
ACCOUNT_ID=$(echo "$BUCKET_READER_ARN" | cut -d':' -f5)

if [ "$BUCKET_NAME" == "null" ] || [ -z "$BUCKET_NAME" ]; then
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

print_user "bucket-reader (reads the bucket directly -> direct)"                     "bucket_reader"
print_user "cak-user (iam:CreateAccessKey on bucket-reader -> escalate)"             "cak_user"
print_user "attach-self-user (iam:AttachUserPolicy on self -> attach admin, read)"   "attach_self_user"

echo -e "${YELLOW}Target Bucket:${NC}"
echo "BUCKET_NAME=$BUCKET_NAME"
echo "BUCKET_ARN=$BUCKET_ARN"
echo ""

echo -e "${BLUE}Expected reverse blast radius for the bucket:${NC}"
echo "direct reader                = bucket-reader"
echo "reachable via escalation too = cak-user, attach-self-user"
echo "Note: cak-user and attach-self-user have NO S3 permission of their own;"
echo "      an escalation-aware query must still include them."
echo ""
echo -e "${RED}Note: the demo for this scenario performs REAL escalation.${NC}"
echo -e "${RED}Always run ./cleanup_attack.sh afterward.${NC}"
echo ""
