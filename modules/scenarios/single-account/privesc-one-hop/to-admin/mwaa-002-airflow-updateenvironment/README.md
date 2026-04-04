# MWAA Environment Update to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $37/mo
* **Technique:** Update existing MWAA environment's DAG source bucket to attacker-controlled bucket containing malicious DAG that executes with admin credentials
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_mwaa_002_airflow_updateenvironment`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** mwaa-002
* **Interactive Demo:** Yes
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1098 - Account Manipulation, T1059 - Command and Scripting Interpreter

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-mwaa-002-to-admin-starting-user` IAM user to the `pl-prod-mwaa-002-to-admin-admin-role` administrative role by updating an existing MWAA environment's DAG source bucket to an attacker-controlled bucket containing a malicious DAG that executes with the environment's admin execution role credentials.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-mwaa-002-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-mwaa-002-to-admin-admin-role`

### Starting Permissions

**Required** (`pl-prod-mwaa-002-to-admin-starting-user`):
- `airflow:UpdateEnvironment` on `arn:aws:airflow:*:*:environment/pl-prod-mwaa-002-to-admin-env` -- change the DAG source bucket to an attacker-controlled bucket
- `airflow:CreateCliToken` on `arn:aws:airflow:*:*:environment/pl-prod-mwaa-002-to-admin-env` -- obtain a CLI token to trigger DAGs via the Airflow REST API
- `ec2:DescribeSubnets` on `*` -- MWAA validates these even when not changing network config
- `ec2:DescribeVpcs` on `*` -- MWAA validates these even when not changing network config
- `ec2:DescribeSecurityGroups` on `*` -- MWAA validates these even when not changing network config
- `s3:GetEncryptionConfiguration` on `*` -- MWAA validates bucket encryption settings

**Helpful** (`pl-prod-mwaa-002-to-admin-starting-user`):
- `airflow:GetEnvironment` -- check environment status and wait for update to complete
- `iam:ListAttachedUserPolicies` -- verify that AdministratorAccess was attached after the attack

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_mwaa_002_airflow_updateenvironment
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `space` to enable it
4. Press `d` to deploy

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-mwaa-002-to-admin-starting-user` | Scenario-specific starting user with access keys and required permissions |
| `arn:aws:airflow:{region}:{account_id}:environment/pl-prod-mwaa-002-to-admin-env` | Existing MWAA environment that can be updated by the starting user |
| `arn:aws:iam::{account_id}:role/pl-prod-mwaa-002-to-admin-admin-role` | Administrative execution role attached to the MWAA environment |
| `arn:aws:ec2:{region}:{account_id}:vpc/pl-prod-mwaa-002-vpc` | Dedicated VPC with private subnets and NAT Gateway for MWAA |
| `arn:aws:s3:::pl-mwaa-002-legitimate-bucket-{account_id}-{suffix}` | Original S3 bucket containing DAGs folder for the MWAA environment |
| `arn:aws:s3:::pl-mwaa-002-attacker-bucket-{account_id}-{suffix}` | Attacker's S3 bucket containing the malicious DAG |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

> **CRITICAL COST WARNING**: This scenario involves Amazon MWAA which has significant ongoing costs. **Destroy the environment immediately after testing to avoid charges.**
>
> - **mw1.small instance**: ~$0.49/hour (~$350/month if left running)
> - **NAT Gateway**: ~$0.045/hour + data processing (~$32/month minimum)
> - **Environment update time**: 10-30 minutes (unavoidable)
> - **Quick test (destroy within 1 hour)**: ~$1-2 | **Left running for 1 day**: ~$15-20

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Update the existing MWAA environment to use the attacker's DAG bucket
4. Wait for environment update (10-30 minutes with progress updates)
5. Wait for DAG synchronization (60 seconds)
6. Obtain a CLI token and trigger the malicious DAG
7. Verify successful privilege escalation by demonstrating admin access
8. Output standardized test results for automation

#### Resources Created by Attack Script

- AdministratorAccess policy attached to `pl-prod-mwaa-002-to-admin-starting-user`
- MWAA environment source bucket updated to attacker's bucket (`pl-mwaa-002-attacker-bucket-{account_id}-{suffix}`)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo mwaa-002-airflow-updateenvironment
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

After demonstrating the attack, **immediately** clean up to stop incurring costs and restore the environment. The cleanup script will:
- Detach the AdministratorAccess policy from the starting user
- Restore the MWAA environment's original DAG source bucket configuration
- Wait for environment update to complete (10-30 minutes)

> **Important**: MWAA environment updates take 10-30 minutes. Verify in the AWS Console that the environment has been restored to avoid leaving the malicious configuration active.

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup mwaa-002-airflow-updateenvironment
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_mwaa_002_airflow_updateenvironment
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user with `airflow:UpdateEnvironment` and `airflow:CreateCliToken` permissions on MWAA environments with privileged execution roles
- MWAA environment with administrative execution role attached
- Combination of UpdateEnvironment permission and overly permissive execution role enabling privilege escalation
- IAM role with administrative permissions that can be assumed by the MWAA service
- Privilege escalation path from user to admin via MWAA environment update and DAG execution

