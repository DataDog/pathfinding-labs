# Cloud Run Service Creation with actAs to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Points:** 10
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Deploy a new Cloud Run service bound to a privileged target service account via `iam.serviceAccounts.actAs` + `run.services.create`, using a public Docker Hub image (no Artifact Registry access needed), execute arbitrary code as it, and exfiltrate its OAuth token from the metadata server through the service's logs to inherit its `roles/editor` project permissions
* **Terraform Variable:** `enable_gcp_single_account_privesc_one_hop_to_admin_gcp_cloudrun_001_iam_serviceaccountsactas_run_servicescreate`
* **Schema Version:** 4.9.4
* **Pathfinding.cloud ID:** gcp-cloudrun-001
* **CTF Flag Location:** secret-manager
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access
* **MITRE Techniques:** T1550.001 - Use Alternate Authentication Material: Application Access Token, T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-cr001-start` service account to the `pl-prod-cr001-target` service account by deploying a new Cloud Run service bound to the target using a public Docker Hub image, executing code as it, and exfiltrating its OAuth access token from the metadata server through the service's logs.

- **Start:** `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-cr001-start@{project_id}.iam.gserviceaccount.com`
- **Destination resource:** `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-cr001-target@{project_id}.iam.gserviceaccount.com`

### Starting Permissions

**Required** (`pl-prod-cr001-start`):
- `iam.serviceAccounts.actAs` on `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-cr001-target@{project_id}.iam.gserviceaccount.com` -- required at Cloud Run service creation time when the service is bound to the target service account (`actas_required` -- the GCP analog of `iam:PassRole`)
- `run.services.create` on `//run.googleapis.com/projects/{project_id}/locations/-` -- deploys the new Cloud Run service, the core of the technique
- `run.services.get` on `//run.googleapis.com/projects/{project_id}/locations/-/services/-` -- fetches the new service's URL (`services.get` returns `urls[]`); also covers gcloud's readiness/preflight polling. Without it the URL cannot be extracted and the demo fails
- `run.operations.get` on `//run.googleapis.com/projects/{project_id}/locations/{region}/operations/-` -- polls the async long-running operation that `services.create` returns -- the only way to know when the deploy finished and whether the revision failed. Required even with the raw API
- `logging.logEntries.list` on `//logging.googleapis.com/projects/{project_id}` -- the exfiltration channel of the technique (gcpwn `--exfil-mode logs`): reads the target service account's OAuth token that the deployed container printed to Cloud Run logs. Required by both demo modes

**Helpful** (`pl-prod-cr001-start`):
- `run.services.update` -- required by `gcloud run deploy` re-runs only: re-deploying to the deterministic service name left behind by a prior run takes the update path; not needed with the raw API for a fresh deploy
- `run.routes.invoke` -- invoke the deployed service to trigger a fresh per-request exfiltration (gcpwn `--invoke`); without it the invoke returns 403, but the deploy-time readiness instance already exfiltrates the token, so the attack itself succeeds
- `iam.serviceAccounts.list` -- enumerate other service accounts in the project to identify actAs targets
- `iam.serviceAccounts.getIamPolicy` -- inspect IAM policy bindings on candidate service accounts to find actAs grants
- `run.services.list` -- enumerate existing Cloud Run services in the project

*Verified NOT needed at all* (removed during empirical permission isolation): `resourcemanager.projects.get`, `iam.serviceAccounts.get`, `run.services.setIamPolicy`, `run.services.getIamPolicy` -- `gcloud run deploy` with `--no-allow-unauthenticated` issues none of these, not even on the re-deploy path. `artifactregistry.repositories.downloadArtifacts` is not needed either: a public Docker Hub image is pulled server-side by Cloud Run's service agent, so that permission only matters when pulling from Artifact Registry. Note that `run.services.invoke` is not a valid GCP IAM permission -- the permission Cloud Run checks on invocation is `run.routes.invoke`.

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your GCP project and credentials in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)
3. Make sure your `gcloud` CLI login and Application Default Credentials are the SAME identity: `gcloud auth login --update-adc` (Terraform reads ADC to determine your identity and grants it impersonation rights; demo scripts use the `gcloud` CLI session, so a mismatch causes `--impersonate-service-account` calls to fail)

### Deploy with plabs non-interactive

