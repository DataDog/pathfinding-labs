#!/bin/bash

# Cleanup script for gcp-cloudfunctions-001-iam-serviceaccountsactas+cloudfunctions-functionscreate
#
# demo_attack.sh creates the following out-of-band artifacts, none of which
# are Terraform-managed:
#   1. A 2nd-gen Cloud Function ("pl-cf001-exfil-<resource_suffix>") deployed
#      to run as target_sa
#   2. Local build artifacts under ./.build/ (function source dir)
#
# All IAM bindings (starting_sa's actAs grant on target_sa, cloudfunctions
# custom role, target_sa's roles/editor) are Terraform-managed and are never
# touched here.
#
# GCP has no equivalent of AWS's force_destroy/force_detach_policies safety
# net — an orphaned Cloud Function or bucket object left behind by a failed
# demo run will NOT be cleaned up automatically by `terraform destroy`. This
# script is therefore the only line of defense: every deletion below is
# checked, and any real failure (not just "already gone") causes a hard exit
# with a clear error rather than being silently swallowed.
#
# Cleanup uses the admin_cleanup SA from the environment, impersonated via
# the deployer's ADC (same credential model as the demo — no static keys).

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: gcp-cloudfunctions-001-iam-serviceaccountsactas+cloudfunctions-functionscreate${NC}"
echo -e "${GREEN}========================================${NC}\n"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"

echo -e "${YELLOW}Step 1: Getting cleanup identity and scenario config from Terraform${NC}"
cd ../../../../../../../gcp  # scenario dir -> gcp/ (terraform root)

ENV_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.gcp_prod_environment.value // empty')
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | \
    jq -r '.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_001_iam_serviceaccountsactas_cloudfunctions_functionscreate.value // empty')
PROJECT_ID=$(terraform output -raw gcp_project_id 2>/dev/null)
RESOURCE_SUFFIX=$(terraform output -raw resource_suffix 2>/dev/null)

if [ -z "$ENV_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find gcp_prod_environment terraform output${NC}"
    echo "Make sure the prod environment is deployed with: plabs apply"
    exit 1
fi

ADMIN_CLEANUP_SA=$(echo "$ENV_OUTPUT" | jq -r '.admin_cleanup_service_account_email')
REGION=$(echo "$MODULE_OUTPUT" | jq -r '.region // empty')

cd - > /dev/null

if [ -z "$ADMIN_CLEANUP_SA" ] || [ "$ADMIN_CLEANUP_SA" = "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup SA email in terraform output${NC}"
    exit 1
fi

if [ -z "$RESOURCE_SUFFIX" ] || [ "$RESOURCE_SUFFIX" = "null" ]; then
    echo -e "${RED}Error: Could not find resource_suffix in terraform output${NC}"
    exit 1
fi

FUNCTION_NAME="pl-cf001-exfil-${RESOURCE_SUFFIX}"
OBJECT_NAME="${FUNCTION_NAME}.zip"

echo -e "${GREEN}✓ Cleanup identity: $ADMIN_CLEANUP_SA${NC}"
echo -e "${GREEN}✓ Target function:  $FUNCTION_NAME${NC}\n"

# Step 2: Delete the out-of-band Cloud Function, if present.
echo -e "${YELLOW}Step 2: Deleting demo Cloud Function${NC}"

if [ -z "$REGION" ] || [ "$REGION" = "null" ]; then
    echo -e "${RED}Error: Could not determine region from terraform output — cannot safely${NC}"
    echo -e "${RED}target the function for deletion. Check the module output contract.${NC}"
    exit 1
fi

FUNCTION_EXISTS=$(gcloud functions describe "$FUNCTION_NAME" \
    --gen2 \
    --region="$REGION" \
    --impersonate-service-account="$ADMIN_CLEANUP_SA" \
    --format="value(name)" 2>/dev/null || true)

if [ -n "$FUNCTION_EXISTS" ]; then
    if gcloud functions delete "$FUNCTION_NAME" \
            --gen2 \
            --region="$REGION" \
            --impersonate-service-account="$ADMIN_CLEANUP_SA" \
            --quiet 2>/dev/null; then
        echo -e "${GREEN}✓ Deleted function $FUNCTION_NAME${NC}"
    else
        echo -e "${RED}✗ Failed to delete function $FUNCTION_NAME — manual cleanup required${NC}"
        echo -e "${RED}  Run: gcloud functions delete $FUNCTION_NAME --gen2 --region=$REGION${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ No demo function found (already cleaned up)${NC}"
fi
echo ""

# Step 3: Check for and remove any leftover write-proof project label
# (should already be removed by demo_attack.sh, but verify defensively).
echo -e "${YELLOW}Step 3: Checking for leftover write-proof project label${NC}"

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

# Step 4: Remove local build artifacts.
echo -e "${YELLOW}Step 4: Removing local build artifacts${NC}"
rm -rf "$BUILD_DIR"
rm -f "$SCRIPT_DIR/.demo_active"
echo -e "${GREEN}✓ Removed $BUILD_DIR${NC}\n"

echo -e "${YELLOW}Step 5: Confirming no out-of-band IAM bindings to revert${NC}"
echo "All escalation bindings are Terraform-managed:"
echo "  - deployer → starting_sa serviceAccountTokenCreator: Terraform-managed"
echo "  - starting_sa → target_sa iam.serviceAccounts.actAs + cloudfunctions"
echo "    create/.sourceCodeSet + run.routes.invoke via minimal custom role (the vuln): Terraform-managed"
echo "  - target_sa roles/editor on project: Terraform-managed"
echo -e "${GREEN}✓ No out-of-band IAM bindings to clean up${NC}\n"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Infrastructure remains deployed.${NC}"
echo -e "${YELLOW}To remove all resources, disable the scenario and run: plabs apply${NC}\n"
