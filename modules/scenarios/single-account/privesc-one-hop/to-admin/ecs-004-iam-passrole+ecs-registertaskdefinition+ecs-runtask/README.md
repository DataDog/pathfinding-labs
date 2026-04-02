# Privilege Escalation via iam:PassRole + ecs:RegisterTaskDefinition + ecs:RunTask

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** ECS Fargate task execution with admin role to grant starting user administrative access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_ecs_004_iam_passrole_ecs_registertaskdefinition_ecs_runtask`
* **Schema Version:** 3.0.0
* **Pathfinding.cloud ID:** ecs-004
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1610 - Deploy Container

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-ecs-004-to-admin-starting-user` IAM user to the `pl-prod-ecs-004-to-admin-target-role` administrative role by registering a malicious ECS task definition with the admin role as the task execution role and running the task on AWS Fargate to attach `AdministratorAccess` to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-ecs-004-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-ecs-004-to-admin-target-role`

### Starting Permissions

**Required:**
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-ecs-004-to-admin-target-role` -- pass the admin role to the ECS task definition
- `ecs:RegisterTaskDefinition` on `*` -- register a task definition specifying the admin role and attacker command
- `ecs:RunTask` on `*` -- launch the registered task on AWS Fargate

**Helpful:**
- `ecs:DescribeTasks` -- monitor task execution status and verify task completion
- `ecs:DeregisterTaskDefinition` -- clean up task definition after demonstration
- `ecs:StopTask` -- stop running tasks during cleanup
- `ec2:DescribeVpcs` -- find default VPC for ECS task network configuration
- `ec2:DescribeSubnets` -- find subnet in default VPC for ECS task network configuration
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
plabs enable enable_single_account_privesc_one_hop_to_admin_ecs_004_iam_passrole_ecs_registertaskdefinition_ecs_runtask
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
| `arn:aws:iam::{account_id}:user/pl-prod-ecs-004-to-admin-starting-user` | Scenario-specific starting user with access keys and ECS permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-ecs-004-to-admin-target-role` | Admin role that can be passed to ECS tasks (trusts ecs-tasks.amazonaws.com) |
| `arn:aws:ecs:{region}:{account_id}:cluster/pl-prod-ecs-004-cluster` | ECS cluster for running Fargate tasks |

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

- ECS task definition registered with admin target role
- ECS Fargate task launched to execute privilege escalation
- `AdministratorAccess` policy attached to the starting user

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo ecs-004-iam-passrole+ecs-registertaskdefinition+ecs-runtask
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ecs-004-iam-passrole+ecs-registertaskdefinition+ecs-runtask
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_ecs_004_iam_passrole_ecs_registertaskdefinition_ecs_runtask
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

- IAM user has `iam:PassRole` permission granting the ability to pass an administrative role to ECS tasks
- IAM user has `ecs:RegisterTaskDefinition` and `ecs:RunTask` permissions, enabling container-based privilege escalation
- Privilege escalation path: starting user can register task definitions with the admin target role and run tasks to gain admin access
- ECS cluster configured to accept Fargate tasks with no restrictions on task execution role permissions

#### Prevention Recommendations

- Restrict `iam:PassRole` permissions using resource-based conditions to limit which roles can be passed and to which AWS services
- Implement condition keys like `iam:PassedToService` with value `ecs-tasks.amazonaws.com` to explicitly control PassRole usage
- Avoid granting broad `ecs:RegisterTaskDefinition` and `ecs:RunTask` permissions; use resource tags or naming patterns to limit task operations
- Implement Service Control Policies (SCPs) that prevent passing roles with administrative permissions to ECS tasks
- Use IAM Access Analyzer to identify privilege escalation paths involving PassRole combined with ECS operations
- Enable AWS Config rules to detect ECS task definitions with overly permissive execution roles
- Implement IAM permission boundaries on users to limit the maximum permissions that can be attached

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PassRole` -- Role passed to ECS task execution role; high severity when the passed role has administrative privileges
- `ECS: RegisterTaskDefinition` -- New or updated task definition registered; critical when task execution role has elevated permissions
- `ECS: RunTask` -- ECS task launched; high severity when combined with a privileged task execution role
- `IAM: AttachUserPolicy` -- Policy attached to a user; critical when `AdministratorAccess` is attached and the principal is an ECS task role

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