```bash
plabs enable gcp-cloudrun-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-cloudrun-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| Resource Identifier | Purpose |
| -- | -- |
| `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-cr001-start@{project_id}.iam.gserviceaccount.com` | Starting service account with no project-level roles of its own |
| `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-cr001-target@{project_id}.iam.gserviceaccount.com` | Privileged target service account holding `roles/editor` on the project |
| Custom role `gcp_cloudrun_001_cr_deploy_req` (project-level binding on `pl-prod-cr001-start`, plus a second SA-scoped binding on `pl-prod-cr001-target`) | The vulnerable PassRole-equivalent grant: the verified raw-API minimum (`iam.serviceAccounts.actAs`, `run.services.create`, `run.services.get`, `run.operations.get`, `logging.logEntries.list`) that lets the starting account deploy a new Cloud Run service bound to the target and recover its exfiltrated token from the logs. Never `roles/iam.serviceAccountUser` or `roles/run.admin` |
| Custom role `gcp_cloudrun_001_cr_deploy_help` bound to `pl-prod-cr001-start` at the project level | The helpful permissions: gcloud re-deploy mechanics (`run.services.update`), the invoke trigger (`run.routes.invoke`), and recon (`iam.serviceAccounts.list`, `iam.serviceAccounts.getIamPolicy`, `run.services.list`) |
| IAM binding: `roles/editor` on the project granted to `pl-prod-cr001-target` | The privilege that makes running code as the target service account valuable |
| IAM binding: `roles/secretmanager.secretAccessor` on the flag secret granted to `pl-prod-cr001-target` | Explicit grant needed because `roles/editor` alone does not include Secret Manager payload access |
| `//secretmanager.googleapis.com/projects/{project_id}/secrets/pl-gcp-cloudrun-001-flag/versions/latest` | CTF flag stored as a Secret Manager secret version |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script supports two modes, both verified green: the default `gcloud` mode and `--api-only` (raw Cloud Run v2 REST via `curl`).

The script will:
1. Confirm the starting service account's identity (via tokeninfo) and that it has no project-level privilege of its own (it cannot read the CTF flag)
2. Deploy a brand-new Cloud Run service bound to the target service account using the PUBLIC Docker Hub image `docker.io/library/python:3.13-slim` -- no Artifact Registry access is involved anywhere, which is the crux of the technique. `iam.serviceAccounts.actAs` on the target is checked at service creation time; the container command override boots an inline Python payload from the `EXFIL_PAYLOAD` environment variable that fetches the target's OAuth token and email from the local metadata server and prints them (flushed) to Cloud Run logs
3. In `--api-only` mode, drive the raw Cloud Run v2 REST API instead: `services.create`, poll the async LRO via `run.operations.get`, and `services.get` to extract the service URL from `urls[0]`
4. Invoke the private service with an OIDC identity token minted as the starting service account (no `setIamPolicy` call is ever needed thanks to `--no-allow-unauthenticated`)
5. Read the exfiltrated token from the Cloud Run logs (`logging.logEntries.list` -- the same `--exfil-mode logs` channel gcpwn uses)
6. Verify the raw stolen token belongs to the target service account (tokeninfo) and prove `roles/editor` write access with a project label round-trip -- all using the raw bearer token directly against Google REST APIs, never gcloud re-impersonation
7. Read the CTF flag from Secret Manager with the raw stolen token and display it

A note on payload mechanics: `gcloud`'s `--args` list splits values on commas (repeated `--args` flags and backslash-escaping do not carry a literal comma through), so the comma-heavy Python payload travels in the `EXFIL_PAYLOAD` environment variable -- via `--env-vars-file` (YAML/JSON, no comma parsing) in gcloud mode and as a plain env entry in the raw JSON body in `--api-only` mode. Every `print` carries `flush=True` because container stdout is block-buffered when piped to the logging agent, and an unflushed token print never reaches the logs.

#### Resources Created by Attack Script

