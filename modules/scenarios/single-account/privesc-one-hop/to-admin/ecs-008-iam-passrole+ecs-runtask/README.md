# Privilege Escalation via iam:PassRole + ecs:RunTask (Command Override)

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Overriding ECS task definition commands and task role at runtime via ecs:RunTask to escalate to admin without ecs:RegisterTaskDefinition
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_ecs_008_iam_passrole_ecs_runtask`
* **Schema Version:** 3.0.0
* **Pathfinding.cloud ID:** ecs-008
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1610 - Deploy Container

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-ecs-008-to-admin-starting-user` IAM user to full administrator access by using `ecs:RunTask` with runtime overrides to replace the task role and container command of an existing Fargate task definition, causing the task to execute with the `pl-prod-ecs-008-to-admin-target-role` admin role and attach `AdministratorAccess` to your user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-ecs-008-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-ecs-008-to-admin-target-role`

### Starting Permissions

**Required:**
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-ecs-008-to-admin-target-role` and `arn:aws:iam::*:role/pl-prod-ecs-008-to-admin-execution-role` -- allows passing the admin role to an ECS task via the taskRoleArn override
- `ecs:RunTask` on `*` -- allows launching ECS tasks against any cluster or task definition

**Helpful:**
- `ecs:ListTaskDefinitions` -- discover existing task definitions to exploit
- `ecs:DescribeTasks` -- monitor task execution status and verify task completion
- `ecs:ListClusters` -- discover available ECS clusters
- `ecs:StopTask` -- stop running tasks during cleanup
- `ec2:DescribeVpcs` -- find default VPC for Fargate task network configuration
- `ec2:DescribeSubnets` -- find subnet in default VPC for Fargate task network configuration
- `iam:DetachUserPolicy` -- remove admin policy from starting user during cleanup
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
plabs enable enable_single_account_privesc_one_hop_to_admin_ecs_008_iam_passrole_ecs_runtask
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `space` to enable it
4. Press `d` to deploy

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-ecs-008-to-admin-starting-user` | Scenario-specific starting user with access keys, iam:PassRole, and ecs:RunTask permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-ecs-008-to-admin-target-role` | Admin role with AdministratorAccess, trusted by ecs-tasks.amazonaws.com |
| `arn:aws:iam::{account_id}:role/pl-prod-ecs-008-to-admin-execution-role` | ECS task execution role for pulling container images and writing logs |
| `arn:aws:ecs:{region}:{account_id}:cluster/pl-prod-ecs-008-cluster` | ECS cluster for running Fargate tasks |
| `arn:aws:ecs:{region}:{account_id}:task-definition/pl-prod-ecs-008-existing-task` | Pre-existing Fargate-compatible task definition (benign, used as override target) |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Verify successful privilege escalation
4. Output standardized test results for automation

#### Resources Created by Attack Script

- AdministratorAccess policy attached to `pl-prod-ecs-008-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo ecs-008-iam-passrole+ecs-runtask
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ecs-008-iam-passrole+ecs-runtask
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_ecs_008_iam_passrole_ecs_runtask
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user or role has both `iam:PassRole` and `ecs:RunTask` permissions, enabling runtime role override without `ecs:RegisterTaskDefinition`
- `iam:PassRole` is granted without resource-level restrictions or `iam:PassedToService` conditions, allowing the role to be passed to ECS tasks
- An IAM principal can pass a role that has `AdministratorAccess` or equivalent broad permissions to ECS task workloads
- No permission boundary is in place to cap maximum privileges attainable via ECS task execution

#### Prevention Recommendations

- Restrict `iam:PassRole` permissions using resource-based conditions to limit which roles can be passed; never allow PassRole to roles with AdministratorAccess
- Use the `iam:PassedToService` condition key with value `ecs-tasks.amazonaws.com` to control which services can receive passed roles, and pair it with resource ARN restrictions to prevent passing admin roles
- Implement Service Control Policies (SCPs) that deny `ecs:RunTask` when the `--overrides` parameter specifies a `taskRoleArn` for privileged roles, or deny PassRole to admin roles entirely
- Consider using a Lambda proxy pattern (as recommended by [the original research](https://labs.reversec.com/posts/2025/08/another-ecs-privilege-escalation-path)) to mediate ECS task launches, preventing direct user access to `ecs:RunTask` and enforcing command and role restrictions
- Use IAM Access Analyzer to identify privilege escalation paths involving `iam:PassRole` combined with `ecs:RunTask`, paying special attention to scenarios that do not require `ecs:RegisterTaskDefinition`
- Implement IAM permission boundaries on users and roles to cap the maximum permissions that can be attached, limiting the blast radius even if escalation succeeds

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PassRole` -- PassRole to an ECS task role; critical when the target role has elevated permissions
- `ECS: RunTask` -- ECS task launched; high severity when the `overrides.taskRoleArn` field references a privileged role and no preceding `RegisterTaskDefinition` event is present
- `IAM: AttachUserPolicy` -- Policy attached to a user; critical when the principal is an ECS task role, indicating runtime privilege escalation from a container workload
- `IAM: PutUserPolicy` -- Inline policy added to a user; critical when the source principal is an ECS task role

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
