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
cd ../../../../../..

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_sts_assumerole.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
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

# Extract target resources
BUCKET_ACCESS_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_access_role_arn')
TARGET_BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.target_bucket_name')

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
echo "BUCKET_ACCESS_ROLE_ARN=$BUCKET_ACCESS_ROLE_ARN"
echo "TARGET_BUCKET_NAME=$TARGET_BUCKET_NAME"
echo "TARGET_BUCKET_ARN=arn:aws:s3:::$TARGET_BUCKET_NAME"

echo ""

echo -e "${BLUE}Attack Path:${NC}"
echo "Privilege escalation scenario"
echo ""
