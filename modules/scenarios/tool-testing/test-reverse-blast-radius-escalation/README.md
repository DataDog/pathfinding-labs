# Reverse Blast Radius Including Privilege Escalations to Bucket

* **Category:** Tool Testing
* **Sub-Category:** reverse-blast-radius
* **Path Type:** one-hop
* **Target:** to-bucket
* **Points:** 30
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Tool testing scenario validating that reverse blast radius queries distinguish principals that can read a bucket today from principals that can grant themselves that ability through privilege escalation (mint an access key for a reader; attach AdministratorAccess to self)
* **Terraform Variable:** `enable_tool_testing_test_reverse_blast_radius_escalation`
* **Schema Version:** 4.9.0
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0009 - Collection
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1530 - Data from Cloud Storage Object

## Objective

Your objective is to learn how to validate that a security tool answers "who can read this bucket" with privilege escalation in scope by demonstrating that `pl-prod-rbr-esc-bucket-reader` reads the `pl-sensitive-data-rbr-esc-{account_id}-{suffix}` bucket directly, while `pl-prod-rbr-esc-cak-user` and `pl-prod-rbr-esc-attach-self-user` hold no S3 access today but can escalate into it -- one by minting an access key for the reader, the other by attaching `AdministratorAccess` to itself.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-rbr-esc-bucket-reader`, `arn:aws:iam::{account_id}:user/pl-prod-rbr-esc-cak-user`, and `arn:aws:iam::{account_id}:user/pl-prod-rbr-esc-attach-self-user`
- **Destination resource:** `arn:aws:s3:::pl-sensitive-data-rbr-esc-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-rbr-esc-bucket-reader`):
- `s3:GetObject` on `arn:aws:s3:::pl-sensitive-data-rbr-esc-*/*` -- direct permission to read objects from the target bucket
- `s3:ListBucket` on `arn:aws:s3:::pl-sensitive-data-rbr-esc-*` -- direct permission to list the target bucket

**Required** (`pl-prod-rbr-esc-cak-user`):
- `iam:CreateAccessKey` on `arn:aws:iam::{account_id}:user/pl-prod-rbr-esc-bucket-reader` -- can mint a new access key for the bucket reader and then operate as it; holds no S3 permission of its own

**Required** (`pl-prod-rbr-esc-attach-self-user`):
- `iam:AttachUserPolicy` on `arn:aws:iam::{account_id}:user/pl-prod-rbr-esc-attach-self-user` -- can attach any managed policy (including `AdministratorAccess`) to itself and then read the bucket as an administrator; holds no S3 permission of its own

**Helpful** (`pl-prod-rbr-esc-cak-user`):
- `sts:GetCallerIdentity` -- verify current identity

### Expected Results

**What this lab tests:** whether reverse blast radius distinguishes who can read the bucket today from who can grant themselves the ability to, via privilege escalation.

**Graph a correct tool should build**

| From | Edge | To |
|---|---|---|
| `pl-prod-rbr-esc-bucket-reader` | can_read | `pl-sensitive-data-rbr-esc-{account_id}-{suffix}` |
| `pl-prod-rbr-esc-cak-user` | can_escalate | `pl-prod-rbr-esc-bucket-reader` |
| `pl-prod-rbr-esc-attach-self-user` | can_escalate | `pl-prod-rbr-esc-attach-self-user` |

**Expected answers**

| Case | Question | Must include | Must not include |
|---|---|---|---|
| rbr-esc-001 | Who can read the bucket directly, with no escalation? | `pl-prod-rbr-esc-bucket-reader` | `pl-prod-rbr-esc-cak-user`, `pl-prod-rbr-esc-attach-self-user` |
| rbr-esc-002 | Who can read the bucket if privilege escalation is allowed? | `pl-prod-rbr-esc-bucket-reader`, `pl-prod-rbr-esc-cak-user`, `pl-prod-rbr-esc-attach-self-user` | (none) |

**Why:**
- **rbr-esc-001:** only bucket-reader holds S3 read today. cak-user and attach-self-user hold only IAM permissions, so a direct-access query must exclude them.
- **rbr-esc-002:** cak-user can call iam:CreateAccessKey on bucket-reader, mint credentials for it, and read the bucket as bucket-reader. attach-self-user can call iam:AttachUserPolicy on itself, attach AdministratorAccess, and then read the bucket as an administrator. An escalation-aware reverse blast radius must include both.

**Proven by:** `demo_attack.sh`, which reads the bucket directly as bucket-reader, then performs each escalation (mint a key for bucket-reader; attach admin to self) and reads the bucket through the escalated access; `cleanup_attack.sh` removes the minted key and detaches the policy.

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable test-reverse-blast-radius-escalation-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-escalation-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-esc-bucket-reader` | Direct reader: `s3:GetObject` and `s3:ListBucket` on the target bucket (access keys provided) |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-esc-cak-user` | Escalator via `iam:CreateAccessKey` on bucket-reader; no S3 permission of its own (access keys provided) |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-esc-attach-self-user` | Escalator via `iam:AttachUserPolicy` on itself; attaches `AdministratorAccess` to read the bucket as admin (access keys provided) |
| `arn:aws:s3:::pl-sensitive-data-rbr-esc-{account_id}-{suffix}` | Target S3 bucket containing `sensitive-data.txt`; no bucket policy |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

This lab's demo performs real privilege escalation: it mints an access key for `bucket-reader` and attaches `AdministratorAccess` to `attach-self-user`. These are live out-of-band changes to IAM state, so `cleanup_attack.sh` must run afterward to remove them.

The script will:
1. Retrieve credentials, the region, and the bucket name from Terraform outputs
2. As `bucket-reader`, list and read `sensitive-data.txt` from the bucket directly (the direct, no-escalation case)
3. As `cak-user`, confirm that a direct bucket read is denied, then call `iam:CreateAccessKey` on `bucket-reader`, export the minted credentials, and read the bucket as `bucket-reader`
4. As `attach-self-user`, confirm that a direct bucket read is denied, then call `iam:AttachUserPolicy` to attach `AdministratorAccess` to itself, wait for IAM propagation, and read the bucket as an administrator
5. Print the observed access matrix and the expected reverse blast radius truth table: direct-only = bucket-reader; escalation-aware = bucket-reader, cak-user, attach-self-user. The script exits non-zero if any observed result differs from the expected ground truth

#### Resources Created by Attack Script

- A new access key for `pl-prod-rbr-esc-bucket-reader` minted by `cak-user` (deleted by the cleanup script)
- The `AdministratorAccess` managed policy attached to `pl-prod-rbr-esc-attach-self-user` (detached by the cleanup script)
- A temporary local file holding the downloaded object body (removed when the demo exits and again by the cleanup script)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo test-reverse-blast-radius-escalation
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup test-reverse-blast-radius-escalation
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable test-reverse-blast-radius-escalation-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-escalation-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

A security analysis platform or CSPM tool answering a reverse blast radius query on the target bucket should distinguish principals with direct access from principals that can escalate into access. When privilege escalation is in scope, the tool should identify:

1. **Direct read access**: `pl-prod-rbr-esc-bucket-reader` via `s3:GetObject` and `s3:ListBucket` statements naming the bucket
2. **Escalation via credential minting**: `pl-prod-rbr-esc-cak-user` can call `iam:CreateAccessKey` on `bucket-reader`, operate as that user, and read the bucket -- even though it holds no S3 permission itself
3. **Escalation via self-attachment**: `pl-prod-rbr-esc-attach-self-user` can call `iam:AttachUserPolicy` on itself, attach `AdministratorAccess`, and read the bucket as an administrator -- even though it holds no S3 permission itself
4. **Direct-only correctness**: a query that excludes privilege escalation must return only `bucket-reader` and must NOT return the two escalators

**Expected Query Results:**

Query: "Who can read bucket `pl-sensitive-data-rbr-esc-{account_id}-{suffix}` directly, with no escalation?"

```
- arn:aws:iam::{account_id}:user/pl-prod-rbr-esc-bucket-reader
```

Query: "Who can read bucket `pl-sensitive-data-rbr-esc-{account_id}-{suffix}` if privilege escalation is allowed?"

```
- arn:aws:iam::{account_id}:user/pl-prod-rbr-esc-bucket-reader (direct)
- arn:aws:iam::{account_id}:user/pl-prod-rbr-esc-cak-user (escalates via iam:CreateAccessKey on bucket-reader)
- arn:aws:iam::{account_id}:user/pl-prod-rbr-esc-attach-self-user (escalates via iam:AttachUserPolicy on self)
```

**Tool Testing Focus:**

This scenario specifically tests:

1. **Escalation awareness**: Does the tool follow privilege escalation edges (`iam:CreateAccessKey` on another user, `iam:AttachUserPolicy` on self) when asked who can reach a resource?
2. **Direct vs. escalation separation**: Does a direct-access query cleanly exclude principals whose access only exists after an escalation?
3. **Escalation style coverage**: Does the tool recognize both credential minting against another principal and self-attachment of a managed policy as paths to the bucket?
4. **No false negatives when escalation is in scope**: Does the escalation-aware answer include both escalators plus the direct reader?

**Expected Tool Behavior:**

Passing tools:
- Return only `bucket-reader` for the direct-only query
- Return `bucket-reader`, `cak-user`, and `attach-self-user` for the escalation-aware query
- Clearly label which principals are direct and which reach the bucket via escalation

Failing tools:
- Return all three for the direct-only query (over-counting; they treat escalation as direct access)
- Return only `bucket-reader` for the escalation-aware query (under-counting; they ignore escalation paths)
- Catch the `iam:CreateAccessKey` escalation but miss the `iam:AttachUserPolicy` self-escalation, or the reverse

#### Prevention Recommendations

This is a tool-testing scenario that validates detection capability rather than a real vulnerability. The following practices apply to limiting privilege escalation into sensitive buckets in production:

- Treat `iam:CreateAccessKey` on another principal as equivalent to holding that principal's permissions; scope it tightly and alert on its use
- Treat `iam:AttachUserPolicy`, `iam:PutUserPolicy`, and `iam:AttachRolePolicy` on self or peers as privilege escalation, and deny self-attachment via permission boundaries or SCPs
- Run reverse blast radius queries for sensitive resources with privilege escalation in scope, and confirm which escalation primitives your tool follows
- Add S3 bucket policies with explicit denies for all but approved principals, so that an escalation into a broad identity policy still does not yield bucket access
- Use IAM Access Analyzer and policy simulation to validate who can reach critical buckets after accounting for escalation
- Alert on `iam:CreateAccessKey` for users that hold sensitive data permissions, and on `iam:AttachUserPolicy` attaching `AdministratorAccess`

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `iam:CreateAccessKey` -- a new access key minted for `pl-prod-rbr-esc-bucket-reader`; critical when the caller is not that user and the target holds sensitive data permissions
- `iam:AttachUserPolicy` -- a managed policy attached to a user; high severity when `AdministratorAccess` is attached to the same user making the call (self-escalation)
- `s3:GetObject` -- object retrieval from the sensitive bucket; monitor for access by principals that reached it via escalation (requires S3 data event logging)
- `s3:ListBucket` -- bucket listing requests; monitor for enumeration of bucket contents

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [T1098.001 - Account Manipulation: Additional Cloud Credentials](https://attack.mitre.org/techniques/T1098/001/) -- MITRE ATT&CK technique for minting additional credentials
- [T1530 - Data from Cloud Storage Object](https://attack.mitre.org/techniques/T1530/) -- MITRE ATT&CK technique for collecting data from cloud storage
- [pathfinding.cloud/paths/iam-002](https://pathfinding.cloud/paths/iam-002) -- iam:CreateAccessKey privilege escalation
- [pathfinding.cloud/paths/iam-003](https://pathfinding.cloud/paths/iam-003) -- iam:AttachUserPolicy privilege escalation
