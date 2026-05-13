# Kinesis Analytics Application to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Pass an admin role to an Amazon Managed Service for Apache Flink application running a pre-staged malicious JAR that grants the starting user administrative access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_kinesisanalytics_001_iam_passrole_kinesisanalytics_createapplication_kinesisanalytics_startapplication`
* **Schema Version:** 4.6.1
* **Pathfinding.cloud ID:** kinesisanalytics-001
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1578 - Modify Cloud Compute Infrastructure

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-kinesisanalytics-001-to-admin-starting-user` IAM user to the `pl-prod-kinesisanalytics-001-to-admin-admin-role` administrative role by creating an Amazon Managed Service for Apache Flink application that passes the admin role as the service execution role and runs a pre-staged malicious JAR that attaches `AdministratorAccess` to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-kinesisanalytics-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-kinesisanalytics-001-to-admin-admin-role`

### Starting Permissions

**Required** (`pl-prod-kinesisanalytics-001-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-kinesisanalytics-001-to-admin-admin-role` -- allows passing the admin role to the Kinesis Analytics service as the service execution role when creating the Flink application; `requestParameters.serviceExecutionRole` in `kinesisanalyticsv2:CreateApplication` carries this ARN
- `kinesisanalytics:CreateApplication` on `*` -- allows creating a Managed Apache Flink application that specifies the admin role as `ServiceExecutionRole` and the pre-staged malicious JAR as the S3 content location
- `kinesisanalytics:StartApplication` on `*` -- allows starting the created Flink application, which causes the Flink runtime to execute the malicious JAR under the admin role's credentials

**Helpful** (`pl-prod-kinesisanalytics-001-to-admin-starting-user`):
- `kinesisanalytics:DescribeApplication` -- check application status and verify it is running
- `kinesisanalytics:ListApplications` -- list existing Flink applications
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
plabs enable kinesisanalytics-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `kinesisanalytics-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-kinesisanalytics-001-to-admin-starting-user` | Scenario-specific starting user with access keys, `iam:PassRole`, and Kinesis Analytics permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-kinesisanalytics-001-to-admin-admin-role` | Administrative role (trusts `kinesisanalytics.amazonaws.com`) passed as `ServiceExecutionRole` to the Flink application |
| `arn:aws:s3:::pl-kinesisanalytics-001-code-{attacker_account_id}-{suffix}` | Attacker-account S3 bucket (created via `aws.attacker` provider); holds the pre-built malicious Apache Flink exploit JAR |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/kinesisanalytics-001-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Retrieve the attacker bucket name and JAR S3 key from Terraform outputs
4. Create a Managed Apache Flink application with the admin role as `ServiceExecutionRole` and the pre-staged exploit JAR as the S3 content location
5. Start the application, triggering the malicious JAR to execute under the admin role's credentials
6. Poll until the application reaches `RUNNING` status and the privilege escalation completes
7. Verify successful privilege escalation by demonstrating admin access
8. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions

An alternate script (`demo_attack_cross_account.sh`) is provided for cross-account deployment variants where the JAR bucket and the target account are in different AWS accounts.

#### Resources Created by Attack Script

- Managed Apache Flink application created in the prod account
- `AdministratorAccess` managed policy attached to `pl-prod-kinesisanalytics-001-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo kinesisanalytics-001-iam-passrole+kinesisanalytics-createapplication+kinesisanalytics-startapplication
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup kinesisanalytics-001-iam-passrole+kinesisanalytics-createapplication+kinesisanalytics-startapplication
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable kinesisanalytics-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `kinesisanalytics-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user with `iam:PassRole` permission on a role that has administrative permissions
- IAM user with `kinesisanalytics:CreateApplication` combined with `iam:PassRole`, forming a privilege escalation path through Amazon Managed Service for Apache Flink
- IAM role with `AdministratorAccess` or equivalent permissions that trusts `kinesisanalytics.amazonaws.com` and can be passed as a Flink service execution role
- Privilege escalation path from IAM user to admin via Amazon Managed Service for Apache Flink application creation

#### Prevention Recommendations

- Restrict `iam:PassRole` using the `iam:PassedToService` condition key to limit which services a role can be passed to; if Kinesis Analytics is not used, deny `"iam:PassedToService": "kinesisanalytics.amazonaws.com"` entirely
- Implement Service Control Policies (SCPs) to deny `kinesisanalytics:CreateApplication` in accounts and regions where Managed Apache Flink is not required, eliminating this attack surface from unused services
- Audit all IAM roles with trust policies allowing `kinesisanalytics.amazonaws.com` and ensure none carry `AdministratorAccess` or broad IAM write permissions
- Scope `iam:PassRole` resource constraints to non-privileged roles only; deny passing roles with `AdministratorAccess` or broad IAM write permissions to Kinesis Analytics
- Use IAM Access Analyzer to automatically detect privilege escalation paths involving `iam:PassRole` and `kinesisanalytics:CreateApplication`
- Apply permission boundaries to Kinesis Analytics service execution roles to cap the maximum privileges available to Flink application code

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `kinesisanalyticsv2:CreateApplication` -- new Managed Apache Flink application created; inspect `requestParameters.serviceExecutionRole` — a privileged role ARN here is the CloudTrail signal for PassRole abuse via Kinesis Analytics; high severity when the role has administrative permissions
- `kinesisanalyticsv2:StartApplication` -- Flink application started; critical when preceded by a `CreateApplication` event with a privileged `serviceExecutionRole`
- `iam:AttachUserPolicy` -- managed policy attached to an IAM user from within a Flink application; critical when the policy is `AdministratorAccess` and the caller is a Kinesis Analytics service execution role

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS Managed Service for Apache Flink Documentation](https://docs.aws.amazon.com/managed-flink/latest/java/what-is.html) -- explains how Managed Apache Flink applications work and why the service execution role's credentials are injected into the application runtime
- [AWS IAM PassRole Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html) -- explains PassRole mechanics and how to restrict it with `iam:PassedToService`
- [Rhino Security Labs - AWS IAM Privilege Escalation Methods](https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation/) -- comprehensive overview of IAM privilege escalation techniques including PassRole patterns
- [pathfinding.cloud/paths/kinesisanalytics-001](https://pathfinding.cloud/paths/kinesisanalytics-001) -- documented attack path for this scenario
