# One-Hop Privilege Escalation: iam:CreateAccessKey

* **Category:** Privilege Escalation
* **Sub-Category:** credential-access
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** User with iam:CreateAccessKey can create credentials for user with S3 bucket access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_bucket_iam_002_iam_createaccesskey`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** iam-002
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0009 - Collection
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1530 - Data from Cloud Storage Object

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-002-to-bucket-privesc-user` IAM user to the `pl-prod-iam-002-to-bucket-access-user` IAM user (and subsequently the `pl-prod-iam-002-to-bucket` S3 bucket) by creating new IAM access keys for the bucket access user and using those credentials to read sensitive data from the target bucket.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-002-to-bucket-privesc-user`
- **Destination resource:** `arn:aws:s3:::pl-prod-iam-002-to-bucket-{account_id}`

### Starting Permissions

**Required** (`pl-prod-iam-002-to-bucket-privesc-user`):
- `iam:CreateAccessKey` on `arn:aws:iam::*:user/pl-prod-iam-002-to-bucket-access-user` -- create new credentials for the bucket access user

**Helpful** (`pl-prod-iam-002-to-bucket-privesc-user`):
- `iam:ListUsers` -- discover users with S3 access
- `iam:GetUserPolicy` -- view a user's inline policies
- `iam:ListAttachedUserPolicies` -- identify users with S3 permissions

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_bucket_iam_002_iam_createaccesskey
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
| `arn:aws:iam::{account_id}:user/pl-prod-iam-002-to-bucket-privesc-user` | Starting principal with CreateAccessKey permission |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-002-to-bucket-access-user` | Destination principal with S3 bucket access |
| `arn:aws:s3:::pl-prod-iam-002-to-bucket-{account_id}-{suffix}` | Target S3 bucket containing sensitive data |
| `arn:aws:s3:::pl-prod-iam-002-to-bucket-{account_id}-{suffix}/sensitive-data.txt` | Sensitive file in the target bucket |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve the privesc user credentials from Terraform outputs
2. Verify identity as `pl-prod-iam-002-to-bucket-privesc-user`
3. Confirm the starting user lacks direct S3 access
4. Create new IAM access keys for `pl-prod-iam-002-to-bucket-access-user`
5. Switch context to the newly created credentials
6. Discover the target S3 bucket
7. List bucket contents and download the sensitive data file

#### Resources Created by Attack Script

- New IAM access key for `pl-prod-iam-002-to-bucket-access-user`
- Downloaded file at `/tmp/createaccesskey-bucket-sensitive-data-{account_id}.txt`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-002-iam-createaccesskey
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-002-iam-createaccesskey
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_bucket_iam_002_iam_createaccesskey
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

- IAM user (`pl-prod-iam-002-to-bucket-privesc-user`) has `iam:CreateAccessKey` permission on another user with S3 bucket access
- Privilege escalation path: starting user can obtain credentials for a user with S3 read/write permissions
- No resource-based condition restricts which users can have access keys created on their behalf

#### Prevention Recommendations

- Avoid granting `iam:CreateAccessKey` permissions on privileged users
- Use resource-based conditions to restrict which users can have keys created
- Implement SCPs to prevent access key creation on privileged users
- Monitor CloudTrail for `CreateAccessKey` API calls on privileged accounts
- Enable MFA requirements for sensitive operations
- Use IAM Access Analyzer to identify privilege escalation paths
- Implement S3 bucket policies that restrict access even for privileged users
- Enable S3 access logging to track data access patterns

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: CreateAccessKey` -- New access keys created for an IAM user; critical when the target user has S3 bucket access permissions
- `S3: GetObject` -- Object retrieved from S3 bucket; high severity when accessed using newly created credentials
- `S3: PutObject` -- Object written to S3 bucket; high severity when performed with freshly minted access keys
- `STS: GetCallerIdentity` -- Identity verification call; commonly seen at the start of an attack after credential theft

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

