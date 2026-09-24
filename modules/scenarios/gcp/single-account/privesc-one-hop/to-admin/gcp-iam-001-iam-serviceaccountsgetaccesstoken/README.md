# Service Account Access Token Generation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** principal-access
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Impersonate a privileged service account via `iam.serviceAccounts.getAccessToken` (granted here through a minimal custom role) to mint an OAuth access token and inherit its `roles/editor` project permissions
* **Terraform Variable:** `enable_gcp_single_account_privesc_one_hop_to_admin_gcp_iam_001_iam_serviceaccountsgetaccesstoken`
* **Schema Version:** 4.8.2
* **Pathfinding.cloud ID:** gcp-iam-001
* **CTF Flag Location:** secret-manager
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access
* **MITRE Techniques:** T1550.001 - Use Alternate Authentication Material: Application Access Token, T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-gcp-iam-001-start` service account to the `pl-prod-gcp-iam-001-target` service account by impersonating it through the `iam.serviceAccounts.getAccessToken` permission and inheriting its `roles/editor` project role.

- **Start:** `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-gcp-iam-001-start@{project_id}.iam.gserviceaccount.com`
- **Destination resource:** `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-gcp-iam-001-target@{project_id}.iam.gserviceaccount.com`

### Starting Permissions

**Required** (`pl-prod-gcp-iam-001-start`):
- `iam.serviceAccounts.getAccessToken` on `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-gcp-iam-001-target@{project_id}.iam.gserviceaccount.com` -- allows minting a short-lived OAuth access token that authenticates as the target service account

**Helpful** (`pl-prod-gcp-iam-001-start`):
- `resourcemanager.projects.get` -- confirm the current project context and lack of direct project-level roles
- `iam.serviceAccounts.list` -- enumerate other service accounts in the project to identify impersonation targets
- `iam.serviceAccounts.getIamPolicy` -- inspect IAM policy bindings on candidate service accounts to find impersonation grants (predefined `roles/iam.serviceAccountTokenCreator` or a custom role granting `iam.serviceAccounts.getAccessToken`)

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
plabs enable gcp-iam-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-iam-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| Resource Identifier | Purpose |
| -- | -- |
| `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-gcp-iam-001-start@{project_id}.iam.gserviceaccount.com` | Starting service account with no project-level roles of its own |
| `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-gcp-iam-001-target@{project_id}.iam.gserviceaccount.com` | Privileged target service account holding `roles/editor` on the project |
| IAM custom role granting `iam.serviceAccounts.getAccessToken` on `pl-prod-gcp-iam-001-target`, bound to `pl-prod-gcp-iam-001-start` | The vulnerable impersonation grant that enables this attack path |
| IAM binding: `roles/editor` on the project granted to `pl-prod-gcp-iam-001-target` | The privilege that makes impersonating the target service account valuable |
| `//secretmanager.googleapis.com/projects/{project_id}/secrets/pl-gcp-iam-001-flag/versions/latest` | CTF flag stored as a Secret Manager secret version |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the `gcloud` commands being executed and their results
3. Mint an impersonated access token for the target service account and verify the identity switch
4. Verify successful privilege escalation to project `roles/editor` access
5. Read the CTF flag from Secret Manager while impersonating the target service account and display it

#### Resources Created by Attack Script

