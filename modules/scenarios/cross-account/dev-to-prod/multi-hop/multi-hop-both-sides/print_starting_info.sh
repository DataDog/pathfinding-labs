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

# Check if AWS profile exists or use current credentials
if aws sts get-caller-identity --profile pl-pathfinding-starting-user-dev &> /dev/null 2>&1; then
    PROFILE_OPTION="--profile pl-pathfinding-starting-user-dev"
    echo -e "${YELLOW}AWS Profile Configuration:${NC}"
    echo "REQUIRED_PROFILE=pl-pathfinding-starting-user-dev"
else
    PROFILE_OPTION=""
    echo -e "${YELLOW}Using current AWS credentials${NC}"
fi
echo ""

# Get account information
DEV_ACCOUNT_ID=$(aws sts get-caller-identity $PROFILE_OPTION --query 'Account' --output text 2>/dev/null || echo "unknown")

echo -e "${YELLOW}Target Information:${NC}"
echo "DEV_ACCOUNT_ID=$DEV_ACCOUNT_ID"
echo "STARTING_USER=pl-pathfinding-starting-user-dev"
echo "DEV_HELPDESK_ROLE=pl-dev-helpdesk-role"
echo "DEV_HELPDESK_ROLE_ARN=arn:aws:iam::${DEV_ACCOUNT_ID}:role/pl-dev-helpdesk-role"
echo ""

echo -e "${BLUE}Attack Path:${NC}"
echo "Cross-account dev → prod: Multi-hop privilege escalation through both accounts"
echo "Dev user → Manipulate login profiles → Cross-account role → Prod admin"
echo ""

echo -e "${YELLOW}Usage:${NC}"
echo "This scenario requires AWS profile configuration or current credentials."
echo "Run the demo_attack.sh script which uses AWS profiles."
echo ""