#### Prevention Recommendations

- **Restrict UpdateEnvironment Permissions**: Limit `airflow:UpdateEnvironment` to specific environments using resource-based conditions. Never grant blanket update permissions across all environments:
  ```json
  {
    "Effect": "Allow",
    "Action": "airflow:UpdateEnvironment",
    "Resource": "arn:aws:airflow:*:*:environment/approved-env-*",
    "Condition": {
      "StringEquals": {
        "aws:ResourceTag/UpdateAllowed": "true"
      }
    }
  }
  ```

- **Restrict CreateCliToken Permissions**: Limit `airflow:CreateCliToken` to users who legitimately need CLI access to MWAA environments. This permission allows triggering any DAG in the environment.

- **Minimize MWAA Execution Role Permissions**: Execution roles for MWAA environments should follow the principle of least privilege. Avoid granting IAM modification permissions. Typical MWAA environments need S3 access for DAGs, CloudWatch Logs access, and specific data service permissions - not IAM modification capabilities.

- **Implement SCPs to Prevent Source Bucket Modification**: Use Service Control Policies to deny environment updates that change source bucket paths to unauthorized locations:
  ```json
  {
    "Effect": "Deny",
    "Action": "airflow:UpdateEnvironment",
    "Resource": "*",
    "Condition": {
      "StringNotLike": {
        "airflow:SourceBucketArn": "arn:aws:s3:::your-approved-bucket-*"
      }
    }
  }
  ```

- **Restrict External S3 Bucket References**: Implement policies that deny environment updates when the source bucket references S3 buckets outside your organization's control.

- **Implement Change Control for MWAA Environments**: Require approval workflows for MWAA environment updates in production. Use AWS Systems Manager Change Manager or third-party tools to gate configuration changes.

- **Use IAM Access Analyzer**: Enable IAM Access Analyzer to automatically detect privilege escalation paths involving UpdateEnvironment permissions and privileged execution roles.

- **Separate DAG Management**: Store approved DAGs in a centralized, tightly-controlled S3 bucket with versioning enabled. Monitor for any attempts to reference DAGs from other locations.

- **Enable MWAA Audit Logging**: Configure comprehensive logging for MWAA environments to capture all API calls and DAG execution for forensic analysis.

- **Regular Permission Audits**: Periodically review which principals have `airflow:UpdateEnvironment` and `airflow:CreateCliToken` permissions and which environments have privileged execution roles. Ensure this combination is necessary for legitimate business functions.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `MWAA: UpdateEnvironment` -- API calls that modify `SourceBucketArn` or `DagS3Path`; high severity when the new source bucket references an external S3 bucket or different AWS account, or targets environments with administrative execution roles
- `MWAA: CreateCliToken` -- CLI token obtained for Airflow API access; critical when occurring shortly after an UpdateEnvironment operation
- `IAM: AttachUserPolicy` -- Managed policy attached to an IAM user; critical when originating from an MWAA execution role context
- `IAM: PutUserPolicy` -- Inline policy added to an IAM user; critical when originating from an MWAA execution role context

**CloudWatch Logs indicators:**
- MWAA task logs showing unexpected AWS CLI commands or boto3 IAM operations
- IAM API calls in MWAA worker logs that don't match expected workflow operations
- Errors related to IAM modifications from MWAA context
- New DAG files appearing with suspicious code patterns

**Behavioral indicators:**
- MWAA environment updates outside of change windows
- Source bucket changes to buckets not owned by the organization
- Environment updates performed by users who don't normally manage MWAA
- Rapid sequence of UpdateEnvironment → CreateCliToken → IAM policy modifications
- Unusual DAG executions after environment configuration changes

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [Amazon MWAA Documentation](https://docs.aws.amazon.com/mwaa/latest/userguide/what-is-mwaa.html) -- official MWAA service documentation
- [MWAA Execution Role Permissions](https://docs.aws.amazon.com/mwaa/latest/userguide/mwaa-create-role.html) -- guidance on scoping execution role permissions
- [MWAA DAGs Configuration](https://docs.aws.amazon.com/mwaa/latest/userguide/configuring-dag-folder.html) -- configuring the DAG source folder
- [MWAA UpdateEnvironment API](https://docs.aws.amazon.com/mwaa/latest/API/API_UpdateEnvironment.html) -- API reference for UpdateEnvironment
- [MWAA CreateCliToken API](https://docs.aws.amazon.com/mwaa/latest/API/API_CreateCliToken.html) -- API reference for CreateCliToken
- [Airflow REST API Reference](https://airflow.apache.org/docs/apache-airflow/stable/stable-rest-api-ref.html) -- Airflow REST API for triggering DAGs
- [Rhino Security Labs - AWS IAM Privilege Escalation Methods](https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation/) -- survey of IAM privilege escalation techniques
