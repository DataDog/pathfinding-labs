# Custom Role Update Self-Escalation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** self-escalation
* **Path Type:** self-escalation
* **Target:** to-admin
* **Points:** 10
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** A service account bound to a project custom role that itself grants `iam.roles.update` edits that same role to add `resourcemanager.projects.setIamPolicy`, then uses the newly-acquired permission to self-bind `roles/owner` on the project
* **Terraform Variable:** `enable_gcp_single_account_privesc_self_escalation_to_admin_gcp_iam_003_iam_rolesupdate`
* **Schema Version:** 4.9.5
* **Pathfinding.cloud ID:** gcp-iam-003
* **CTF Flag Location:** secret-manager
* **MITRE Tactics:** TA0004 - Privilege Escalation
* **MITRE Techniques:** T1098 - Account Manipulation, T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-gcp-iam-003-start` service account to project administrator (`roles/owner`) by updating the very custom role it is bound to -- adding `resourcemanager.projects.setIamPolicy` -- and then using that acquired permission to grant itself `roles/owner`.

- **Start:** `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-gcp-iam-003-start@{project_id}.iam.gserviceaccount.com`
- **Destination resource:** `//cloudresourcemanager.googleapis.com/projects/{project_id}` (self-bound `roles/owner`)

### Starting Permissions

**Required** (`pl-prod-gcp-iam-003-start`):
- `iam.roles.update` on `projects/{project_id}/roles/gcp_iam_003_editable` -- the vulnerability: the service account is a member of this custom role and can also update it, so it can add any permission it wants to the role it already holds. (`resourcemanager.projects.setIamPolicy` is **not** a starting permission -- it is *acquired* mid-attack by editing the role.)

**Helpful** (`pl-prod-gcp-iam-003-start`):
- `iam.roles.get` -- required by `gcloud iam roles update --add-permissions` only: gcloud reads the role before writing the appended permission list; not needed with the raw `roles.patch` API, which replaces `includedPermissions` wholesale
- `resourcemanager.projects.getIamPolicy` -- required by `gcloud projects add-iam-policy-binding` only: gcloud reads the project IAM policy before writing it; not needed with the raw `setIamPolicy` API
- `iam.roles.list` -- enumerate project custom roles to identify which bound role is editable
- `resourcemanager.projects.get` -- confirm the current project context and the lack of any direct admin roles

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
plabs enable gcp-iam-003-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-iam-003-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| Resource Identifier | Purpose |
| -- | -- |
| `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-gcp-iam-003-start@{project_id}.iam.gserviceaccount.com` | Starting service account -- the single principal in this self-escalation; holds no direct admin roles |
| `projects/{project_id}/roles/gcp_iam_003_editable` | The vulnerable project custom role. It grants `iam.roles.update` (plus the helpful gcloud-mechanic/recon permissions) and is bound to the starting service account -- so the SA can edit the very role it holds |
| IAM binding: `gcp_iam_003_editable` custom role granted to `pl-prod-gcp-iam-003-start` at the project level | Both the required-permission grant and the "attacker already holds the role" precondition in one binding |
| `//secretmanager.googleapis.com/projects/{project_id}/secrets/pl-gcp-iam-003-flag/versions/latest` | CTF flag stored as a Secret Manager secret version; no `secretAccessor` is pre-granted, so it is readable only after the attacker self-binds `roles/owner` |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output, impersonating the starting service account via `--impersonate-service-account` throughout (no second principal, no static key)
2. Confirm the baseline: the starting service account cannot read the flag secret (no `secretAccessor`), then enumerate project custom roles and describe the editable role to confirm it includes `iam.roles.update`
3. Call `iam.roles.update` to add `resourcemanager.projects.setIamPolicy` to the editable custom role the service account is bound to
4. Use the newly-acquired `resourcemanager.projects.setIamPolicy` permission to self-bind `roles/owner` on the project
5. Read the CTF flag from Secret Manager as the escalated starting service account (`roles/owner` includes `secretmanager.versions.access`) and display it

Run with `--api-only` to execute the attack against the raw IAM (`roles.patch`) and Cloud Resource Manager (`setIamPolicy`) REST APIs directly, proving that only `iam.roles.update` and the acquired `resourcemanager.projects.setIamPolicy` are strictly required -- without the gcloud-mechanic permissions (`iam.roles.get`, `resourcemanager.projects.getIamPolicy`).

#### Resources Created by Attack Script

