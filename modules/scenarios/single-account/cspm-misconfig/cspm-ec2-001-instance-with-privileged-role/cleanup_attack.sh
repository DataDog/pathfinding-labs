#!/bin/bash

# Cleanup script for CSPM Misconfiguration: EC2 Instance with Privileged Role
#
# This scenario doesn't create any artifacts during the demo - the SSM session
# is logged but no persistent changes are made. This script exists for
# consistency with other scenarios.

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Source demo permissions library for safety restore
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/lib/demo_permissions.sh"

# Safety: remove any orphaned restriction policies
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}CSPM Misconfiguration Cleanup${NC}"
echo -e "${CYAN}EC2 Instance with Privileged Role${NC}"
echo -e "${CYAN}========================================${NC}\n"

echo -e "${GREEN}✓ No cleanup required${NC}"
echo ""
echo "This scenario's demo uses an SSM session to demonstrate the risk."
echo "No persistent attack artifacts are created."
echo ""
echo -e "${YELLOW}What was logged during the demo:${NC}"
echo "  - SSM session start/end events in CloudTrail"
echo "  - SSM Session Manager logs (if configured)"
echo "  - IMDS access logs on the instance (if CloudWatch agent configured)"
echo ""
echo -e "${YELLOW}To remove the infrastructure:${NC}"
echo "  cd ../../../../.."
echo "  terraform destroy"
echo ""
echo -e "${YELLOW}Or disable this scenario:${NC}"
echo "  Set enable_single_account_cspm_misconfig_cspm_ec2_001_instance_with_privileged_role = false"
echo "  Then run: terraform apply"
echo ""

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
