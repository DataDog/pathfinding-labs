# Cloud Function Creation with actAs to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Deploy a 2nd-generation Cloud Function ("Cloud Run functions") configured to run as a privileged service account via `iam.serviceAccounts.actAs`, invoke it directly, and exfiltrate the function's OAuth access token from the local metadata server to inherit its `roles/editor` project permissions
* **Terraform Variable:** `enable_gcp_single_account_privesc_one_hop_to_admin_gcp_cloudfunctions_001_iam_serviceaccountsactas_cloudfunctions_functionscreate`
* **Schema Version:** 4.8.2
* **Pathfinding.cloud ID:** gcp-cloudfunctions-001
* **CTF Flag Location:** secret-manager
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access
* **MITRE Techniques:** T1550.001 - Use Alternate Authentication Material: Application Access Token, T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-cf001-start` service account to the `pl-prod-cf001-target` service account by deploying a Cloud Function configured to run as the target, invoking it directly, and exfiltrating its OAuth access token from the function's metadata server.

- **Start:** `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-cf001-start@{project_id}.iam.gserviceaccount.com`
- **Destination resource:** `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-cf001-target@{project_id}.iam.gserviceaccount.com`

### Starting Permissions

**Required** (`pl-prod-cf001-start`):
- `iam.serviceAccounts.actAs` on `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-cf001-target@{project_id}.iam.gserviceaccount.com` -- allows attaching the target service account to a new compute resource (here, a Cloud Function) so that the resource runs with the target's identity
- `cloudfunctions.functions.create` on `//cloudfunctions.googleapis.com/projects/{project_id}/locations/-` -- allows deploying a new Cloud Function anywhere in the project
- `cloudfunctions.functions.sourceCodeSet` on `//cloudfunctions.googleapis.com/projects/{project_id}/locations/-` -- allows uploading the function's source code (the handler that reads the metadata server)
- `run.routes.invoke` on `//run.googleapis.com/projects/{project_id}/locations/-/services/-` -- allows sending authenticated HTTP requests to the 2nd-gen function's underlying Cloud Run endpoint; gen2 function auth goes through Cloud Run directly (neither `cloudfunctions.functions.call` nor `cloudfunctions.functions.invoke` is needed -- confirmed empirically with both absent)

**Helpful** (`pl-prod-cf001-start`) -- required only because `gcloud functions deploy` does extra preflight work beyond the raw API call:
- `cloudfunctions.functions.get` -- `gcloud` checks whether the function already exists (create vs. update path) before submitting; raw API callers can skip this
- `cloudfunctions.operations.get` -- `gcloud` polls the deploy long-running operation; no `--async` flag exists for gen2, so this is unavoidable with the CLI
- `resourcemanager.projects.get` -- `gcloud` calls `GET /v1/projects/{id}` unconditionally before submitting the deploy; using the project number instead of ID does not bypass this call
- `iam.serviceAccounts.list` -- enumerate other service accounts in the project to identify impersonation targets
- `iam.serviceAccounts.getIamPolicy` -- inspect IAM policy bindings on candidate service accounts to find `actAs` grants (predefined `roles/iam.serviceAccountUser` or a custom role granting `iam.serviceAccounts.actAs`)

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your GCP project and credentials in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)
3. Make sure your `gcloud` CLI login and Application Default Credentials are the SAME identity: `gcloud auth login --update-adc` (Terraform reads ADC to determine your identity and grants it impersonation rights; the demo script uses the `gcloud` CLI session, so a mismatch causes `--impersonate-service-account` calls to fail)

### Deploy with plabs non-interactive

