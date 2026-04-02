# S3 Bucket Access Through Resource Policy

* **Category:** Privilege Escalation
* **Sub-Category:** principal-access
* **Path Type:** multi-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Bypass S3 bucket resource policy restrictions by assuming role with bucket access
* **Terraform Variable:** `enable_tool_testing_resource_policy_bypass`
* **Schema Version:** 3.0.0
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0005 - Defense Evasion, TA0009 - Collection
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1530 - Data from Cloud Storage Object

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-pathfinding-starting-user-prod` IAM user to the `pl-sensitive-data-bucket-{account_id}` S3 bucket by assuming the `pl-bucket-access-role` IAM role, which has only `s3:ListAllMyBuckets` in its IAM identity policy but is explicitly granted full object access by the bucket's resource policy.

- **Start:** `arn:aws:iam::{account_id}:user/pl-pathfinding-starting-user-prod`
- **Destination resource:** `arn:aws:s3:::pl-sensitive-data-bucket-{account_id}`

### Starting Permissions

**Required:**
- `sts:AssumeRole` on `arn:aws:iam::*:role/pl-bucket-access-role` -- allows the starting user to assume the role that the bucket's resource policy grants access to

**Helpful:**
- `iam:ListRoles` -- discover roles with bucket access
- `s3:GetBucketPolicy` -- view bucket resource policy restrictions
- `iam:GetRole` -- view role permissions

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_tool_testing_resource_policy_bypass
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
|-----|---------|
| `arn:aws:iam::{account_id}:role/pl-bucket-access-role` | Role that trusts the prod starting user; has only `s3:ListAllMyBuckets` in its IAM policy |
| `arn:aws:s3:::pl-sensitive-data-bucket-{account_id}` | Sensitive S3 bucket with resource policy granting the bucket access role full object access |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:

1. Retrieve credentials from Terraform outputs for the starting user
2. Verify the current identity and confirm permissions are limited
3. Assume the `pl-bucket-access-role` using `sts:AssumeRole`
4. Confirm the assumed role has only `s3:ListAllMyBuckets` in its IAM identity policy
5. Use `s3:ListAllMyBuckets` to discover the sensitive bucket
6. Access the sensitive bucket via its resource policy (listing objects, reading files)
7. Test write access by uploading and then removing a test file

#### Resources Created by Attack Script

- Temporary AWS STS session credentials for `pl-bucket-access-role`
- Transient test file uploaded to `pl-sensitive-data-bucket-{account_id}` (cleaned up by script)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo resource-policy-bypass
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup resource-policy-bypass
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_tool_testing_resource_policy_bypass
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

- S3 bucket resource policy grants access to an IAM role that has `s3:ListAllMyBuckets` on `*`, creating a path from that role to sensitive bucket data
- IAM role (`pl-bucket-access-role`) is assumable by a low-privilege starting user and is explicitly named in an S3 bucket resource policy granting broad object permissions (`s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`)
- Resource policy on `pl-sensitive-data-bucket` permits full object access without requiring any corresponding IAM identity policy permission on the bucket, meaning any entity that can assume the role gains data access regardless of their IAM policies
- Discovery through `s3:ListAllMyBuckets` enables the role to enumerate bucket names, compounding the data exposure risk

#### Prevention Recommendations

- **Principle of Least Privilege**: Avoid granting `s3:ListAllMyBuckets` unless absolutely necessary; scope bucket list permissions to specific buckets where possible
- **Resource Policy Auditing**: Regularly audit S3 bucket resource policies to ensure that every principal explicitly named has a legitimate business need for that level of access
- **Access Logging**: Enable S3 server access logging and CloudTrail data events on sensitive buckets to monitor for unexpected access patterns
- **Conditional Policies**: Use `aws:PrincipalTag` or `aws:ResourceTag` conditions in resource policies to restrict access to tagged/approved principals rather than static ARNs
- **Regular Cross-Reference Reviews**: Periodically cross-reference which IAM roles are named in bucket resource policies against which users or roles can assume those roles transitively
- **Monitoring**: Set up CloudTrail and CloudWatch alerts for `s3:GetObject` and `s3:PutObject` events on sensitive buckets from roles with no direct IAM bucket permissions

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `STS: AssumeRole` -- starting user assumes `pl-bucket-access-role`; watch for cross-role chains leading to S3 data events
- `S3: ListBucket` -- bucket enumeration using `s3:ListAllMyBuckets`; precursor to targeted data access
- `S3: GetObject` -- object read from the sensitive bucket; critical when the caller assumed a role with no direct IAM bucket permissions
- `S3: PutObject` -- object write to the sensitive bucket; high severity from a role with minimal IAM policy

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
