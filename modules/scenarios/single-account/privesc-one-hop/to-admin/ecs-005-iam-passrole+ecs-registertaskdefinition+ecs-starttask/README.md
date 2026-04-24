# ECS Task Definition Registration + Start Task to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $8/mo
* **Cost Estimate When Demo Executed:** $8/mo
* **Technique:** ECS EC2 task execution with admin role using ecs:StartTask to grant starting user administrative access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_ecs_005_iam_passrole_ecs_registertaskdefinition_ecs_starttask`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** ecs-005
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1610 - Deploy Container

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-ecs-005-to-admin-starting-user` IAM user to the `pl-prod-ecs-005-to-admin-target-role` administrative role by passing the admin role to a malicious ECS task definition, starting the task on an EC2 container instance, and having the task attach AdministratorAccess to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-ecs-005-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-ecs-005-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-ecs-005-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-ecs-005-to-admin-target-role` -- allows passing the admin role to an ECS task definition
- `ecs:RegisterTaskDefinition` on `*` -- allows registering a task definition that specifies the admin role
- `ecs:StartTask` on `*` -- allows launching the malicious task on an EC2 container instance

**Helpful** (`pl-prod-ecs-005-to-admin-starting-user`):
- `ecs:ListContainerInstances` -- retrieve container instance ARN for the StartTask command
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
plabs enable ecs-005-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-005-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-ecs-005-to-admin-starting-user` | Scenario-specific starting user with access keys and ECS permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-ecs-005-to-admin-target-role` | Admin role that can be passed to ECS tasks (trusts ecs-tasks.amazonaws.com) |
| `arn:aws:ecs:{region}:{account_id}:cluster/pl-prod-ecs-005-cluster` | ECS cluster for running tasks on EC2 instances |
| `arn:aws:ec2:{region}:{account_id}:instance/{instance_id}` | EC2 container instance registered with the ECS cluster |
| `arn:aws:iam::{account_id}:role/pl-prod-ecs-005-to-admin-instance-role` | IAM role for the EC2 instance (allows ECS agent to function) |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/ecs-005-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Register a malicious ECS task definition referencing the admin target role
4. Start the ECS task on the EC2 container instance
5. Wait for the task to complete and attach AdministratorAccess to the starting user
6. Verify successful privilege escalation by demonstrating admin access
7. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions


#### Resources Created by Attack Script

- ECS task definition referencing the admin target role
- AdministratorAccess policy attached to the starting user

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo ecs-005-iam-passrole+ecs-registertaskdefinition+ecs-starttask
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-005-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ecs-005-iam-passrole+ecs-registertaskdefinition+ecs-starttask
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-005-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable ecs-005-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-005-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user has `iam:PassRole` permission to an admin role trusted by `ecs-tasks.amazonaws.com`
- IAM user has `ecs:RegisterTaskDefinition` and `ecs:StartTask` permissions, enabling container-based privilege escalation
- ECS task execution role has administrative permissions (`AdministratorAccess` or equivalent)
- Privilege escalation path exists: starting user can register an ECS task definition with an admin role and launch it on cluster instances

#### Prevention Recommendations

- Restrict `iam:PassRole` permissions using resource-based conditions to limit which roles can be passed and to which AWS services
- Implement condition keys like `iam:PassedToService` with value `ecs-tasks.amazonaws.com` to explicitly control PassRole usage
- Avoid granting broad `ecs:RegisterTaskDefinition` and `ecs:StartTask` permissions; use resource tags or naming patterns to limit task operations
- Implement Service Control Policies (SCPs) that prevent passing roles with administrative permissions to ECS tasks
- Use IAM Access Analyzer to identify privilege escalation paths involving PassRole combined with ECS operations
- Enable AWS Config rules to detect ECS task definitions with overly permissive execution roles
- Implement IAM permission boundaries on users to limit the maximum permissions that can be attached
- Pay special attention to `ecs:StartTask` permissions as they are less common than `ecs:RunTask` and may be overlooked in security reviews

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PassRole` — Role passed to ECS task definition; critical when the target role has administrative permissions
- `ECS: RegisterTaskDefinition` — New task definition registered; high severity when the task execution role has elevated permissions
- `ECS: StartTask` — Task launched on EC2 container instance; investigate when combined with a recently registered task definition using a privileged role
- `IAM: AttachUserPolicy` — Policy attached to an IAM user; critical when the source principal is an ECS task role and the policy is AdministratorAccess

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
