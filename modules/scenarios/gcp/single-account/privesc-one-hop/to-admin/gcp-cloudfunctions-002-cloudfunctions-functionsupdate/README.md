# Cloud Function Code Update to Existing Admin SA

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Replace the source code of an existing 2nd-gen Cloud Function that already runs as a privileged service account via the raw Cloud Functions v2 REST API -- not `gcloud`, which requires extra Cloud Build preflight permissions -- then invoke the updated function to exfiltrate the function's OAuth access token from the local metadata server, inheriting the target service account's `roles/editor` project permissions
* **Terraform Variable:** `enable_gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_002_cloudfunctions_functionsupdate`
* **Schema Version:** 4.8.2
* **Pathfinding.cloud ID:** gcp-cloudfunctions-002
* **CTF Flag Location:** secret-manager
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access
* **MITRE Techniques:** T1550.001 - Use Alternate Authentication Material: Application Access Token, T1078.004 - Valid Accounts: Cloud Accounts, T1525 - Implant Internal Image

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-cf002-start` service account to the `pl-prod-cf002-target` service account by replacing the source code of an existing 2nd-gen Cloud Function that already runs as the target identity, invoking the updated function, and exfiltrating its OAuth access token from the function's metadata server.

- **Start:** `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-cf002-start@{project_id}.iam.gserviceaccount.com`
- **Destination resource:** `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-cf002-target@{project_id}.iam.gserviceaccount.com`

### Starting Permissions

**Required** (`pl-prod-cf002-start`):
- `iam.serviceAccounts.actAs` on `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-cf002-target@{project_id}.iam.gserviceaccount.com` -- required by the Cloud Functions v2 PATCH API on every update that touches `buildConfig`, even if the attached service account field is not changing; GCP enforces this actAs check against the function's existing runtime SA regardless of whether the SA is being replaced
- `cloudfunctions.functions.update` on `//cloudfunctions.googleapis.com/projects/{project_id}/locations/-/functions/{function_name}` -- allows replacing an existing 2nd-gen Cloud Function's source code and entry point via the PATCH endpoint without touching its attached service account
- `cloudfunctions.functions.sourceCodeSet` on `//cloudfunctions.googleapis.com/projects/{project_id}/locations/-/functions/{function_name}` -- allows calling `generateUploadUrl` to obtain a signed GCS URL and upload a new source archive before submitting the PATCH
- `run.routes.invoke` on `//run.googleapis.com/projects/{project_id}/locations/-/services/-` -- allows sending authenticated HTTP requests to the 2nd-gen function's underlying Cloud Run endpoint using an OIDC identity token; gen2 function invocation auth is enforced by Cloud Run, not the Cloud Functions API

