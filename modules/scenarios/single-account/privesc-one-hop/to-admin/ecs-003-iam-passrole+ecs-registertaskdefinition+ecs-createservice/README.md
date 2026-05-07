# ECS Task Definition Registration + Service Creation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** ECS service creation with admin role to grant starting user administrative access through persistent task execution
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_ecs_003_iam_passrole_ecs_registertaskdefinition_ecs_createservice`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** ecs-003
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution, TA0003 - Persistence
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1610 - Deploy Container

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-ecs-003-to-admin-starting-user` IAM user to the `pl-prod-ecs-003-to-admin-target-role` administrative role by registering a malicious ECS task definition with the admin role and deploying it as a Fargate service that attaches AdministratorAccess to your starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-ecs-003-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-ecs-003-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-ecs-003-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-ecs-003-to-admin-target-role` -- allows passing the admin role to ECS tasks
- `ecs:RegisterTaskDefinition` on `*` -- allows creating a task definition specifying the admin role
- `ecs:CreateService` on `*` -- allows deploying the task definition as a persistent Fargate service

**Helpful** (`pl-prod-ecs-003-to-admin-starting-user`):
- `ecs:DescribeServices` -- monitor service status and verify service creation
- `ecs:DescribeTasks` -- monitor task execution status and verify task completion
- `ecs:DeleteService` -- clean up ECS service after demonstration
- `ecs:UpdateService` -- scale down service or force new deployment during cleanup
- `ecs:DeregisterTaskDefinition` -- clean up task definition after demonstration
- `ecs:StopTask` -- stop running tasks during cleanup
- `ec2:DescribeVpcs` -- find default VPC for ECS service network configuration
- `ec2:DescribeSubnets` -- find subnet in default VPC for ECS service network configuration
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
plabs enable ecs-003-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-003-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-ecs-003-to-admin-starting-user` | Scenario-specific starting user with access keys and ECS permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-ecs-003-to-admin-target-role` | Admin role that can be passed to ECS services (trusts ecs-tasks.amazonaws.com) |
| `arn:aws:ecs:{region}:{account_id}:cluster/pl-prod-ecs-003-cluster` | ECS cluster for running Fargate services |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/ecs-003-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve scenario credentials and configuration from Terraform outputs
2. Verify the starting user identity and confirm no admin access yet
3. Register a malicious ECS task definition specifying the admin target role
4. Identify a VPC subnet for the Fargate service network configuration
5. Create an ECS Fargate service that launches a task running as the admin role
6. Monitor service and task status until the privilege escalation command completes
7. Verify that AdministratorAccess is now attached to the starting user
8. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions

#### Resources Created by Attack Script

- ECS task definition (`pl-ecs-003-admin-escalation`) registered with the admin target role as both task role and execution role
- ECS service (`pl-prod-ecs-003-attack-service`) deployed on AWS Fargate in the `pl-prod-ecs-003-cluster` cluster
- `AdministratorAccess` managed policy attached to `pl-prod-ecs-003-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo ecs-003-iam-passrole+ecs-registertaskdefinition+ecs-createservice
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-003-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

After demonstrating the attack, clean up the ECS service, task definition, running tasks, and detach the AdministratorAccess policy from the starting user.

**Note**: The cleanup process requires deleting the ECS service first before deregistering the task definition. The service will stop all running tasks automatically when deleted.

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ecs-003-iam-passrole+ecs-registertaskdefinition+ecs-createservice
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-003-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable ecs-003-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-003-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user (`pl-prod-ecs-003-to-admin-starting-user`) has `iam:PassRole` permission targeting a role with administrative privileges
- IAM user has `ecs:RegisterTaskDefinition` and `ecs:CreateService` permissions, enabling privilege escalation through ECS service deployment
- IAM role (`pl-prod-ecs-003-to-admin-target-role`) can be passed to ECS tasks (`ecs-tasks.amazonaws.com` as trusted principal) and holds administrative permissions
- Combination of `iam:PassRole` + `ecs:RegisterTaskDefinition` + `ecs:CreateService` represents a privilege escalation path to admin
- ECS cluster exists with no guardrails preventing deployment of task definitions with highly privileged roles

#### Prevention Recommendations

- Restrict `iam:PassRole` permissions using resource-based conditions to limit which roles can be passed and to which AWS services
- Implement condition keys like `iam:PassedToService` with value `ecs-tasks.amazonaws.com` to explicitly control PassRole usage
- Avoid granting broad `ecs:RegisterTaskDefinition` and `ecs:CreateService` permissions; use resource tags or naming patterns to limit service operations
- Implement Service Control Policies (SCPs) that prevent passing roles with administrative permissions to ECS services
- Use IAM Access Analyzer to identify privilege escalation paths involving PassRole combined with ECS operations
- Enable AWS Config rules to detect ECS task definitions and services with overly permissive execution roles
- Implement IAM permission boundaries on users to limit the maximum permissions that can be attached
- Require approval workflows for ECS services that reference privileged IAM roles or run in production environments

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `ecs:RegisterTaskDefinition` -- new ECS task definition registered; inspect `taskRoleArn` and `executionRoleArn` in request parameters — a privileged role ARN in either field is the CloudTrail signal for PassRole to ECS; high severity when the role has elevated privileges
- `ecs:CreateService` -- ECS service created; review task definition to confirm it uses expected roles
- `ecs:RunTask` -- ECS task launched; correlate with prior RegisterTaskDefinition and CreateService events
- `iam:AttachUserPolicy` -- policy attached to a user; critical when the source principal is an ECS task role and the policy is AdministratorAccess

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