- Short-lived OAuth access tokens minted via impersonation (no persistent credential material is created)
- Local shell variables holding the impersonated identity for the duration of the demo

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo gcp-iam-001-iam-serviceaccountsgetaccesstoken
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-iam-001-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup gcp-iam-001-iam-serviceaccountsgetaccesstoken
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-iam-001-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable gcp-iam-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-iam-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- **Service accounts holding `iam.serviceAccounts.getAccessToken` on other service accounts**: Any principal granted this permission on a service account can mint access tokens that fully authenticate as that account -- functionally equivalent to holding its credentials. This can come from the predefined `roles/iam.serviceAccountTokenCreator` role *or* a custom role (as in this scenario) that grants only `getAccessToken` -- CSPM detection logic that greps for `roles/iam.serviceAccountTokenCreator` by name will miss the custom-role variant, so detection should resolve custom role permission lists too.
- **Impersonation grants that cross a privilege boundary**: Specifically flag cases where the impersonating principal has fewer project-level roles than the service account it can impersonate -- this is the GCP analog of AWS's "role can create access keys for a privileged user" finding.
- **Service accounts with `roles/editor` or `roles/owner` at the project level**: Broad primitive roles like `roles/editor` grant near-administrative access across most GCP services (though notably *not* Secret Manager access -- see below).
- **Unscoped impersonation bindings**: The binding in this scenario is not scoped with IAM Conditions (e.g., time-bound or resource-tag-bound), meaning the starting service account can impersonate the target indefinitely.
- **Lack of separation between automation identities and privileged identities**: The pattern of a low-privilege "operator" service account holding impersonation rights over a high-privilege "workload" service account is a common but risky automation pattern.

#### Prevention Recommendations

- **Avoid granting `iam.serviceAccounts.getAccessToken` across privilege boundaries**: Never grant impersonation rights on a service account to a principal that should not otherwise hold that service account's permissions -- whether via the predefined `roles/iam.serviceAccountTokenCreator` role or a custom role scoped to just this permission.
- **Use IAM Conditions to scope impersonation grants**: Restrict impersonation bindings with conditions such as time-bound access or requester attributes, rather than granting unconditional, standing access.
- **Apply least privilege to the target service account**: Replace broad primitive roles like `roles/editor` with narrowly scoped predefined or custom roles that grant only the permissions the workload actually needs.
- **Enable Organization Policy constraints**: Use `iam.disableServiceAccountKeyCreation` and related organization policies to reduce standing credential material, and pair this with regular audits of service-account impersonation and `serviceAccountUser` bindings via IAM Recommender.
- **Audit IAM bindings regularly with Policy Analyzer**: Use GCP's Policy Analyzer / IAM Recommender to identify service accounts with unused or overly broad impersonation grants and remove them.
- **Prefer Workload Identity Federation over service account impersonation chains**: Where possible, grant external workloads direct, narrowly-scoped access via Workload Identity Federation instead of chaining through an intermediate impersonatable service account.

### Detecting Abuse (CloudSIEM)

#### Cloud Audit Log Events to Monitor

- `iam.googleapis.com/GenerateAccessToken` -- a short-lived access token was minted via service account impersonation; critical when the impersonated service account holds `roles/editor` or `roles/owner` at the project level
- `iam.googleapis.com/SignJwt` -- a JWT was signed on behalf of a service account, commonly used in OIDC-based impersonation flows
- `secretmanager.googleapis.com/AccessSecretVersion` -- a Secret Manager secret version was accessed; investigate when the caller identity is an impersonated service account shortly after a `GenerateAccessToken` event
- `iam.googleapis.com/SetIamPolicy` -- an IAM policy binding was modified on a service account; monitor for new impersonation grants (predefined `roles/iam.serviceAccountTokenCreator` or a custom role including `iam.serviceAccounts.getAccessToken`) being added to service accounts that hold elevated project roles

**Impersonation Chain Pattern**:
- A `GenerateAccessToken` (or `SignJwt`) call for a target service account, followed within seconds by API calls to services the caller's own identity does not have direct access to, is a strong signal of privilege escalation via impersonation.

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [pathfinding.cloud/paths/gcp-iam-001](https://pathfinding.cloud/paths/gcp-iam-001) -- catalog entry for this privilege escalation path
- [GCP IAM documentation: Service Account Impersonation](https://cloud.google.com/iam/docs/service-account-impersonation) -- official documentation on the `roles/iam.serviceAccountTokenCreator` role and impersonation mechanics
- [MITRE ATT&CK T1550.001](https://attack.mitre.org/techniques/T1550/001/) -- Use Alternate Authentication Material: Application Access Token