**Helpful** (`pl-prod-cf002-start`) -- required only because `gcloud functions deploy` does extra preflight work beyond the raw API:
- `cloudfunctions.functions.get` -- `gcloud functions deploy` reads the function's current configuration before submitting the update; also used to retrieve the invocation URL after the update completes; not needed for the raw PATCH API
- `cloudfunctions.operations.get` -- `gcloud functions deploy` polls the update long-running operation; no `--async` flag exists for gen2, so this is unavoidable with the CLI
- `resourcemanager.projects.get` -- `gcloud functions deploy` calls `GET /v1/projects/{id}` unconditionally before submitting; unavoidable with the CLI but not required for the raw API
- `iam.serviceAccounts.list` -- enumerate service accounts in the project to identify which privileged SA is attached to the target function
- `iam.serviceAccounts.getIamPolicy` -- inspect IAM policy bindings on candidate service accounts to understand their project roles and confirm the attached SA is high-value

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
plabs enable gcp-cloudfunctions-002-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-cloudfunctions-002-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| Resource Identifier | Purpose |
| -- | -- |
| `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-cf002-start@{project_id}.iam.gserviceaccount.com` | Starting service account with no project-level roles of its own |
| `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-cf002-target@{project_id}.iam.gserviceaccount.com` | Privileged target service account holding `roles/editor` on the project |
| Custom IAM role `gcp_cloudfunctions_002_cf_update_min` bound to `pl-prod-cf002-start` at the project level | Grants `cloudfunctions.functions.update`, `.sourceCodeSet`, `run.routes.invoke`, and gcloud mechanic permissions (`functions.get`, `operations.get`, `resourcemanager.projects.get`) |
| IAM binding: `roles/iam.serviceAccountUser` on `pl-prod-cf002-target`, granted to `pl-prod-cf002-start` | The vulnerable actAs grant -- satisfies the actAs check the PATCH API performs on the function's existing runtime SA |
| IAM binding: `roles/editor` on the project granted to `pl-prod-cf002-target` | The privilege that makes running code as the target service account valuable |
| IAM binding: `roles/secretmanager.secretAccessor` on the flag secret granted to `pl-prod-cf002-target` | Explicit grant needed because `roles/editor` alone does not include Secret Manager payload access |
| `//cloudfunctions.googleapis.com/projects/{project_id}/locations/{region}/functions/pl-cf002-victim-{resource_suffix}` | Pre-deployed 2nd-gen Cloud Function running as `pl-prod-cf002-target`, initially serving benign hello-world code; the attacker replaces its code in place during the attack |
| `//secretmanager.googleapis.com/projects/{project_id}/secrets/pl-gcp-cloudfunctions-002-flag/versions/latest` | CTF flag stored as a Secret Manager secret version |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Verify that `pl-prod-cf002-start` cannot read the CTF flag secret directly
3. Observe the pre-deployed victim function to confirm it already runs as `pl-prod-cf002-target` (hello-world code, privileged identity already attached)
4. Build a malicious source package locally: a Python handler that queries the GCE metadata server for the function's own runtime identity's OAuth access token and returns it in the HTTP response body
5. Upload the malicious source archive to a Cloud Functions-managed presigned GCS URL using `cloudfunctions.functions.sourceCodeSet`
6. Replace the victim function's code via a raw PATCH call to the Cloud Functions v2 REST API using `cloudfunctions.functions.update` and `iam.serviceAccounts.actAs` -- the raw API is used instead of `gcloud functions deploy` because `gcloud` makes an extra Cloud Build preflight call (`GetDefaultServiceAccount`) that `pl-prod-cf002-start` is not granted
7. Wait for the function to return to `ACTIVE` state
8. Invoke the updated function using an OIDC identity token scoped to the function's Cloud Run URL (`run.routes.invoke`)
9. Verify the exfiltrated OAuth token belongs to `pl-prod-cf002-target` using Google's tokeninfo endpoint
10. Confirm `roles/editor` write access by patching a project label with the raw stolen token
11. Read the CTF flag from Secret Manager using the exfiltrated access token and display it

#### Resources Created by Attack Script

