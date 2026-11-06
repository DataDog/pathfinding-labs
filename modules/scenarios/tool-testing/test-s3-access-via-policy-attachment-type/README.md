# S3 Access via Inline and Managed Policy Attachment Types

* **Category:** Tool Testing
* **Sub-Category:** policy-parsing-edge-case
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Tool testing scenario with 4 principals (IAM user with inline policy, IAM user with managed policy, IAM role with inline policy, IAM role with managed policy) that each already have full read/write access to the same S3 bucket, to validate that graph/CSPM tools detect equivalent bucket access regardless of the IAM attachment mechanism used
* **Terraform Variable:** `enable_tool_testing_test_s3_access_via_policy_attachment_type`
* **Schema Version:** 4.7.1
* **MITRE Tactics:** TA0009 - Collection
* **MITRE Techniques:** T1530 - Data from Cloud Storage Object, T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to validate security tool accuracy by deploying four independent IAM principals -- `pl-prod-patn-user-inline`, `pl-prod-patn-user-managed`, `pl-prod-patn-role-inline`, and `pl-prod-patn-role-managed` -- that each already hold identical full read/write access to `pl-patn-bucket-{account_id}-{suffix}`, and measuring whether your graph/CSPM tool infers the same bucket-access edge for all four regardless of whether the grant comes from an inline policy or a customer-managed policy attachment.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-patn-starting-user`
- **Destination resource:** `arn:aws:s3:::pl-patn-bucket-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-patn-user-inline`):
- `s3:GetObject` on `arn:aws:s3:::pl-patn-bucket-{account_id}-{suffix}/*` -- read access granted via an inline user policy
- `s3:PutObject` on `arn:aws:s3:::pl-patn-bucket-{account_id}-{suffix}/*` -- write access granted via an inline user policy
- `s3:ListBucket` on `arn:aws:s3:::pl-patn-bucket-{account_id}-{suffix}` -- list access granted via an inline user policy
- `s3:ListAllMyBuckets` on `*` -- account-wide bucket enumeration

**Required** (`pl-prod-patn-user-managed`):
- `s3:GetObject` on `arn:aws:s3:::pl-patn-bucket-{account_id}-{suffix}/*` -- read access granted via a customer-managed policy attachment
- `s3:PutObject` on `arn:aws:s3:::pl-patn-bucket-{account_id}-{suffix}/*` -- write access granted via a customer-managed policy attachment
- `s3:ListBucket` on `arn:aws:s3:::pl-patn-bucket-{account_id}-{suffix}` -- list access granted via a customer-managed policy attachment
- `s3:ListAllMyBuckets` on `*` -- account-wide bucket enumeration

**Required** (`pl-prod-patn-role-inline`):
- `s3:GetObject` on `arn:aws:s3:::pl-patn-bucket-{account_id}-{suffix}/*` -- read access granted via an inline role policy
- `s3:PutObject` on `arn:aws:s3:::pl-patn-bucket-{account_id}-{suffix}/*` -- write access granted via an inline role policy
- `s3:ListBucket` on `arn:aws:s3:::pl-patn-bucket-{account_id}-{suffix}` -- list access granted via an inline role policy
- `s3:ListAllMyBuckets` on `*` -- account-wide bucket enumeration

**Required** (`pl-prod-patn-role-managed`):
- `s3:GetObject` on `arn:aws:s3:::pl-patn-bucket-{account_id}-{suffix}/*` -- read access granted via a customer-managed policy attachment
- `s3:PutObject` on `arn:aws:s3:::pl-patn-bucket-{account_id}-{suffix}/*` -- write access granted via a customer-managed policy attachment
- `s3:ListBucket` on `arn:aws:s3:::pl-patn-bucket-{account_id}-{suffix}` -- list access granted via a customer-managed policy attachment
- `s3:ListAllMyBuckets` on `*` -- account-wide bucket enumeration

**Helpful** (`pl-prod-patn-starting-user`):
- `sts:GetCallerIdentity` -- verify assumed identity
- `sts:AssumeRole` -- starting user assumes the two role-based test principals (`pl-prod-patn-role-inline` and `pl-prod-patn-role-managed`)

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable test-s3-access-via-policy-attachment-type-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-s3-access-via-policy-attachment-type-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
|-----|---------|
| `arn:aws:iam::{account_id}:user/pl-prod-patn-starting-user` | Shared assumer; only used to `sts:AssumeRole` into the two role-based test principals |
| `arn:aws:iam::{account_id}:user/pl-prod-patn-user-inline` | IAM user with an inline policy granting full read/write access to the target bucket |
| `arn:aws:iam::{account_id}:user/pl-prod-patn-user-managed` | IAM user with a customer-managed policy attached granting full read/write access to the target bucket |
| `arn:aws:iam::{account_id}:role/pl-prod-patn-role-inline` | IAM role with an inline policy granting full read/write access to the target bucket |
| `arn:aws:iam::{account_id}:role/pl-prod-patn-role-managed` | IAM role with a customer-managed policy attached granting full read/write access to the target bucket |
| `arn:aws:s3:::pl-patn-bucket-{account_id}-{suffix}` | Target resource for access validation |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

This scenario focuses on CSPM/graph tool detection validation rather than exploitation. All four test principals already have the access they need before the script runs; the script exists purely to confirm at runtime that the four independent IAM attachment mechanisms produce identical, functioning bucket access.

The script will:
1. Retrieve credentials for `pl-prod-patn-user-inline` and `pl-prod-patn-user-managed` directly from Terraform outputs
2. Use `pl-prod-patn-starting-user` to `sts:AssumeRole` into `pl-prod-patn-role-inline` and `pl-prod-patn-role-managed`
3. For each of the four test principals, run `s3:ListBucket`, `s3:PutObject`, and `s3:GetObject` against the target bucket
4. Delete the test object written by each principal to leave the bucket clean
5. Print a summary confirming all four principals resolved to identical bucket access despite the differing IAM attachment mechanisms

#### Resources Created by Attack Script

- A temporary test object per principal, written to and then deleted from the target bucket during the access check
- No persistent attack artifacts remain after the script completes

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo test-s3-access-via-policy-attachment-type
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-s3-access-via-policy-attachment-type-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

This scenario creates no persistent attack artifacts beyond the temporary test objects removed at the end of the demo script. All infrastructure is managed by Terraform.

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup test-s3-access-via-policy-attachment-type
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-s3-access-via-policy-attachment-type-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable test-s3-access-via-policy-attachment-type-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-s3-access-via-policy-attachment-type-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

A comprehensive graph/CSPM tool should correctly identify all four principals as having equivalent effective access to `pl-patn-bucket-{account_id}-{suffix}`:

- `pl-prod-patn-user-inline` -- an IAM user whose bucket access comes from a policy document embedded directly on the user (`aws_iam_user_policy`)
- `pl-prod-patn-user-managed` -- an IAM user whose bucket access comes from a standalone customer-managed policy attached via `aws_iam_user_policy_attachment`
- `pl-prod-patn-role-inline` -- an IAM role whose bucket access comes from a policy document embedded directly on the role (`aws_iam_role_policy`)
- `pl-prod-patn-role-managed` -- an IAM role whose bucket access comes from a standalone customer-managed policy attached via `aws_iam_role_policy_attachment`

**Critical test cases for tool validation:**

1. **Inline vs. managed parity** -- does your tool traverse both `aws_iam_user_policy` / `aws_iam_role_policy` (inline) documents and `aws_iam_policy` (managed) documents attached via `*_policy_attachment` resources, and resolve them to the same effective-access edge?
2. **User vs. role parity** -- does your tool build the same bucket-access edge for an IAM user and an IAM role that hold functionally identical policies, or does it treat one principal type differently in its graph model?
3. **False negative risk** -- a tool that only parses one attachment mechanism (e.g., only managed policies) will silently miss two of the four principals in this scenario, undercounting who has access to the sensitive bucket.
4. **Bucket-level blast radius** -- all four principals should appear as edges into the same bucket node in any blast-radius or "who can access this bucket" query, regardless of the underlying IAM mechanism.

#### Prevention Recommendations

While this is a tool-testing scenario rather than a vulnerability demonstration, the configurations illustrate important security principles:

- **Standardize on one attachment mechanism where possible.** Mixing inline and managed policies across principals with equivalent access makes manual security review harder and increases the chance that a scan misses a grant.
- **Prefer managed policies over inline policies for auditability.** Managed policies are independently listable and versioned (`iam:ListPolicies`, `iam:GetPolicyVersion`), which makes them easier to track over time than inline documents buried on individual principals.
- **Regularly enumerate both attachment types.** Any manual or automated review of "who can access bucket X" must query `iam:ListUserPolicies` / `iam:ListRolePolicies` (inline) and `iam:ListAttachedUserPolicies` / `iam:ListAttachedRolePolicies` (managed) for every principal, not just one.
- **Validate your CSPM/graph tool against known-answer benchmarks.** Use scenarios like this one to confirm your tool's policy-parsing engine handles every combination of principal type (user/role) and attachment mechanism (inline/managed) before trusting its blast-radius reporting.
- **Apply least privilege regardless of mechanism.** Full read/write access to a bucket should be scoped down to only the specific prefixes and actions a principal actually needs, whether granted inline or via a managed policy.
- **Monitor policy changes on both mechanisms.** CloudTrail events for inline policy writes (`PutUserPolicy`/`PutRolePolicy`) and managed policy attachments (`AttachUserPolicy`/`AttachRolePolicy`) both need equal monitoring coverage -- a detection rule tuned only for one will miss half of all new grants.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `iam:PutUserPolicy` -- inline policy attached directly to an IAM user; grants can be easy to miss if monitoring only tracks managed policy attachments
- `iam:PutRolePolicy` -- inline policy attached directly to an IAM role
- `iam:AttachUserPolicy` -- customer-managed (or AWS-managed) policy attached to an IAM user
- `iam:AttachRolePolicy` -- customer-managed (or AWS-managed) policy attached to an IAM role
- `sts:AssumeRole` -- starting user assumes the two role-based test principals during validation
- `s3:GetObject` -- read access to the test bucket; all four principals should succeed identically
- `s3:PutObject` -- write access to the test bucket; all four principals should succeed identically
- `s3:ListBucket` -- listing the test bucket contents during access validation

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
