# ECS Start Task to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $8/mo
* **Cost Estimate When Demo Executed:** $8/mo
* **Technique:** Overriding existing ECS task definition commands and task role via ecs:StartTask --overrides to escalate to admin on an already-registered container instance
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_ecs_009_iam_passrole_ecs_starttask`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** ecs-009
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1610 - Deploy Container

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-ecs-009-to-admin-starting-user` IAM user to the `pl-prod-ecs-009-to-admin-target-role` administrative role by starting an existing ECS task with `--overrides` that substitutes both the task role and container command at runtime, without registering any new task definition or container instance.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-ecs-009-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-ecs-009-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-ecs-009-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-ecs-009-to-admin-target-role` and `arn:aws:iam::*:role/pl-prod-ecs-009-to-admin-execution-role` -- allows substituting these roles as the ECS task role at runtime via `--overrides`
- `ecs:StartTask` on `*` -- allows launching tasks on registered container instances

**Helpful** (`pl-prod-ecs-009-to-admin-starting-user`):
- `ecs:ListContainerInstances` -- retrieve container instance ARN required for the StartTask command
- `ecs:ListTaskDefinitions` -- discover existing task definitions to exploit
- `ecs:DescribeTasks` -- monitor task execution status and verify task completion
- `ecs:ListClusters` -- discover available ECS clusters
- `ecs:StopTask` -- stop running tasks during cleanup
- `ec2:DescribeVpcs` -- find default VPC for network configuration
- `ec2:DescribeSubnets` -- find subnet in default VPC for network configuration
- `ec2:DescribeSecurityGroups` -- discover security groups for network configuration
- `iam:DetachUserPolicy` -- remove admin policy from starting user during cleanup
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
plabs enable ecs-009-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-009-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-ecs-009-to-admin-starting-user` | Scenario-specific starting user with access keys, iam:PassRole and ecs:StartTask permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-ecs-009-to-admin-target-role` | Admin role with AdministratorAccess that can be passed to ECS tasks (trusts ecs-tasks.amazonaws.com) |
| `arn:aws:iam::{account_id}:role/pl-prod-ecs-009-to-admin-execution-role` | Task execution role for pulling container images and writing logs |
| `arn:aws:ecs:{region}:{account_id}:cluster/pl-prod-ecs-009-cluster` | ECS cluster for running tasks on EC2 instances |
| `arn:aws:ecs:{region}:{account_id}:task-definition/pl-prod-ecs-009-existing-task` | Pre-existing benign task definition that gets overridden at runtime |
| `arn:aws:ec2:{region}:{account_id}:instance/{instance_id}` | ECS-optimized EC2 container instance pre-registered with the cluster |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/ecs-009-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve scenario credentials and configuration from Terraform outputs
2. Verify the starting user identity and confirm no admin access exists yet
3. Discover the pre-existing ECS cluster, task definition, and registered container instance
4. Launch the existing task definition via `ecs:StartTask` with `--overrides` substituting the admin task role and a malicious container command
5. Wait for the ECS task to reach `STOPPED` status and confirm a zero exit code
6. Wait for IAM policy changes to propagate, then verify `AdministratorAccess` is attached to the starting user
7. Confirm admin access by successfully calling `aws iam list-users`
8. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions

#### Resources Created by Attack Script

- `AdministratorAccess` managed policy attached to `pl-prod-ecs-009-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo ecs-009-iam-passrole+ecs-starttask
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-009-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ecs-009-iam-passrole+ecs-starttask
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-009-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable ecs-009-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-009-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user has `iam:PassRole` permission on an ECS task role with `AdministratorAccess`, enabling privilege escalation via `ecs:StartTask` overrides
- IAM user has `ecs:StartTask` permission combined with `iam:PassRole`, forming a known privilege escalation path
- ECS task role (`pl-prod-ecs-009-to-admin-target-role`) has `AdministratorAccess` attached; high-privilege roles trusted by `ecs-tasks.amazonaws.com` should be flagged
- No permission boundary restricts the maximum permissions that can be granted to the starting user

#### Prevention Recommendations

- Restrict `iam:PassRole` permissions using resource-based conditions to limit which roles can be passed; never allow PassRole to roles with administrative permissions
- Use the `iam:PassedToService` condition key with value `ecs-tasks.amazonaws.com` to control which services can receive passed roles, and combine it with resource ARN restrictions to limit which specific roles can be passed
- Monitor CloudTrail for `StartTask` API calls that include `overrides` parameters, particularly those specifying a `taskRoleArn` different from the task definition's default role
- Implement Service Control Policies (SCPs) that prevent passing roles with administrative permissions to ECS tasks
- Adopt a Lambda proxy pattern for ECS task launches (as recommended by the [original research](https://labs.reversec.com/posts/2025/08/another-ecs-privilege-escalation-path)) -- instead of granting users direct `ecs:StartTask` permissions, route task launches through a Lambda function that validates and restricts overrides
- Do not rely solely on restricting `ecs:RegisterTaskDefinition` as a mitigation for ECS privilege escalation; the `--overrides` parameter on `ecs:StartTask` bypasses task definition controls entirely
- Use IAM Access Analyzer to identify privilege escalation paths involving PassRole combined with ECS StartTask permissions
- Enable AWS Config rules and CloudWatch alerts for `AttachUserPolicy` and `PutUserPolicy` API calls where the principal is an ECS task role
- Implement IAM permission boundaries on IAM users to cap the maximum permissions that can be attached, even if an escalation path is exploited

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `ecs:StartTask` -- ECS task started; inspect `overrides.taskRoleArn` in request parameters — a privileged role ARN here is the CloudTrail signal for PassRole; high severity when the request includes container command overrides
- `iam:AttachUserPolicy` -- admin policy attached to an IAM user; critical when the caller is an ECS task role
- `iam:DetachUserPolicy` -- admin policy detached from an IAM user; useful for detecting cleanup after escalation

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
