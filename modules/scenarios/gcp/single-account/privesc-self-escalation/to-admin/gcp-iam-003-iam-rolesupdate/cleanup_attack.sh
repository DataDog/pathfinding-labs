#!/bin/bash

# Cleanup script for gcp-iam-003-iam-rolesupdate.
#
# demo_attack.sh creates two out-of-band IAM mutations that this script must
# reverse — both bypass Terraform and are therefore the ONLY line of defense
# for restoring the environment (GCP has no force_destroy equivalent):
#
#   1. roles/owner self-binding: starting_sa added itself as roles/owner on
#      the project via resourcemanager.projects.setIamPolicy.
#
#   2. Custom role mutation: starting_sa added resourcemanager.projects.setIamPolicy
#      to the editable custom role it is bound to via iam.roles.update.
#
# Cleanup removes the owner binding first (highest risk), then restores the
# custom role's permissions to their Terraform-defined state.
#
# All cleanup commands use the admin_cleanup SA from the environment, impersonated
# via the deployer's ADC — no static keys.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: gcp-iam-003-iam-rolesupdate${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${YELLOW}Step 1: Retrieving cleanup identity and scenario configuration from Terraform${NC}"
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
    jq -r '.gcp_single_account_privesc_self_escalation_to_admin_gcp_iam_003_iam_rolesupdate.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find scenario terraform output${NC}"
    echo "Make sure the scenario is still deployed with: plabs apply"
    exit 1
fi

STARTING_SA_EMAIL=$(echo "$MODULE_OUTPUT"     | jq -r '.starting_sa_email')
EDITABLE_ROLE_FULL_ID=$(echo "$MODULE_OUTPUT" | jq -r '.editable_role_id')

cd - > /dev/null

for var_name in ADMIN_CLEANUP_SA PROJECT_ID STARTING_SA_EMAIL EDITABLE_ROLE_FULL_ID; do
    val="${!var_name}"
    if [ -z "$val" ] || [ "$val" = "null" ]; then
        echo -e "${RED}Error: Could not extract $var_name from Terraform output${NC}"
        exit 1
    fi
done

# Extract the bare role ID for gcloud subcommands
EDITABLE_ROLE_ID=$(echo "$EDITABLE_ROLE_FULL_ID" | sed 's|.*/||')

echo "Admin cleanup SA: $ADMIN_CLEANUP_SA"
echo "Starting SA:      $STARTING_SA_EMAIL"
echo "Editable role:    $EDITABLE_ROLE_FULL_ID"
echo "Project:          $PROJECT_ID"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Step 2: Remove the roles/owner self-binding added by starting_sa
#
# This is the highest-risk artifact — starting_sa has full project admin access
# as long as this binding exists. Remove it first.
echo -e "${YELLOW}Step 2: Removing the roles/owner self-binding added to starting_sa${NC}"

OWNER_BINDING_PRESENT=$(gcloud projects get-iam-policy "$PROJECT_ID" \
    --impersonate-service-account="$ADMIN_CLEANUP_SA" \
    --flatten="bindings[].members" \
    --filter="bindings.role=roles/owner AND bindings.members:serviceAccount:$STARTING_SA_EMAIL" \
    --format="value(bindings.role)" 2>/dev/null || true)

if [ -n "$OWNER_BINDING_PRESENT" ]; then
    echo "Found roles/owner binding for $STARTING_SA_EMAIL — removing it..."
    gcloud projects remove-iam-policy-binding "$PROJECT_ID" \
        --member="serviceAccount:$STARTING_SA_EMAIL" \
        --role="roles/owner" \
        --impersonate-service-account="$ADMIN_CLEANUP_SA" \
        --quiet 2>/dev/null
    echo -e "${GREEN}✓ Removed roles/owner binding from $STARTING_SA_EMAIL${NC}"
else
    echo -e "${GREEN}✓ No roles/owner binding found for starting_sa (may already be removed)${NC}"
fi
echo ""

echo -e "${YELLOW}Waiting for IAM policy to propagate (15s)...${NC}"
sleep 15
echo -e "${GREEN}✓ Propagation wait complete${NC}\n"

# Step 3: Restore the editable custom role's permissions
#
# demo_attack.sh added resourcemanager.projects.setIamPolicy to the custom role.
# Remove it to restore the role to its Terraform-defined state.
echo -e "${YELLOW}Step 3: Removing resourcemanager.projects.setIamPolicy from the editable custom role${NC}"

# Check whether the added permission is still present before attempting removal
CURRENT_PERMISSIONS=$(gcloud iam roles describe "$EDITABLE_ROLE_ID" \
    --project="$PROJECT_ID" \
    --impersonate-service-account="$ADMIN_CLEANUP_SA" \
    --format="value(includedPermissions)" 2>/dev/null || true)

if echo "$CURRENT_PERMISSIONS" | grep -q "resourcemanager.projects.setIamPolicy"; then
    echo "Found resourcemanager.projects.setIamPolicy in $EDITABLE_ROLE_ID — removing it..."
    gcloud iam roles update "$EDITABLE_ROLE_ID" \
        --project="$PROJECT_ID" \
        --remove-permissions=resourcemanager.projects.setIamPolicy \
        --impersonate-service-account="$ADMIN_CLEANUP_SA" \
        --quiet 2>/dev/null
    echo -e "${GREEN}✓ Removed resourcemanager.projects.setIamPolicy from $EDITABLE_ROLE_ID${NC}"
else
    echo -e "${GREEN}✓ resourcemanager.projects.setIamPolicy not present in role (may already be removed)${NC}"
fi
echo ""

# Step 4: Verify the environment is restored
echo -e "${YELLOW}Step 4: Verifying cleanup is complete${NC}"

REMAINING_OWNER=$(gcloud projects get-iam-policy "$PROJECT_ID" \
    --impersonate-service-account="$ADMIN_CLEANUP_SA" \
    --flatten="bindings[].members" \
    --filter="bindings.role=roles/owner AND bindings.members:serviceAccount:$STARTING_SA_EMAIL" \
    --format="value(bindings.role)" 2>/dev/null || true)

if [ -n "$REMAINING_OWNER" ]; then
    echo -e "${RED}✗ roles/owner binding still present for $STARTING_SA_EMAIL — manual remediation required${NC}"
    exit 1
fi

REMAINING_SETIAM=$(gcloud iam roles describe "$EDITABLE_ROLE_ID" \
    --project="$PROJECT_ID" \
    --impersonate-service-account="$ADMIN_CLEANUP_SA" \
    --format="value(includedPermissions)" 2>/dev/null | \
    grep "resourcemanager.projects.setIamPolicy" || true)

if [ -n "$REMAINING_SETIAM" ]; then
    echo -e "${RED}✗ resourcemanager.projects.setIamPolicy still in $EDITABLE_ROLE_ID — manual remediation required${NC}"
    exit 1
fi

echo -e "${GREEN}✓ roles/owner binding removed${NC}"
echo -e "${GREEN}✓ Custom role permissions restored to Terraform-defined state${NC}\n"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
rm -f "$SCRIPT_DIR/.demo_active"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Both out-of-band mutations have been reversed:${NC}"
echo "  - roles/owner self-binding: removed from $STARTING_SA_EMAIL"
echo "  - Custom role $EDITABLE_ROLE_ID: resourcemanager.projects.setIamPolicy removed"
echo -e "\n${YELLOW}Infrastructure remains deployed.${NC}"
echo -e "${YELLOW}To remove all resources, disable the scenario and run: plabs apply${NC}\n"
