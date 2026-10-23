#!/bin/bash

# Cleanup script for test-reverse-blast-radius-identity-side-block
# This demo makes no lasting AWS changes (no IAM mutations, no objects written).
# Cleanup only removes the local demo marker file.

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Reverse Blast Radius Identity-Side Access Blocks${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Safety restore: ensure any helpful-permission deny policy is removed (no-op here).
# Uses admin cleanup credentials from Terraform (never an AWS profile).
echo -e "${YELLOW}Step 1: Safety restore of helpful permissions (no-op for this scenario)${NC}"
cd ../../../..  # Navigate to root of terraform project
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")
if [ -z "$CURRENT_REGION" ]; then
    CURRENT_REGION="us-east-1"
fi
cd - > /dev/null

if [ -n "$ADMIN_ACCESS_KEY" ] && [ "$ADMIN_ACCESS_KEY" != "null" ]; then
    export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
    export AWS_REGION="$CURRENT_REGION"
    unset AWS_SESSION_TOKEN
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true
echo -e "${GREEN}✓ Done${NC}\n"

# Step 2: Remove local demo marker
echo -e "${YELLOW}Step 2: Removing local demo marker${NC}"
rm -f "$SCRIPT_DIR/.demo_active"
echo -e "${GREEN}✓ Removed .demo_active (if present)${NC}\n"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- This demo only attempted bucket reads; no IAM or S3 changes were made"
echo "- Removed local marker file .demo_active (if present)"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and bucket) remains deployed.${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
