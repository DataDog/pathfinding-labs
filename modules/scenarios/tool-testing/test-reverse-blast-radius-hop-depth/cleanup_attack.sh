#!/bin/bash

# Cleanup script for test-reverse-blast-radius-hop-depth
# The demo only reads from S3 and assumes roles; nothing in AWS is modified.
# Cleanup removes the local temp file and clears credentials from the environment.

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TERRAFORM_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Reverse Blast Radius Hop Depth${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Safety restore: remove any orphaned restriction policy using admin cleanup creds
echo -e "${YELLOW}Step 1: Safety restore of helpful permissions${NC}"
ADMIN_ACCESS_KEY=$(cd "$TERRAFORM_ROOT" && terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(cd "$TERRAFORM_ROOT" && terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
CURRENT_REGION=$(cd "$TERRAFORM_ROOT" && terraform output -raw aws_region 2>/dev/null || echo "")
if [ -z "$CURRENT_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    CURRENT_REGION="us-east-1"
fi

if [ -n "$ADMIN_ACCESS_KEY" ] && [ "$ADMIN_ACCESS_KEY" != "null" ]; then
    unset AWS_SESSION_TOKEN
    export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
    export AWS_REGION="$CURRENT_REGION"
    source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"
    restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true
    echo -e "${GREEN}✓ Restriction policy check complete${NC}"
else
    echo -e "${YELLOW}Admin cleanup credentials not found; skipping safety restore${NC}"
fi
echo ""

# Step 2: Remove temp files
echo -e "${YELLOW}Step 2: Removing temporary downloaded files${NC}"
if [ -f "/tmp/rbr-hd-sensitive.txt" ]; then
    rm -f /tmp/rbr-hd-sensitive.txt
    echo -e "${GREEN}✓ Removed: /tmp/rbr-hd-sensitive.txt${NC}"
else
    echo -e "${YELLOW}Note: /tmp/rbr-hd-sensitive.txt not found (may already be deleted)${NC}"
fi
echo ""

# Step 3: Clear credentials from the environment
echo -e "${YELLOW}Step 3: Clearing AWS credentials from environment${NC}"
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
echo -e "${GREEN}✓ Credentials cleared${NC}\n"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "  - Temporary files removed"
echo "  - No IAM policies, trust policies, access keys or bucket contents were modified by the demo"
echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo "To remove infrastructure, set the scenario flag to false and run terraform apply"
echo ""

# Clear demo active marker for plabs tracking
rm -f "$SCRIPT_DIR/.demo_active"
