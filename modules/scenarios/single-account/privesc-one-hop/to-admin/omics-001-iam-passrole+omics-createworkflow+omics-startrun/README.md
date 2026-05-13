# AWS HealthOmics Workflow to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Pass an admin role to an AWS HealthOmics WDL workflow whose task exfiltrates the execution role's temporary credentials to S3, then retrieve and use those credentials to attach AdministratorAccess to the starting user
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_omics_001_iam_passrole_omics_createworkflow_omics_startrun`
* **Schema Version:** 4.6.1
* **Pathfinding.cloud ID:** omics-001
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1578 - Modify Cloud Compute Infrastructure

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-omics-001-to-admin-starting-user` IAM user to the `pl-prod-omics-001-to-admin-admin-role` administrative role by creating an AWS HealthOmics WDL workflow that runs with the admin role as its execution role, exfiltrates that role's temporary credentials to an S3 bucket, and uses those stolen credentials to attach `AdministratorAccess` to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-omics-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-omics-001-to-admin-admin-role`

### Starting Permissions

**Required** (`pl-prod-omics-001-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-omics-001-to-admin-admin-role` -- allows passing the admin role to HealthOmics as the workflow execution role ARN when calling `omics:StartRun`
- `omics:CreateWorkflow` on `*` -- allows creating the malicious WDL workflow definition that will run as the admin role
- `omics:StartRun` on `*` -- allows launching the workflow run; `requestParameters.roleArn` in CloudTrail carries the passed admin role ARN

**Helpful** (`pl-prod-omics-001-to-admin-starting-user`):
- `s3:GetObject` -- retrieve the exfiltrated admin credentials from the attacker-controlled S3 bucket after the workflow completes
- `omics:GetWorkflow` -- poll workflow status to confirm it reached `ACTIVE` before starting the run
- `omics:GetRun` -- poll run status to confirm it reached `COMPLETED` before retrieving credentials
- `omics:ListRuns` -- enumerate existing workflow runs to discover the run ID
- `iam:ListAttachedUserPolicies` -- verify privilege escalation succeeded by listing policies attached to the starting user

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable omics-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `omics-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-omics-001-to-admin-starting-user` | Scenario-specific starting user with access keys; has `iam:PassRole`, `omics:CreateWorkflow`, and `omics:StartRun` |
| `arn:aws:iam::{account_id}:role/pl-prod-omics-001-to-admin-admin-role` | Administrative role (trusts `omics.amazonaws.com`) passed as `roleArn` to the HealthOmics workflow run |
| `arn:aws:s3:::pl-prod-omics-001-to-admin-output-{attacker_account_id}-{suffix}` | Attacker-account S3 bucket (created via `aws.attacker` provider); HealthOmics output location and credential exfiltration channel |
| `arn:aws:ecr:{region}:{attacker_account_id}:repository/pl-prod-omics-001-to-admin-aws-cli` | Private ECR repository (in attacker account) holding the `aws-cli` image required by HealthOmics (cannot pull from public registries); seeded by `demo_attack.sh` on first run using Docker |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/omics-001-to-admin` | CTF flag stored in SSM Parameter Store; readable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve scenario configuration (admin role ARN, attacker bucket name, ECR image URI) from Terraform outputs
2. Ensure the `aws-cli` container image is available in the private ECR repository (triggers CodeBuild seed on first run, approximately 2-3 minutes)
3. Create a malicious WDL workflow definition that extracts the execution role's temporary credentials from the container credential provider and writes them to the attacker S3 bucket
4. Start a HealthOmics workflow run, passing the admin role as the execution role via `iam:PassRole`
5. Poll until the workflow run reaches `COMPLETED` status (approximately 4-10 minutes)
6. Retrieve the exfiltrated admin role credentials from the S3 bucket
7. Use the stolen credentials to attach `AdministratorAccess` to the starting user
8. Verify successful privilege escalation
9. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions

For deployments using the `aws.attacker` provider (cross-account S3 bucket), the alternate script `demo_attack_cross_account.sh` handles the additional cross-account credential wiring. Use `cleanup_attack_cross_account.sh` to clean up after that variant.

#### Resources Created by Attack Script

- HealthOmics workflow definition (deleted by cleanup script)
- HealthOmics workflow run (deleted by cleanup script)
- Exfiltrated credential file at `s3://pl-prod-omics-001-to-admin-output-{attacker_account_id}-{suffix}/exfil/creds.json` (deleted by cleanup script)
- `AdministratorAccess` managed policy attached to `pl-prod-omics-001-to-admin-starting-user` (detached by cleanup script)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo omics-001-iam-passrole+omics-createworkflow+omics-startrun
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup omics-001-iam-passrole+omics-createworkflow+omics-startrun
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable omics-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `omics-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user with `iam:PassRole` on a role that has `AdministratorAccess` or equivalent permissions, combined with `omics:CreateWorkflow` and `omics:StartRun` — a complete privilege escalation path through AWS HealthOmics
- IAM role with `AdministratorAccess` whose trust policy allows `omics.amazonaws.com` to assume it — this role can be passed to any HealthOmics workflow as the execution role
- `iam:PassRole` permission scoped to an administrative role without a `iam:PassedToService` condition key restricting which services the role can be passed to

#### Prevention Recommendations

- Restrict `iam:PassRole` using the `iam:PassedToService` condition key; if HealthOmics is not used in the account, deny `"iam:PassedToService": "omics.amazonaws.com"` entirely via SCP
- Scope `iam:PassRole` resource ARNs to least-privilege HealthOmics execution roles only; never allow passing roles with `AdministratorAccess` or broad IAM write permissions to compute services
- Audit all IAM roles with `omics.amazonaws.com` in their trust policy and verify none carry `AdministratorAccess` or permissions allowing IAM mutations
- Apply permission boundaries to HealthOmics execution roles to cap maximum privileges even when broad managed policies are attached — network isolation does not compensate for overly permissive role credentials inside workflow tasks
- Implement SCPs to deny `omics:CreateWorkflow` and `omics:StartRun` in accounts and regions where HealthOmics is not in use
- Use IAM Access Analyzer to automatically detect privilege escalation paths combining `iam:PassRole` with `omics:CreateWorkflow` and `omics:StartRun`

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `omics:CreateWorkflow` -- new HealthOmics workflow definition created; high severity when the caller also holds `iam:PassRole` on high-privilege roles; inspect `requestParameters.name` for attacker-chosen workflow names
- `omics:StartRun` -- HealthOmics workflow run started; inspect `requestParameters.roleArn` — a privileged or administrative role ARN here is the CloudTrail signal for PassRole abuse via HealthOmics; correlate with a preceding `omics:CreateWorkflow` from the same principal
- `s3:PutObject` -- credential file written to S3 from within the HealthOmics task context; suspicious when the caller is a HealthOmics execution role identity and the object contains credential-shaped JSON
- `s3:GetObject` -- attacker retrieving the exfiltrated credential file from the output bucket after workflow completion
- `iam:AttachUserPolicy` -- `AdministratorAccess` or similar managed policy attached to an IAM user using temporary credentials belonging to a HealthOmics execution role; the caller identity in CloudTrail will be the assumed execution role, not the starting user

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS HealthOmics Workflow Documentation](https://docs.aws.amazon.com/omics/latest/dev/workflows.html) -- explains how HealthOmics WDL workflows execute and why the execution role's credentials are injected into task containers
- [AWS IAM PassRole Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html) -- explains PassRole mechanics and how to restrict it with `iam:PassedToService`
- [Rhino Security Labs - AWS IAM Privilege Escalation Methods](https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation/) -- comprehensive overview of IAM privilege escalation techniques including PassRole patterns
- [pathfinding.cloud/paths/omics-001](https://pathfinding.cloud/paths/omics-001) -- documented attack path for this scenario
