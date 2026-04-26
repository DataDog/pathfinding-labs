# IAM Console Password Creation to Bucket

* **Category:** Privilege Escalation
* **Sub-Category:** credential-access
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** User with iam:CreateLoginProfile can set password for user with S3 bucket access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_bucket_iam_004_iam_createloginprofile`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** iam-004
* **CTF Flag Location:** s3-object
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0009 - Collection
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1530 - Data from Cloud Storage Object

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-004-bucket-starting-user` IAM user to the `pl-sensitive-data-iam-004-{account_id}` S3 bucket by using `iam:CreateLoginProfile` to create a console password for the target user `pl-prod-iam-004-bucket-hop1`, who already has read access to the sensitive bucket.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-004-bucket-starting-user`
- **Destination resource:** `arn:aws:s3:::pl-sensitive-data-iam-004-{account_id}`

### Starting Permissions

**Required** (`pl-prod-iam-004-bucket-starting-user`):
- `iam:CreateLoginProfile` on `arn:aws:iam::*:user/pl-prod-iam-004-bucket-hop1` -- creates a console password for the target user, enabling console login

**Helpful** (`pl-prod-iam-004-bucket-starting-user`):
- `iam:ListUsers` -- discover IAM users and identify candidates without login profiles
- `iam:GetUser` -- view details of individual IAM users
- `iam:GetLoginProfile` -- check whether a user already has a console login profile set

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable iam-004-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-004-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-004-bucket-starting-user` | Scenario-specific starting user with programmatic access and CreateLoginProfile permission |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-004-bucket-hop1` | Target user with S3 bucket access (initially no console password) |
| `pl-prod-iam-004-bucket-starting-user-policy` (inline policy) | Allows `iam:CreateLoginProfile` on `pl-prod-iam-004-bucket-hop1` only |
| `pl-prod-iam-004-bucket-hop1-s3-policy` (inline policy) | Grants S3 read access to sensitive bucket |
| `arn:aws:s3:::pl-sensitive-data-iam-004-{account_id}-{suffix}` | Target S3 bucket containing sensitive data and the CTF flag |
| `arn:aws:s3:::pl-sensitive-data-iam-004-{account_id}-{suffix}/sensitive-data.txt` | Sensitive file in the target bucket |
| `arn:aws:s3:::pl-sensitive-data-iam-004-{account_id}-{suffix}/flag.txt` | CTF flag file in the target bucket |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create a console password for the target user
4. Display console login URL and credentials
5. Verify successful privilege escalation to bucket access
6. Read `flag.txt` from the target bucket and display the CTF flag


#### Resources Created by Attack Script

- Console login profile (password) for `pl-prod-iam-004-bucket-hop1`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-004-iam-createloginprofile
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-004-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-004-iam-createloginprofile
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-004-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable iam-004-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-004-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user `pl-prod-iam-004-bucket-starting-user` has `iam:CreateLoginProfile` permission scoped to another user with S3 data access
- Privilege escalation path exists from starting user to bucket access via login profile creation
- IAM user `pl-prod-iam-004-bucket-hop1` has S3 read access to a sensitive data bucket but no MFA requirement
- No MFA enforcement on users with access to sensitive S3 buckets

#### Prevention Recommendations

- Avoid granting `iam:CreateLoginProfile` permissions on users with sensitive data access (S3, databases, etc.)
- Use resource-based conditions to restrict which users can have login profiles created: `"Condition": {"StringEquals": {"aws:username": "${aws:username}"}}`
- Implement SCPs to prevent login profile creation on users with data access roles
- Enable MFA requirements for users with sensitive data access to mitigate credential compromise
- Use IAM Access Analyzer to identify privilege escalation paths to sensitive resources, not just admin access
- Implement S3 bucket policies that require MFA for object access
- Regularly audit IAM users for unexpected login profiles and console access

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: CreateLoginProfile` -- Console password created for an IAM user; critical when the target user has access to sensitive data
- `S3: GetObject` -- Objects accessed in S3 bucket; high severity when accessed from a newly created console session
- `S3: ListBucket` -- Bucket contents listed; monitor for access from users that typically use only programmatic access

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
