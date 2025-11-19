#!/bin/bash

# Cleanup script for test-reverse-blast-radius-direct-and-indirect-through-admin
# This script verifies that no persistent artifacts were created during the demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Reverse Blast Radius Test${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${YELLOW}Checking for artifacts...${NC}"
echo "This scenario only involves reading S3 data and assuming roles."
echo "It does not create any persistent artifacts or modify any resources."
echo ""

# Check for temporary files that might have been left behind
TEMP_FILES="/tmp/user1-sensitive-data.txt /tmp/admin-sensitive-data.txt"
FOUND_FILES=false

echo -e "${YELLOW}Checking for temporary files...${NC}"
for file in $TEMP_FILES; do
    if [ -f "$file" ]; then
        echo "  Found: $file"
        rm -f "$file"
        echo -e "  ${GREEN}✓ Removed: $file${NC}"
        FOUND_FILES=true
    fi
done

if [ "$FOUND_FILES" = false ]; then
    echo -e "${GREEN}✓ No temporary files found${NC}"
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- No persistent artifacts were created during the demo"
echo "- No IAM policies were modified"
echo "- No access keys were created"
echo "- No AWS resources were launched"
echo "- Only read operations were performed"
echo ""
echo -e "${GREEN}The environment is in its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, and bucket) remains deployed.${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
