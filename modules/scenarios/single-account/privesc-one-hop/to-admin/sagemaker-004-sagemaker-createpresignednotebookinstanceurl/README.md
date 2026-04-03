# Privilege Escalation via sagemaker:CreatePresignedNotebookInstanceUrl

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $37/mo
* **Technique:** User with CreatePresignedNotebookInstanceUrl can generate presigned URL to access existing notebook with admin role and execute commands with elevated privileges
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_sagemaker_004_sagemaker_createpresignednotebookinstanceurl`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** sagemaker-004
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1552 - Unsecured Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-sagemaker-004-to-admin-starting-user` IAM user to the `pl-prod-sagemaker-004-to-admin-notebook-role` administrative role by generating a presigned URL for an existing SageMaker notebook instance and executing AWS CLI commands from its Jupyter terminal with the notebook's admin execution role credentials.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-sagemaker-004-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-sagemaker-004-to-admin-notebook-role`

### Starting Permissions

**Required** (`pl-prod-sagemaker-004-to-admin-starting-user`):
- `sagemaker:CreatePresignedNotebookInstanceUrl` on `arn:aws:sagemaker:*:*:notebook-instance/pl-prod-sagemaker-004-to-admin-notebook` -- generates a presigned URL granting access to the Jupyter interface, which runs as the notebook's admin execution role

**Helpful** (`pl-prod-sagemaker-004-to-admin-starting-user`):
- `sagemaker:ListNotebookInstances` -- discover available notebook instances to target
- `sagemaker:DescribeNotebookInstance` -- view notebook details and verify the admin execution role
- `iam:GetRole` -- verify the notebook's execution role has admin permissions

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_sagemaker_004_sagemaker_createpresignednotebookinstanceurl
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
| `arn:aws:iam::{account_id}:user/pl-prod-sagemaker-004-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:policy/pl-prod-sagemaker-004-to-admin-starting-policy` | Policy granting CreatePresignedNotebookInstanceUrl permission |
| `arn:aws:sagemaker:{region}:{account_id}:notebook-instance/pl-prod-sagemaker-004-to-admin-notebook` | Pre-existing SageMaker notebook instance with admin role |
| `arn:aws:iam::{account_id}:role/pl-prod-sagemaker-004-to-admin-notebook-role` | Admin execution role attached to the notebook instance |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Generate a presigned URL for accessing the notebook
4. Provide instructions for manual browser-based access to the Jupyter interface
5. Demonstrate AWS CLI commands that can be executed from the terminal
6. Verify successful privilege escalation
7. Output standardized test results for automation

**Note**: Due to the browser-based nature of this attack, the demo script will generate the presigned URL and provide instructions, but the actual Jupyter terminal access must be performed manually in a web browser.

#### Resources Created by Attack Script

- Presigned URL for the SageMaker notebook instance (expires after 12 hours)
- `AdministratorAccess` managed policy attached to `pl-prod-sagemaker-004-to-admin-starting-user` (via Jupyter terminal step)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo sagemaker-004-sagemaker-createpresignednotebookinstanceurl
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup sagemaker-004-sagemaker-createpresignednotebookinstanceurl
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_sagemaker_004_sagemaker_createpresignednotebookinstanceurl
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

- **Overly Permissive SageMaker Permissions**: Users or roles with `sagemaker:CreatePresignedNotebookInstanceUrl` on notebook instances with privileged execution roles
- **Admin Roles on SageMaker Resources**: SageMaker notebook instances with execution roles that have administrative permissions
- **Privilege Escalation Path**: A complete path from a low-privileged user to admin access via SageMaker notebook URL generation
- **Missing Resource-Based Conditions**: SageMaker permissions without proper resource restrictions or condition keys
- **Separation of Duties Violation**: Same principals that can generate presigned URLs having access to notebooks with privileged roles

#### Prevention Recommendations

1. **Restrict CreatePresignedNotebookInstanceUrl Permission**: Limit `sagemaker:CreatePresignedNotebookInstanceUrl` to only specific notebook instances that don't have privileged execution roles. Use resource-level permissions:
   ```json
   {
     "Effect": "Allow",
     "Action": "sagemaker:CreatePresignedNotebookInstanceUrl",
     "Resource": "arn:aws:sagemaker:*:*:notebook-instance/non-privileged-*",
     "Condition": {
       "StringEquals": {
         "aws:RequestedRegion": ["us-east-1"]
       }
     }
   }
   ```

2. **Implement Least Privilege for Notebook Execution Roles**: SageMaker notebook instances should use execution roles with minimal permissions required for their specific machine learning tasks. Avoid attaching `AdministratorAccess` or overly broad IAM policies:
   ```json
   {
     "Effect": "Allow",
     "Action": [
       "s3:GetObject",
       "s3:PutObject"
     ],
     "Resource": "arn:aws:s3:::ml-training-data-bucket/*"
   }
   ```

3. **Use Resource Tags and Condition Keys**: Tag SageMaker notebooks by sensitivity level and use IAM conditions to prevent presigned URL generation for high-privilege notebooks:
   ```json
   {
     "Effect": "Deny",
     "Action": "sagemaker:CreatePresignedNotebookInstanceUrl",
     "Resource": "*",
     "Condition": {
       "StringEquals": {
         "aws:ResourceTag/PrivilegeLevel": "high"
       }
     }
   }
   ```

4. **Enable CloudTrail Monitoring**: Monitor for `CreatePresignedNotebookInstanceUrl` API calls, especially from unexpected users or at unusual times. Set up CloudWatch alarms for this event:
   ```json
   {
     "eventName": "CreatePresignedNotebookInstanceUrl",
     "errorCode": null
   }
   ```

5. **Implement Network Isolation**: Use VPC-only SageMaker notebook instances with private subnets and restrict access through security groups. This prevents external attackers from accessing presigned URLs even if they obtain them.

6. **Use Service Control Policies (SCPs)**: At the AWS Organizations level, restrict SageMaker notebook creation and access in production accounts, or require MFA for presigned URL generation:
   ```json
   {
     "Effect": "Deny",
     "Action": "sagemaker:CreatePresignedNotebookInstanceUrl",
     "Resource": "*",
     "Condition": {
       "BoolIfExists": {
         "aws:MultiFactorAuthPresent": "false"
       }
     }
   }
   ```

7. **Regular Access Reviews**: Conduct periodic reviews of who has SageMaker permissions and which notebook instances have privileged execution roles. Use IAM Access Analyzer to identify cross-account or external access risks.

8. **Disable Direct Internet Access**: Configure SageMaker notebooks with `DirectInternetAccess: Disabled` to prevent outbound internet connections from the notebook, limiting the attacker's ability to exfiltrate data or credentials.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `SageMaker: CreatePresignedNotebookInstanceUrl` — Presigned URL generated for a notebook instance; critical when the target notebook has an execution role with elevated permissions
- `SageMaker: DescribeNotebookInstance` — Notebook details retrieved; may indicate reconnaissance to identify notebooks with privileged execution roles
- `SageMaker: ListNotebookInstances` — Enumeration of available notebook instances; commonly precedes presigned URL generation

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
