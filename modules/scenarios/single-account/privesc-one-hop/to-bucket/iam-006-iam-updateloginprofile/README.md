# IAM Console Password Update to Bucket

* **Category:** Privilege Escalation
* **Sub-Category:** credential-access
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** User with iam:UpdateLoginProfile can reset password for user with S3 bucket access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_bucket_iam_006_iam_updateloginprofile`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** iam-006
* **CTF Flag Location:** s3-object
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0009 - Collection
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1530 - Data from Cloud Storage Object

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-006-to-bucket-starting-user` IAM user to the `pl-prod-iam-006-to-bucket-sensitive-data-{account_id}` S3 bucket by resetting the console password for `pl-prod-iam-006-to-bucket-user` and logging into the AWS Management Console as that user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-006-to-bucket-starting-user`
- **Destination resource:** `arn:aws:s3:::pl-prod-iam-006-to-bucket-sensitive-data-{account_id}`

### Starting Permissions

**Required** (`pl-prod-iam-006-to-bucket-starting-user`):
- `iam:UpdateLoginProfile` on `arn:aws:iam::*:user/pl-prod-iam-006-to-bucket-user` -- allows resetting the console password for the target user

**Helpful** (`pl-prod-iam-006-to-bucket-starting-user`):
- `iam:ListUsers` -- discover users with login profiles
- `iam:GetUser` -- view user details
- `iam:GetLoginProfile` -- verify the target user has an existing login profile

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable iam-006-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-006-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-006-to-bucket-starting-user` | Scenario-specific starting user with access keys and UpdateLoginProfile permission |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-006-to-bucket-user` | Target user with S3 bucket access and console login enabled |
| `arn:aws:iam::{account_id}:policy/pl-prod-iam-006-to-bucket-policy` | Allows `iam:UpdateLoginProfile` on `pl-prod-iam-006-to-bucket-user` only |
| `arn:aws:s3:::pl-prod-iam-006-to-bucket-sensitive-data-{account_id}-{suffix}` | Target S3 bucket containing sensitive data and the CTF flag (`flag.txt`) |
| `arn:aws:s3:::pl-prod-iam-006-to-bucket-sensitive-data-{account_id}-{suffix}/sensitive-data.txt` | Sensitive file in the target bucket |
| `arn:aws:s3:::pl-prod-iam-006-to-bucket-sensitive-data-{account_id}-{suffix}/flag.txt` | CTF flag stored as an S3 object; retrieved after gaining bucket access as the target user |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Extract starting user credentials from Terraform outputs
2. Verify identity as `pl-prod-iam-006-to-bucket-starting-user`
3. Confirm that `pl-prod-iam-006-to-bucket-user` has an existing login profile
4. Verify that the starting user cannot access the target S3 bucket
5. Reset the console password for `pl-prod-iam-006-to-bucket-user` using `iam:UpdateLoginProfile`
6. Display the console login URL and new credentials for verification
7. Read `flag.txt` from the target bucket to capture the CTF flag

#### Resources Created by Attack Script

- Updated console login profile password for `pl-prod-iam-006-to-bucket-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-006-iam-updateloginprofile
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-006-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-006-iam-updateloginprofile
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-006-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable iam-006-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-006-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user `pl-prod-iam-006-to-bucket-starting-user` has `iam:UpdateLoginProfile` permission on `pl-prod-iam-006-to-bucket-user`, enabling console credential takeover
- `pl-prod-iam-006-to-bucket-user` has S3 read permissions on a sensitive data bucket, making it a high-value target for credential takeover
- Privilege escalation path exists: starting user can reset another user's console password to gain S3 bucket access

#### Prevention Recommendations

- Avoid granting `iam:UpdateLoginProfile` permissions on users with sensitive data access (S3, databases, etc.)
- Use resource-based conditions to restrict which users can have login profiles updated: `"Condition": {"StringEquals": {"aws:username": "${aws:username}"}}`
- Implement SCPs to prevent login profile updates on users with data access roles
- Monitor CloudTrail for `UpdateLoginProfile` API calls, especially on users with S3 permissions
- Enable MFA requirements for users with sensitive data access
- Use IAM Access Analyzer to identify privilege escalation paths to sensitive resources, not just admin access
- Implement S3 bucket policies that require MFA for object access
- Enable S3 access logging and CloudTrail data events to track data access patterns
- Consider using AWS Secrets Manager or Parameter Store instead of long-lived IAM user credentials
- Regularly review and rotate console passwords for users with data access

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: UpdateLoginProfile` -- Console password reset for an IAM user; critical when the target user has S3 bucket access permissions
- `S3: GetObject` -- Object retrieval from S3; high severity when preceded by a login profile update on the accessing user
- `S3: ListBucket` -- Bucket enumeration; monitor for access following a login profile change event

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
