# IAM Managed Role Policy Attachment to Bucket

* **Category:** Privilege Escalation
* **Sub-Category:** self-escalation
* **Path Type:** self-escalation
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Role with iam:AttachRolePolicy on itself can attach policy granting S3 bucket access
* **Terraform Variable:** `enable_single_account_privesc_self_escalation_to_bucket_iam_009_iam_attachrolepolicy`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** iam-009
* **CTF Flag Location:** s3-object
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0009 - Collection
* **MITRE Techniques:** T1098 - Account Manipulation, T1530 - Data from Cloud Storage Object

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-009-to-bucket-starting-role` IAM role to the `pl-prod-iam-009-to-bucket` S3 bucket by using `iam:AttachRolePolicy` to attach a bucket access policy to the role itself, then reading sensitive data from the bucket.

- **Start:** `arn:aws:iam::{account_id}:user/pl-pathfinding-starting-user-prod`
- **Destination resource:** `arn:aws:s3:::pl-prod-iam-009-to-bucket-{account_id}`

### Starting Permissions

**Required** (`pl-pathfinding-starting-user-prod`):
- `iam:AttachRolePolicy` on `arn:aws:iam::*:role/pl-prod-iam-009-to-bucket-starting-role` -- allows the role to attach any managed policy to itself

**Helpful** (`pl-pathfinding-starting-user-prod`):
- `iam:ListAttachedRolePolicies` -- list managed policies already attached to the role
- `iam:ListPolicies` -- discover available managed policies to identify candidate policies to attach
- `s3:ListBucket` -- verify bucket access after escalation

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
plabs enable iam-009-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-009-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-009-to-bucket-starting-user` | Starting user with credentials |
| `arn:aws:iam::{account_id}:role/pl-prod-iam-009-to-bucket-starting-role` | Starting role with AttachRolePolicy permission on itself |
| `arn:aws:iam::{account_id}:policy/pl-prod-iam-009-to-bucket-access-policy` | Grants S3 read/write access to target bucket (to be attached during escalation) |
| `arn:aws:s3:::pl-prod-iam-009-to-bucket-{account_id}-{suffix}` | Target S3 bucket containing sensitive data |
| `arn:aws:s3:::pl-prod-iam-009-to-bucket-{account_id}-{suffix}/sensitive-data.txt` | Sensitive file in the target bucket |
| `arn:aws:s3:::pl-prod-iam-009-to-bucket-{account_id}-{suffix}/flag.txt` | CTF flag in the target bucket |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve starting user credentials from Terraform output
2. Verify identity as the starting user
3. Assume the `pl-prod-iam-009-to-bucket-starting-role`
4. Confirm that S3 bucket access is not available before escalation
5. Attach the bucket access policy to the role using `iam:AttachRolePolicy`
6. Wait 15 seconds for policy propagation
7. Verify S3 bucket access by listing objects
8. Download `sensitive-data.txt` from the target bucket
9. Read `flag.txt` from the target bucket to capture the CTF flag

#### Resources Created by Attack Script

- Managed policy attachment: `pl-prod-iam-009-to-bucket-access-policy` attached to `pl-prod-iam-009-to-bucket-starting-role`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-009-iam-attachrolepolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-009-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-009-iam-attachrolepolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-009-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable iam-009-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-009-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM role `pl-prod-iam-009-to-bucket-starting-role` has `iam:AttachRolePolicy` permission scoped to itself, enabling self-escalation
- A role with `iam:AttachRolePolicy` on its own ARN can attach any managed policy, including high-privilege policies like `AmazonS3FullAccess`
- Privilege escalation path exists: starting user can assume the role and then escalate to gain S3 bucket access
- No SCP or permission boundary prevents the role from attaching additional policies to itself

#### Prevention Recommendations

- Avoid granting `iam:AttachRolePolicy` permissions on other roles
- Use resource-based conditions to restrict which roles can be modified
- Implement SCPs to prevent privilege escalation techniques
- Use IAM Access Analyzer to identify privilege escalation paths
- Restrict attachment of high-privilege AWS-managed policies like `AmazonS3FullAccess`
- Implement S3 bucket policies that restrict access even for privileged roles
- Enable S3 access logging to track data access patterns

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `iam:AttachRolePolicy` -- Managed policy attached to a role; critical when the target role is the same as the calling principal (self-escalation)
- `sts:AssumeRole` -- Role assumption event; look for the starting user assuming the privesc role prior to the policy attachment
- `s3:GetObject` -- Object retrieved from S3 bucket; high severity when preceded by an `AttachRolePolicy` event on the accessing role
- `s3:ListBucket` -- Bucket enumeration; watch for new access patterns following a policy attachment event

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

