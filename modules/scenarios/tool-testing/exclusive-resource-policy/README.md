# Exclusive Resource Policy Access to Bucket

* **Category:** Privilege Escalation
* **Sub-Category:** principal-access
* **Path Type:** multi-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Access S3 bucket with exclusive resource policy that denies all except specific role
* **Terraform Variable:** `enable_tool_testing_exclusive_resource_policy`
* **Schema Version:** 4.1.1
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0009 - Collection
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1530 - Data from Cloud Storage Object

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-pathfinding-starting-user-prod` IAM user to the `pl-exclusive-sensitive-data-bucket-{account_id}` S3 bucket by assuming the `pl-exclusive-bucket-access-role` role, which has only `s3:ListAllMyBuckets` in its identity policy but gains full read/write access to the bucket through an exclusive resource-based policy that denies all other principals.

- **Start:** `arn:aws:iam::{account_id}:user/pl-pathfinding-starting-user-prod`
- **Destination resource:** `arn:aws:s3:::pl-exclusive-sensitive-data-bucket-{account_id}`

### Starting Permissions

**Required** (`pl-pathfinding-starting-user-prod`):
- `sts:AssumeRole` on `arn:aws:iam::*:role/pl-exclusive-bucket-access-role` -- allows the starting user to assume the exclusive bucket access role

**Helpful** (`pl-pathfinding-starting-user-prod`):
- `iam:ListRoles` -- discover roles with exclusive bucket access
- `s3:GetBucketPolicy` -- view the bucket resource policy to understand the exclusive-access grant

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
plabs enable exclusive-resource-policy-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `exclusive-resource-policy-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
|-----|---------|
| `arn:aws:iam::{account_id}:role/pl-exclusive-bucket-access-role` | Role that trusts the prod starting user; IAM policy contains only `s3:ListAllMyBuckets` |
| `arn:aws:s3:::pl-exclusive-sensitive-data-bucket-{account_id}` | Bucket with highly sensitive sample data, encryption enabled, and restrictive resource policy |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:

1. Retrieve credentials for the starting user and the readonly user from Terraform outputs
2. Verify the current identity and test initial permissions
3. Assume the `pl-exclusive-bucket-access-role` using the starting user's credentials
4. Verify that the assumed role has limited IAM permissions (`s3:ListAllMyBuckets` only)
5. Use `s3:ListAllMyBuckets` to discover the exclusive sensitive bucket
6. Access the exclusive sensitive bucket through the restrictive resource policy
7. Read all objects from the exclusive bucket, demonstrating data exfiltration
8. Write a test object to the exclusive bucket, confirming write access
9. Retrieve and display the bucket policy, showing the Allow + Deny structure

#### Resources Created by Attack Script

- No persistent attack artifacts are created; the demo reads and writes objects in the exclusive bucket using the pre-provisioned role credentials, and any test uploads are deleted before the script exits

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo exclusive-resource-policy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `exclusive-resource-policy-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup exclusive-resource-policy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `exclusive-resource-policy-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable exclusive-resource-policy-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `exclusive-resource-policy-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- S3 bucket resource policy grants `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, and `s3:ListBucket` to a specific IAM role while explicitly denying all other principals — creating a hidden exclusive-access channel
- IAM role (`pl-exclusive-bucket-access-role`) has no direct S3 permissions in its identity policy yet can fully read and write a sensitive bucket via the bucket resource policy
- S3 bucket resource policy contains an explicit `Deny` on `Principal: "*"` with a `StringNotEquals` condition on `aws:PrincipalArn` -- a pattern that is easy to misconfigure and creates blind spots in access reviews
- The combination of a minimal-permission role and an exclusive resource policy means standard IAM analysis tools will underreport actual access

#### Prevention Recommendations

- **Principle of Least Privilege**: Avoid granting `s3:ListAllMyBuckets` unless absolutely necessary; prefer scoped `s3:ListBucket` on specific buckets
- **Resource Policy Auditing**: Regularly audit S3 bucket resource policies for exclusive-access patterns using AWS Access Analyzer or third-party CSPM tools
- **Access Logging**: Enable S3 server access logging and CloudTrail data events to monitor all bucket access patterns
- **Conditional Policies**: Strengthen resource policy conditions (e.g., require `aws:SourceVpc` or `aws:PrincipalOrgID`) rather than relying solely on `aws:PrincipalArn`
- **Policy Testing**: Regularly test effective permissions using `aws iam simulate-principal-policy` and Access Analyzer to surface resource-policy-granted access
- **Monitoring**: Set up CloudTrail and CloudWatch alerts for `s3:GetObject` and `s3:PutObject` events from roles with no explicit S3 identity policy

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `sts:AssumeRole` -- Role assumption by the starting user; flag when the assumed role has minimal IAM permissions but is known to have exclusive resource-policy access
- `s3:ListBucket` -- Bucket enumeration by the exclusive role; precedes data access
- `s3:GetObject` -- Object read from the exclusive bucket; critical when the accessing principal has no direct S3 IAM permissions
- `s3:PutObject` -- Object write to the exclusive bucket; high severity when the accessing principal's identity policy does not grant S3 write access

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
