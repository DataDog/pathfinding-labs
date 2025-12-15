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

echo -e "${RED}NOTE: This scenario uses AWS profile-based authentication${NC}"
echo -e "${RED}It does not yet have Terraform output integration${NC}\n"

# Check if AWS profile exists
if ! aws sts get-caller-identity --profile pl-pathfinding-starting-user-operations &> /dev/null; then
    echo -e "${RED}Error: AWS profile 'pl-pathfinding-starting-user-operations' not found${NC}"
    echo "Please configure the profile or run: ./create_pathfinding_profiles.sh"
    exit 1
fi

echo -e "${YELLOW}AWS Profile Configuration:${NC}"
echo "REQUIRED_PROFILE=pl-pathfinding-starting-user-operations"
echo ""

# Get account information
OPS_ACCOUNT_ID=$(aws sts get-caller-identity --profile pl-pathfinding-starting-user-operations --query 'Account' --output text 2>/dev/null || echo "unknown")

# Try to get prod account ID
if aws sts get-caller-identity --profile pl-pathfinding-starting-user-prod &> /dev/null 2>&1; then
    PROD_ACCOUNT_ID=$(aws sts get-caller-identity --profile pl-pathfinding-starting-user-prod --query 'Account' --output text 2>/dev/null || echo "unknown")
else
    PROD_ACCOUNT_ID="unknown"
fi

echo -e "${YELLOW}Target Information:${NC}"
echo "OPS_ACCOUNT_ID=$OPS_ACCOUNT_ID"
echo "PROD_ACCOUNT_ID=$PROD_ACCOUNT_ID"
echo "OPS_ROLE_NAME=pl-x-account-ops-role-with-assume-role-star"
echo "OPS_ROLE_NAME_ARN=arn:aws:iam::${ACCOUNT_ID}:role/pl-x-account-ops-role-with-assume-role-star"
echo "OPS_ROLE_ARN=arn:aws:iam::${OPS_ACCOUNT_ID}:role/pl-x-account-ops-role-with-assume-role-star"
echo "PROD_ROLE_1_NAME=pl-x-account-prod-role-trusts-operations"
echo "PROD_ROLE_1_NAME_ARN=arn:aws:iam::${PROD_ACCOUNT_ID}:role/pl-x-account-prod-role-trusts-operations"
echo "PROD_ROLE_2_NAME=pl-x-account-prod-admin-role-trusts-operations"
echo "PROD_ROLE_2_NAME_ARN=arn:aws:iam::${PROD_ACCOUNT_ID}:role/pl-x-account-prod-admin-role-trusts-operations"
echo "PROD_ROLE_3_NAME=pl-x-account-prod-admin-role"
echo "PROD_ROLE_3_NAME_ARN=arn:aws:iam::${PROD_ACCOUNT_ID}:role/pl-x-account-prod-admin-role"
echo ""

echo -e "${BLUE}Attack Path:${NC}"
echo "Cross-account ops → prod: Simple role assumption for privilege escalation"
echo "Ops starting user → Ops role with AssumeRole:* → Prod admin role"
echo ""

echo -e "${YELLOW}Usage:${NC}"
echo "This scenario requires AWS profile configuration."
echo "Run the demo_attack.sh script which uses AWS profiles."
echo ""
