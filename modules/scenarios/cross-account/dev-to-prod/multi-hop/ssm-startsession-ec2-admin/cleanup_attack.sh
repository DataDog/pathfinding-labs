#!/bin/bash

# Cleanup script for ssm-startsession-ec2-admin cross-account privilege escalation demo
#
# This demo creates NO persistent AWS artifacts — it only runs a read-only SSM command
# on the EC2 instance and reads an SSM parameter. No IAM policies were attached,
# no access keys were created, and no resources were modified.
#
# The EC2 instance itself is managed by Terraform. To remove all infrastructure,
# disable the scenario flag and run: plabs destroy (or terraform apply)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: SSM SendCommand EC2 Admin Cross-Account${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TERRAFORM_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

cd "$TERRAFORM_ROOT"

ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    echo "Make sure the admin cleanup user is deployed"
    exit 1
fi

if [ -z "$CURRENT_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    CURRENT_REGION="us-east-1"
fi

export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

echo "Region from Terraform: $CURRENT_REGION"
echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

cd "$SCRIPT_DIR"

# Safety restore: ensure helpful permissions deny policy is removed if a previous
# demo run exited early without calling restore_helpful_permissions.
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# Step 2: Confirm no persistent artifacts exist
echo -e "${YELLOW}Step 2: Confirming no demo artifacts require cleanup${NC}"
echo ""
echo "This scenario creates no persistent AWS artifacts during the demo."
echo "The attack only performs the following read-only operations:"
echo "  - sts:AssumeRole to assume the prod pivot role (session expires automatically)"
echo "  - ssm:SendCommand to run a shell script on the EC2 instance"
echo "  - ssm:GetCommandInvocation to retrieve command output"
echo "  - ssm:GetParameter (run inside the instance as the admin role)"
echo ""
echo "No IAM policies were attached, no access keys were created,"
echo "and no resources were modified out-of-band from Terraform."
echo -e "${GREEN}✓ No cleanup required for demo artifacts${NC}\n"

# Step 3: Infrastructure note
echo -e "${YELLOW}Step 3: Infrastructure${NC}"
echo "The following resources remain deployed and are managed by Terraform:"
echo "  - pl-prod-ssm-ec2-pivot-role        (IAM role in prod account)"
echo "  - pl-prod-ssm-ec2-admin-role         (IAM role in prod account)"
echo "  - pl-prod-ssm-ec2-instance-profile   (IAM instance profile in prod account)"
echo "  - pl-prod-ssm-ec2-instance           (EC2 t3.micro in prod account)"
echo "  - /pathfinding-labs/flags/ssm-startsession-ec2-admin-to-admin (SSM parameter)"
echo ""
echo "To remove all infrastructure, set the scenario flag to false and run:"
echo "  plabs disable ssm-startsession-ec2-admin && plabs apply"
echo "  (or: terraform apply after setting enable_cross_account_dev_to_prod_multi_hop_ssm_startsession_ec2_admin = false)"
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- No demo artifacts to remove (scenario is read-only)"
echo "- Helpful permission deny policies restored (if any were applied)"
echo -e "\n${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (roles, instance, SSM parameter) remains deployed.${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply.${NC}\n"

# Remove the demo active marker
rm -f "$(dirname "$0")/.demo_active"
