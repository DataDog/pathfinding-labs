# SageMaker Processing Job Creation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** User with PassRole and CreateProcessingJob can create processing job with malicious script and admin role to execute code with elevated privileges
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_sagemaker_003_iam_passrole_sagemaker_createprocessingjob`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** sagemaker-003
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1098.001 - Account Manipulation: Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-sagemaker-003-to-admin-starting-user` IAM user to the `pl-prod-sagemaker-003-to-admin-passable-role` administrative role by uploading a malicious Python script to S3 and creating a SageMaker processing job that executes the script with the admin role's credentials, causing it to attach AdministratorAccess to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-sagemaker-003-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-sagemaker-003-to-admin-passable-role`

### Starting Permissions

**Required** (`pl-prod-sagemaker-003-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-sagemaker-003-to-admin-passable-role` -- allows passing the admin-privileged execution role to SageMaker
- `sagemaker:CreateProcessingJob` on `*` -- allows creating a processing job that runs arbitrary code
- `s3:PutObject` on `arn:aws:s3:::pl-prod-sagemaker-003-to-admin-bucket-*/*` -- allows uploading the malicious script to the staging bucket
- `s3:GetObject` on `arn:aws:s3:::pl-prod-sagemaker-003-to-admin-bucket-*/*` -- allows the processing job to download the script from S3

**Helpful** (`pl-prod-sagemaker-003-to-admin-starting-user`):
- `iam:ListRoles` -- discover available privileged roles to pass
- `iam:GetRole` -- verify the role has administrative permissions before passing it
- `sagemaker:DescribeProcessingJob` -- monitor processing job status and execution
- `s3:ListBucket` -- verify S3 bucket access and list contents

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_sagemaker_003_iam_passrole_sagemaker_createprocessingjob
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
| `arn:aws:iam::{account_id}:user/pl-prod-sagemaker-003-to-admin-starting-user` | Scenario-specific starting user with iam:PassRole and sagemaker:CreateProcessingJob permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-sagemaker-003-to-admin-passable-role` | Admin role with AdministratorAccess that trusts sagemaker.amazonaws.com service |
| `arn:aws:s3:::pl-prod-sagemaker-003-to-admin-bucket-{account_id}-{suffix}` | S3 bucket for storing the malicious processing script and job outputs |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve scenario credentials and configuration from Terraform outputs
2. Verify the starting user identity and confirm no admin access exists yet
3. Create a malicious Python processing script (`exploit.py`) that attaches AdministratorAccess to the starting user
4. Upload the malicious script to the S3 staging bucket
5. Create a SageMaker processing job referencing the admin-privileged execution role and the uploaded script
6. Wait (up to 10 minutes) for the processing job to reach `Completed` status
7. Verify that AdministratorAccess is now attached to the starting user

#### Resources Created by Attack Script

- SageMaker processing job (`pl-demo-processing-{timestamp}`) that executes the malicious script
- S3 object at `s3://pl-prod-sagemaker-003-to-admin-bucket-{account_id}-{suffix}/scripts/exploit.py`
- `AdministratorAccess` managed policy attachment on `pl-prod-sagemaker-003-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo sagemaker-003-iam-passrole+sagemaker-createprocessingjob
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup sagemaker-003-iam-passrole+sagemaker-createprocessingjob
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_sagemaker_003_iam_passrole_sagemaker_createprocessingjob
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

- IAM user has `iam:PassRole` permission granting the ability to pass a role with administrative privileges to SageMaker
- IAM user has `sagemaker:CreateProcessingJob` permission combined with `iam:PassRole`, creating a privilege escalation path
- Role `pl-prod-sagemaker-003-to-admin-passable-role` has `AdministratorAccess` and trusts `sagemaker.amazonaws.com`, making it passable for unrestricted code execution
- Privilege escalation path exists: starting user can execute arbitrary code with admin-level permissions via SageMaker processing jobs

#### Prevention Recommendations

- Implement least privilege principles - avoid granting `iam:PassRole` and `sagemaker:CreateProcessingJob` together unless absolutely necessary for legitimate ML workflows
- Use resource-based conditions on `iam:PassRole` to restrict which roles can be passed: `"Condition": {"StringEquals": {"iam:PassedToService": "sagemaker.amazonaws.com"}}`
- Add condition keys to prevent passing highly privileged roles: `"Condition": {"StringNotLike": {"iam:PassedToService": "*admin*"}}`
- Implement Service Control Policies (SCPs) at the organization level to restrict PassRole permissions on administrative roles
- Use IAM Access Analyzer to identify and remediate privilege escalation paths involving PassRole to SageMaker services
- Implement VPC configurations for SageMaker processing jobs to restrict network access and prevent data exfiltration
- Enable AWS Config rules to detect SageMaker processing jobs using overly permissive execution roles
- Audit existing SageMaker execution roles regularly to ensure they follow least privilege principles

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PassRole` -- IAM role passed to SageMaker service; critical when the passed role has administrative permissions
- `SageMaker: CreateProcessingJob` -- SageMaker processing job created; high severity when the execution role has elevated permissions
- `IAM: AttachUserPolicy` -- Managed policy attached to IAM user; critical when the policy is AdministratorAccess
- `IAM: PutUserPolicy` -- Inline policy added to IAM user; investigate if policy grants broad permissions
- `IAM: CreateAccessKey` -- New access keys created for an IAM user; critical when the target has elevated permissions

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
