#!/bin/bash

# Prints starting information for the hop-depth reverse blast radius scenario.
# All five principals are listed with the hop depth they are expected to have.

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Pathrunner Starting Information${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Navigate to root of terraform project (resolved from this script's location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/../../../.."

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_reverse_blast_radius_hop_depth.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

USER_A_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.user_a_access_key_id')
USER_A_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.user_a_secret_access_key')
USER_B_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.user_b_access_key_id')
USER_B_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.user_b_secret_access_key')
USER_C_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.user_c_access_key_id')
USER_C_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.user_c_secret_access_key')

if [ "$USER_A_ACCESS_KEY_ID" == "null" ] || [ -z "$USER_A_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")

USER_A_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.user_a_arn')
USER_B_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.user_b_arn')
USER_C_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.user_c_arn')
ROLE_R1_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.role_r1_arn')
ROLE_R2_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.role_r2_arn')
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_name')
BUCKET_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_arn')
ACCOUNT_ID=$(echo "$USER_A_ARN" | cut -d':' -f5)

cd - > /dev/null

echo -e "${YELLOW}AWS Configuration:${NC}"
echo "AWS_REGION=$AWS_REGION"
echo "ACCOUNT_ID=$ACCOUNT_ID"
echo ""

echo -e "${YELLOW}user-a credentials (depth 0):${NC}"
echo "AWS_ACCESS_KEY_ID=$USER_A_ACCESS_KEY_ID"
echo "AWS_SECRET_ACCESS_KEY=$USER_A_SECRET_ACCESS_KEY"
echo ""
echo -e "${YELLOW}user-b credentials (depth 1):${NC}"
echo "AWS_ACCESS_KEY_ID=$USER_B_ACCESS_KEY_ID"
echo "AWS_SECRET_ACCESS_KEY=$USER_B_SECRET_ACCESS_KEY"
echo ""
echo -e "${YELLOW}user-c credentials (depth 2):${NC}"
echo "AWS_ACCESS_KEY_ID=$USER_C_ACCESS_KEY_ID"
echo "AWS_SECRET_ACCESS_KEY=$USER_C_SECRET_ACCESS_KEY"
echo ""

echo -e "${YELLOW}Target Information:${NC}"
echo "USER_A_ARN=$USER_A_ARN (depth 0, direct S3 permissions)"
echo "ROLE_R1_ARN=$ROLE_R1_ARN (depth 0, direct S3 permissions)"
echo "USER_B_ARN=$USER_B_ARN (depth 1, assumes role-r1)"
echo "ROLE_R2_ARN=$ROLE_R2_ARN (depth 1, assumes role-r1)"
echo "USER_C_ARN=$USER_C_ARN (depth 2, assumes role-r2 which assumes role-r1)"
echo "BUCKET_NAME=$BUCKET_NAME"
echo "BUCKET_ARN=$BUCKET_ARN"
echo ""

echo -e "${BLUE}Expected reverse blast radius for the bucket:${NC}"
echo "  Exactly 0 hops: user-a, role-r1"
echo "  Exactly 1 hop:  user-b, role-r2"
echo "  Exactly 2 hops: user-c"
echo "Tool testing scenario for CSPM detection validation"
echo ""