```bash
plabs enable gcp-cloudfunctions-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-cloudfunctions-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| Resource Identifier | Purpose |
| -- | -- |
| `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-cf001-start@{project_id}.iam.gserviceaccount.com` | Starting service account with no project-level roles of its own |
| `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-cf001-target@{project_id}.iam.gserviceaccount.com` | Privileged target service account holding `roles/editor` on the project |
| IAM custom role granting `iam.serviceAccounts.actAs` on `pl-prod-cf001-target`, bound to `pl-prod-cf001-start` | The vulnerable PassRole-equivalent grant that lets the starting account attach the target's identity to new compute |
| IAM custom role granting `cloudfunctions.functions.create` / `.sourceCodeSet` and `run.routes.invoke` at the project level, bound to `pl-prod-cf001-start` | The compute-creation and invocation permissions that combine with `actAs` to complete the escalation |
| IAM binding: `roles/editor` on the project granted to `pl-prod-cf001-target` | The privilege that makes running code as the target service account valuable |
| IAM binding: `roles/secretmanager.secretAccessor` on the flag secret granted to `pl-prod-cf001-target` | Explicit grant needed because `roles/editor` alone does not include Secret Manager payload access |
| `//secretmanager.googleapis.com/projects/{project_id}/secrets/pl-gcp-cloudfunctions-001-flag/versions/latest` | CTF flag stored as a Secret Manager secret version |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the `gcloud` commands being executed and their results
3. Write an inline Cloud Function handler that queries the local metadata server for its own identity's OAuth access token and returns it in the HTTP response body
4. Deploy a brand-new 2nd-generation Cloud Function (branded "Cloud Run functions" in the current console) configured with `--service-account` set to the target service account, using only `cloudfunctions.functions.create` and `cloudfunctions.functions.sourceCodeSet`
5. Invoke the function directly via its Cloud Run endpoint using an OIDC identity token (`run.routes.invoke`) -- no `setIamPolicy` call is needed to make the function public
6. Capture the target service account's OAuth access token from the function's HTTP response
7. Verify successful privilege escalation by using the exfiltrated token to call a `roles/editor`-gated API the starting account cannot reach on its own
8. Read the CTF flag from Secret Manager using the exfiltrated access token and display it

#### Resources Created by Attack Script

- A new 2nd-generation Cloud Function (Cloud Run functions) configured to run as the target service account
- An underlying Cloud Run service and revision, auto-provisioned behind the scenes by the Cloud Functions v2 API's own service agent (not created directly by the caller)
- A source archive uploaded to a Cloud Functions-managed presigned GCS URL (no storage IAM on the attacker identity -- the Cloud Functions service agent handles the bucket)
- Local shell variables holding the exfiltrated OAuth access token for the duration of the demo (no persistent credential material)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo gcp-cloudfunctions-001-iam-serviceaccountsactas+cloudfunctions-functionscreate
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-cloudfunctions-001-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup gcp-cloudfunctions-001-iam-serviceaccountsactas+cloudfunctions-functionscreate
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-cloudfunctions-001-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable gcp-cloudfunctions-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-cloudfunctions-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- **Service accounts holding `iam.serviceAccounts.actAs` combined with `cloudfunctions.functions.create`**: Any principal that can both attach a service account to new compute *and* create that compute is functionally able to steal the attached service account's OAuth token. Neither permission alone is dangerous -- it is the pairing that matters, exactly like AWS `iam:PassRole` + `lambda:CreateFunction`.
- **Service accounts that are valid `actAs` targets for a less-privileged principal AND hold a broad project role**: Flag any service account reachable via `actAs` (through the predefined `roles/iam.serviceAccountUser` role *or* a custom role scoped to just `actAs`) that also holds `roles/editor`, `roles/owner`, or another broad primitive role. This toxic combination is the actual finding -- not either permission in isolation.
- **The Cloud Functions API as a distinct attack surface from Cloud Run**: Cloud Functions 2nd generation is implemented on top of Cloud Run internally, but provisioning is handled entirely by the Cloud Functions v2 API's own internal service agent -- the caller only ever needs `cloudfunctions.functions.*` permissions, never `run.services.*` directly. A CSPM tool that models "who can create compute that runs as a privileged service account" and only inspects `run.services.create`/`roles/run.admin` grants will miss this path entirely. Cloud Functions coverage must be modeled independently of Cloud Run coverage.
- **Functions invocable without public exposure**: This scenario never calls `setIamPolicy` to make the function public -- `run.routes.invoke` is enough for the attacker's own identity to invoke the underlying Cloud Run endpoint directly using an OIDC identity token. CSPM logic that only flags *publicly invocable* functions as risky will miss privately-invocable functions that still leak a privileged identity to any caller who holds `run.routes.invoke`.
- **`roles/editor`/`roles/owner` service accounts missing scoped-down alternatives**: Broad primitive roles grant near-administrative access across most GCP services (though notably *not* Secret Manager payload access -- see below), making any compute that can assume that identity a high-value target.

