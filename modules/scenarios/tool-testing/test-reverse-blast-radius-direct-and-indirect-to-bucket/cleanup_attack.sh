#!/bin/bash

# Cleanup script for test-reverse-blast-radius-direct-and-indirect-to-bucket
# This script removes temporary files created during the demonstration
# No IAM modifications or resource changes were made, so minimal cleanup is needed


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Source demo permissions library for safety restore
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"

# Safety: remove any orphaned restriction policies
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Reverse Blast Radius Test${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo "This scenario only reads data from S3 and does not modify any resources."
echo "Cleanup will remove temporary downloaded files only."
echo ""

# Step 1: Remove temporary files
echo -e "${YELLOW}Step 1: Removing temporary downloaded files${NC}"

FILES_REMOVED=0
FILES_NOT_FOUND=0

# Check and remove file downloaded by user1
if [ -f "/tmp/sensitive-user1.txt" ]; then
    rm -f /tmp/sensitive-user1.txt
    echo -e "${GREEN}✓ Removed: /tmp/sensitive-user1.txt${NC}"
    FILES_REMOVED=$((FILES_REMOVED + 1))
else
    echo -e "${YELLOW}Note: /tmp/sensitive-user1.txt not found (may already be deleted)${NC}"
    FILES_NOT_FOUND=$((FILES_NOT_FOUND + 1))
fi

# Check and remove file downloaded by role3
if [ -f "/tmp/sensitive-role3.txt" ]; then
    rm -f /tmp/sensitive-role3.txt
    echo -e "${GREEN}✓ Removed: /tmp/sensitive-role3.txt${NC}"
    FILES_REMOVED=$((FILES_REMOVED + 1))
else
    echo -e "${YELLOW}Note: /tmp/sensitive-role3.txt not found (may already be deleted)${NC}"
    FILES_NOT_FOUND=$((FILES_NOT_FOUND + 1))
fi

echo ""

# Step 2: Verify no other artifacts exist
echo -e "${YELLOW}Step 2: Verifying no other artifacts exist${NC}"

# Check for any other sensitive files that might have been created
OTHER_FILES=$(find /tmp -name "sensitive-*.txt" -type f 2>/dev/null | grep -v "sensitive-user1.txt" | grep -v "sensitive-role3.txt" || true)

if [ -n "$OTHER_FILES" ]; then
    echo -e "${YELLOW}Warning: Found other sensitive files in /tmp:${NC}"
    echo "$OTHER_FILES"
    echo ""
    echo "These files were not created by this demo and will not be removed."
else
    echo -e "${GREEN}✓ No other sensitive files found in /tmp${NC}"
fi

echo ""

# Final summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Summary:${NC}"
echo "  - Temporary files removed: $FILES_REMOVED"
if [ $FILES_NOT_FOUND -gt 0 ]; then
    echo "  - Files already deleted: $FILES_NOT_FOUND"
fi
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo ""
echo -e "${YELLOW}Note:${NC} This scenario is read-only and does not modify:"
echo "  - IAM policies"
echo "  - S3 bucket contents"
echo "  - Access keys"
echo "  - Trust policies"
echo ""
echo "All infrastructure remains deployed and unchanged."
echo "To remove infrastructure, set the scenario flag to false and run terraform apply"
echo ""

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
