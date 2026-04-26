# ECS New Cluster + Run Task to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Passing a privileged role to an attacker-controlled ECS task to gain administrative access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_ecs_002_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_runtask`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** ecs-002
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1610 - Deploy Container

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-ecs-002-to-admin-starting-user` IAM user to the `pl-prod-ecs-002-to-admin-target-role` administrative role by creating an attacker-controlled ECS cluster, registering a malicious task definition with the privileged role, and running the task on Fargate to execute `iam:AttachUserPolicy` as that role.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-ecs-002-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-ecs-002-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-ecs-002-to-admin-starting-user`):
- `ecs:CreateCluster` on `*` -- create attacker-controlled cluster infrastructure
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-ecs-002-to-admin-target-role` -- authorize attaching the privileged role to the task definition
- `ecs:RegisterTaskDefinition` on `*` -- define the malicious container workload
- `ecs:RunTask` on `*` -- execute the task on Fargate

**Helpful** (`pl-prod-ecs-002-to-admin-starting-user`):
- `ec2:DescribeVpcs` -- find the default VPC for ECS task network configuration
- `ec2:DescribeSubnets` -- find a subnet in the default VPC for ECS task network configuration
- `ecs:DescribeTasks` -- monitor task execution status and verify task completion
- `ecs:StopTask` -- stop running tasks during cleanup
- `ecs:DeregisterTaskDefinition` -- clean up task definition after demonstration
- `ecs:DeleteCluster` -- clean up ECS cluster after demonstration
- `iam:ListAttachedUserPolicies` -- verify privilege escalation success by listing attached policies
- `iam:DetachUserPolicy` -- remove admin policy from starting user during cleanup

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable ecs-002-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-002-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-ecs-002-to-admin-starting-user` | Scenario-specific starting user with access keys, ECS cluster creation, task definition registration, and task execution permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-ecs-002-to-admin-target-role` | Privileged role with administrative permissions that can be passed to ECS tasks |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/ecs-002-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create a new ECS cluster and register a malicious task definition with the privileged target role
4. Run the task on Fargate and wait for it to attach AdministratorAccess to the starting user
5. Verify successful privilege escalation
6. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions


#### Resources Created by Attack Script

- A new ECS cluster created by the starting user
- A malicious ECS task definition referencing the privileged target role
- An ECS Fargate task execution that attaches AdministratorAccess to the starting user

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo ecs-002-iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-runtask
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-002-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ecs-002-iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-runtask
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-002-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable ecs-002-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-002-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM principal has both `iam:PassRole` and `ecs:CreateCluster` permissions, enabling creation of attacker-controlled container infrastructure
- IAM principal can pass a role with administrative permissions (`arn:aws:iam::{account_id}:role/pl-prod-ecs-002-to-admin-target-role`) to ECS tasks
- IAM principal has `ecs:RegisterTaskDefinition` and `ecs:RunTask` permissions combined with `iam:PassRole`, forming a complete privilege escalation path
- Privileged role (`pl-prod-ecs-002-to-admin-target-role`) is passable to ECS tasks by a non-admin principal

#### Prevention Recommendations

- Implement strict separation of duties — never grant both `iam:PassRole` and ECS execution permissions (`ecs:CreateCluster`, `ecs:RunTask`) to the same principal
- Use resource-based conditions on `iam:PassRole` to restrict which roles can be passed: `"Condition": {"StringEquals": {"iam:PassedToService": "ecs-tasks.amazonaws.com"}}`
- Implement Service Control Policies (SCPs) to prevent passing administrative or privileged roles to ECS tasks
- Restrict `ecs:CreateCluster` permissions to infrastructure teams only — most developers should use existing clusters
- Use IAM Access Analyzer to identify roles with administrative permissions that can be passed to compute services
- Implement tag-based access control requiring specific tags on roles before they can be passed to ECS tasks

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PassRole` -- role passed to an ECS task; critical when the passed role has administrative permissions
- `ECS: CreateCluster` -- new ECS cluster created; suspicious when created by non-infrastructure principals
- `ECS: RegisterTaskDefinition` -- new task definition registered; high severity when combined with a privileged role ARN in the task role field
- `ECS: RunTask` -- ECS task executed; correlate with prior cluster creation and task definition registration events to identify attack chains

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
