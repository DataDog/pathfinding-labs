#!/usr/bin/env bash

# Cleanup script for sts-role-chain cross-account privilege escalation demo
#
# This scenario is pure sts:AssumeRole — the demo does not modify any IAM policies,
# create access keys, attach managed policies, or change any infrastructure state.
# All assumed-role sessions expire automatically (typically within 1 hour).
#
# There are no out-of-band artifacts to reverse. The Terraform resources themselves
# (users, roles, SSM parameter) are removed by `terraform destroy` or by disabling
# the scenario and running `terraform apply`.

set -euo pipefail

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Dev-to-Prod STS Role Chain${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Safety restore: ensure helpful permissions deny policy is removed
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

echo -e "${YELLOW}Checking for demo artifacts...${NC}"
echo ""
echo "This scenario uses only sts:AssumeRole — no IAM policies were modified,"
echo "no access keys were created, and no infrastructure state was changed."
echo "Assumed-role sessions expire automatically."
echo ""
echo -e "${GREEN}✓ No cleanup required${NC}"
echo ""

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- No persistent artifacts were created by the demo"
echo "- All assumed-role sessions have expired or will expire automatically"
echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed.${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply.${NC}\n"