- A modified `includedPermissions` list on the `gcp_iam_003_editable` custom role (adds `resourcemanager.projects.setIamPolicy`)
- A new project IAM binding granting `roles/owner` to the starting service account
- Short-lived OAuth access tokens minted via impersonation (no persistent credential material is created)
- A `.demo_active` marker file in the scenario directory

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo gcp-iam-003-iam-rolesupdate
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-iam-003-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup gcp-iam-003-iam-rolesupdate
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-iam-003-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable gcp-iam-003-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-iam-003-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- **An identity that is a member of a custom role it can also update**: This is the core of the vulnerability. If a principal holds effective `iam.roles.update` on a custom role *and* is itself bound to that same role, it can add any permission to the role and thereby grant itself that permission. Detection must correlate role membership with `iam.roles.update` authority over that same role -- a scan that looks at either fact in isolation misses it.
- **Custom roles that include `iam.roles.update`**: Any custom role granting `iam.roles.update` on project roles is effectively a grant of the full set of permissions the role holder can later add -- treat it as a sensitive, near-administrative capability.
- **`resourcemanager.projects.setIamPolicy` reachable (even indirectly)**: Because the editable role can be amended to include `setIamPolicy`, the starting service account's *potential* permission set includes full project IAM policy control. CSPM path analysis should model "permissions the identity can grant itself," not just its current effective permissions.
- **Unscoped, standing custom-role bindings**: The binding here is not restricted with IAM Conditions, so the service account can update the role at any time, indefinitely.
- **Service accounts with no obvious need for role-administration permissions**: An automation/workload identity holding `iam.roles.update` is a strong signal of over-provisioning.

#### Prevention Recommendations

- **Never bind a principal to a custom role that grants `iam.roles.update` over that same role**: Break the self-reference. If a principal must administer roles, ensure it is not itself a member of the roles it can edit, and keep role-administration permissions in a separate, tightly-held identity.
- **Restrict `iam.roles.update` to dedicated administrators**: Treat role-editing permissions as administrative. Use predefined roles like `roles/iam.roleAdmin` only for break-glass or platform-team identities, never for workload service accounts.
- **Use IAM Conditions to scope role-administration bindings**: Add time-bound or resource-constrained conditions so standing, unconditional role-edit access is not granted.
- **Alert on changes to custom role `includedPermissions`**: Especially additions of high-impact permissions such as `resourcemanager.projects.setIamPolicy`, `iam.serviceAccounts.getAccessToken`, or `iam.serviceAccounts.setIamPolicy`.
- **Audit project IAM bindings with Policy Analyzer / IAM Recommender**: Regularly review which identities can modify project IAM policy and remove `roles/owner`/`setIamPolicy` capability from identities that do not need it.
- **Apply least privilege to custom roles**: Grant only the specific permissions a workload needs; avoid bundling role-administration or policy-administration permissions into general-purpose custom roles.

### Detecting Abuse (CloudSIEM)

#### Cloud Audit Log Events to Monitor

- `iam.googleapis.com/UpdateRole` -- a custom role's definition was modified; critical when the modification adds high-impact permissions (e.g. `resourcemanager.projects.setIamPolicy`) and the caller is itself a member of that role
- `cloudresourcemanager.googleapis.com/SetIamPolicy` -- the project IAM policy was changed; flag when a new `roles/owner`, `roles/editor`, or other privileged binding is added, especially when the member being added is the same identity making the call (self-binding)
- `iam.googleapis.com/GenerateAccessToken` -- a short-lived token was minted via impersonation; relevant here because the demo operates the starting service account through `--impersonate-service-account`
- `secretmanager.googleapis.com/AccessSecretVersion` -- a Secret Manager secret version was accessed; investigate when the caller gained `roles/owner` shortly beforehand via a `SetIamPolicy` self-binding

**Self-Escalation Chain Pattern**:
- An `UpdateRole` that adds `resourcemanager.projects.setIamPolicy`, followed within seconds by a `SetIamPolicy` that grants the caller `roles/owner`, followed by access to previously-denied resources, is a high-confidence signal of custom-role self-escalation.

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [Rhino Security Labs: Privilege Escalation in GCP (Part 1)](https://rhinosecuritylabs.com/gcp/privilege-escalation-google-cloud-platform-part-1/) -- original research describing `iam.roles.update`-based self-escalation and related GCP privilege escalation primitives
- [GCP IAM documentation: Custom roles](https://cloud.google.com/iam/docs/creating-custom-roles) -- official documentation on creating and updating custom roles
- [MITRE ATT&CK T1098](https://attack.mitre.org/techniques/T1098/) -- Account Manipulation
