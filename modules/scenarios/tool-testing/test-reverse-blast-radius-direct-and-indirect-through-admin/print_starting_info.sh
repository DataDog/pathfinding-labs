#!/bin/bash

# Script to print starting information for Pathrunner exploitation tool
# This extracts credentials and target information needed to run the attack

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Pathrunner Starting Information${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Navigate to root of terraform project
cd ../../

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_reverse_blast_radius_direct_and_indirect_through_admin.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.user1_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

# Get region
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")

# Get account ID for constructing ARNs
STARTING_USER_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_arn')
ACCOUNT_ID=$(echo "$STARTING_USER_ARN" | cut -d':' -f5)

# Navigate back to scenario directory
cd - > /dev/null

# Print the information
echo -e "${YELLOW}Starting User Credentials:${NC}"
echo "AWS_ACCESS_KEY_ID=$STARTING_ACCESS_KEY_ID"
echo "AWS_SECRET_ACCESS_KEY=$STARTING_SECRET_ACCESS_KEY"
echo ""

echo -e "${YELLOW}AWS Configuration:${NC}"
echo "AWS_REGION=$AWS_REGION"
echo "ACCOUNT_ID=$ACCOUNT_ID"
echo ""

echo -e "${YELLOW}Target Information:${NC}"
echo "USER1_NAME=pl-prod-rbr-admin-user1"
echo "USER1_NAME_ARN=arn:aws:iam::${ACCOUNT_ID}:user/pl-prod-rbr-admin-user1"
echo "USER2_NAME=pl-prod-rbr-admin-user2"
echo "USER2_NAME_ARN=arn:aws:iam::${ACCOUNT_ID}:user/pl-prod-rbr-admin-user2"
echo "ROLE3_NAME=pl-prod-rbr-admin-role3"
echo "ROLE3_NAME_ARN=arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-rbr-admin-role3"

echo ""

echo -e "${BLUE}Attack Path:${NC}"
echo "Tool testing scenario for CSPM detection validation"
echo ""
