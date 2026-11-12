# Service Account setIamPolicy to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** principal-access
* **Path Type:** one-hop
* **Target:** to-admin
* **Points:** 10
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Rewrite a privileged service account's IAM policy via `iam.serviceAccounts.setIamPolicy` (granted here through a minimal custom role) to self-grant `roles/iam.serviceAccountTokenCreator`, then chain impersonation to mint a token for the target and inherit its `roles/owner` project permissions
* **Terraform Variable:** `enable_gcp_single_account_privesc_one_hop_to_admin_gcp_iam_002_iam_serviceaccountssetiampolicy`
* **Schema Version:** 4.9.5
* **Pathfinding.cloud ID:** gcp-iam-002
* **CTF Flag Location:** secret-manager
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1550.001 - Use Alternate Authentication Material: Application Access Token, T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-gcp-iam-002-start` service account to the `pl-prod-gcp-iam-002-target` service account by rewriting the target's IAM policy to self-grant `roles/iam.serviceAccountTokenCreator`, then chaining impersonation to mint a token for the target and inherit its `roles/owner` project role.

- **Start:** `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-gcp-iam-002-start@{project_id}.iam.gserviceaccount.com`
- **Destination resource:** `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-gcp-iam-002-target@{project_id}.iam.gserviceaccount.com`

### Starting Permissions

**Required** (`pl-prod-gcp-iam-002-start`):
- `iam.serviceAccounts.setIamPolicy` on `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-gcp-iam-002-target@{project_id}.iam.gserviceaccount.com` -- allows overwriting the target service account's IAM policy, including adding a self-binding for `roles/iam.serviceAccountTokenCreator`

**Helpful** (`pl-prod-gcp-iam-002-start`):
- `iam.serviceAccounts.getIamPolicy` -- required by `gcloud iam service-accounts add-iam-policy-binding` only: gcloud reads the existing SA policy before merging and writing it back; not needed with the raw `setIamPolicy` API, which accepts a full policy body constructed from scratch
- `iam.serviceAccounts.list` -- enumerate other service accounts in the project to identify `setIamPolicy` targets

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
plabs enable gcp-iam-002-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-iam-002-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| Resource Identifier | Purpose |
| -- | -- |
| `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-gcp-iam-002-start@{project_id}.iam.gserviceaccount.com` | Starting service account with no project-level roles of its own |
| `//iam.googleapis.com/projects/{project_id}/serviceAccounts/pl-prod-gcp-iam-002-target@{project_id}.iam.gserviceaccount.com` | Privileged target service account holding `roles/owner` on the project |
| IAM custom role `gcp_iam_002_sa_setiampolicy_min` granting only `iam.serviceAccounts.setIamPolicy`, bound to `pl-prod-gcp-iam-002-start` at the `pl-prod-gcp-iam-002-target` SA resource level | The vulnerable grant: lets the starting SA rewrite the target SA's IAM policy |
| IAM custom role `gcp_iam_002_sa_recon_help` bound to `pl-prod-gcp-iam-002-start` at the project level | The helpful recon + gcloud-mechanic permissions (`iam.serviceAccounts.getIamPolicy`, `iam.serviceAccounts.list`) so the starting SA can find the target itself — not part of the modeled vulnerability |
| IAM binding: `roles/owner` on the project granted to `pl-prod-gcp-iam-002-target` | The privilege that makes impersonating the target service account valuable |
| `//secretmanager.googleapis.com/projects/{project_id}/secrets/pl-gcp-iam-002-flag/versions/latest` | CTF flag stored as a Secret Manager secret version |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Confirm the starting service account cannot read the flag and enumerate the project's service accounts to identify the target
3. Call `setIamPolicy` on the target service account to self-grant `roles/iam.serviceAccountTokenCreator` (the exploit)
4. Chain impersonation (your ADC → starting SA → target SA) to mint a short-lived token for the target service account
5. Verify `roles/owner` access by writing and removing a project label, then read the CTF flag from Secret Manager and display it
6. Run with `--api-only` to prove the attack needs only `iam.serviceAccounts.setIamPolicy`: it calls the raw `setIamPolicy` REST endpoint with a policy body built from scratch, skipping the `getIamPolicy` read that `gcloud add-iam-policy-binding` performs

#### Resources Created by Attack Script

