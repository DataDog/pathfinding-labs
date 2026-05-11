# SageMaker Notebook Lifecycle Config Update to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $37/mo
* **Cost Estimate When Demo Executed:** $37/mo
* **Technique:** User with SageMaker update permissions can inject malicious lifecycle config into existing notebook to execute code with notebook's admin role
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_sagemaker_005_sagemaker_updatenotebook_lifecycle_config`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** sagemaker-005
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1525 - Implant Internal Image

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-sagemaker-005-to-admin-starting-user` IAM user to the `pl-prod-sagemaker-005-to-admin-notebook-role` administrative role by injecting a malicious lifecycle configuration script into the `pl-prod-sagemaker-005-to-admin-notebook` SageMaker notebook instance, causing it to execute arbitrary code with admin credentials upon startup.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-sagemaker-005-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-sagemaker-005-to-admin-notebook-role`

### Starting Permissions

**Required** (`pl-prod-sagemaker-005-to-admin-starting-user`):
- `sagemaker:CreateNotebookInstanceLifecycleConfig` on `*` -- create the malicious lifecycle config
- `sagemaker:StopNotebookInstance` on `arn:aws:sagemaker:*:*:notebook-instance/pl-prod-sagemaker-005-to-admin-notebook` -- stop the notebook so its config can be modified
- `sagemaker:UpdateNotebookInstance` on `arn:aws:sagemaker:*:*:notebook-instance/pl-prod-sagemaker-005-to-admin-notebook` -- attach the malicious lifecycle config
- `sagemaker:StartNotebookInstance` on `arn:aws:sagemaker:*:*:notebook-instance/pl-prod-sagemaker-005-to-admin-notebook` -- trigger lifecycle script execution

**Helpful** (`pl-prod-sagemaker-005-to-admin-starting-user`):
- `sagemaker:DescribeNotebookInstance` -- view notebook details, status, and attached execution role
- `sagemaker:ListNotebookInstances` -- discover available notebook instances to target
- `iam:GetRole` -- verify the notebook's execution role has admin permissions

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
plabs enable sagemaker-005-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `sagemaker-005-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-sagemaker-005-to-admin-starting-user` | Scenario-specific starting user with access keys and SageMaker management permissions |
| `arn:aws:sagemaker:{region}:{account_id}:notebook-instance/pl-prod-sagemaker-005-to-admin-notebook` | SageMaker notebook instance running ml.t3.medium with admin execution role |
| `arn:aws:iam::{account_id}:role/pl-prod-sagemaker-005-to-admin-notebook-role` | Notebook execution role with AdministratorAccess policy attached |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/sagemaker-005-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Stop the notebook instance and wait for it to stop
4. Create a malicious lifecycle configuration with a privilege escalation script
5. Update the notebook to use the malicious lifecycle configuration
6. Start the notebook and wait for the lifecycle script to execute
7. Verify successful privilege escalation to administrator access
8. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions


**Note**: The demo includes wait times for the notebook to stop (~5 minutes) and start (~5-7 minutes), as SageMaker notebook state transitions take several minutes to complete.

#### Resources Created by Attack Script

- Malicious SageMaker notebook lifecycle configuration (`AdministratorAccess` policy attachment script)
- `AdministratorAccess` managed policy attached to `pl-prod-sagemaker-005-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo sagemaker-005-sagemaker-updatenotebook-lifecycle-config
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `sagemaker-005-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup sagemaker-005-sagemaker-updatenotebook-lifecycle-config
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `sagemaker-005-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable sagemaker-005-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `sagemaker-005-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- **High-Risk Execution Roles**: SageMaker notebook instances configured with highly privileged execution roles (especially AdministratorAccess or similar broad permissions)
- **Broad SageMaker Permissions**: IAM principals with permissions to update notebook instance configurations, particularly when combined with CreateLifecycleConfig permissions
- **Lifecycle Configuration Changes**: Changes to notebook instance lifecycle configurations, especially when performed by non-administrative users
- **Privilege Escalation Path**: Direct privilege escalation path from SageMaker update permissions to administrative access through notebook execution roles
- **Overprivileged ML Infrastructure**: Machine learning infrastructure components running with permissions exceeding their operational requirements

#### Prevention Recommendations

- **Principle of Least Privilege for Execution Roles**: Never grant SageMaker notebook execution roles administrative access. Scope execution roles to only the specific S3 buckets, data sources, and AWS services required for data science workloads
- **Restrict SageMaker Management Permissions**: Limit `sagemaker:UpdateNotebookInstance` and `sagemaker:CreateNotebookInstanceLifecycleConfig` permissions to infrastructure administrators only, not data science users
- **Implement Resource-Based Conditions**: Use IAM condition keys to restrict lifecycle configuration changes: `"Condition": {"StringNotLike": {"sagemaker:LifecycleConfigName": ["approved-config-*"]}}`
- **Require Approval Workflows**: Implement approval workflows for notebook configuration changes using AWS Service Catalog or custom automation
- **Use SCPs for Guardrails**: Implement Service Control Policies to prevent creation of SageMaker execution roles with administrative permissions
- **Enable IMDSv2**: Configure notebook instances to require IMDSv2 to add an additional layer of credential security
- **Audit Existing Notebooks**: Regularly audit all SageMaker notebook instances for overprivileged execution roles and unnecessary lifecycle configurations
- **Segregate Permissions**: Use separate IAM roles for notebook creation (infrastructure team) and notebook usage (data science team)

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `sagemaker:StopNotebookInstance` -- Notebook instance stopped; when followed by lifecycle config changes, indicates potential injection setup
- `sagemaker:CreateNotebookInstanceLifecycleConfig` -- New lifecycle configuration created; high severity when performed by non-infrastructure users
- `sagemaker:UpdateNotebookInstance` -- Notebook instance configuration modified; critical when lifecycle config attachment is changed
- `sagemaker:StartNotebookInstance` -- Notebook instance started; the lifecycle script executes here with the notebook's execution role credentials
- `iam:AttachUserPolicy` -- Policy attached to a user; watch for AdministratorAccess attachments originating from a SageMaker execution role

Monitor for the specific API call sequence: `StopNotebookInstance` → `CreateNotebookInstanceLifecycleConfig` → `UpdateNotebookInstance` → `StartNotebookInstance` as this pattern indicates potential exploitation.

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

