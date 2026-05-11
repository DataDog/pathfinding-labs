# Role Assumption + ECS Service Creation to Admin

* **Category:** Privilege Escalation
* **Path Type:** multi-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Assume a role with ECS permissions, then use PassRole combined with ECS Fargate to run a task with an administrative role
* **Terraform Variable:** `enable_single_account_privesc_multi_hop_to_admin_sts_001_to_ecs_002_to_admin`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** sts-001 + ecs-002
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1578 - Modify Cloud Compute Infrastructure

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-sts001-ecs002-starting-user` IAM user to the `pl-prod-sts001-ecs002-admin-role` administrative role by first assuming an intermediate role with ECS management permissions and then running a Fargate task that executes with the admin role and attaches `AdministratorAccess` to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-sts001-ecs002-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-sts001-ecs002-admin-role`

### Starting Permissions

**Required** (`pl-prod-sts001-ecs002-starting-user`):
- `sts:AssumeRole` on `arn:aws:iam::*:role/pl-prod-sts001-ecs002-intermediate-role` -- allows assuming the intermediate role (Hop 1)

**Required** (`pl-prod-sts001-ecs002-intermediate-role`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-sts001-ecs002-admin-role` -- allows attaching the admin role to an ECS task definition (Hop 2)
- `ecs:CreateCluster` on `*` -- allows creating an ECS cluster to host the malicious task (Hop 2)
- `ecs:RegisterTaskDefinition` on `*` -- allows registering a task definition with the admin role attached (Hop 2)
- `ecs:RunTask` on `*` -- allows launching the Fargate task that escalates privileges (Hop 2)

**Helpful** (`pl-prod-sts001-ecs002-starting-user`):
- `iam:ListRoles` -- discover available roles that trust ecs-tasks.amazonaws.com
- `iam:GetRole` -- view role permissions and trust policies before assuming

**Helpful** (`pl-prod-sts001-ecs002-intermediate-role`):
- `ec2:DescribeVpcs` -- find the default VPC for Fargate network configuration
- `ec2:DescribeSubnets` -- find subnets for Fargate network configuration
- `ecs:DescribeTasks` -- monitor task status and completion

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
plabs enable sts-001-to-ecs-002-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `sts-001-to-ecs-002-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-sts001-ecs002-starting-user` | Scenario-specific starting user with sts:AssumeRole permission on the intermediate role |
| `arn:aws:iam::{account_id}:role/pl-prod-sts001-ecs002-intermediate-role` | Intermediate role with ECS management permissions and iam:PassRole on the admin role |
| `arn:aws:iam::{account_id}:role/pl-prod-sts001-ecs002-admin-role` | Target admin role with AdministratorAccess, trusts ecs-tasks.amazonaws.com (also serves as task execution role) |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/sts-001-to-ecs-002-to-admin-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Assume the intermediate role to obtain ECS management permissions
3. Create an ECS cluster for hosting the malicious task
4. Register a task definition with the admin role attached
5. Run the task on Fargate and wait for completion
6. Extract the admin role credentials from the task output
7. Verify successful privilege escalation to administrator
8. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions


#### Resources Created by Attack Script

- ECS cluster (`pl-prod-sts001-ecs002-attack-cluster`)
- ECS task definition (`pl-sts001-ecs002-admin-escalation`) with admin role attached
- CloudWatch log group (`/ecs/pl-sts001-ecs002-admin-escalation`)
- `AdministratorAccess` policy attached to `pl-prod-sts001-ecs002-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo sts-001-to-ecs-002-to-admin
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `sts-001-to-ecs-002-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup sts-001-to-ecs-002-to-admin
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `sts-001-to-ecs-002-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable sts-001-to-ecs-002-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `sts-001-to-ecs-002-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

**High Severity Findings:**
- IAM role has `ecs:RegisterTaskDefinition` combined with `iam:PassRole` -- allows task role injection
- IAM role can pass administrative roles to ECS tasks
- Administrative role trusts `ecs-tasks.amazonaws.com` -- can be assumed by ECS tasks
- Multi-hop privilege escalation path from starting user to administrator via ECS
- User can assume role with dangerous ECS/PassRole combination

**Medium Severity Findings:**
- IAM role has `ecs:CreateCluster` permission -- allows creation of compute resources
- IAM role has `ecs:RunTask` permission -- allows code execution in account
- Administrative role exists that trusts AWS service principals
- ECS task execution role with broad permissions exists

**Attack Path Detection:**
- Path: `starting-user` -> `sts:AssumeRole` -> `intermediate-role` -> `iam:PassRole + ecs:*` -> `admin-role` (via ECS task)
- Risk: Complete environment compromise through chained privilege escalation via container service

#### Prevention Recommendations

- **Restrict iam:PassRole with conditions**: Limit which roles can be passed and to which services using conditions: `"Condition": {"StringEquals": {"iam:PassedToService": "ecs-tasks.amazonaws.com"}, "ArnNotLike": {"iam:AssociatedResourceArn": "*admin*"}}`

- **Separate ECS permissions from PassRole**: Avoid granting both `ecs:RegisterTaskDefinition` and `iam:PassRole` to the same principal -- this combination enables task role injection attacks

- **Use permission boundaries on task roles**: Apply permission boundaries that explicitly deny administrative actions to roles that trust `ecs-tasks.amazonaws.com`

- **Restrict trust policies on administrative roles**: Administrative roles should not trust service principals like `ecs-tasks.amazonaws.com`. Use dedicated, least-privilege task roles instead

- **Implement SCPs for ECS task roles**: Organization-level SCPs can prevent ECS tasks from using roles with administrative permissions regardless of their attached policies

- **Monitor ECS task definitions**: Set up CloudWatch Events/EventBridge rules to alert when task definitions are registered with privileged task roles

- **Use AWS Config rules**: Implement Config rules to detect IAM roles with AdministratorAccess that trust ECS service principals

- **Require task definition review**: Implement approval workflows for task definition changes that include privileged roles

- **Enable VPC Flow Logs**: Monitor network traffic from ECS tasks to detect credential exfiltration attempts via the container metadata service

- **Limit sts:AssumeRole permissions**: Use resource-based conditions to restrict which roles users can assume, preventing lateral movement to roles with dangerous permissions

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `sts:AssumeRole` -- role assumption (initial escalation step); monitor for assumption of roles with ECS management permissions
- `ecs:CreateCluster` -- new ECS cluster created; suspicious when not part of a normal deployment workflow
- `ecs:RegisterTaskDefinition` -- task definition registered; critical when `taskRoleArn` points to a privileged role — this field is the CloudTrail signal for PassRole to ECS; inspect `executionRoleArn` as well
- `ecs:RunTask` -- task execution initiated; high severity when combined with a recently registered task definition bearing an admin role

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [pathfinding.cloud - sts-001](https://pathfinding.cloud/paths/sts-001) -- STS AssumeRole privilege escalation
- [pathfinding.cloud - ecs-002](https://pathfinding.cloud/paths/ecs-002) -- ECS PassRole + Task execution privilege escalation
- [MITRE ATT&CK T1098.001](https://attack.mitre.org/techniques/T1098/001/) -- Account Manipulation: Additional Cloud Credentials
- [MITRE ATT&CK T1578](https://attack.mitre.org/techniques/T1578/) -- Modify Cloud Compute Infrastructure
- [AWS ECS Task IAM Roles](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html) -- AWS documentation on ECS task roles
- [AWS IAM PassRole](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html) -- Understanding the PassRole permission
- [AWS Fargate Security](https://docs.aws.amazon.com/AmazonECS/latest/bestpracticesguide/security-fargate.html) -- Best practices for securing Fargate workloads
