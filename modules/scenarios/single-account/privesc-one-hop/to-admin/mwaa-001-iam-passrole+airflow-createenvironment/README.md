# MWAA Environment Creation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $37/mo
* **Cost Estimate When Demo Executed:** $37/mo
* **Technique:** Pass privileged role to MWAA environment with malicious startup script for privilege escalation
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_mwaa_001_iam_passrole_airflow_createenvironment`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** mwaa-001
* **CTF Flag Location:** ssm-parameter
* **Interactive Demo:** Yes
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1098 - Account Manipulation, T1059 - Command and Scripting Interpreter

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-mwaa-001-to-admin-starting-user` IAM user to the `pl-prod-mwaa-001-to-admin-admin-role` administrative role by creating an Amazon MWAA environment that passes an administrative execution role and runs a malicious startup script that attaches `AdministratorAccess` to your starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-mwaa-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-mwaa-001-to-admin-admin-role`

### Starting Permissions

**Required** (`pl-prod-mwaa-001-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-mwaa-001-to-admin-admin-role` -- pass the admin execution role to the MWAA service
- `airflow:CreateEnvironment` on `*` -- create an MWAA environment with the admin execution role
- `ec2:CreateNetworkInterface` on `*` -- MWAA validates caller has this permission (SLR does actual work)
- `ec2:CreateNetworkInterfacePermission` on `*` -- MWAA validates caller has this permission
- `ec2:DescribeNetworkInterfaces` on `*` -- MWAA validates caller has this permission
- `ec2:DescribeSubnets` on `*` -- MWAA validates caller has this permission
- `ec2:DescribeSecurityGroups` on `*` -- MWAA validates caller has this permission
- `ec2:DescribeVpcs` on `*` -- MWAA validates caller has this permission
- `ec2:CreateVpcEndpoint` on `*` -- MWAA validates caller has this permission
- `ec2:DeleteVpcEndpoints` on `*` -- MWAA validates caller has this permission
- `ec2:DescribeVpcEndpoints` on `*` -- MWAA validates caller has this permission
- `ec2:DescribeVpcEndpointServices` on `*` -- MWAA validates caller has this permission
- `s3:GetEncryptionConfiguration` on `*` -- MWAA validates caller has this permission

**Helpful** (`pl-prod-mwaa-001-to-admin-starting-user`):
- `airflow:GetEnvironment` -- check environment status and wait for it to be ready
- `airflow:DeleteEnvironment` -- clean up the MWAA environment after the attack
- `ec2:DescribeRouteTables` -- verify subnets have routes to NAT Gateway

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable mwaa-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `mwaa-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-mwaa-001-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-mwaa-001-to-admin-admin-role` | Administrative execution role passed to MWAA environment |
| `arn:aws:ec2:{region}:{account_id}:vpc/pl-prod-mwaa-001-vpc` | Dedicated VPC with private subnets and NAT Gateway for MWAA |
| `arn:aws:s3:::pl-mwaa-001-attacker-bucket-{account_id}-{suffix}` | S3 bucket containing DAGs folder and malicious startup script |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/mwaa-001-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

> **CRITICAL COST WARNING**: This scenario involves Amazon MWAA which has significant ongoing costs. Run the cleanup script immediately after verification to avoid charges. MWAA environment creation takes 20-30 minutes and costs approximately $0.49/hour (~$350/month) plus NAT Gateway fees (~$0.045/hour).

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create an S3 bucket with a malicious startup script (or use an external bucket)
4. Create an MWAA environment with the admin execution role
5. Wait for environment creation (20-30 minutes with progress updates)
6. Verify successful privilege escalation by demonstrating admin access
7. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions


#### Resources Created by Attack Script

- MWAA environment with admin execution role and malicious startup script
- S3 bucket containing DAGs folder and malicious startup script (attacker-controlled)
- `AdministratorAccess` policy attached to the starting user

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo mwaa-001-iam-passrole+airflow-createenvironment
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `mwaa-001-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

After demonstrating the attack, **immediately** clean up the MWAA environment to stop incurring costs.

The cleanup script will:
- Delete the MWAA environment (takes 15-20 minutes to fully delete)
- Detach the AdministratorAccess policy from the starting user
- Remove the attacker's S3 bucket and startup script
- Clean up any VPC resources created for the environment

