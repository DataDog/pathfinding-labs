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
if ! aws sts get-caller-identity --profile pl-pathfinder-starting-user-dev &> /dev/null; then
    echo -e "${RED}Error: AWS profile 'pl-pathfinder-starting-user-dev' not found${NC}"
    echo "Please configure the profile or run: ./create_pathfinder_profiles.sh"
    exit 1
fi

echo -e "${YELLOW}AWS Profile Configuration:${NC}"
echo "REQUIRED_PROFILE=pl-pathfinder-starting-user-dev"
echo ""

# Get account information
DEV_ACCOUNT_ID=$(aws sts get-caller-identity --profile pl-pathfinder-starting-user-dev --query 'Account' --output text 2>/dev/null || echo "unknown")

echo -e "${YELLOW}Target Information:${NC}"
echo "DEV_ACCOUNT_ID=$DEV_ACCOUNT_ID"
echo "DEV_ROLE_NAME=pl-lambda-prod-updater"
echo "DEV_ROLE_NAME_ARN=arn:aws:iam::${DEV_ACCOUNT_ID}:role/pl-lambda-prod-updater"
echo "DEV_ROLE_ARN=arn:aws:iam::${DEV_ACCOUNT_ID}:role/pl-lambda-prod-updater"
echo ""

echo -e "${BLUE}Attack Path:${NC}"
echo "Cross-account dev → prod: Multi-hop via PassRole and Lambda"
echo "Dev starting user → Lambda prod updater role → Prod Lambda admin"
echo ""

echo -e "${YELLOW}Usage:${NC}"
echo "This scenario requires AWS profile configuration."
echo "Run the demo_attack.sh script which uses AWS profiles."
echo ""
