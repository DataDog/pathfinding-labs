#!/bin/bash

# Cleanup script for gcp-cloudfunctions-002-cloudfunctions-functionsupdate
#
# demo_attack.sh modifies the following Terraform-managed resource out-of-band:
#   1. The victim Cloud Function ("pl-cf002-victim-<resource_suffix>") — its
#      code is replaced with the exfiltration payload. The SA remains unchanged
#      (Terraform-managed). This cleanup restores the function to a benign
#      hello-world handler.
#
# demo_attack.sh also creates the following local artifact:
#   2. Local build artifacts under ./.build/ (malicious function source dir)
#
# All IAM bindings (starting_sa's update/sourceCodeSet/invoke custom role,
# target_sa's roles/editor) are Terraform-managed and are never touched here.
#
# GCP has no equivalent of AWS's force_destroy/force_detach_policies safety
# net — a function left with our malicious code after a failed demo run will
# NOT be automatically restored by `terraform destroy` (destroy removes the
# function; apply recreates it from scratch). This script is the only line of
# defense: every restoration below is checked, and any real failure causes a
# hard exit with a clear error rather than being silently swallowed.
#
# Cleanup uses the admin_cleanup SA from the environment, impersonated via
# the deployer's ADC (same credential model as the demo — no static keys).

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: gcp-cloudfunctions-002-cloudfunctions-functionsupdate${NC}"
echo -e "${GREEN}========================================${NC}\n"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
HELLO_WORLD_DIR="$(mktemp -d)"

# Write the benign hello-world source that Terraform originally deployed.
# We restore to this exact handler so the function is functional again and
# `terraform plan` shows no drift after cleanup.
cat > "$HELLO_WORLD_DIR/main.py" <<'PYEOF'
def hello_world(request):
    return ("Hello, World!", 200, {"Content-Type": "text/plain"})
PYEOF

cat > "$HELLO_WORLD_DIR/requirements.txt" <<'REQEOF'
functions-framework==3.*
REQEOF

echo -e "${YELLOW}Step 1: Getting cleanup identity and scenario config from Terraform${NC}"
cd ../../../../../../../gcp  # scenario dir -> gcp/ (terraform root)

ENV_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.gcp_prod_environment.value // empty')
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | \
    jq -r '.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_002_cloudfunctions_functionsupdate.value // empty')
PROJECT_ID=$(terraform output -raw gcp_project_id 2>/dev/null)

if [ -z "$ENV_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find gcp_prod_environment terraform output${NC}"
    echo "Make sure the prod environment is deployed with: plabs apply"
    exit 1
fi

ADMIN_CLEANUP_SA=$(echo "$ENV_OUTPUT"    | jq -r '.admin_cleanup_service_account_email')
REGION=$(echo "$MODULE_OUTPUT"           | jq -r '.region // empty')
VICTIM_FUNCTION_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.victim_function_name // empty')

cd - > /dev/null

if [ -z "$ADMIN_CLEANUP_SA" ] || [ "$ADMIN_CLEANUP_SA" = "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup SA email in terraform output${NC}"
    exit 1
fi

if [ -z "$REGION" ] || [ "$REGION" = "null" ]; then
    echo -e "${RED}Error: Could not determine region from terraform output${NC}"
    exit 1
fi

if [ -z "$VICTIM_FUNCTION_NAME" ] || [ "$VICTIM_FUNCTION_NAME" = "null" ]; then
    echo -e "${RED}Error: Could not determine victim function name from terraform output${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Cleanup identity: $ADMIN_CLEANUP_SA${NC}"
echo -e "${GREEN}✓ Victim function:  $VICTIM_FUNCTION_NAME${NC}\n"

# Step 2: Restore the victim function to its original hello-world code.
# The function's service account (target_sa) is NOT changed — it was never
# changed by the demo either. We only restore the code.
echo -e "${YELLOW}Step 2: Restoring victim function to original hello-world code${NC}"

FUNCTION_EXISTS=$(gcloud functions describe "$VICTIM_FUNCTION_NAME" \
    --gen2 \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --impersonate-service-account="$ADMIN_CLEANUP_SA" \
    --format="value(name)" 2>/dev/null || true)

if [ -z "$FUNCTION_EXISTS" ]; then
    echo -e "${YELLOW}Note: victim function $VICTIM_FUNCTION_NAME not found — may have been destroyed.${NC}"
    echo -e "${YELLOW}Run 'plabs apply' to redeploy the scenario infrastructure.${NC}"
else
    if gcloud functions deploy "$VICTIM_FUNCTION_NAME" \
            --gen2 \
            --runtime=python312 \
            --region="$REGION" \
            --source="$HELLO_WORLD_DIR" \
            --entry-point=hello_world \
            --trigger-http \
            --no-allow-unauthenticated \
            --impersonate-service-account="$ADMIN_CLEANUP_SA" \
            --quiet 2>/dev/null; then
        echo -e "${GREEN}✓ Restored $VICTIM_FUNCTION_NAME to hello-world handler${NC}"
    else
        echo -e "${RED}✗ Failed to restore function $VICTIM_FUNCTION_NAME — manual cleanup required${NC}"
        echo -e "${RED}  Run: gcloud functions deploy $VICTIM_FUNCTION_NAME --gen2 --runtime=python312 --region=$REGION --source=<hello-world-dir> --entry-point=hello_world${NC}"
        rm -rf "$HELLO_WORLD_DIR"
        exit 1
    fi
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

# Step 4: Remove local build artifacts and hello-world temp dir.
echo -e "${YELLOW}Step 4: Removing local build artifacts${NC}"
rm -rf "$BUILD_DIR"
rm -rf "$HELLO_WORLD_DIR"
rm -f "$SCRIPT_DIR/.demo_active"
echo -e "${GREEN}✓ Removed $BUILD_DIR and temp hello-world source dir${NC}\n"

echo -e "${YELLOW}Step 5: Confirming no out-of-band IAM bindings to revert${NC}"
echo "All escalation bindings are Terraform-managed:"
echo "  - deployer → starting_sa serviceAccountTokenCreator: Terraform-managed"
echo "  - starting_sa cloudfunctions.functions.update/.sourceCodeSet + run.routes.invoke"
echo "    via minimal custom role (the vuln): Terraform-managed"
echo "  - target_sa roles/editor on project: Terraform-managed"
echo -e "${GREEN}✓ No out-of-band IAM bindings to clean up${NC}\n"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}The victim function has been restored to its original hello-world code.${NC}"
echo -e "${YELLOW}Infrastructure remains deployed.${NC}"
echo -e "${YELLOW}To remove all resources, disable the scenario and run: plabs apply${NC}\n"