- The victim function `pl-cf002-victim-{resource_suffix}` is updated in place: its source code and entry point are replaced with the token-exfiltration payload; its runtime SA (`pl-prod-cf002-target`) is unchanged
- A new Cloud Run revision is auto-provisioned by the Cloud Functions service agent behind the scenes after the code update
- A malicious source archive uploaded to a Cloud Functions-managed presigned GCS URL (no persistent storage IAM required on the attacker's identity)
- A temporary project label (`pl-privesc-verified: true`) written and immediately removed during the editor-access verification step
- Local shell variables holding the exfiltrated OAuth access token for the duration of the demo (no persistent credential material)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo gcp-cloudfunctions-002-cloudfunctions-functionsupdate
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup gcp-cloudfunctions-002-cloudfunctions-functionsupdate
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable gcp-cloudfunctions-002-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-cloudfunctions-002-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- **Service accounts holding `cloudfunctions.functions.update` combined with `iam.serviceAccounts.actAs` on a privileged service account that is already the runtime SA of an existing function**: This is the update-path analog of `actAs` + `cloudfunctions.functions.create`. The function already exists; the attacker does not need to create anything. CSPM tools that only flag the create pairing will miss this surface entirely.
- **Existing Cloud Functions where a less-privileged principal holds update rights over the function and the function runs as a broad-privilege service account**: Unlike a one-time deployment event, an overly permissive `cloudfunctions.functions.update` grant is an ongoing risk -- any future code the function serves can be silently replaced. Flag this as a standing misconfiguration, not just a deployment-time one.
- **`iam.serviceAccounts.actAs` enforced on code-only updates**: Many practitioners assume actAs is only checked when the attached SA is changing. GCP enforces it on every PATCH that touches `buildConfig`, even when the SA field is not present in `updateMask`. Detection that only watches for SA-change events will miss pure code-replacement attacks.
- **`cloudfunctions.functions.sourceCodeSet` as a distinct attack-enabling permission**: This permission gates the `generateUploadUrl` call that precedes every raw-API code replacement. CSPM tools that model only `cloudfunctions.functions.update` without `sourceCodeSet` will produce false-negative findings.
- **`run.routes.invoke` as an invocation vector for 2nd-gen functions**: Neither `cloudfunctions.functions.call` nor `cloudfunctions.functions.invoke` is required to invoke a gen2 function; Cloud Run enforces authentication at the endpoint level. Detection logic that only watches those Cloud Functions-layer permissions will miss invocations made directly to the Cloud Run URL.
- **`roles/editor`/`roles/owner` service accounts attached to existing functions where a less-privileged principal holds update rights**: Broad primitive roles grant near-administrative access across most GCP services, making any function running as such an account a high-value target once its code can be replaced.

#### Prevention Recommendations

- **Never co-locate `cloudfunctions.functions.update` and `iam.serviceAccounts.actAs` on the same principal for any service account attached to a production Cloud Function**: Treat this pairing the same way you treat AWS `iam:PassRole` + `lambda:UpdateFunctionCode` -- as a single toxic combination regardless of how the grants were delivered.
- **Apply the Principle of Least Privilege to Cloud Function runtime service accounts**: Replace `roles/editor` with narrowly scoped predefined or custom roles granting only the permissions the function workload actually needs, so that code replacement is not automatically equivalent to near-admin access.
- **Separate the identities permitted to deploy/update functions from the identities those functions run as**: A CI/CD service account that deploys functions should not also hold `actAs` on the function's runtime SA if those are two different accounts -- structure the pipeline so the deployment principal cannot assume the function's runtime identity.
- **Restrict `iam.serviceAccounts.actAs` with IAM Conditions**: Scope actAs bindings with resource tags or time-based conditions rather than granting unconditional standing access, so that the grant cannot be exploited outside its intended window.
- **Audit `cloudfunctions.functions.update` grants project-wide alongside the runtime SA of each function**: The combination is detectable from IAM policy alone without any runtime signal. Regularly review and remove update grants held by principals that do not belong to the function's owning CI/CD pipeline.
- **Enable Cloud Audit Logs for `cloudfunctions.googleapis.com/UpdateFunction` and alert on callers whose identity does not match the expected CI/CD service account**: Code replacement is the most impactful variant of this technique and should generate a low-latency alert when performed by an unexpected identity.

### Detecting Abuse (CloudSIEM)

#### Cloud Audit Log Events to Monitor

- `cloudfunctions.googleapis.com/GenerateUploadUrl` -- a presigned source upload URL was requested; this call always precedes a source-code replacement via the raw Cloud Functions v2 API and should be correlated with a subsequent `UpdateFunction` event from the same identity
- `cloudfunctions.googleapis.com/UpdateFunction` -- an existing function's source code or entry point was replaced; inspect the caller identity and compare it against the expected CI/CD principal; flag any update where the caller does not itself hold the function's attached runtime SA's permissions
- `run.googleapis.com/CreateRevision` -- a new Cloud Run revision was auto-provisioned by the Cloud Functions service agent following a code update; useful corroborating signal, though the direct trigger is the Cloud Functions service agent rather than the attacker's own identity
- `secretmanager.googleapis.com/AccessSecretVersion` -- a Secret Manager secret version was accessed; investigate when the caller identity is the target service account shortly after a `GenerateUploadUrl`/`UpdateFunction` pair for an unrelated function

**Replace-Invoke-Exfiltrate Chain Pattern**: A `GenerateUploadUrl` event followed by an `UpdateFunction` event from the same non-CI/CD identity, followed within minutes by authenticated HTTP invocation of that function via Cloud Run and then API calls authenticated as the function's runtime SA, is a strong signal of PassRole-style privilege escalation via code replacement.

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [pathfinding.cloud/paths/gcp-cloudfunctions-002](https://pathfinding.cloud/paths/gcp-cloudfunctions-002) -- catalog entry for this privilege escalation path
- [pathfinding.cloud/paths/gcp-cloudfunctions-001](https://pathfinding.cloud/paths/gcp-cloudfunctions-001) -- the create-path variant: same token-exfiltration primitive, different entry permission (`functions.create` vs `functions.update`)
- [GCP Cloud Functions documentation: Service identity](https://cloud.google.com/functions/docs/securing/function-identity) -- official documentation on the runtime service account attached to a Cloud Function
- [GCP metadata server documentation](https://cloud.google.com/compute/docs/metadata/default-metadata-values) -- how workloads retrieve their attached service account's OAuth access token
- [MITRE ATT&CK T1550.001](https://attack.mitre.org/techniques/T1550/001/) -- Use Alternate Authentication Material: Application Access Token
- [MITRE ATT&CK T1525](https://attack.mitre.org/techniques/T1525/) -- Implant Internal Image
