# DataPipeline Job Creation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Creating a Data Pipeline with an admin role to execute commands with elevated privileges
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_iam_passrole_datapipeline_pipeline`
* **Schema Version:** 4.1.1
* **Pathfinding.cloud ID:** datapipeline-001
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1578 - Modify Cloud Compute Infrastructure

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-datapipeline-001-to-admin-starting-user` IAM user to administrator access by using `iam:PassRole` and AWS Data Pipeline permissions to create a pipeline that launches an EC2 instance with an administrative role and executes a ShellCommandActivity attaching `AdministratorAccess` to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-datapipeline-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::aws:policy/AdministratorAccess` attached to the starting user

### Starting Permissions

**Required** (`pl-prod-datapipeline-001-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-datapipeline-001-to-admin-pipeline-role` -- allows passing the admin role to the Data Pipeline EC2 resource
- `datapipeline:CreatePipeline` on `*` -- create a new Data Pipeline
- `datapipeline:PutPipelineDefinition` on `*` -- define the pipeline with a malicious ShellCommandActivity
- `datapipeline:ActivatePipeline` on `*` -- trigger pipeline execution

**Helpful** (`pl-prod-datapipeline-001-to-admin-starting-user`):
- `datapipeline:DescribePipelines` -- monitor pipeline status and verify activation
- `datapipeline:GetPipelineDefinition` -- view pipeline configuration for verification
- `iam:ListRoles` -- discover available privileged roles to pass
- `iam:GetUser` -- verify policy attachment after escalation

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable datapipeline-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `datapipeline-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-datapipeline-001-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-datapipeline-001-to-admin-pipeline-role` | Administrative role that can be passed to Data Pipeline EC2 instances |
| `arn:aws:iam::{account_id}:policy/pl-prod-datapipeline-001-to-admin-starting-policy` | Policy granting Data Pipeline permissions and iam:PassRole |
| `arn:aws:datapipeline:{region}:{account_id}:pipeline/df-*` | Data Pipeline created during attack (ephemeral) |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create and activate a Data Pipeline with an admin role
4. Wait for the pipeline to execute the privilege escalation command
5. Verify successful privilege escalation to administrator access


#### Resources Created by Attack Script

- Data Pipeline (`datapipeline:CreatePipeline`) with a ShellCommandActivity payload
- EC2 instance launched by the pipeline with the admin role attached
- `AdministratorAccess` managed policy attachment on the starting user

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-passrole+datapipeline-pipeline-to-admin
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `datapipeline-001-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-passrole+datapipeline-pipeline-to-admin
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `datapipeline-001-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable datapipeline-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `datapipeline-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user with `iam:PassRole` permissions on an administrative role combined with Data Pipeline creation permissions (`datapipeline:CreatePipeline`, `datapipeline:PutPipelineDefinition`, `datapipeline:ActivatePipeline`) constitutes a privilege escalation path
- Administrative roles configured as passable EC2 instance profiles for AWS services
- Graph-based analysis showing path from low-privilege user to admin access via Data Pipeline

#### Prevention Recommendations

- **Restrict iam:PassRole**: Implement strict resource-based conditions on `iam:PassRole` permissions to prevent passing administrative roles to services:
  ```json
  {
    "Effect": "Allow",
    "Action": "iam:PassRole",
    "Resource": "arn:aws:iam::*:role/LimitedServiceRole",
    "Condition": {
      "StringEquals": {
        "iam:PassedToService": "datapipeline.amazonaws.com"
      }
    }
  }
  ```

- **Service Control Policies (SCPs)**: Use AWS Organizations SCPs to prevent Data Pipeline creation in accounts where it's not needed:
  ```json
  {
    "Effect": "Deny",
    "Action": [
      "datapipeline:CreatePipeline",
      "datapipeline:PutPipelineDefinition",
      "datapipeline:ActivatePipeline"
    ],
    "Resource": "*",
    "Condition": {
      "StringNotLike": {
        "aws:PrincipalArn": "arn:aws:iam::*:role/ApprovedAutomationRole"
      }
    }
  }
  ```

- **Least Privilege for Roles**: Avoid granting administrative permissions to roles that can be passed to AWS services. Create service-specific roles with minimal permissions required for the task.

- **IAM Access Analyzer**: Enable IAM Access Analyzer to continuously evaluate IAM policies and identify privilege escalation paths through service integrations.

- **Resource Tagging and Monitoring**: Tag all Data Pipeline resources and monitor for untagged or improperly tagged pipelines that may indicate unauthorized creation.

- **VPC and Network Controls**: Configure Data Pipeline EC2 instances to launch in private subnets without internet access when possible, limiting the attack surface for command execution.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `DataPipeline: CreatePipeline` -- new pipeline created; suspicious when followed immediately by PutPipelineDefinition and ActivatePipeline
- `DataPipeline: PutPipelineDefinition` -- pipeline definition set; high severity when the definition contains a ShellCommandActivity with IAM-related commands
- `DataPipeline: ActivatePipeline` -- pipeline activated; alert when called by non-automation principals
- `IAM: AttachUserPolicy` -- managed policy attached to a user; critical when the source is an EC2 instance launched by Data Pipeline
- `IAM: AttachRolePolicy` -- managed policy attached to a role; critical when originating from Data Pipeline-launched EC2 instances
- `EC2: RunInstances` -- EC2 instance launched; monitor for instances launched with administrative instance profiles by Data Pipeline service principals
- `IAM: PassRole` -- role passed to a service; alert when an administrative role is passed to `datapipeline.amazonaws.com`

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS Data Pipeline Documentation](https://docs.aws.amazon.com/datapipeline/) -- official AWS documentation for the Data Pipeline service
- [Bishop Fox - Privilege Escalation via Data Pipeline](https://bishopfox.com/blog/privilege-escalation-in-aws) -- original research on Data Pipeline privilege escalation
- [Rhino Security Labs - AWS IAM Privilege Escalation Techniques](https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation/) -- comprehensive overview of IAM privilege escalation methods
- [MITRE ATT&CK - T1098.001](https://attack.mitre.org/techniques/T1098/001/) -- Account Manipulation: Additional Cloud Credentials
- [MITRE ATT&CK - T1578](https://attack.mitre.org/techniques/T1578/) -- Modify Cloud Compute Infrastructure
