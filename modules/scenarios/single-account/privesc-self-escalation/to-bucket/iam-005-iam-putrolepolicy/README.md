# Self-Escalation to Bucket: iam:PutRolePolicy

* **Category:** Privilege Escalation
* **Sub-Category:** self-escalation
* **Path Type:** self-escalation
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Role with iam:PutRolePolicy on itself can add inline policy granting S3 bucket access
* **Terraform Variable:** `enable_single_account_privesc_self_escalation_to_bucket_iam_005_iam_putrolepolicy`
* **Schema Version:** 3.0.0
* **Pathfinding.cloud ID:** iam-005
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0009 - Collection
* **MITRE Techniques:** T1098 - Account Manipulation, T1530 - Data from Cloud Storage Object

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-005-to-bucket-starting-user` IAM user to the sensitive S3 bucket `pl-prod-iam-005-to-bucket-{account_id}` by assuming the `pl-prod-iam-005-to-bucket-starting-role`, using `iam:PutRolePolicy` to add an inline policy granting S3 access to itself, and then reading sensitive data directly from the bucket.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-005-to-bucket-starting-user`
- **Destination resource:** `arn:aws:s3:::pl-prod-iam-005-to-bucket-{account_id}`

### Starting Permissions

**Required:**
- `iam:PutRolePolicy` on `arn:aws:iam::*:role/pl-prod-iam-005-to-bucket-starting-role` -- allows the role to write an inline policy to itself, granting S3 bucket access

**Helpful:**
- `iam:GetRolePolicy` -- view existing inline policies on the role
- `iam:ListRolePolicies` -- list all inline policies attached to the role
- `s3:ListBucket` -- verify bucket access after escalation

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_self_escalation_to_bucket_iam_005_iam_putrolepolicy
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
| `arn:aws:iam::{account_id}:user/pl-prod-iam-005-to-bucket-starting-user` | Starting user with AssumeRole permission |
| `arn:aws:iam::{account_id}:role/pl-prod-iam-005-to-bucket-starting-role` | Starting role with PutRolePolicy permission on itself |
| `arn:aws:iam::{account_id}:role/pl-prod-iam-005-to-bucket-target-role` | Target role with S3 bucket permissions |
| `arn:aws:iam::{account_id}:policy/pl-prod-iam-005-to-bucket-access-policy` | Grants S3 read/write access to target bucket |
| `arn:aws:s3:::pl-prod-iam-005-to-bucket-{account_id}-{suffix}` | Target S3 bucket containing sensitive data |
| `arn:aws:s3:::pl-prod-iam-005-to-bucket-{account_id}-{suffix}/sensitive-data.txt` | Sensitive file in the target bucket |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve starting user credentials from Terraform output
2. Assume the `pl-prod-iam-005-to-bucket-starting-role`
3. Verify that S3 bucket access is denied before escalation
4. Use `iam:PutRolePolicy` to add an inline S3 access policy to the starting role (self-escalation)
5. Wait 15 seconds for IAM policy propagation
6. List the target S3 bucket contents to confirm access
7. Download `sensitive-data.txt` from the target bucket

#### Resources Created by Attack Script

- Inline IAM policy `EscalatedS3Access` added to `pl-prod-iam-005-to-bucket-starting-role` granting `s3:ListBucket`, `s3:GetObject`, and `s3:PutObject` on the target bucket

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-005-iam-putrolepolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-005-iam-putrolepolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_self_escalation_to_bucket_iam_005_iam_putrolepolicy
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

- IAM role (`pl-prod-iam-005-to-bucket-starting-role`) has `iam:PutRolePolicy` permission scoped to itself, enabling self-escalation
- Privilege escalation path exists: starting role can modify its own inline policy to gain S3 bucket access
- Role chain allows indirect access to sensitive S3 bucket via intermediate role assumption

#### Prevention Recommendations

- Avoid granting `iam:PutRolePolicy` permissions on roles (especially on self)
- Use resource-based conditions to restrict which roles can be modified
- Implement SCPs to prevent privilege escalation techniques
- Monitor CloudTrail for `PutRolePolicy` API calls on the same role followed by `AssumeRole` and S3 access
- Enable MFA requirements for sensitive operations
- Use IAM Access Analyzer to identify privilege escalation paths
- Implement S3 bucket policies that restrict access even for privileged roles
- Enable S3 access logging to track data access patterns

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PutRolePolicy` -- inline policy added to a role; critical when the target role is the same as the calling principal (self-escalation)
- `STS: AssumeRole` -- role assumption event; watch for the starting role assuming the target role after a PutRolePolicy call
- `S3: GetObject` -- object retrieved from S3 bucket; monitor for access by roles that recently had inline policies added

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

