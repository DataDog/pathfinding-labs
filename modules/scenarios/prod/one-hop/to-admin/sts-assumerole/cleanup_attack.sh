#!/bin/bash

# Cleanup script for sts:AssumeRole to admin demo
# Since this scenario only involves role assumption, there are no artifacts to clean up

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}STS AssumeRole Demo Cleanup${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${YELLOW}Note:${NC} The sts:AssumeRole scenario creates no artifacts"
echo ""
echo "This attack only involves:"
echo "  - Assuming an existing role with admin permissions"
echo "  - Using temporary session credentials"
echo ""
echo "The temporary credentials from the assumed role session will:"
echo "  - Expire automatically (typically after 1 hour)"
echo "  - Cannot be manually revoked (they're temporary)"
echo ""
echo -e "${GREEN}✓ No cleanup necessary${NC}"
echo ""
echo -e "${YELLOW}Infrastructure status:${NC}"
echo "  - The admin role remains deployed (as designed)"
echo "  - No inline policies were added"
echo "  - No access keys were created"
echo "  - No trust policies were modified"
echo ""
echo -e "${YELLOW}To remove the infrastructure:${NC}"
echo "  Set the scenario flag to false in terraform.tfvars"
echo "  Run: terraform apply"
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup Check Complete${NC}"
echo -e "${GREEN}========================================${NC}"