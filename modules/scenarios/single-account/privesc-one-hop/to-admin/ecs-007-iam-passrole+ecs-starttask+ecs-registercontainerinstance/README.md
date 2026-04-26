# ECS Container Instance Registration + Start Task to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $8/mo
* **Cost Estimate When Demo Executed:** $8/mo
* **Technique:** Registering an unregistered EC2 instance to an ECS cluster via SSM, then using ecs:StartTask with --overrides to launch an existing task definition with an admin role and malicious command
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_ecs_007_iam_passrole_ecs_starttask_ecs_registercontainerinstance`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** ecs-007
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1610 - Deploy Container

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-ecs-007-to-admin-instance-role` EC2 instance role to the `pl-prod-ecs-007-to-admin-target-role` administrative role by registering an unregistered EC2 instance to an ECS cluster via `ecs:RegisterContainerInstance` and then launching an existing task definition with an overridden `taskRoleArn` and command via `ecs:StartTask --overrides`.

- **Start:** `arn:aws:iam::{account_id}:role/pl-prod-ecs-007-to-admin-instance-role`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-ecs-007-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-ecs-007-to-admin-instance-role`):
- `ecs:RegisterContainerInstance` on `*` -- register the EC2 instance to the target ECS cluster via direct API call using IMDS identity documents
- `ecs:StartTask` on `*` -- start a task on the registered container instance with --overrides to override taskRoleArn and container command
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-ecs-007-to-admin-target-role, arn:aws:iam::*:role/pl-prod-ecs-007-to-admin-execution-role` -- pass the admin target role as the task role override in ecs:StartTask
- `ecs:DeregisterContainerInstance` on `*` -- deregister the container instance from the cluster (cleanup)

**Helpful** (`pl-prod-ecs-007-to-admin-instance-role`):
- `ecs:ListContainerInstances` -- verify container instance registered and retrieve its ARN
- `ecs:ListTaskDefinitions` -- discover existing task definitions to exploit
- `ecs:DescribeTasks` -- monitor task execution status and verify task completion

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable single_account_privesc_one_hop_to_admin_ecs_007_iam_passrole_ecs_starttask_ecs_registercontainerinstance
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-007-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-ecs-007-to-admin-starting-user` | Scenario-specific starting user with access keys, iam:PassRole, ecs:StartTask, and ssm:SendCommand permissions |
| `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-ecs-007-to-admin-target-role` | Admin role with AdministratorAccess that can be passed to ECS tasks (trusts ecs-tasks.amazonaws.com) |
| `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-ecs-007-to-admin-execution-role` | Task execution role for pulling container images and writing logs |
| `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-ecs-007-to-admin-instance-role` | EC2 instance role with AmazonEC2ContainerServiceforEC2Role and AmazonSSMManagedInstanceCore policies |
| `arn:aws:ecs:REGION:PROD_ACCOUNT:cluster/pl-prod-ecs-007-cluster` | ECS cluster (starts empty with no registered container instances) |
| `arn:aws:ecs:REGION:PROD_ACCOUNT:task-definition/pl-prod-ecs-007-existing-task` | Pre-existing benign task definition that gets overridden at runtime |
| `arn:aws:ec2:REGION:PROD_ACCOUNT:instance/INSTANCE_ID` | ECS-optimized EC2 instance with ECS agent installed (NOT registered to any cluster until the demo runs) |
| `arn:aws:ssm:REGION:PROD_ACCOUNT:parameter/pathfinding-labs/flags/ecs-007-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Verify successful privilege escalation
4. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions


#### Resources Created by Attack Script

- AdministratorAccess policy attached to `pl-prod-ecs-007-to-admin-instance-role`
- ECS container instance registration for the EC2 instance in `pl-prod-ecs-007-cluster`
- ECS task launched on the container instance via `ecs:StartTask` with overrides

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo ecs-007-iam-passrole+ecs-starttask+ecs-registercontainerinstance
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-007-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ecs-007-iam-passrole+ecs-starttask+ecs-registercontainerinstance
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-007-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable single_account_privesc_one_hop_to_admin_ecs_007_iam_passrole_ecs_starttask_ecs_registercontainerinstance
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-007-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user or role has `iam:PassRole` permission granting access to a role with administrative privileges (e.g., `AdministratorAccess`), combined with `ecs:StartTask` — forming a privilege escalation path
- IAM principal has `ssm:SendCommand` permission on EC2 instances running the ECS agent, enabling remote reconfiguration of the ECS cluster assignment
- ECS task definition exists with no container-level resource restrictions, making it exploitable via `--overrides` at launch time
- EC2 instances with ECS agent installed are not assigned to any cluster, leaving them in an uncontrolled state susceptible to cluster hijacking via SSM

#### Prevention Recommendations

- Restrict `iam:PassRole` permissions using resource-based conditions to limit which roles can be passed; never allow PassRole to roles with administrative permissions
- Use the `iam:PassedToService` condition key with value `ecs-tasks.amazonaws.com` to control which services can receive passed roles, and combine it with resource ARN restrictions to limit which specific roles can be passed
- Restrict `ssm:SendCommand` access to specific instances and specific SSM documents using resource ARN conditions; avoid granting broad SendCommand permissions that allow arbitrary command execution on any instance
- Implement Service Control Policies (SCPs) that prevent passing roles with administrative permissions to ECS tasks
- Adopt a Lambda proxy pattern for ECS task launches (as recommended by the [original research](https://labs.reversec.com/posts/2025/08/another-ecs-privilege-escalation-path)) — instead of granting users direct `ecs:StartTask` permissions, route task launches through a Lambda function that validates and restricts overrides
- Use IAM Access Analyzer to identify privilege escalation paths involving PassRole combined with ECS StartTask and SSM SendCommand permissions
- Implement IAM permission boundaries on IAM users to cap the maximum permissions that can be attached, even if an escalation path is exploited

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `SSM: SendCommand` — SSM command sent to an EC2 instance; suspicious when used to modify ECS agent configuration files or restart the ECS agent service
- `ECS: RegisterContainerInstance` — EC2 instance registered to an ECS cluster; unexpected registrations may indicate an attacker redirecting an unmanaged instance to a target cluster
- `ECS: StartTask` — ECS task started on a specific container instance; high severity when the request includes `overrides` with a `taskRoleArn` that differs from the task definition's default role
- `IAM: AttachUserPolicy` — Policy attached to an IAM user; critical when AdministratorAccess or similarly broad policies are attached during or immediately after ECS task execution

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
