# ECS New Cluster + Service Creation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Creating ECS cluster and deploying service with privileged role to gain administrative access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_ecs_001_iam_passrole_ecs_createcluster_ecs_registertaskdefinition_ecs_createservice`
* **Schema Version:** 4.1.1
* **Pathfinding.cloud ID:** ecs-001
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution, TA0003 - Persistence
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1610 - Deploy Container

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-ecs-001-to-admin-starting-user` IAM user to the `pl-prod-ecs-001-to-admin-target-role` administrative role by creating an ECS cluster, registering a task definition with the privileged role via `iam:PassRole`, and deploying a Fargate service that runs a container which attaches `AdministratorAccess` to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-ecs-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-ecs-001-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-ecs-001-to-admin-starting-user`):
- `ecs:CreateCluster` on `*` -- create a new ECS cluster to host the malicious Fargate service
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-ecs-001-to-admin-target-role` -- pass the privileged target role to the ECS task definition
- `ecs:RegisterTaskDefinition` on `*` -- register a task definition that references the privileged role
- `ecs:CreateService` on `*` -- deploy a persistent Fargate service that executes the malicious task

**Helpful** (`pl-prod-ecs-001-to-admin-starting-user`):
- `ec2:DescribeVpcs` -- find the default VPC for ECS service network configuration
- `ec2:DescribeSubnets` -- find subnets in the default VPC for Fargate awsvpc networking
- `ecs:DescribeServices` -- monitor service status and verify service creation
- `ecs:DescribeTasks` -- monitor task execution status and verify task completion
- `ecs:ListTasks` -- list tasks in the cluster to get the task ARN for monitoring
- `ecs:UpdateService` -- scale down the service during cleanup
- `ecs:DeleteService` -- clean up the ECS service after demonstration
- `ecs:StopTask` -- stop running tasks during cleanup
- `ecs:DeregisterTaskDefinition` -- clean up the task definition after demonstration
- `ecs:DeleteCluster` -- clean up the ECS cluster after demonstration
- `iam:ListAttachedUserPolicies` -- verify privilege escalation success by listing attached policies
- `iam:ListUsers` -- verify administrator access by listing IAM users
- `iam:DetachUserPolicy` -- remove the admin policy from the starting user during cleanup

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable ecs-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-ecs-001-to-admin-starting-user` | Scenario-specific starting user with access keys and ECS permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-ecs-001-to-admin-target-role` | Target role with AdministratorAccess policy that can be passed to ECS tasks |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create an ECS cluster and deploy a malicious service
4. Wait for the task to execute and grant administrative access
5. Verify successful privilege escalation
6. Output standardized test results for automation

#### Resources Created by Attack Script

- ECS cluster created for hosting the malicious service
- ECS task definition registered with the privileged target role
- ECS Fargate service deployed to execute the malicious task
- AdministratorAccess policy attached to the starting user

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo ecs-001-iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-createservice
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-001-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ecs-001-iam-passrole+ecs-createcluster+ecs-registertaskdefinition+ecs-createservice
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-001-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable ecs-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ecs-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- **Privilege Escalation Path**: User with `iam:PassRole` + `ecs:CreateCluster` + `ecs:RegisterTaskDefinition` + `ecs:CreateService` can escalate to administrative access
- **Overly Permissive PassRole**: IAM user can pass roles with administrative privileges to ECS services
- **Unrestricted ECS Creation**: User can create ECS clusters and services without resource restrictions
- **Service PassRole Risk**: Combination of service creation permissions (ECS) with ability to pass privileged roles
- **Fargate Service Deployment**: User can deploy containerized workloads with privileged execution roles

#### Prevention Recommendations

- Implement strict resource-based conditions on `iam:PassRole` to limit which roles can be passed: `"Condition": {"StringEquals": {"iam:PassedToService": "ecs-tasks.amazonaws.com"}}`
- Add resource constraints to `iam:PassRole` to prevent passing administrative roles: `"Resource": "arn:aws:iam::*:role/AppSpecificRole*"`
- Use Service Control Policies (SCPs) to prevent creation of ECS clusters in unauthorized accounts or regions
- Implement tag-based access control requiring specific tags on roles before they can be passed to ECS services
- Enable MFA requirements for ECS service creation operations using condition keys like `aws:MultiFactorAuthPresent`
- Use IAM Access Analyzer to identify privilege escalation paths involving ECS PassRole permissions
- Restrict task execution roles to least privilege — avoid attaching AdministratorAccess to roles used by ECS tasks
- Implement automated alerting on ECS service creation events that pass privileged roles using EventBridge

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PassRole` -- role passed to ECS task; critical when the passed role has administrative permissions
- `ECS: CreateCluster` -- new ECS cluster created; high severity when followed by task definition registration and service creation
- `ECS: RegisterTaskDefinition` -- new task definition registered; high severity when it references a privileged IAM role
- `ECS: CreateService` -- ECS service created; high severity when service uses a task definition with a privileged role and Fargate launch type

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
