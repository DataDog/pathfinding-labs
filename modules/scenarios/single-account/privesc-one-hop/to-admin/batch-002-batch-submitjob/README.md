# AWS Batch SubmitJob to Admin via Existing Admin Job Definition

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Submit a job to an existing Batch job definition that carries an admin jobRoleArn, overriding the container command to attach AdministratorAccess to the starting user
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_batch_002_batch_submitjob`
* **Schema Version:** 4.7.1
* **Pathfinding.cloud ID:** batch-002
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1610 - Deploy Container
* **Required Preconditions:**
  - aws_batch_job_definition: A pre-existing AWS Batch job definition with a privileged jobRoleArn (e.g., AdministratorAccess) must exist in the account
  - aws_batch_job_queue: An active AWS Batch job queue connected to a Fargate compute environment must exist

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-batch-002-to-admin-starting-user` IAM user to the `pl-prod-batch-002-to-admin-admin-role` administrative role by submitting a job to an existing Batch job definition whose `jobRoleArn` is the admin role, overriding the container command via `ContainerOverrides` to attach `AdministratorAccess` to the starting user — all without holding `iam:PassRole`.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-batch-002-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-batch-002-to-admin-admin-role`

### Starting Permissions

**Required** (`pl-prod-batch-002-to-admin-starting-user`):
- `batch:SubmitJob` on `*` -- allows submitting jobs to the pre-existing Batch job definition, overriding the container command via `ContainerOverrides.Command`. The job definition runs `python:3.11-slim` (a generic data-processing image with no custom entrypoint), so the override fully replaces execution and runs arbitrary shell code as the admin `jobRoleArn`

**Helpful** (`pl-prod-batch-002-to-admin-starting-user`):
- `batch:DescribeJobDefinitions` -- Discover existing job definitions with privileged jobRoleArn
- `batch:DescribeJobQueues` -- List available job queues for job submission
- `batch:DescribeJobs` -- Monitor job execution status and verify job completion
- `batch:DescribeComputeEnvironments` -- Discover available compute environments

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable batch-002-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `batch-002-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-batch-002-to-admin-starting-user` | Scenario-specific starting user with access keys and `batch:SubmitJob` permission only |
| `arn:aws:iam::{account_id}:role/pl-prod-batch-002-to-admin-admin-role` | Administrative role (trusts `ecs-tasks.amazonaws.com`) bound as `jobRoleArn` in the pre-existing job definition |
| `arn:aws:iam::{account_id}:role/pl-prod-batch-002-to-admin-exec-role` | ECS task execution role for pulling container images and sending logs to CloudWatch |
| `arn:aws:batch:{region}:{account_id}:job-definition/pl-prod-batch-002-to-admin-job-def` | Pre-existing Batch job definition with the admin role as `jobRoleArn`; the attacker submits to this definition without modifying or re-registering it |
| Fargate compute environment | AWS Batch compute environment using Fargate for serverless container execution |
| Job queue | AWS Batch job queue associated with the Fargate compute environment |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/batch-002-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Confirm the starting user cannot read the CTF flag before escalation
3. Build a `ContainerOverrides` JSON payload that replaces the job command with a shell one-liner (pip-installs the aws CLI, since `python:3.11-slim` lacks it, then runs `iam:AttachUserPolicy`)
4. Submit the job to the pre-existing Batch job definition using `batch:SubmitJob` with `--container-overrides`
5. Poll the job status until it reaches `SUCCEEDED` (Fargate provisioning typically takes 1-3 minutes)
6. Wait 30 seconds for IAM policy propagation
7. Verify successful privilege escalation by reading the CTF flag from SSM Parameter Store as the starting user

#### Resources Created by Attack Script

- `AdministratorAccess` managed policy attached to `pl-prod-batch-002-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo batch-002-batch-submitjob
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup batch-002-batch-submitjob
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable batch-002-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `batch-002-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- AWS Batch job definition with `jobRoleArn` set to a role that carries `AdministratorAccess` or equivalent broad permissions
- IAM user or role with `batch:SubmitJob` permission scoped to `*` — any principal that can submit jobs to this definition can abuse the admin `jobRoleArn` without holding `iam:PassRole`
- Privilege escalation path from `batch:SubmitJob` alone to admin via an existing Batch job definition with a privileged `jobRoleArn` — CSPM tools that only flag `iam:PassRole + batch:RegisterJobDefinition` chains will miss this path
- Admin IAM role that trusts `ecs-tasks.amazonaws.com` and is referenced as a `jobRoleArn` in an active Batch job definition

#### Prevention Recommendations

- Never attach `AdministratorAccess` or other broad wildcard policies to roles used as `jobRoleArn` — scope the job role to only the permissions the workload actually needs
- Restrict `batch:SubmitJob` to specific job definition ARNs rather than `*`; use IAM resource-level conditions like `batch:JobDefinition` to limit which definitions a principal can submit to
- Add a resource-based condition on the admin role's trust policy to restrict which job definition ARNs can assume it (using `aws:SourceArn` or a custom condition), preventing arbitrary Batch submissions from inheriting the role
- Audit all active Batch job definitions and alert whenever `jobRoleArn` references a role with IAM administrative permissions (`iam:*`, `iam:AttachUserPolicy`, `iam:PutRolePolicy`, or managed policies like `AdministratorAccess`)
- Use AWS Config managed rules or custom rules to continuously evaluate Batch job definitions for overly-permissive `jobRoleArn` values
- Review `batch:SubmitJob` grants in IAM Access Analyzer findings — treat this permission as high-risk when any job definition in the account carries a privileged `jobRoleArn`

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `batch:SubmitJob` -- Batch job submitted; inspect `requestParameters.containerOverrides.command`. Any command override on a job definition carrying a privileged `jobRoleArn` is suspicious — the payload is often a shell wrapper (`sh -c ...`) that hides the real intent, so match on shell invocation, package installs (`pip install`, `apt-get`), or embedded IAM verbs (`iam:AttachUserPolicy`, `iam:PutUserPolicy`, `iam:PutRolePolicy`) inside the argument string, not just the first array element; also inspect `requestParameters.jobDefinition` to identify which definition was targeted
- `iam:AttachUserPolicy` -- managed policy attached to an IAM user from within a Batch/ECS task context; critical when the policy is `AdministratorAccess` and the caller's ARN includes `ecs-tasks` or a Batch job role
- `iam:PutUserPolicy` -- inline policy added to an IAM user from a Batch job context; monitor for policies granting broad IAM or `*` permissions

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS Batch Job Roles Documentation](https://docs.aws.amazon.com/batch/latest/userguide/job_roles.html) -- explains how `jobRoleArn` works and why ContainerOverrides can be used to change the command without requiring PassRole
- [AWS Batch SubmitJob API Reference](https://docs.aws.amazon.com/batch/latest/APIReference/API_SubmitJob.html) -- documents the `containerOverrides` parameter and which fields can be overridden at submit time
- [Rhino Security Labs - AWS IAM Privilege Escalation Methods](https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation/) -- comprehensive overview of IAM privilege escalation techniques including PassRole patterns
- [pathfinding.cloud/paths/batch-002](https://pathfinding.cloud/paths/batch-002) -- documented attack path for this scenario
