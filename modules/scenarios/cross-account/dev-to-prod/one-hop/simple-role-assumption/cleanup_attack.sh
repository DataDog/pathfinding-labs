#!/bin/bash

# Cleanup script for cross-account simple-role-assumption privilege escalation demo
# This script verifies no persistent artifacts were created

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Cross-Account Simple Role Assumption${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${YELLOW}Checking for artifacts...${NC}"
echo "This scenario only performs role assumption and does not create any persistent artifacts."
echo ""

echo -e "${BLUE}ℹ What this scenario does:${NC}"
echo "- Assumes a role across accounts using sts:AssumeRole"
echo "- Creates temporary session credentials (AccessKeyId, SecretAccessKey, SessionToken)"
echo "- These temporary credentials expire automatically"
echo ""

echo -e "${BLUE}ℹ What this scenario does NOT do:${NC}"
echo "- No IAM policies are created or modified"
echo "- No access keys are created for IAM users"
echo "- No trust policies are changed"
echo "- No resources are deployed during the demo"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ NO CLEANUP REQUIRED${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- No persistent artifacts were created during the demo"
echo "- Temporary session credentials from role assumption expire automatically"
echo "- The infrastructure (IAM users and roles) remains deployed"

echo -e "\n${YELLOW}Infrastructure Status:${NC}"
echo "- Dev starting user: Still exists (deployed by Terraform)"
echo "- Prod target role: Still exists (deployed by Terraform)"
echo "- Trust relationship: Unchanged"

echo -e "\n${GREEN}The environment is already in its original state.${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
