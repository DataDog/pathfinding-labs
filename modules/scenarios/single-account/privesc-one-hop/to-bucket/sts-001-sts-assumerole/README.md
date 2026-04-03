# One-Hop Privilege Escalation: sts:AssumeRole

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** User with sts:AssumeRole can directly assume role with S3 bucket access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_bucket_sts_001_sts_assumerole`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** sts-001
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0009 - Collection
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1530 - Data from Cloud Storage Object

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-sts-001-to-bucket-starting-user` IAM user to the `pl-prod-sts-001-to-bucket-{account_id}` S3 bucket by directly assuming the `pl-prod-sts-001-to-bucket-access-role` IAM role, which grants read and write access to the sensitive bucket.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-sts-001-to-bucket-starting-user`
- **Destination resource:** `arn:aws:s3:::pl-prod-sts-001-to-bucket-{account_id}`

### Starting Permissions

**Required** (`pl-prod-sts-001-to-bucket-starting-user`):
- `sts:AssumeRole` on `arn:aws:iam::{account_id}:role/pl-prod-sts-001-to-bucket-access-role` -- allows the starting user to assume the bucket access role directly

**Helpful** (`pl-prod-sts-001-to-bucket-starting-user`):
- `iam:ListRoles` -- discover available roles to assume
- `iam:GetRole` -- view role permissions and trust policy
- `s3:ListBucket` -- verify S3 access after role assumption

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_bucket_sts_001_sts_assumerole
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
| `arn:aws:iam::{account_id}:user/pl-prod-sts-001-to-bucket-starting-user` | Starting IAM user with sts:AssumeRole permission |
| `arn:aws:iam::{account_id}:role/pl-prod-sts-001-to-bucket-access-role` | Role with S3 bucket access permissions |
| `arn:aws:s3:::pl-prod-sts-001-to-bucket-{account_id}-{suffix}` | Target S3 bucket containing sensitive data |
| `arn:aws:s3:::pl-prod-sts-001-to-bucket-{account_id}-{suffix}/sensitive-data.txt` | Sensitive file in the target bucket |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve starting user credentials from Terraform outputs
2. Verify the starting user identity and confirm limited initial permissions (cannot list S3 buckets)
3. Assume `pl-prod-sts-001-to-bucket-access-role` using `sts:AssumeRole`
4. List the contents of the target sensitive S3 bucket
5. Download `sensitive-data.txt` from the bucket
6. Upload a test file to the bucket to confirm write access
7. Output standardized test results for automation

#### Resources Created by Attack Script

- Temporary AWS credentials (session token) obtained via `sts:AssumeRole` for `pl-prod-sts-001-to-bucket-access-role`
- `/tmp/sensitive-data-{account_id}.txt` -- downloaded copy of the sensitive bucket object
- `s3://pl-prod-sts-001-to-bucket-{account_id}-{suffix}/demo-test-file.txt` -- test file written to the bucket during the demo

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo sts-001-sts-assumerole
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup sts-001-sts-assumerole
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_bucket_sts_001_sts_assumerole
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

- IAM user `pl-prod-sts-001-to-bucket-starting-user` has `sts:AssumeRole` permission allowing it to assume `pl-prod-sts-001-to-bucket-access-role`, which grants access to a sensitive S3 bucket
- Privilege escalation path detected: starting user can reach sensitive S3 data via role assumption
- Role trust policy on `pl-prod-sts-001-to-bucket-access-role` permits assumption by a low-privilege user principal
- Sensitive S3 bucket accessible to principals reachable via role assumption chains

#### Prevention Recommendations

- Avoid granting `sts:AssumeRole` permissions to roles with access to sensitive resources
- Use resource-based conditions to restrict which principals can assume sensitive roles
- Implement SCPs to enforce least-privilege access patterns
- Enable MFA requirements for assuming roles with access to sensitive data
- Use IAM Access Analyzer to identify privilege escalation paths
- Implement S3 bucket policies that restrict access even for assumed roles
- Enable S3 access logging to track data access patterns

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `STS: AssumeRole` -- Role assumption by the starting user; critical when the assumed role has access to sensitive S3 resources
- `S3: GetObject` -- Object download from the sensitive bucket; high severity when performed under a newly assumed role session
- `S3: ListBucket` -- Bucket enumeration; watch for listing activity immediately following a role assumption event

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
