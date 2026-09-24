# S3 Read/Write/Delete Permission Edge Granularity

* **Category:** Tool Testing
* **Sub-Category:** edge-case-detection
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Tool testing scenario with 8 principals (4 permission tiers x IAM user/role) each granted a precise, non-overlapping subset of read/write/delete access to the same S3 bucket, to validate that graph/CSPM tools generate can_read/can_write/can_delete edges with exact granularity and no over- or under-inference
* **Terraform Variable:** `enable_tool_testing_test_s3_read_write_delete_permission_edges`
* **Schema Version:** 4.7.1
* **MITRE Tactics:** TA0009 - Collection, TA0040 - Impact
* **MITRE Techniques:** T1530 - Data from Cloud Storage Object, T1485 - Data Destruction, T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to validate security tool accuracy by deploying eight independent IAM principals -- split across a read-only, write-only, delete-only, and full read+write+delete tier, each represented by both an IAM user and an IAM role -- against a single S3 bucket, and measuring whether your graph/CSPM tool generates `can_read`/`can_write`/`can_delete` edges that match each principal's actual permissions exactly, with no permission inferred that wasn't granted and none missed that was.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-rwd-starting-user`
- **Destination resource:** `arn:aws:s3:::pl-rwd-bucket-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-rwd-user-read-only`):
- `s3:GetObject` on `arn:aws:s3:::pl-rwd-bucket-{account_id}-{suffix}/*` -- read the pre-seeded object; no write or delete permission granted
- `s3:ListBucket` on `arn:aws:s3:::pl-rwd-bucket-{account_id}-{suffix}` -- list bucket contents

**Required** (`pl-prod-rwd-role-read-only`):
- `s3:GetObject` on `arn:aws:s3:::pl-rwd-bucket-{account_id}-{suffix}/*` -- read the pre-seeded object; no write or delete permission granted
- `s3:ListBucket` on `arn:aws:s3:::pl-rwd-bucket-{account_id}-{suffix}` -- list bucket contents

**Required** (`pl-prod-rwd-user-write-only`):
- `s3:PutObject` on `arn:aws:s3:::pl-rwd-bucket-{account_id}-{suffix}/*` -- write objects; no read or delete permission granted

**Required** (`pl-prod-rwd-role-write-only`):
- `s3:PutObject` on `arn:aws:s3:::pl-rwd-bucket-{account_id}-{suffix}/*` -- write objects; no read or delete permission granted

**Required** (`pl-prod-rwd-user-delete-only`):
- `s3:DeleteObject` on `arn:aws:s3:::pl-rwd-bucket-{account_id}-{suffix}/*` -- delete objects; no read or write permission granted

**Required** (`pl-prod-rwd-role-delete-only`):
- `s3:DeleteObject` on `arn:aws:s3:::pl-rwd-bucket-{account_id}-{suffix}/*` -- delete objects; no read or write permission granted

**Required** (`pl-prod-rwd-user-read-write-delete`):
- `s3:GetObject` on `arn:aws:s3:::pl-rwd-bucket-{account_id}-{suffix}/*` -- full read access
- `s3:PutObject` on `arn:aws:s3:::pl-rwd-bucket-{account_id}-{suffix}/*` -- full write access
- `s3:DeleteObject` on `arn:aws:s3:::pl-rwd-bucket-{account_id}-{suffix}/*` -- full delete access
- `s3:ListBucket` on `arn:aws:s3:::pl-rwd-bucket-{account_id}-{suffix}` -- list bucket contents

**Required** (`pl-prod-rwd-role-read-write-delete`):
- `s3:GetObject` on `arn:aws:s3:::pl-rwd-bucket-{account_id}-{suffix}/*` -- full read access
- `s3:PutObject` on `arn:aws:s3:::pl-rwd-bucket-{account_id}-{suffix}/*` -- full write access
- `s3:DeleteObject` on `arn:aws:s3:::pl-rwd-bucket-{account_id}-{suffix}/*` -- full delete access
- `s3:ListBucket` on `arn:aws:s3:::pl-rwd-bucket-{account_id}-{suffix}` -- list bucket contents

**Helpful** (`pl-prod-rwd-starting-user`):
- `sts:GetCallerIdentity` -- verify assumed identity
- `sts:AssumeRole` -- starting user assumes the four role-based test principals

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable test-s3-read-write-delete-permission-edges-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-s3-read-write-delete-permission-edges-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
|-----|---------|
| `arn:aws:iam::{account_id}:user/pl-prod-rwd-starting-user` | Shared assumer; only used to `sts:AssumeRole` into the four role-based test principals |
| `arn:aws:iam::{account_id}:user/pl-prod-rwd-user-read-only` | IAM user granted `s3:GetObject` + `s3:ListBucket` only |
| `arn:aws:iam::{account_id}:role/pl-prod-rwd-role-read-only` | IAM role granted `s3:GetObject` + `s3:ListBucket` only |
| `arn:aws:iam::{account_id}:user/pl-prod-rwd-user-write-only` | IAM user granted `s3:PutObject` only |
| `arn:aws:iam::{account_id}:role/pl-prod-rwd-role-write-only` | IAM role granted `s3:PutObject` only |
| `arn:aws:iam::{account_id}:user/pl-prod-rwd-user-delete-only` | IAM user granted `s3:DeleteObject` only |
| `arn:aws:iam::{account_id}:role/pl-prod-rwd-role-delete-only` | IAM role granted `s3:DeleteObject` only |
| `arn:aws:iam::{account_id}:user/pl-prod-rwd-user-read-write-delete` | IAM user granted full `s3:GetObject`/`s3:PutObject`/`s3:DeleteObject`/`s3:ListBucket` |
| `arn:aws:iam::{account_id}:role/pl-prod-rwd-role-read-write-delete` | IAM role granted full `s3:GetObject`/`s3:PutObject`/`s3:DeleteObject`/`s3:ListBucket` |
| `arn:aws:s3:::pl-rwd-bucket-{account_id}-{suffix}` | Target bucket, pre-seeded with one object (`seed-object.txt`) so read-only and delete-only principals have something to act on |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

This scenario focuses on CSPM/graph tool detection validation rather than exploitation. All eight test principals already have the exact tier of access they need before the script runs; the script exists purely to confirm at runtime that each principal can do exactly what it was granted and nothing more.

The script will:
1. Retrieve credentials for the four IAM-user test principals directly from Terraform outputs
2. Use `pl-prod-rwd-starting-user` to `sts:AssumeRole` into the four role-based test principals
3. For each of the eight test principals, attempt `s3:GetObject` against the pre-seeded object, `s3:PutObject` of a new test object, and `s3:DeleteObject` of an object it does not own the writes to -- confirming each call succeeds or fails to match the principal's exact tier
4. Restore the bucket to its pre-seeded state (re-upload `seed-object.txt` if a delete-capable principal removed it, remove any stray objects a write-capable principal added)
5. Print a summary table showing, per principal, whether observed read/write/delete access matched the expected tier exactly

#### Resources Created by Attack Script

- A temporary test object per write-capable principal, written to and then deleted from the target bucket during the access check
- No persistent attack artifacts remain after the script completes; the pre-seeded `seed-object.txt` object is restored if removed during testing

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo test-s3-read-write-delete-permission-edges
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-s3-read-write-delete-permission-edges-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

This scenario creates no persistent attack artifacts beyond the temporary test objects removed at the end of the demo script. All infrastructure is managed by Terraform.

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup test-s3-read-write-delete-permission-edges
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-s3-read-write-delete-permission-edges-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable test-s3-read-write-delete-permission-edges-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-s3-read-write-delete-permission-edges-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

A comprehensive graph/CSPM tool should build `can_read`, `can_write`, and `can_delete` edges into `pl-rwd-bucket-{account_id}-{suffix}` with exact per-principal granularity:

- `pl-prod-rwd-user-read-only` / `pl-prod-rwd-role-read-only` -- `can_read: true`, `can_write: false`, `can_delete: false`
- `pl-prod-rwd-user-write-only` / `pl-prod-rwd-role-write-only` -- `can_read: false`, `can_write: true`, `can_delete: false`
- `pl-prod-rwd-user-delete-only` / `pl-prod-rwd-role-delete-only` -- `can_read: false`, `can_write: false`, `can_delete: true`
- `pl-prod-rwd-user-read-write-delete` / `pl-prod-rwd-role-read-write-delete` -- `can_read: true`, `can_write: true`, `can_delete: true`

**Critical test cases for tool validation:**

1. **Under-inference (false negatives)** -- does your tool correctly detect the single permission granted to each single-tier principal, or does it miss `s3:PutObject`-only or `s3:DeleteObject`-only grants because it only checks for `s3:GetObject` when building bucket-access edges?
2. **Over-inference (false positives)** -- does your tool ever assume `s3:PutObject` implies `s3:DeleteObject`, or that any S3 action on a bucket implies full CRUD? A tool that collapses these three actions into a single "has access" edge will over-report risk on the write-only and delete-only principals and under-report the precise blast radius of the read-write-delete tier.
3. **User vs. role parity** -- does your tool build the same per-action edges for an IAM user and an IAM role holding identical policies, or does it treat one principal type differently?
4. **Action-to-edge mapping completeness** -- does your tool's IAM action-to-graph-edge mapping table include `s3:DeleteObject` as a distinct edge type, or does it only model `s3:GetObject`/`s3:PutObject` and silently drop delete capability from its graph?

#### Prevention Recommendations

While this is a tool-testing scenario rather than a vulnerability demonstration, the configurations illustrate important security principles:

- **Scope S3 grants to the specific actions actually needed.** Avoid attaching broad `s3:*` statements when a principal only ever needs to read, write, or delete -- not all three.
- **Treat delete capability as a distinct, higher-severity grant.** `s3:DeleteObject` enables data destruction and should be flagged separately from read/write access in any risk scoring model.
- **Validate your CSPM/graph tool against known-answer benchmarks.** Use scenarios like this one to confirm your tool's action-to-edge mapping is complete and does not conflate write access with delete access, or partial access with full CRUD.
- **Enable S3 versioning and MFA delete on buckets holding sensitive data.** This limits the blast radius of a delete-only or read-write-delete principal being compromised.
- **Audit least-privilege drift over time.** Principals often accumulate additional S3 actions (e.g., a read-only principal later granted `s3:PutObject` for a one-off task) that never get revoked; periodic policy review catches this before it becomes a standing over-grant.
- **Monitor for anomalous delete activity.** A principal that has only ever called `s3:GetObject` suddenly calling `s3:DeleteObject` (if it has that permission) is a strong signal of compromise or misuse.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `s3:GetObject` -- read access to the target bucket; only the read-only and read-write-delete tier principals should succeed
- `s3:PutObject` -- write access to the target bucket; only the write-only and read-write-delete tier principals should succeed
- `s3:DeleteObject` -- delete access to the target bucket; only the delete-only and read-write-delete tier principals should succeed
- `s3:ListBucket` -- listing the target bucket contents; only principals granted `s3:ListBucket` should succeed
- `sts:AssumeRole` -- starting user assumes the four role-based test principals during validation

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
