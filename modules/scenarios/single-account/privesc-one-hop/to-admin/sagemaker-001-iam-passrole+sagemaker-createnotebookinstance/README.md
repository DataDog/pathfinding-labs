# SageMaker Notebook Instance Creation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** User with PassRole and CreateNotebookInstance can create notebook with admin role, then access via presigned URL to execute commands with elevated privileges
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_sagemaker_001_iam_passrole_sagemaker_createnotebookinstance`
* **Schema Version:** 4.1.1
* **Pathfinding.cloud ID:** sagemaker-001
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1098.001 - Account Manipulation: Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-sagemaker-001-to-admin-starting-user` IAM user to the `pl-prod-sagemaker-001-to-admin-passable-role` administrative role by passing the admin role to a new SageMaker notebook instance, accessing the Jupyter terminal via a presigned URL, and executing AWS CLI commands with the notebook's elevated execution role credentials.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-sagemaker-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-sagemaker-001-to-admin-passable-role`

### Starting Permissions

**Required** (`pl-prod-sagemaker-001-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-sagemaker-001-to-admin-passable-role` -- pass the admin role to a SageMaker notebook instance
- `sagemaker:CreateNotebookInstance` on `*` -- create a notebook instance that assumes the passed role

**Helpful** (`pl-prod-sagemaker-001-to-admin-starting-user`):
- `iam:ListRoles` -- discover available privileged roles to pass
- `iam:GetRole` -- verify a role has administrative permissions before passing it
- `sagemaker:CreatePresignedNotebookInstanceUrl` -- generate a presigned URL for notebook access (can also access directly via console)
- `sagemaker:DescribeNotebookInstance` -- check notebook status and wait for InService state
- `sagemaker:ListNotebookInstances` -- verify the notebook was created successfully
- `sts:GetCallerIdentity` -- verify current identity and retrieve the account ID

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable sagemaker-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `sagemaker-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-sagemaker-001-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-sagemaker-001-to-admin-passable-role` | Admin role that can be passed to SageMaker notebook instances (trusted by sagemaker.amazonaws.com) |
| Policy attached to starting user | Grants `iam:PassRole` on passable role, `sagemaker:CreateNotebookInstance`, and `sagemaker:CreatePresignedNotebookInstanceUrl` |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create a SageMaker notebook instance with an admin execution role
4. Wait for the instance to become available (this may take 5-8 minutes)
5. Generate a presigned URL for accessing the notebook
6. Display instructions for accessing the Jupyter terminal and executing commands
7. Verify successful privilege escalation
8. Output standardized test results for automation

**Note**: The notebook instance will incur costs (~$0.05/hour for ml.t3.medium instance type). The cleanup script should be run promptly after testing.

#### Resources Created by Attack Script

- SageMaker notebook instance (`pl-demo-notebook-{timestamp}`) with the admin execution role attached
- `AdministratorAccess` managed policy attached to `pl-prod-sagemaker-001-to-admin-starting-user`
- Presigned URL for Jupyter notebook access (temporary, expires after a short period)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo sagemaker-001-iam-passrole+sagemaker-createnotebookinstance
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `sagemaker-001-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup sagemaker-001-iam-passrole+sagemaker-createnotebookinstance
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `sagemaker-001-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable sagemaker-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `sagemaker-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM principal has `iam:PassRole` permission scoped broadly enough to pass a role with administrative permissions to SageMaker
- IAM principal has `sagemaker:CreateNotebookInstance` permission, enabling creation of notebook instances with arbitrary execution roles
- IAM principal has both `iam:PassRole` and `sagemaker:CreateNotebookInstance`, creating a privilege escalation path
- SageMaker execution role (`pl-prod-sagemaker-001-to-admin-passable-role`) has `AdministratorAccess` or equivalent admin-level policy attached
- No SCP or permission boundary prevents passing privileged roles to `sagemaker.amazonaws.com`

#### Prevention Recommendations

- Restrict `iam:PassRole` permissions using strict resource conditions to limit which roles can be passed to SageMaker: `"Condition": {"StringEquals": {"iam:PassedToService": "sagemaker.amazonaws.com"}}`
- Implement naming patterns or resource tags to restrict which roles can be used as SageMaker execution roles
- Avoid granting `sagemaker:CreateNotebookInstance` to users who don't require machine learning capabilities
- Use resource-based conditions to restrict notebook instance creation to specific VPCs or subnets: `"Condition": {"StringEquals": {"sagemaker:VpcSubnets": ["subnet-specific-id"]}}`
- Implement Service Control Policies (SCPs) that prevent passing roles with `AdministratorAccess` or sensitive permissions to SageMaker
- Enable AWS Config rules to detect SageMaker notebook instances with overly permissive execution roles
- Use IAM Access Analyzer to identify privilege escalation paths involving `iam:PassRole` and SageMaker services
- Consider requiring direct internet access to be disabled for notebook instances: `"Condition": {"StringEquals": {"sagemaker:DirectInternetAccess": "Disabled"}}`
- Require MFA for sensitive operations like creating notebook instances with privileged roles
- Implement VPC restrictions to limit network access from notebook instances to sensitive resources
- Use AWS Organizations SCPs to prevent SageMaker usage in accounts where machine learning is not a business requirement

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `SageMaker: CreateNotebookInstance` -- new notebook instance created; high severity when the execution role has elevated privileges; the `roleArn` field in the event identifies which role was passed
- `SageMaker: CreatePresignedNotebookInstanceUrl` -- presigned URL generated for notebook access; indicates imminent interactive access to the notebook environment
- `SageMaker: DescribeNotebookInstance` -- notebook instance status queried; often seen while attacker polls for InService state

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

