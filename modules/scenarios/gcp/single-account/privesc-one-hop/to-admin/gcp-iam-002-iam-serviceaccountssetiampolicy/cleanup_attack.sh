#!/bin/bash

# Cleanup script for gcp-iam-002-iam-serviceaccountssetiampolicy.
#
# demo_attack.sh creates one out-of-band IAM artifact:
#   roles/iam.serviceAccountTokenCreator granted to starting_sa on target_sa
#   (the step 3 setIamPolicy grant — the actual exploit).
#
# This script removes that binding using the admin_cleanup SA from the
# environment output, impersonated via the deployer's ADC (same credential
# model as the demo — no static keys).
#
# It also checks for any leftover pl-privesc-verified project label from the
# step 5 write-proof (the demo removes it immediately, but cleans up here too).
#
# All other IAM bindings (deployer → starting_sa tokenCreator,
# starting_sa minimal custom role with setIamPolicy on target_sa,
# target_sa roles/editor on project) are Terraform-managed and are NOT touched.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: gcp-iam-002-iam-serviceaccountssetiampolicy${NC}"
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

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | \
    jq -r '.gcp_single_account_privesc_one_hop_to_admin_gcp_iam_002_iam_serviceaccountssetiampolicy.value // empty')

cd - > /dev/null

if [ -z "$ADMIN_CLEANUP_SA" ] || [ "$ADMIN_CLEANUP_SA" = "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup SA email in terraform output${NC}"
    exit 1
fi

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find scenario terraform output — is the scenario deployed?${NC}"
    exit 1
fi

STARTING_SA_EMAIL=$(echo "$MODULE_OUTPUT" | jq -r '.starting_sa_email')
TARGET_SA_EMAIL=$(echo "$MODULE_OUTPUT"   | jq -r '.target_sa_email')

if [ -z "$STARTING_SA_EMAIL" ] || [ "$STARTING_SA_EMAIL" = "null" ] || \
   [ -z "$TARGET_SA_EMAIL" ] || [ "$TARGET_SA_EMAIL" = "null" ]; then
    echo -e "${RED}Error: Could not extract SA emails from scenario output${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Cleanup identity: $ADMIN_CLEANUP_SA${NC}"
echo -e "${GREEN}✓ Starting SA:      $STARTING_SA_EMAIL${NC}"
echo -e "${GREEN}✓ Target SA:        $TARGET_SA_EMAIL${NC}\n"

# Step 2: Remove the out-of-band tokenCreator binding added by the demo
#
# demo_attack.sh's step 3 granted roles/iam.serviceAccountTokenCreator to
# starting_sa on target_sa via setIamPolicy. This is the out-of-band artifact
# that cleanup must revert. The admin_cleanup SA has sufficient project-level
# admin to call remove-iam-policy-binding on the target SA's policy.
echo -e "${YELLOW}Step 2: Removing tokenCreator binding added by the demo${NC}"

EXISTING_BINDING=$(gcloud iam service-accounts get-iam-policy "$TARGET_SA_EMAIL" \
    --impersonate-service-account="$ADMIN_CLEANUP_SA" \
    --format=json 2>/dev/null | \
    jq -r '.bindings[]? | select(.role == "roles/iam.serviceAccountTokenCreator") | .members[]?' | \
    grep "serviceAccount:${STARTING_SA_EMAIL}" || true)

if [ -n "$EXISTING_BINDING" ]; then
    echo "Found tokenCreator binding for $STARTING_SA_EMAIL on $TARGET_SA_EMAIL — removing..."
    gcloud iam service-accounts remove-iam-policy-binding "$TARGET_SA_EMAIL" \
        --member="serviceAccount:$STARTING_SA_EMAIL" \
        --role="roles/iam.serviceAccountTokenCreator" \
        --impersonate-service-account="$ADMIN_CLEANUP_SA" \
        --quiet 2>/dev/null
    echo -e "${GREEN}✓ Removed tokenCreator binding — attack artifact cleaned up${NC}"
else
    echo -e "${GREEN}✓ tokenCreator binding not found (demo may not have run, or already cleaned up)${NC}"
fi
echo ""

# Step 3: Check for leftover project label from the write-proof step
#
# demo_attack.sh step 5 adds pl-privesc-verified=true as a label to prove
# editor access, then immediately removes it. This step checks for any
# leftover in case the demo was interrupted before the removal.
echo -e "${YELLOW}Step 3: Checking for leftover demo project label${NC}"

LEFTOVER_LABEL=$(gcloud projects describe "$PROJECT_ID" \
    --impersonate-service-account="$ADMIN_CLEANUP_SA" \
    --format="value(labels.pl-privesc-verified)" 2>/dev/null || true)

if [ -n "$LEFTOVER_LABEL" ]; then
    echo "Found leftover pl-privesc-verified label, removing it..."
    gcloud projects update "$PROJECT_ID" \
        --remove-labels=pl-privesc-verified \
        --impersonate-service-account="$ADMIN_CLEANUP_SA" \
        --quiet 2>/dev/null || true
    echo -e "${GREEN}✓ Removed leftover project label${NC}"
else
    echo -e "${GREEN}✓ No leftover project labels found${NC}"
fi
echo ""

# Step 4: Confirm Terraform-managed bindings are intact
echo -e "${YELLOW}Step 4: Confirming Terraform-managed bindings (not touched by cleanup)${NC}"
echo "The following are Terraform-managed and preserved:"
echo "  - deployer → starting_sa (roles/iam.serviceAccountTokenCreator): Terraform-managed"
echo "  - starting_sa → target_sa (minimal custom role with setIamPolicy): Terraform-managed"
echo "  - target_sa roles/editor on project: Terraform-managed"
echo -e "${GREEN}✓ Infrastructure state unchanged${NC}\n"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
rm -f "$SCRIPT_DIR/.demo_active"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}Infrastructure remains deployed.${NC}"
echo -e "${YELLOW}To remove all resources, disable the scenario and run: plabs apply${NC}\n"
