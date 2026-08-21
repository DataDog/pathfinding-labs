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
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.cross_account_dev_to_prod_sts_role_chain_to_admin.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output 'cross_account_dev_to_prod_sts_role_chain_to_admin'${NC}"
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

# Extract ARNs from grouped output
STARTING_USER_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_arn')
DEV_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.dev_role_arn')
PROD_NON_ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.prod_non_admin_role_arn')
PROD_ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.prod_admin_role_arn')
FLAG_SSM_PARAM=$(echo "$MODULE_OUTPUT" | jq -r '.flag_ssm_parameter_name')

DEV_ACCOUNT_ID=$(echo "$STARTING_USER_ARN" | cut -d':' -f5)
PROD_ACCOUNT_ID=$(echo "$PROD_ADMIN_ROLE_ARN" | cut -d':' -f5)

# Navigate back to scenario directory
cd - > /dev/null

# Print the information
echo -e "${YELLOW}Starting User Credentials:${NC}"
echo "AWS_ACCESS_KEY_ID=$STARTING_ACCESS_KEY_ID"
echo "AWS_SECRET_ACCESS_KEY=$STARTING_SECRET_ACCESS_KEY"
echo ""

echo -e "${YELLOW}AWS Configuration:${NC}"
echo "AWS_REGION=$AWS_REGION"
echo "DEV_ACCOUNT_ID=$DEV_ACCOUNT_ID"
echo "PROD_ACCOUNT_ID=$PROD_ACCOUNT_ID"
echo ""

echo -e "${YELLOW}Starting Principal:${NC}"
echo "STARTING_USER=pl-dev-sts-role-chain-starting-user"
echo "STARTING_USER_ARN=$STARTING_USER_ARN"
echo ""

echo -e "${YELLOW}Attack Chain Roles:${NC}"
echo "DEV_ROLE=pl-dev-sts-role-chain-dev-role"
echo "DEV_ROLE_ARN=$DEV_ROLE_ARN"
echo "PROD_NON_ADMIN_ROLE=pl-prod-sts-role-chain-prod-non-admin-role"
echo "PROD_NON_ADMIN_ROLE_ARN=$PROD_NON_ADMIN_ROLE_ARN"
echo "PROD_ADMIN_ROLE=pl-prod-sts-role-chain-prod-admin-role"
echo "PROD_ADMIN_ROLE_ARN=$PROD_ADMIN_ROLE_ARN"
echo ""

echo -e "${YELLOW}CTF Flag:${NC}"
echo "FLAG_SSM_PARAMETER=$FLAG_SSM_PARAM"
echo ""

echo -e "${BLUE}Attack Path:${NC}"
echo "Cross-account multi-hop role chain: dev user -> dev role -> prod non-admin role -> prod admin role"
echo ""