> **Important**: MWAA environment deletion takes 15-20 minutes. Verify in the AWS Console that the environment has been fully deleted to stop charges.

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup mwaa-001-iam-passrole+airflow-createenvironment
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `mwaa-001-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable single_account_privesc_one_hop_to_admin_mwaa_001_iam_passrole_airflow_createenvironment
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `mwaa-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user with `iam:PassRole` permission on privileged roles
- IAM user with `airflow:CreateEnvironment` permission
- Combination of PassRole and MWAA permissions enabling privilege escalation
- IAM role with administrative permissions that can be passed to MWAA service
- MWAA trust policy allowing the airflow service to assume privileged roles
- Privilege escalation path from user to admin via MWAA environment creation

#### Prevention Recommendations

- **Restrict PassRole permissions**: Limit `iam:PassRole` to only the specific roles and services needed. Use resource-level restrictions:
  ```json
  {
    "Effect": "Allow",
    "Action": "iam:PassRole",
    "Resource": "arn:aws:iam::*:role/specific-mwaa-role",
    "Condition": {
      "StringEquals": {
        "iam:PassedToService": "airflow.amazonaws.com"
      }
    }
  }
  ```

- **Implement SCPs to prevent privilege escalation**: Use Service Control Policies to deny PassRole on administrative roles to MWAA:
  ```json
  {
    "Effect": "Deny",
    "Action": "iam:PassRole",
    "Resource": "arn:aws:iam::*:role/*admin*",
    "Condition": {
      "StringEquals": {
        "iam:PassedToService": "airflow.amazonaws.com"
      }
    }
  }
  ```

- **Restrict external S3 bucket references**: Implement SCPs or IAM policies that deny `airflow:CreateEnvironment` when the source bucket or startup script references external AWS accounts:
  ```json
  {
    "Effect": "Deny",
    "Action": "airflow:CreateEnvironment",
    "Resource": "*",
    "Condition": {
      "StringNotEquals": {
        "airflow:SourceBucketArn": "arn:aws:s3:::your-approved-bucket-*"
      }
    }
  }
  ```

- **Disable startup scripts**: If startup scripts are not required in your organization, deny their use entirely or require them to come from approved, audited S3 locations.

- **Restrict airflow:CreateEnvironment permissions**: Only grant this permission to users who legitimately need to create MWAA environments (data engineering teams, platform administrators). This is a powerful permission that should be tightly controlled.

- **Use IAM Access Analyzer**: Enable IAM Access Analyzer to automatically detect privilege escalation paths involving PassRole and MWAA services.

- **Implement least privilege for MWAA execution roles**: When creating IAM roles for MWAA, grant only the minimum permissions required for the specific workflows. Typical MWAA environments need S3 access for DAGs, CloudWatch Logs access, and specific data service permissions — not IAM modification capabilities.

- **Require VPC endpoints and private subnets**: Configure MWAA environments to run within private VPCs without public access, reducing the attack surface and limiting data exfiltration paths.

- **Implement environment approval workflows**: Require code review and approval before MWAA environments can be created, especially reviewing execution roles and startup scripts.

- **Enable MWAA audit logging**: Configure comprehensive logging for MWAA environments to capture all API calls and startup script execution for forensic analysis.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `MWAA: CreateEnvironment` -- MWAA environment created; critical when the `ExecutionRoleArn` references an administrative role or when `StartupScriptS3Path` references an external AWS account
- `IAM: PassRole` -- role passed to a service; monitor when the passed role has administrative permissions and the service is `airflow.amazonaws.com`
- `IAM: AttachUserPolicy` -- policy attached to a user; high severity when originating from an MWAA execution role context
- `IAM: PutUserPolicy` -- inline policy written to a user; high severity when originating from an MWAA execution role context

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [Amazon MWAA Documentation](https://docs.aws.amazon.com/mwaa/latest/userguide/what-is-mwaa.html) -- official MWAA service documentation
- [MWAA Execution Role Permissions](https://docs.aws.amazon.com/mwaa/latest/userguide/mwaa-create-role.html) -- documentation on execution role requirements
- [MWAA Startup Script Configuration](https://docs.aws.amazon.com/mwaa/latest/userguide/using-startup-script.html) -- documentation on the startup script feature exploited in this scenario
- [AWS IAM PassRole Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html) -- how iam:PassRole works and security considerations
- [Rhino Security Labs - AWS IAM Privilege Escalation Methods](https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation/) -- comprehensive guide to IAM privilege escalation techniques
