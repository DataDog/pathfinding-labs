# AWS Braket Hybrid Job to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Pass an admin role to an Amazon Braket Hybrid Job running a pre-staged malicious Python script that grants the starting user administrative access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_braket_001_iam_passrole_braket_createjob`
* **Schema Version:** 4.6.1
* **Pathfinding.cloud ID:** braket-001
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1578 - Modify Cloud Compute Infrastructure

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-braket-001-to-admin-starting-user` IAM user to the `pl-prod-braket-001-to-admin-admin-role` administrative role by creating an Amazon Braket Hybrid Job that passes the admin role as the execution role and runs a pre-staged malicious Python script that attaches `AdministratorAccess` to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-braket-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-braket-001-to-admin-admin-role`

### Starting Permissions

**Required** (`pl-prod-braket-001-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-braket-001-to-admin-admin-role` -- allows passing the admin role to the Braket service as the job execution role ARN when creating the Hybrid Job
- `braket:CreateJob` on `*` -- allows creating a Braket Hybrid Job that specifies the admin role as `roleArn` and the pre-staged malicious script as the algorithm source

**Helpful** (`pl-prod-braket-001-to-admin-starting-user`):
- `braket:GetJob` -- monitor job execution status and verify job completion
- `braket:SearchJobs` -- list existing Braket jobs to discover job ARN
- `s3:GetObject` -- retrieve job output results from S3
- `iam:ListAttachedUserPolicies` -- verify privilege escalation success by listing attached policies

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable braket-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `braket-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-braket-001-to-admin-starting-user` | Scenario-specific starting user with access keys, `iam:PassRole`, and `braket:CreateJob` permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-braket-001-to-admin-admin-role` | Administrative role (trusts `braket.amazonaws.com`) passed as `roleArn` to the Braket Hybrid Job |
| `arn:aws:s3:::amazon-braket-pl-prod-braket-001-{attacker_account_id}-{suffix}` | Attacker-account S3 bucket (created via `aws.attacker` provider) with the required `amazon-braket-` prefix; holds the pre-staged malicious Python exploit script |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/braket-001-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Retrieve the attacker bucket name from Terraform outputs
4. Create a Braket Hybrid Job with the admin role as `roleArn` and the pre-staged exploit script as the algorithm source
5. Poll until the Braket job reaches `COMPLETED` status
6. Verify successful privilege escalation by demonstrating admin access
7. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions

#### Resources Created by Attack Script

- `AdministratorAccess` managed policy attached to `pl-prod-braket-001-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo braket-001-iam-passrole+braket-createjob
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup braket-001-iam-passrole+braket-createjob
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable braket-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `braket-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user with `iam:PassRole` permission on a role that has administrative permissions
- IAM user with `braket:CreateJob` combined with `iam:PassRole`, forming a privilege escalation path through Amazon Braket Hybrid Jobs
- IAM role with `AdministratorAccess` or equivalent permissions that trusts `braket.amazonaws.com` and can be passed to Braket jobs
- Privilege escalation path from IAM user to admin via Amazon Braket Hybrid Job submission

#### Prevention Recommendations

- Restrict `iam:PassRole` using the `iam:PassedToService` condition key to limit which services a role can be passed to; if Braket is not used, deny `"iam:PassedToService": "braket.amazonaws.com"` entirely
- Implement Service Control Policies (SCPs) to deny `braket:CreateJob` in accounts and regions where Amazon Braket is not required, eliminating this attack surface from unused services
- Audit all IAM roles with trust policies allowing `braket.amazonaws.com` and ensure none carry `AdministratorAccess` or broad IAM permissions
- Scope `iam:PassRole` resource constraints to non-privileged roles only; deny passing roles with `AdministratorAccess` or broad IAM write permissions to Braket
- Use IAM Access Analyzer to automatically detect privilege escalation paths involving `iam:PassRole` and `braket:CreateJob`
- Apply least-privilege to Braket execution roles and scope permissions to only the quantum devices and S3 paths the job legitimately needs

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `braket:CreateJob` -- new Braket Hybrid Job created; inspect `requestParameters.roleArn` — a privileged role ARN here is the CloudTrail signal for PassRole abuse via Braket; high severity when the role has administrative permissions
- `iam:AttachUserPolicy` -- managed policy attached to an IAM user from within a Braket job context; critical when the policy is `AdministratorAccess` and the caller is a Braket execution role

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS Braket Hybrid Jobs Documentation](https://docs.aws.amazon.com/braket/latest/developerguide/braket-jobs.html) -- explains how Hybrid Jobs work and why the execution role's credentials are injected into the container environment
- [AWS IAM PassRole Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html) -- explains PassRole mechanics and how to restrict it with `iam:PassedToService`
- [Rhino Security Labs - AWS IAM Privilege Escalation Methods](https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation/) -- comprehensive overview of IAM privilege escalation techniques including PassRole patterns
- [pathfinding.cloud/paths/braket-001](https://pathfinding.cloud/paths/braket-001) -- documented attack path for this scenario
