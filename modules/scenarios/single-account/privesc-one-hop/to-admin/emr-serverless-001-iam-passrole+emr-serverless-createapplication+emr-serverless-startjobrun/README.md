# EMR Serverless Application Job to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Creating an EMR Serverless Spark application and running a job with an admin execution role to grant the starting user administrative access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_emr_serverless_001_iam_passrole_emr_serverless_createapplication_emr_serverless_startjobrun`
* **Schema Version:** 4.6.1
* **Pathfinding.cloud ID:** emr-serverless-001
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1578 - Modify Cloud Compute Infrastructure

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-emr-serverless-001-to-admin-starting-user` IAM user to the `pl-prod-emr-serverless-001-to-admin-admin-role` administrative role by creating an EMR Serverless Spark application and submitting a pre-staged PySpark job run that passes the admin role as the execution role and attaches `AdministratorAccess` to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-emr-serverless-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-emr-serverless-001-to-admin-admin-role`

### Starting Permissions

**Required** (`pl-prod-emr-serverless-001-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-emr-serverless-001-to-admin-admin-role` -- allows passing the admin role to the EMR Serverless service as the job execution role ARN (`requestParameters.executionRoleArn`) when starting a job run
- `emr-serverless:CreateApplication` on `*` -- allows creating an EMR Serverless Spark application that serves as the compute environment for the exploit job
- `emr-serverless:StartJobRun` on `*` -- allows submitting a job run that specifies the admin role as `executionRoleArn` and the pre-staged exploit script as the entry point

**Helpful** (`pl-prod-emr-serverless-001-to-admin-starting-user`):
- `emr-serverless:GetApplication` -- check application state before submitting job
- `emr-serverless:GetJobRun` -- monitor job run status and verify completion
- `emr-serverless:ListApplications` -- discover existing applications
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
plabs enable emr-serverless-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `emr-serverless-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-emr-serverless-001-to-admin-starting-user` | Scenario-specific starting user with access keys, `iam:PassRole`, `emr-serverless:CreateApplication`, and `emr-serverless:StartJobRun` permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-emr-serverless-001-to-admin-admin-role` | Administrative role (trusts `emr-serverless.amazonaws.com`) passed as `executionRoleArn` to the EMR Serverless job run |
| `arn:aws:s3:::pl-prod-emr-serverless-001-to-admin-scripts-{attacker_account_id}-{suffix}` | Attacker-account S3 bucket (created via `aws.attacker` provider); holds the pre-staged PySpark exploit script that attaches `AdministratorAccess` to the starting user |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/emr-serverless-001-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Retrieve the attacker bucket name and admin role ARN from Terraform outputs
4. Create an EMR Serverless Spark application and wait for it to reach `CREATED` state
5. Submit a job run passing the admin role as `executionRoleArn` and the pre-staged PySpark exploit script as the entry point
6. Poll until the EMR Serverless job reaches `SUCCESS` status (typically 1-2 minutes)
7. Verify successful privilege escalation by confirming `AdministratorAccess` is attached to the starting user
8. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions

#### Resources Created by Attack Script

- `AdministratorAccess` managed policy attached to `pl-prod-emr-serverless-001-to-admin-starting-user`
- EMR Serverless application created in the prod account (deleted by cleanup script)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo emr-serverless-001-iam-passrole+emr-serverless-createapplication+emr-serverless-startjobrun
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup emr-serverless-001-iam-passrole+emr-serverless-createapplication+emr-serverless-startjobrun
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable emr-serverless-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `emr-serverless-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user with `iam:PassRole` permission on a role that has administrative permissions
- IAM user with `emr-serverless:CreateApplication` and `emr-serverless:StartJobRun` combined with `iam:PassRole`, forming a privilege escalation path through EMR Serverless
- IAM role with `AdministratorAccess` or equivalent permissions that trusts `emr-serverless.amazonaws.com` and can be passed to EMR Serverless job runs
- Privilege escalation path from IAM user to admin via EMR Serverless job submission

#### Prevention Recommendations

- Restrict `iam:PassRole` using the `iam:PassedToService` condition key to limit which services a role can be passed to; if EMR Serverless is not used, deny `"iam:PassedToService": "emr-serverless.amazonaws.com"` entirely
- Implement Service Control Policies (SCPs) to deny `emr-serverless:CreateApplication` and `emr-serverless:StartJobRun` in accounts and regions where EMR Serverless is not required
- Audit all IAM roles with trust policies allowing `emr-serverless.amazonaws.com` and ensure none carry `AdministratorAccess` or broad IAM write permissions
- Scope `iam:PassRole` resource constraints to non-privileged roles only; deny passing roles with `AdministratorAccess` or broad IAM permissions to EMR Serverless
- Use IAM Access Analyzer to automatically detect privilege escalation paths involving `iam:PassRole` and `emr-serverless:StartJobRun`
- Restrict which S3 buckets can be used as EMR Serverless job entry points to prevent arbitrary code execution via attacker-controlled scripts

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `emr-serverless:CreateApplication` -- new EMR Serverless application created; inspect subsequent `StartJobRun` calls from the same principal for privileged execution roles
- `emr-serverless:StartJobRun` -- job run submitted; inspect `requestParameters.executionRoleArn` -- a privileged role ARN here is the CloudTrail signal for PassRole abuse via EMR Serverless; high severity when the execution role has administrative permissions
- `iam:AttachUserPolicy` -- managed policy attached to an IAM user from within an EMR Serverless job context; critical when the policy is `AdministratorAccess` and the caller is an EMR Serverless execution role

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS EMR Serverless Documentation](https://docs.aws.amazon.com/emr/latest/EMR-Serverless-UserGuide/getting-started.html) -- explains how EMR Serverless job runs work and why the execution role's credentials are injected into the Spark worker environment
- [AWS IAM PassRole Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html) -- explains PassRole mechanics and how to restrict it with `iam:PassedToService`
- [Rhino Security Labs - AWS IAM Privilege Escalation Methods](https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation/) -- comprehensive overview of IAM privilege escalation techniques including PassRole patterns
- [pathfinding.cloud/paths/emr-serverless-001](https://pathfinding.cloud/paths/emr-serverless-001) -- documented attack path for this scenario