- A new IAM policy binding on the target service account granting `roles/iam.serviceAccountTokenCreator` to the starting service account (removed by `cleanup_attack.sh`)
- Short-lived OAuth access tokens minted via chained impersonation (no persistent credential material is created)
- A transient project label (`pl-privesc-verified=true`) written and then removed during the write-access proof
- Local shell variables holding the impersonated identities for the duration of the demo

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo gcp-iam-002-iam-serviceaccountssetiampolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-iam-002-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup gcp-iam-002-iam-serviceaccountssetiampolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-iam-002-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable gcp-iam-002-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gcp-iam-002-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- **Service accounts holding `iam.serviceAccounts.setIamPolicy` on other service accounts**: Any principal that can write a service account's IAM policy can grant itself (or any identity it controls) `roles/iam.serviceAccountTokenCreator` on that account, then mint tokens as it -- functionally equivalent to holding its credentials. This is the key teaching point of this scenario: detection should key on the **effective `iam.serviceAccounts.setIamPolicy` permission on an enabled service account**, not on `getIamPolicy` reads. `gcloud add-iam-policy-binding` happens to call `getIamPolicy` first, but the raw `setIamPolicy` API does not need it (proven by the demo's `--api-only` mode), so `getIamPolicy` is a weak and bypassable signal.
- **`setIamPolicy` granted via a custom role, not just the predefined roles**: The permission can arrive through `roles/iam.serviceAccountAdmin` *or* a narrowly scoped custom role (as in this scenario) that bundles only `setIamPolicy`. Detection logic that greps for predefined role names by string will miss the custom-role variant -- resolve custom role permission lists too.
- **Impersonation/policy-write grants that cross a privilege boundary**: Flag cases where the principal with `setIamPolicy` on a service account has fewer project-level roles than the account it can rewrite -- this is the GCP analog of AWS's "role can modify a privileged user" finding.
- **Service accounts with `roles/editor` or `roles/owner` at the project level**: Broad primitive roles grant administrative access across most GCP services, including Secret Manager payload access in the case of `roles/owner`.
- **Unscoped `setIamPolicy` bindings on service accounts**: The binding in this scenario is not scoped with IAM Conditions, so the starting service account can rewrite the target's policy at will and indefinitely.

#### Prevention Recommendations

- **Avoid granting `iam.serviceAccounts.setIamPolicy` across privilege boundaries**: Never grant policy-write rights on a service account to a principal that should not otherwise hold that account's permissions -- whether via `roles/iam.serviceAccountAdmin` or a custom role scoped to just `setIamPolicy`. Writing a SA's policy is equivalent to being able to impersonate it.
- **Use IAM Conditions to scope policy-management grants**: Restrict `setIamPolicy` bindings with conditions (time-bound access, requester attributes) rather than granting unconditional, standing access.
- **Apply least privilege to the target service account**: Replace broad primitive roles like `roles/owner` with narrowly scoped predefined or custom roles that grant only what the workload needs.
- **Enable Organization Policy constraints**: Use `iam.disableServiceAccountKeyCreation` and related org policies to reduce standing credential material, and pair this with regular audits of `serviceAccountAdmin`/`setIamPolicy` and `serviceAccountTokenCreator` bindings via IAM Recommender.
- **Alert on self-referential `setIamPolicy` changes**: Monitor for a principal adding a `roles/iam.serviceAccountTokenCreator` binding for itself on a service account it can write -- the signature of this exact escalation.
- **Audit IAM bindings regularly with Policy Analyzer**: Use GCP's Policy Analyzer / IAM Recommender to identify service accounts whose policies can be written by lower-privilege principals and remove those grants.

### Detecting Abuse (CloudSIEM)

#### Cloud Audit Log Events to Monitor

- `iam.googleapis.com/SetIamPolicy` -- a service account's IAM policy was overwritten; critical when the new policy adds `roles/iam.serviceAccountTokenCreator` (or a custom role including `iam.serviceAccounts.getAccessToken`/`getOpenIdToken`) for a principal that previously could not impersonate the account. This is the primary signal for this attack and fires in both the `gcloud` and raw-API paths.
- `iam.googleapis.com/GenerateAccessToken` -- a short-lived access token was minted via service account impersonation; critical when the impersonated service account holds `roles/owner` or `roles/editor`, and especially when it immediately follows a `SetIamPolicy` event that granted the caller tokenCreator
- `secretmanager.googleapis.com/AccessSecretVersion` -- a Secret Manager secret version was accessed; investigate when the caller is an impersonated service account shortly after a `GenerateAccessToken` event
- `cloudresourcemanager.googleapis.com/UpdateProject` -- a project was modified (e.g., labels changed); flag when the caller is an impersonated service account whose own identity could not otherwise write the project

**Self-Grant + Impersonation Chain Pattern**:
- A `SetIamPolicy` call on a service account that adds tokenCreator for the caller, followed within seconds by a `GenerateAccessToken` for that same service account and then API calls the caller's own identity could not make, is a high-confidence signal of privilege escalation via policy rewrite.

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [GCP IAM documentation: Service Account Impersonation](https://cloud.google.com/iam/docs/service-account-impersonation) -- official documentation on `roles/iam.serviceAccountTokenCreator` and impersonation mechanics
- [GCP IAM documentation: Manage access to service accounts](https://cloud.google.com/iam/docs/manage-access-service-accounts) -- how `setIamPolicy` on a service account controls who can impersonate it
- [Rhino Security Labs: Privilege Escalation in Google Cloud Platform – Part 2](https://rhinosecuritylabs.com/gcp/privilege-escalation-google-cloud-platform-part-2/) -- original research describing service-account IAM-policy abuse for privilege escalation
- [MITRE ATT&CK T1098.001](https://attack.mitre.org/techniques/T1098/001/) -- Account Manipulation: Additional Cloud Credentials
