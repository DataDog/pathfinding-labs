# AWS Batch Job Submission to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Pass privileged role to AWS Batch job definition and submit a job that grants the starting user administrative access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_batch_001_iam_passrole_batch_registerjobdefinition_batch_submitjob`
* **Schema Version:** 4.6.1
* **Pathfinding.cloud ID:** batch-001
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1610 - Deploy Container

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-batch-001-to-admin-starting-user` IAM user to the `pl-prod-batch-001-to-admin-admin-role` administrative role by registering an AWS Batch job definition with the admin role as the `jobRoleArn`, submitting the job, and having the container execute with administrative credentials to attach `AdministratorAccess` to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-batch-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-batch-001-to-admin-admin-role`

### Starting Permissions

**Required** (`pl-prod-batch-001-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-batch-001-to-admin-admin-role` -- allows passing the admin role to the Batch service as the job role ARN in the job definition
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-batch-001-to-admin-execution-role` -- allows passing the ECS task execution role to the Batch service when registering the job definition
- `batch:RegisterJobDefinition` on `*` -- allows registering a new Batch job definition specifying the admin role as `jobRoleArn`
- `batch:SubmitJob` on `*` -- allows submitting the registered job definition to the existing Fargate job queue

**Helpful** (`pl-prod-batch-001-to-admin-starting-user`):
- `batch:DescribeJobs` -- monitor job execution status and verify job completion
- `batch:DescribeJobQueues` -- discover existing job queues available for job submission
- `batch:DescribeComputeEnvironments` -- discover existing compute environments
- `batch:DeregisterJobDefinition` -- clean up the job definition after the demonstration
- `iam:ListAttachedUserPolicies` -- verify privilege escalation success by listing attached policies

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew tap DataDog/pathfinding-labs https://github.com/DataDog/pathfinding-labs
   brew install DataDog/pathfinding-labs/plabs
   ```
   Or with Go 1.25+ installed:
   ```bash
   go install github.com/DataDog/pathfinding-labs/cmd/plabs@latest
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable batch-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `batch-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-batch-001-to-admin-starting-user` | Scenario-specific starting user with access keys, PassRole, and Batch permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-batch-001-to-admin-admin-role` | Administrative role (trusts `ecs-tasks.amazonaws.com`) passed as `jobRoleArn` to the Batch job definition |
| `arn:aws:iam::{account_id}:role/pl-prod-batch-001-to-admin-execution-role` | ECS task execution role for pulling container images and sending logs to CloudWatch |
| Fargate compute environment | AWS Batch compute environment using Fargate for serverless container execution |
| Job queue | AWS Batch job queue associated with the Fargate compute environment |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/batch-001-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Register a Batch job definition with the admin role as the `jobRoleArn`
4. Submit the job to the existing Fargate job queue
5. Wait for the Batch job to complete execution
6. Verify successful privilege escalation by demonstrating admin access
7. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions

#### Resources Created by Attack Script

- AWS Batch job definition with the admin role as `jobRoleArn`
- `AdministratorAccess` managed policy attached to `pl-prod-batch-001-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo batch-001-iam-passrole+batch-registerjobdefinition+batch-submitjob
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `batch-001-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup batch-001-iam-passrole+batch-registerjobdefinition+batch-submitjob
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `batch-001-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable batch-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `batch-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user with `iam:PassRole` permission on a role that has administrative permissions
- IAM user with `batch:RegisterJobDefinition` and `batch:SubmitJob` permissions combined with `iam:PassRole`, forming a privilege escalation path
- IAM role with `AdministratorAccess` or equivalent permissions that trusts `ecs-tasks.amazonaws.com` and can be passed to Batch job definitions
- Privilege escalation path from IAM user to admin via AWS Batch job submission

#### Prevention Recommendations

- Restrict `iam:PassRole` using the `iam:PassedToService` condition key to limit which services a role can be passed to (e.g., `"iam:PassedToService": "ecs-tasks.amazonaws.com"`)
- Scope `iam:PassRole` resource constraints to non-privileged roles only; deny passing roles with `AdministratorAccess` or broad IAM permissions to Batch
- Implement SCPs that deny `batch:RegisterJobDefinition` when the request includes a `jobRoleArn` referencing a privileged role
- Use IAM Access Analyzer to automatically detect privilege escalation paths involving `iam:PassRole` and Batch job submission
- Grant `batch:RegisterJobDefinition` and `batch:SubmitJob` only to automation accounts or roles with a demonstrated need; treat these as high-risk permissions in any IAM user policy
- Enable AWS Config rules to alert when Batch job definitions are registered with roles that carry administrative permissions

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `batch:RegisterJobDefinition` -- new Batch job definition registered; inspect `requestParameters.containerProperties.jobRoleArn` — a privileged role ARN here is the CloudTrail signal for PassRole abuse via Batch; high severity when the role has administrative permissions
- `batch:SubmitJob` -- Batch job submitted; correlate with a preceding `RegisterJobDefinition` call from the same principal to identify abuse of newly registered definitions
- `iam:AttachUserPolicy` -- managed policy attached to an IAM user from within a Batch job context; critical when the policy is `AdministratorAccess` and the caller is an ECS task role
- `iam:PutUserPolicy` -- inline policy added to an IAM user from within a Batch job context; monitor for policies granting broad permissions

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS Batch Job Roles Documentation](https://docs.aws.amazon.com/batch/latest/userguide/job_roles.html) -- explains how `jobRoleArn` works and why it must trust `ecs-tasks.amazonaws.com`
- [AWS IAM PassRole Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html) -- explains PassRole mechanics and how to restrict it with `iam:PassedToService`
- [Rhino Security Labs - AWS IAM Privilege Escalation Methods](https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation/) -- comprehensive overview of IAM privilege escalation techniques including PassRole patterns
- [pathfinding.cloud/paths/batch-001](https://pathfinding.cloud/paths/batch-001) -- documented attack path for this scenario
