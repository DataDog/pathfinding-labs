# AWS Batch Full Pipeline Creation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** User with iam:PassRole and broad Batch permissions creates entire Batch pipeline from scratch -- compute environment, job queue, job definition with admin jobRoleArn -- and submits a job to escalate to admin
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_batch_003_iam_passrole_batch_createcomputeenvironment_batch_createjobqueue_batch_registerjobdefinition_batch_submitjob`
* **Schema Version:** 4.7.1
* **Pathfinding.cloud ID:** batch-003
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1610 - Deploy Container
* **Required Preconditions:**
  - IAM Role: with administrative privileges that trusts ecs-tasks.amazonaws.com, allowing it to be passed as jobRoleArn to Batch job definitions
  - IAM Role: ECS task execution role trusting ecs-tasks.amazonaws.com with AmazonECSTaskExecutionRolePolicy, required for Fargate to pull container images
  - [network] VPC subnet with internet access (public subnet or NAT gateway) for Fargate tasks to pull container images and make AWS API calls

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-batch-003-to-admin-starting-user` IAM user to the `pl-prod-batch-003-to-admin-admin-role` administrative role by creating an entire AWS Batch pipeline from scratch -- a Fargate compute environment, a job queue, and a job definition with the admin role as the `jobRoleArn` -- then submitting a job whose container executes with administrative credentials to attach `AdministratorAccess` to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-batch-003-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-batch-003-to-admin-admin-role`

### Starting Permissions

**Required** (`pl-prod-batch-003-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-batch-003-to-admin-admin-role` -- allows passing the admin role to the Batch service as the job role ARN in the job definition
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-batch-003-to-admin-execution-role` -- allows passing the ECS task execution role to the Batch service when registering the job definition
- `batch:CreateComputeEnvironment` on `*` -- allows creating a new Fargate compute environment, which auto-creates an ECS cluster via the Batch service-linked role
- `batch:CreateJobQueue` on `*` -- allows creating a new job queue wired to the attacker-created compute environment
- `batch:RegisterJobDefinition` on `*` -- allows registering a new Batch job definition specifying the admin role as `jobRoleArn`
- `batch:SubmitJob` on `*` -- allows submitting the registered job definition to the attacker-created job queue

**Helpful** (`pl-prod-batch-003-to-admin-starting-user`):
- `batch:DescribeComputeEnvironments` -- monitor compute environment status during creation
- `batch:DescribeJobQueues` -- verify job queue creation and state
- `batch:DescribeJobs` -- monitor job execution status and verify job completion
- `batch:DescribeJobDefinitions` -- verify job definition registration
- `iam:ListAttachedUserPolicies` -- verify privilege escalation success by listing attached policies
- `iam:ListRoles` -- discover IAM roles in the account to identify passable admin and execution roles
- `ec2:DescribeSubnets` -- discover subnets for compute environment reconnaissance
- `ec2:DescribeSecurityGroups` -- discover security groups for compute environment reconnaissance

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable batch-003-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `batch-003-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-batch-003-to-admin-starting-user` | Starting user with broad Batch permissions and iam:PassRole on the admin and execution roles |
| `arn:aws:iam::{account_id}:role/pl-prod-batch-003-to-admin-admin-role` | Administrative role (trusts `ecs-tasks.amazonaws.com`) passed as `jobRoleArn` to the Batch job definition |
| `arn:aws:iam::{account_id}:role/pl-prod-batch-003-to-admin-execution-role` | ECS task execution role for pulling container images and sending logs to CloudWatch |
| `arn:aws:ec2:{region}:{account_id}:security-group/{sg-id}` | Egress-only security group for Fargate tasks in the Batch compute environment |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/batch-003-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create a Fargate compute environment (which auto-creates an ECS cluster behind the scenes)
4. Create a job queue wired to the new compute environment
5. Register a Batch job definition with the admin role as the `jobRoleArn`
6. Submit the job to the attacker-created job queue
7. Wait for the Batch job to complete execution
8. Verify successful privilege escalation by demonstrating admin access
9. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions

