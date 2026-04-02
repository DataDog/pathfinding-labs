# Privilege Escalation via iam:PassRole + sagemaker:CreateTrainingJob

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Creating SageMaker training job with malicious script and admin role to execute code with elevated privileges
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_sagemaker_002_iam_passrole_sagemaker_createtrainingjob`
* **Schema Version:** 3.0.0
* **Pathfinding.cloud ID:** sagemaker-002
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1098.001 - Account Manipulation: Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-sagemaker-002-to-admin-starting-user` IAM user to the `pl-prod-sagemaker-002-to-admin-passable-role` administrative role by uploading a malicious Python training script to S3 and creating a SageMaker training job that executes that script with the admin role's credentials.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-sagemaker-002-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-sagemaker-002-to-admin-passable-role`

### Starting Permissions

**Required:**
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-sagemaker-002-to-admin-passable-role` -- allows passing the admin execution role to the SageMaker training job
- `sagemaker:CreateTrainingJob` on `*` -- allows creating the training job that executes the malicious script
- `s3:PutObject` on `arn:aws:s3:::pl-prod-sagemaker-002-to-admin-bucket-*/*` -- allows uploading the malicious training script to the bucket
- `s3:GetObject` on `arn:aws:s3:::pl-prod-sagemaker-002-to-admin-bucket-*/*` -- allows reading objects from the training bucket

**Helpful:**
- `iam:ListRoles` -- discover available privileged roles to pass
- `iam:GetRole` -- verify the role has administrative permissions before passing it
- `sagemaker:DescribeTrainingJob` -- monitor training job status and execution progress
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
plabs enable enable_single_account_privesc_one_hop_to_admin_sagemaker_002_iam_passrole_sagemaker_createtrainingjob
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
| `arn:aws:iam::{account_id}:user/pl-prod-sagemaker-002-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-sagemaker-002-to-admin-passable-role` | Admin role that trusts SageMaker service and can be passed to training jobs |
| `arn:aws:s3:::pl-prod-sagemaker-002-to-admin-bucket-{account_id}-{suffix}` | S3 bucket for storing training scripts and outputs |
| Policy attached to starting user | Grants `iam:PassRole` on admin role, `sagemaker:CreateTrainingJob`, and S3 upload/download permissions |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve scenario credentials and configuration from Terraform outputs
2. Verify the starting user identity and confirm it lacks admin permissions
3. Create a malicious Python training script that attaches `AdministratorAccess` to the starting user
4. Package and upload the exploit script to the scenario S3 bucket
5. Create a SageMaker training job passing the admin role and referencing the uploaded script
6. Poll the training job status until it completes (typically 3-5 minutes)
7. Wait for IAM policy propagation and verify administrator access was granted

#### Resources Created by Attack Script

- Malicious Python training script uploaded to the scenario S3 bucket (`sourcedir.tar.gz`)
- SageMaker training job executing with the admin passable role
- `AdministratorAccess` managed policy attached to the starting user

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo sagemaker-002-iam-passrole+sagemaker-createtrainingjob
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup sagemaker-002-iam-passrole+sagemaker-createtrainingjob
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_sagemaker_002_iam_passrole_sagemaker_createtrainingjob
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

- IAM principal has both `iam:PassRole` and `sagemaker:CreateTrainingJob` permissions, enabling privilege escalation via SageMaker training jobs
- Passable role (`pl-prod-sagemaker-002-to-admin-passable-role`) has administrative permissions and trusts the SageMaker service principal
- Starting user has `s3:PutObject` on the training bucket, allowing malicious script injection
- Privilege escalation path exists: starting user can achieve admin access through SageMaker training job execution

#### Prevention Recommendations

- Restrict `iam:PassRole` permissions using strict resource conditions to limit which roles can be passed to SageMaker
- Implement condition keys like `iam:PassedToService` to ensure PassRole is only allowed for specific services: `"Condition": {"StringEquals": {"iam:PassedToService": "sagemaker.amazonaws.com"}}`
- Avoid granting broad `sagemaker:CreateTrainingJob` permissions; use resource tags or naming patterns to control training job creation
- Implement Service Control Policies (SCPs) that prevent passing roles with administrative privileges to SageMaker
- Use IAM Access Analyzer to identify privilege escalation paths involving PassRole to SageMaker
- Restrict S3 bucket permissions to prevent unauthorized script uploads, or implement S3 Object Lambda to scan uploaded training scripts
- Enable AWS Config rules to detect SageMaker training jobs with overly permissive execution roles
- Consider using SageMaker service role boundaries to limit the maximum permissions that can be used by training jobs

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PassRole` -- IAM role passed to SageMaker service; critical when the passed role has administrative permissions
- `SageMaker: CreateTrainingJob` -- New training job created; high severity when the execution role has elevated privileges
- `S3: PutObject` -- Object uploaded to training bucket; suspicious when followed by a CreateTrainingJob event targeting that bucket
- `IAM: CreateAccessKey` -- Access keys created; indicates the training script may have executed privilege escalation actions
- `IAM: AttachUserPolicy` -- Managed policy attached to a user; indicates the training script may have granted elevated permissions
- `IAM: PutUserPolicy` -- Inline policy added to a user; indicates privilege escalation via training job execution

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
