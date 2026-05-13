# EMR RunJobFlow with Admin Instance Profile to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Passing an admin instance profile to an EMR cluster and executing a step via command-runner.jar to attach AdministratorAccess to the starting user
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_emr_001_iam_passrole_elasticmapreduce_runjobflow`
* **Schema Version:** 4.6.1
* **Pathfinding.cloud ID:** emr-001
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1578 - Modify Cloud Compute Infrastructure

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-emr-001-to-admin-starting-user` IAM user to the `pl-prod-emr-001-to-admin-admin-role` administrative role by creating an EMR cluster with the admin role as the instance profile and executing a step via `command-runner.jar` that attaches `AdministratorAccess` to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-emr-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-emr-001-to-admin-admin-role`

### Starting Permissions

**Required** (`pl-prod-emr-001-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-emr-001-to-admin-admin-role` and `arn:aws:iam::*:role/pl-prod-emr-001-to-admin-service-role` -- allows passing the admin role to the EMR cluster as the job flow role (instance profile) and the EMR service role trusted by `elasticmapreduce.amazonaws.com`
- `elasticmapreduce:RunJobFlow` on `*` -- allows creating an EMR cluster with the admin instance profile and submitting a step

**Helpful** (`pl-prod-emr-001-to-admin-starting-user`):
- `elasticmapreduce:DescribeCluster` -- monitor cluster status and verify step completion
- `elasticmapreduce:DescribeStep` -- check step execution status
- `elasticmapreduce:ListSteps` -- list steps on the EMR cluster to check step execution status
- `elasticmapreduce:ListClusters` -- list existing clusters
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
plabs enable emr-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `emr-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-emr-001-to-admin-starting-user` | Scenario-specific starting user with access keys, PassRole, and EMR permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-emr-001-to-admin-admin-role` | Administrative role with AdministratorAccess, used as the EMR instance profile (trusts `ec2.amazonaws.com`) |
| `arn:aws:iam::{account_id}:instance-profile/pl-prod-emr-001-to-admin-admin-instance-profile` | Instance profile associated with the admin role |
| `arn:aws:iam::{account_id}:role/pl-prod-emr-001-to-admin-service-role` | EMR service role with AmazonElasticMapReduceRole (trusts `elasticmapreduce.amazonaws.com`) |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/emr-001-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create an EMR cluster passing the admin instance profile as `JobFlowRole` and the service role as `ServiceRole`
4. Include a step using `command-runner.jar` to run `aws iam attach-user-policy` with the admin instance profile credentials
5. Wait for the EMR cluster to provision and the step to complete (5-15 minutes)
6. Verify successful privilege escalation by demonstrating admin access
7. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions

#### Resources Created by Attack Script

- EMR cluster with the admin instance profile as `JobFlowRole` (auto-terminates after step completion)
- `AdministratorAccess` managed policy attached to `pl-prod-emr-001-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo emr-001-iam-passrole+elasticmapreduce-runjobflow
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup emr-001-iam-passrole+elasticmapreduce-runjobflow
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable emr-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `emr-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user with `iam:PassRole` permission on a role that has `AdministratorAccess` or equivalent permissions
- IAM user with `elasticmapreduce:RunJobFlow` combined with `iam:PassRole`, forming a privilege escalation path via EMR cluster creation
- IAM role with `AdministratorAccess` that trusts `ec2.amazonaws.com` and can be passed as an EMR instance profile
- Privilege escalation path from IAM user to admin via EMR job flow submission with an admin instance profile

#### Prevention Recommendations

- Restrict `iam:PassRole` using the `iam:PassedToService` condition key to limit which services a role can be passed to (e.g., `"iam:PassedToService": ["elasticmapreduce.amazonaws.com", "ec2.amazonaws.com"]`)
- Scope `iam:PassRole` resource constraints to non-privileged roles only; deny passing roles with `AdministratorAccess` or broad IAM permissions to EMR clusters
- Use EMR runtime roles (available in EMR 5.34+ and 6.9+) to provide per-step IAM credentials instead of relying on the instance profile for all step execution
- Never attach `AdministratorAccess` or other highly privileged policies to instance profiles used by compute services like EMR, EC2, or ECS
- Implement SCPs that deny `elasticmapreduce:RunJobFlow` when `requestParameters.jobFlowRole` references a privileged role
- Use IAM Access Analyzer to automatically detect privilege escalation paths involving `iam:PassRole` and EMR job flow creation

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `elasticmapreduce:RunJobFlow` -- new EMR cluster created; inspect `requestParameters.serviceRole` and `requestParameters.jobFlowRole` (or `requestParameters.ec2Attributes.instanceProfile`) — a privileged role ARN in either field is the CloudTrail signal for PassRole abuse via EMR; high severity when the job flow role has administrative permissions
- `iam:AttachUserPolicy` -- managed policy attached to an IAM user from within an EMR step context; critical when the policy is `AdministratorAccess` and the caller is an EC2 instance role

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS EMR Instance Profile Documentation](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-iam-role-for-ec2.html) -- explains how the EC2 instance profile works in EMR and why it grants credentials to steps running on cluster nodes
- [AWS IAM PassRole Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html) -- explains PassRole mechanics and how to restrict it with `iam:PassedToService`
- [AWS EMR Runtime Roles](https://docs.aws.amazon.com/emr/latest/ManagementGuide/emr-steps-runtime-roles.html) -- per-step IAM credentials as a mitigation for overly permissive instance profiles
- [Rhino Security Labs - AWS IAM Privilege Escalation Methods](https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation/) -- comprehensive overview of IAM privilege escalation techniques including PassRole patterns
- [pathfinding.cloud/paths/emr-001](https://pathfinding.cloud/paths/emr-001) -- documented attack path for this scenario