- A new Cloud Run service `pl-cr001-exfil-{resource_suffix}` running as the target service account, built from the public Docker Hub image `docker.io/library/python:3.13-slim` with the inline exfil command (deleted by `cleanup_attack.sh`; also deleted best-effort by the demo's exit trap on abnormal exit)
- A temporary env-vars file carrying the `EXFIL_PAYLOAD` (removed automatically at exit)
- A short-lived `pl-privesc-verified` project label added and removed as the `roles/editor` write proof (removed within the demo itself; `cleanup_attack.sh` verifies defensively)
- Local shell variables holding the exfiltrated OAuth access token for the duration of the demo (no persistent credential material)
- A `.demo_active` marker file

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo gcp-cloudrun-001-iam-serviceaccountsactas+run-servicescreate
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-cloudrun-001-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup gcp-cloudrun-001-iam-serviceaccountsactas+run-servicescreate
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-cloudrun-001-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable gcp-cloudrun-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-cloudrun-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- **`run.services.create` + `iam.serviceAccounts.actAs` delivered through CUSTOM roles rather than `roles/run.admin` or `roles/iam.serviceAccountUser`**: Any principal that can both create compute *and* attach a service account to that compute is functionally able to steal the attached account's OAuth token. A CSPM that only models the predefined roles will miss the pairing entirely when it hides inside a custom role scoped to exactly `run.services.create` + `actAs` -- flattening custom-role permission sets is the only way to see this toxic combination.
- **actAs targets that hold elevated project roles**: Flag any service account reachable via `actAs` (predefined `roles/iam.serviceAccountUser` *or* a custom role scoped to just `iam.serviceAccounts.actAs`) that also holds `roles/editor`, `roles/owner`, or another broad primitive role. The finding is the combination -- neither permission in isolation is the issue.
- **Cloud Run services deployed bound to service accounts they weren't previously bound to**: A `CreateService` event whose `template.serviceAccount` differs from every prior service the caller deployed -- or from any usage pattern of that service account -- is a strong indicator of a PassRole-style abuse. Track caller-to-attached-identity history per service account, not just per service.
- **Services deployed from public Docker Hub images instead of Artifact Registry**: The attack needs zero registry permissions because Cloud Run's service agent pulls `docker.io/...` images server-side. Registry-centric controls and detections (download permissions, image provenance policies scoped to AR) do not constrain this path at all.
- **Cloud Logging-based detection of metadata token access from Cloud Run containers**: Containers that reach `http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/` (via `urlopen` or similar) and print tokens/emails to stdout are exfiltration payloads -- the gcpwn `--exfil-mode logs` pattern. Alert on log entries matching `EXFIL`-style token prints or any container stdout containing long `ya29.`/OAuth token strings from Cloud Run revisions.

#### Prevention Recommendations

- **Never co-locate `iam.serviceAccounts.actAs` and `run.services.create` (or any compute-create permission) on the same principal for a privileged target service account**: Treat this pairing the same way you would treat AWS `iam:PassRole` + `lambda:CreateFunction` -- as a single toxic combination, not two independent low-risk grants.
- **Apply least privilege to the target service account**: Replace `roles/editor` with narrowly scoped predefined or custom roles that grant only the permissions the workload actually needs, so that binding compute to the account is not automatically equivalent to near-admin access.
- **Restrict actAs grants with IAM Conditions**: Scope `actAs`/`serviceAccountUser` bindings with conditions (time-bound access, resource-tag bound) rather than granting unconditional standing access. Prefer SA-scoped actAs bindings over project-wide ones so the grant surface is auditable.
- **Model custom roles in your CSPM/graph tooling, not just predefined roles**: This scenario's entire attack surface lives in a five-permission custom role. Detection logic keyed on `roles/run.admin` or `roles/iam.serviceAccountUser` membership will produce a false "clean" result here.
- **Audit `CreateService` events for caller/attached-identity mismatches and unexpected public-image deploys**: A Cloud Run service whose runtime identity differs from the caller's own identity, deployed from an external public image, deserves review -- especially when the attached account holds elevated project roles.
- **Enable Policy Analyzer / IAM Recommender audits**: Regularly review which principals can create Cloud Run services and which service accounts they can act as, removing unused or overly broad `actAs` grants.

### Detecting Abuse (CloudSIEM)

#### Cloud Audit Log Events to Monitor

- `run.googleapis.com/CreateService` -- a new Cloud Run service was deployed; inspect the `template.serviceAccount` field in the request and flag deployments where the caller's own identity does not otherwise hold that service account's permissions
- `run.googleapis.com/GetOperation` -- long-running-operation polling that immediately follows a `CreateService`; a corroborating signal of the deploy-then-wait exfiltration chain
- `run.googleapis.com/GetService` -- service metadata retrieval (URL extraction) shortly after a `CreateService` by the same caller; part of the deploy chain that precedes invocation and log reading
- `logging.googleapis.com/ListLogEntries` -- log entries read via `gcloud logging read` or the raw `entries:list` API; investigate when the reader is a service account with no logging-related duties, immediately after it deployed a Cloud Run service -- this is the exfiltration channel
- `secretmanager.googleapis.com/AccessSecretVersion` -- a Secret Manager secret version was accessed; investigate when the caller identity is the target service account shortly after a `CreateService` event for an unrelated service
- `cloudresourcemanager.googleapis.com/UpdateProject` -- project metadata (labels) written; used in this scenario as the `roles/editor` write proof, and a common editor-level verification step in real intrusions

**Create-Deploy-Exfiltrate Chain Pattern**:
- A `CreateService` event where the attached `serviceAccount` differs from the caller's own identity, followed by LRO polling and a `GetService` URL fetch, then `ListLogEntries` calls by the same caller, then API calls authenticated as the attached service account, is a strong signal of PassRole-style privilege escalation via Cloud Run. Complement audit-log analysis with Cloud Logging inspection for the payload itself: container stdout from Cloud Run revisions containing OAuth access tokens (`ya29.`-prefixed strings) or metadata-server fetch patterns (`urlopen` to `metadata.google.internal`) is direct evidence of token exfiltration.

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [pathfinding.cloud/paths/gcp-cloudrun-001](https://pathfinding.cloud/paths/gcp-cloudrun-001) -- catalog entry for this privilege escalation path
- [NetSPI gcpwn](https://github.com/NetSPI/gcpwn) -- the CREATE_CLOUDRUN_SERVICE_AS_SA privilege escalation edge (status CONFIRMED, `actas_required: true`) in gcpwn's defined edges, modeled on the minimum of `run.services.create` + `actAs`
- [Cloud Run documentation: Service identity](https://cloud.google.com/run/docs/securing/service-identity) -- official documentation on the runtime service account attached to a Cloud Run service
- [GCP metadata server documentation](https://cloud.google.com/compute/docs/metadata/default-metadata-values) -- how workloads retrieve their attached service account's OAuth access token
- [MITRE ATT&CK T1550.001](https://attack.mitre.org/techniques/T1550/001/) -- Use Alternate Authentication Material: Application Access Token
