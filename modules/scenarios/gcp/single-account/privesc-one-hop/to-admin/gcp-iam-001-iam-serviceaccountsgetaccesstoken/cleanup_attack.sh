#!/bin/bash

# Cleanup script for gcp-iam-001-iam-serviceaccountsgetaccesstoken.
#
# All IAM bindings (starting_sa → target_sa getAccessToken grant via a minimal
# custom role, target_sa roles/editor) are Terraform-managed and not touched
# by the demo.
# The only out-of-band artifact demo_attack.sh creates is a temporary project
# label (pl-privesc-verified), which it removes immediately after proving
# editor access. This script checks for any leftover label and removes it.
#
# Cleanup uses the admin_cleanup SA from the environment, impersonated via
# the deployer's ADC (same credential model as the demo — no static keys).

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: gcp-iam-001-iam-serviceaccountsgetaccesstoken${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${YELLOW}Step 1: Getting cleanup identity from Terraform${NC}"
cd ../../../../../../../gcp  # scenario dir -> gcp/ (terraform root)

ENV_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.gcp_prod_environment.value // empty')
PROJECT_ID=$(terraform output -raw gcp_project_id 2>/dev/null)

if [ -z "$ENV_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find gcp_prod_environment terraform output${NC}"
    echo "Make sure the prod environment is deployed with: plabs apply"
    exit 1
fi

ADMIN_CLEANUP_SA=$(echo "$ENV_OUTPUT" | jq -r '.admin_cleanup_service_account_email')
cd - > /dev/null

if [ -z "$ADMIN_CLEANUP_SA" ] || [ "$ADMIN_CLEANUP_SA" = "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup SA email in terraform output${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Cleanup identity: $ADMIN_CLEANUP_SA${NC}\n"

echo -e "${YELLOW}Step 2: Checking for leftover demo artifacts${NC}"

# Check for leftover project label from the editor write-proof step
LEFTOVER_LABEL=$(gcloud projects describe "$PROJECT_ID" \
    --impersonate-service-account="$ADMIN_CLEANUP_SA" \
    --format="value(labels.pl-privesc-verified)" 2>/dev/null || true)

if [ -n "$LEFTOVER_LABEL" ]; then
    echo "Found leftover pl-privesc-verified label, removing it..."
    gcloud projects update "$PROJECT_ID" \
        --remove-labels=pl-privesc-verified \
        --impersonate-service-account="$ADMIN_CLEANUP_SA" \
        --quiet 2>/dev/null || true
    echo -e "${GREEN}✓ Removed leftover label${NC}"
else
    echo -e "${GREEN}✓ No leftover project labels found${NC}"
fi
echo ""

echo -e "${YELLOW}Step 3: Confirming no out-of-band IAM bindings to revert${NC}"
echo "All escalation bindings are Terraform-managed:"
echo "  - deployer → starting_sa serviceAccountTokenCreator: Terraform-managed"
echo "  - starting_sa → target_sa getAccessToken via minimal custom role (the vuln): Terraform-managed"
echo "  - target_sa roles/editor on project: Terraform-managed"
echo "demo_attack.sh creates no persistent IAM changes."
echo -e "${GREEN}✓ No out-of-band artifacts to clean up${NC}\n"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
rm -f "$SCRIPT_DIR/.demo_active"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Infrastructure remains deployed.${NC}"
echo -e "${YELLOW}To remove all resources, disable the scenario and run: plabs apply${NC}\n"