#### Resources Created by Attack Script

- Fargate compute environment (auto-creates an ECS cluster via the Batch service-linked role)
- Job queue wired to the attacker-created compute environment
- AWS Batch job definition with the admin role as `jobRoleArn`
- `AdministratorAccess` managed policy attached to `pl-prod-batch-003-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo batch-003-iam-passrole+batch-createcomputeenvironment+batch-createjobqueue+batch-registerjobdefinition+batch-submitjob
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `batch-003-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup batch-003-iam-passrole+batch-createcomputeenvironment+batch-createjobqueue+batch-registerjobdefinition+batch-submitjob
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `batch-003-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable batch-003-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `batch-003-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user with `iam:PassRole` permission on a role that has administrative permissions
- IAM user with `batch:CreateComputeEnvironment`, `batch:CreateJobQueue`, `batch:RegisterJobDefinition`, and `batch:SubmitJob` permissions combined with `iam:PassRole`, forming a privilege escalation path where the attacker can build the entire Batch pipeline from scratch
- IAM role with `AdministratorAccess` or equivalent permissions that trusts `ecs-tasks.amazonaws.com` and can be passed to Batch job definitions
- Privilege escalation path from IAM user to admin via AWS Batch full pipeline creation -- more dangerous than scenarios requiring pre-existing infrastructure because no Batch resources need to exist beforehand

#### Prevention Recommendations

- Restrict `iam:PassRole` using the `iam:PassedToService` condition key to limit which services a role can be passed to (e.g., `"iam:PassedToService": "ecs-tasks.amazonaws.com"`)
- Scope `iam:PassRole` resource constraints to non-privileged roles only; deny passing roles with `AdministratorAccess` or broad IAM permissions to Batch
- Implement SCPs that deny `batch:CreateComputeEnvironment` and `batch:CreateJobQueue` for non-automation principals; these permissions allow an attacker to build the entire pipeline without relying on pre-existing infrastructure
- Implement SCPs that deny `batch:RegisterJobDefinition` when the request includes a `jobRoleArn` referencing a privileged role
- Use IAM Access Analyzer to automatically detect privilege escalation paths involving `iam:PassRole` and Batch permissions
- Enable AWS Config rules to alert when Batch job definitions are registered with roles that carry administrative permissions

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `batch:CreateComputeEnvironment` -- new Batch compute environment created; unexpected creation by a non-automation principal may indicate an attacker building infrastructure for privilege escalation
- `batch:CreateJobQueue` -- new Batch job queue created; correlate with a preceding `CreateComputeEnvironment` from the same principal
- `batch:RegisterJobDefinition` -- new Batch job definition registered; inspect `requestParameters.containerProperties.jobRoleArn` -- a privileged role ARN here is the CloudTrail signal for PassRole abuse via Batch; high severity when the role has administrative permissions
- `batch:SubmitJob` -- Batch job submitted; correlate with a preceding `RegisterJobDefinition` call from the same principal to identify abuse of newly registered definitions
- `iam:AttachUserPolicy` -- managed policy attached to an IAM user from within a Batch job context; critical when the policy is `AdministratorAccess` and the caller is an ECS task role

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS Batch Job Roles Documentation](https://docs.aws.amazon.com/batch/latest/userguide/job_roles.html) -- explains how `jobRoleArn` works and why it must trust `ecs-tasks.amazonaws.com`
- [AWS Batch Compute Environments](https://docs.aws.amazon.com/batch/latest/userguide/compute_environments.html) -- explains Fargate compute environments and how Batch auto-creates ECS clusters
- [AWS IAM PassRole Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html) -- explains PassRole mechanics and how to restrict it with `iam:PassedToService`
- [pathfinding.cloud/paths/batch-003](https://pathfinding.cloud/paths/batch-003) -- documented attack path for this scenario
