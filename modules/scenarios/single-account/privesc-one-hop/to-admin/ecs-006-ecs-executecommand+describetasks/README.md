# ECS Execute Command to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $9/mo
* **Cost Estimate When Demo Executed:** $9/mo
* **Technique:** Shelling into a running ECS task with an admin role to retrieve credentials from the container metadata service
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_ecs_006_ecs_executecommand_describetasks`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** ecs-006
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access
* **MITRE Techniques:** T1552.005 - Unsecured Credentials: Cloud Instance Metadata API, T1059 - Command and Scripting Interpreter

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-ecs-006-to-admin-starting-user` IAM user to the `pl-prod-ecs-006-to-admin-target-role` administrative role by shelling into a running ECS container with ECS Exec and retrieving the task role's temporary credentials from the container metadata service.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-ecs-006-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-ecs-006-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-ecs-006-to-admin-starting-user`):
- `ecs:ExecuteCommand` on `arn:aws:ecs:*:*:task/pl-prod-ecs-006-to-admin-cluster/*` -- establishes the interactive shell session in the running container
- `ecs:DescribeTasks` on `arn:aws:ecs:*:*:task/pl-prod-ecs-006-to-admin-cluster/*` -- required internally by the AWS CLI to retrieve the container runtime ID for the SSM session

**Helpful** (`pl-prod-ecs-006-to-admin-starting-user`):
- `ecs:ListTasks` -- discover task ARNs in the cluster
- `ecs:DescribeTaskDefinition` -- get task definition to discover task role ARN
- `ecs:ListClusters` -- discover ECS clusters in the account

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
plabs enable ecs-006-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-006-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-ecs-006-to-admin-starting-user` | Scenario-specific starting user with access keys and ecs:ExecuteCommand permission |
| `arn:aws:iam::{account_id}:role/pl-prod-ecs-006-to-admin-target-role` | Admin task role with AdministratorAccess attached to the running ECS task |
| `arn:aws:iam::{account_id}:role/pl-prod-ecs-006-to-admin-execution-role` | ECS execution role for pulling images and CloudWatch logging |
| `arn:aws:ecs:{region}:{account_id}:cluster/pl-prod-ecs-006-to-admin-cluster` | ECS cluster hosting the vulnerable task |
| `arn:aws:ecs:{region}:{account_id}:service/pl-prod-ecs-006-to-admin-cluster/pl-prod-ecs-006-to-admin-service` | ECS service that maintains the running task with ECS Exec enabled |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/ecs-006-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Verify successful privilege escalation
4. Capture the CTF flag from SSM Parameter Store using the stolen admin credentials


#### Resources Created by Attack Script

- No persistent resources are created; the attack only reads credentials from the container metadata service

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo ecs-006-ecs-executecommand+describetasks
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-006-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ecs-006-ecs-executecommand+describetasks
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-006-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable ecs-006-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-006-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- ECS services with `enable_execute_command = true` that have task definitions using privileged task roles
- Task roles with administrative or highly privileged permissions attached to tasks in clusters where ECS Exec is enabled
- IAM users or roles with both `ecs:ExecuteCommand` and `ecs:DescribeTasks` permissions on clusters/tasks running with sensitive roles (both are required for exploitation)
- Privilege escalation paths from low-privileged principals through ECS Exec to administrative task roles

#### Prevention Recommendations

- Disable ECS Exec on production tasks unless absolutely necessary for debugging; use it only on demand and disable immediately after troubleshooting
- Follow the principle of least privilege for ECS task roles - avoid attaching administrative permissions to task roles, even for "internal" services
- Restrict both `ecs:ExecuteCommand` and `ecs:DescribeTasks` permissions using IAM conditions to limit which clusters, services, or tasks can be accessed (both are required for ECS Exec to work)
- Use resource tags and condition keys like `aws:ResourceTag` to control which tasks allow execute command access
- Implement Service Control Policies (SCPs) at the organization level to prevent ECS Exec on sensitive workloads
- Monitor CloudTrail for `ExecuteCommand` API calls and alert on executions targeting tasks with privileged roles
- Enable CloudWatch logging for ECS Exec sessions to capture commands executed within containers
- Use IAM Access Analyzer to identify principals with ecs:ExecuteCommand access to tasks running with elevated permissions
- Implement network segmentation to limit what credentials obtained from ECS tasks can access
- Consider using separate ECS clusters for debugging (with ECS Exec enabled) and production (with ECS Exec disabled)
- Use VPC endpoints for ECS and SSM to ensure Exec traffic doesn't traverse the public internet

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `ecs:ExecuteCommand` -- Interactive shell session established in a running ECS container; critical when the target task has an elevated task role attached
- `ecs:DescribeTasks` -- Task details retrieved; required internally by the AWS CLI to establish the SSM session for ECS Exec; correlate with subsequent ExecuteCommand calls

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