#### Prevention Recommendations

- **Never co-locate `iam.serviceAccounts.actAs` and `cloudfunctions.functions.create` (or any compute-create permission) on the same principal for a privileged target service account**: Treat this pairing the same way you would treat AWS `iam:PassRole` + `lambda:CreateFunction` -- as a single toxic combination, not two independent low-risk grants.
- **Apply least privilege to the target service account**: Replace `roles/editor` with narrowly scoped predefined or custom roles that grant only the permissions the workload actually needs, so that impersonating or attaching the account is not automatically equivalent to near-admin access.
- **Restrict who can attach service accounts to new compute with IAM Conditions**: Scope `actAs`/`serviceAccountUser` bindings with conditions (time-bound access, resource-tag bound) rather than granting unconditional standing access.
- **Model Cloud Functions and Cloud Run as separate privilege-escalation surfaces in your CSPM/graph tooling**: Do not assume that coverage of `run.services.create` also covers the Cloud Functions v2 deployment path -- they use different caller-facing permissions even though the underlying infrastructure overlaps.
- **Audit `run.routes.invoke` grants alongside `actAs` grants**: A principal that can both deploy privileged compute and invoke it needs no further permissions to exfiltrate the attached identity's token -- there is no `setIamPolicy` step to catch. Note that `cloudfunctions.functions.call` and `cloudfunctions.functions.invoke` are not required for gen2 authenticated invocation; detection logic that only watches those permissions will miss this path.
- **Enable Organization Policy constraints and Policy Analyzer / IAM Recommender audits**: Regularly review which principals can create Cloud Functions and which service accounts they can attach, removing unused or overly broad `actAs` grants.

### Detecting Abuse (CloudSIEM)

#### Cloud Audit Log Events to Monitor

- `cloudfunctions.googleapis.com/CreateFunction` -- a new Cloud Function was deployed; inspect the `serviceAccount`/`buildServiceAccount` field in the request to see which identity it runs as, and flag deployments where the caller's own identity does not otherwise hold that service account's permissions
- `cloudfunctions.googleapis.com/UpdateFunction` -- an existing function's source code or attached service account was changed; the same detection logic applies
- `cloudfunctions.googleapis.com/CallFunction` -- a function was invoked directly via the API rather than its public HTTP trigger; correlate with a recent `CreateFunction`/`UpdateFunction` event for the same function to catch a create-then-invoke exfiltration pattern
- `run.googleapis.com/CreateService` -- the underlying Cloud Run service auto-provisioned for a 2nd-generation Cloud Function; useful corroborating signal, but do not rely on it alone since it is triggered by the Cloud Functions service agent, not the attacker's own identity
- `secretmanager.googleapis.com/AccessSecretVersion` -- a Secret Manager secret version was accessed; investigate when the caller identity is the target service account shortly after a `CreateFunction`/`CallFunction` pair for an unrelated function

**Create-Invoke-Exfiltrate Chain Pattern**:
- A `CreateFunction` event where the attached service account differs from the caller's own identity, followed within minutes by a `CallFunction` event for that same function, followed by API calls authenticated as the attached service account, is a strong signal of PassRole-style privilege escalation via Cloud Functions.

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [pathfinding.cloud/paths/gcp-cloudfunctions-001](https://pathfinding.cloud/paths/gcp-cloudfunctions-001) -- catalog entry for this privilege escalation path
- [GCP Cloud Functions documentation: Service identity](https://cloud.google.com/functions/docs/securing/function-identity) -- official documentation on the runtime service account attached to a Cloud Function
- [GCP metadata server documentation](https://cloud.google.com/compute/docs/metadata/default-metadata-values) -- how workloads retrieve their attached service account's OAuth access token
- [MITRE ATT&CK T1550.001](https://attack.mitre.org/techniques/T1550/001/) -- Use Alternate Authentication Material: Application Access Token
