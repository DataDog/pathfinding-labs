# Reverse Blast Radius with Identity-Side Access Blocks

* **Category:** Tool Testing
* **Sub-Category:** edge-case-detection
* **Path Type:** self-escalation
* **Target:** to-bucket
* **Points:** 20
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Tool testing scenario validating that a reverse blast radius answer for a bucket excludes principals whose bucket-read permission is nullified on the identity side by an explicit deny or a permissions boundary
* **Terraform Variable:** `enable_tool_testing_test_reverse_blast_radius_identity_side_block`
* **Schema Version:** 4.9.0
* **MITRE Tactics:** TA0009 - Collection
* **MITRE Techniques:** T1530 - Data from Cloud Storage Object

## Objective

Your objective is to learn how to validate that a security tool excludes identity-side-blocked principals from reverse blast radius answers by demonstrating that only `pl-prod-rbr-isb-plain-reader` can read the `pl-sensitive-data-rbr-isb-{account_id}-{suffix}` bucket, while `pl-prod-rbr-isb-explicit-deny-reader` (same Allow plus an inline Deny on `s3:*`) and `pl-prod-rbr-isb-boundary-excludes-s3` (same Allow but an EC2-only permissions boundary) look like readers yet have no effective access.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-rbr-isb-plain-reader`, `arn:aws:iam::{account_id}:user/pl-prod-rbr-isb-explicit-deny-reader`, and `arn:aws:iam::{account_id}:user/pl-prod-rbr-isb-boundary-excludes-s3`
- **Destination resource:** `arn:aws:s3:::pl-sensitive-data-rbr-isb-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-rbr-isb-plain-reader`):
- `s3:GetObject` on `arn:aws:s3:::pl-sensitive-data-rbr-isb-*/*` -- explicit permission to read objects in the target bucket, with nothing blocking it
- `s3:ListBucket` on `arn:aws:s3:::pl-sensitive-data-rbr-isb-*` -- explicit permission to list the target bucket

**Required** (`pl-prod-rbr-isb-explicit-deny-reader`):
- `s3:GetObject` on `arn:aws:s3:::pl-sensitive-data-rbr-isb-*/*` -- the same read Allow as plain-reader, but paired with an inline `Deny` on `s3:*`, which always wins
- `s3:ListBucket` on `arn:aws:s3:::pl-sensitive-data-rbr-isb-*` -- the same list Allow, also nullified by the inline deny

**Required** (`pl-prod-rbr-isb-boundary-excludes-s3`):
- `s3:GetObject` on `arn:aws:s3:::pl-sensitive-data-rbr-isb-*/*` -- the same read Allow, but capped by an EC2-only permissions boundary, so effective S3 access is nil
- `s3:ListBucket` on `arn:aws:s3:::pl-sensitive-data-rbr-isb-*` -- the same list Allow, also capped away by the boundary

### Expected Results

**What this lab tests:** whether a reverse-blast-radius answer for a bucket excludes principals whose bucket-read Allow is nullified on the identity side, by an explicit deny or a permissions boundary.

**Graph a correct tool should build**

| From | Edge | To |
|---|---|---|
| `pl-prod-rbr-isb-plain-reader` | can_read | `pl-sensitive-data-rbr-isb-{account_id}-{suffix}` |

**Expected answers**

| Case | Question | Must include | Must not include |
|---|---|---|---|
| rbr-isb-001 | Who can read the bucket? | `pl-prod-rbr-isb-plain-reader` | `pl-prod-rbr-isb-explicit-deny-reader`, `pl-prod-rbr-isb-boundary-excludes-s3` |

**Why:**
- **rbr-isb-001:** plain-reader has an unobstructed Allow for s3:GetObject/s3:ListBucket. explicit-deny-reader has the same Allow plus an inline Deny on s3:*, and an explicit deny always wins. boundary-excludes-s3 has the same Allow but an EC2-only permissions boundary, and effective permissions are the intersection of the boundary and the identity policy, so its S3 access is nil. Both are false positives for any tool that reads Allow statements without applying denies and boundaries.

**Proven by:** `demo_attack.sh`, which reads the bucket as each of the three users and confirms only plain-reader succeeds while the other two receive AccessDenied.

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable test-reverse-blast-radius-identity-side-block-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-identity-side-block-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-isb-plain-reader` | Control: explicit `s3:GetObject` and `s3:ListBucket` Allow on the target bucket, with nothing blocking it (access keys provided) |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-isb-explicit-deny-reader` | False positive: same read Allow plus an inline `Deny` on `s3:*`, so effective access is none (access keys provided) |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-isb-boundary-excludes-s3` | False positive: same read Allow, but an EC2-only permissions boundary caps effective S3 access to none (access keys provided) |
| `arn:aws:iam::{account_id}:policy/pl-prod-rbr-isb-ec2-only-boundary` | Permissions boundary allowing only `ec2:Describe*`; excludes S3 entirely |
| `arn:aws:s3:::pl-sensitive-data-rbr-isb-{account_id}-{suffix}` | Target bucket containing test data, with no bucket policy |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve credentials, the region, and the bucket name from Terraform outputs
2. Confirm the identity of each of the three users
3. As `plain-reader`, list the bucket and read `sensitive-data.txt` successfully
4. As `explicit-deny-reader`, attempt the same list and read and confirm both are denied by the inline `Deny` on `s3:*`
5. As `boundary-excludes-s3`, attempt the same list and read and confirm both are denied by the EC2-only permissions boundary
6. Print the observed access matrix and the expected reverse blast radius truth table: `can_read` = plain-reader only; explicit-deny-reader and boundary-excludes-s3 in neither. The script exits non-zero if any observed result differs from the expected ground truth

#### Resources Created by Attack Script

- No persistent AWS resources are created; the demo performs read-only `s3 ls` and `s3 cp` probes against the existing bucket
- A temporary local file may be written under `/tmp` to capture downloaded object bodies (removed when the demo exits and again by the cleanup script)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo test-reverse-blast-radius-identity-side-block
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-identity-side-block-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup test-reverse-blast-radius-identity-side-block
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-identity-side-block-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable test-reverse-blast-radius-identity-side-block-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-identity-side-block-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

A security analysis platform or CSPM tool answering a reverse blast radius query on the target bucket must apply the full IAM evaluation chain -- not just collect Allow statements -- before naming a principal as a reader. The tool should identify:

1. **Effective read access**: `pl-prod-rbr-isb-plain-reader` via an unobstructed `s3:GetObject` and `s3:ListBucket` Allow naming the bucket
2. **Explicit deny nullification**: `pl-prod-rbr-isb-explicit-deny-reader` carries the same read Allow, but an inline `Deny` on `s3:*` overrides it; an explicit deny always wins, so this principal has no effective access
3. **Permissions boundary nullification**: `pl-prod-rbr-isb-boundary-excludes-s3` carries the same read Allow, but an EC2-only permissions boundary caps its effective permissions to the intersection of boundary and identity policy, leaving zero S3 access
4. **No false positives**: neither the deny-blocked nor the boundary-blocked user may appear in the reverse blast radius answer

**Expected Query Results:**

Query: "Who can read bucket `pl-sensitive-data-rbr-isb-{account_id}-{suffix}`?"

```
- arn:aws:iam::{account_id}:user/pl-prod-rbr-isb-plain-reader (effective read)
```

**Tool Testing Focus:**

This scenario specifically tests:

1. **Explicit deny handling**: Does the tool subtract an inline `Deny` on `s3:*` from a principal's effective permissions, rather than reporting the Allow at face value?
2. **Permissions boundary handling**: Does the tool compute the intersection of a permissions boundary and the identity policy, excluding a principal whose boundary does not permit S3?
3. **Allow-only false positives**: Does the tool avoid naming principals whose only basis for inclusion is an Allow statement that is overridden on the identity side?
4. **Control preservation**: Does the tool still return `plain-reader`, whose Allow is unobstructed?

**Expected Tool Behavior:**

Passing tools:
- Return only `plain-reader` for `can_read`
- Exclude `explicit-deny-reader` because the inline deny overrides its Allow
- Exclude `boundary-excludes-s3` because its permissions boundary does not permit S3

Failing tools:
- Return all three principals, treating any bucket-read Allow as effective access
- Include `explicit-deny-reader`, missing that an explicit deny always wins
- Include `boundary-excludes-s3`, missing that effective permissions are the intersection of boundary and identity policy

#### Prevention Recommendations

This is a tool-testing scenario that validates detection capability rather than a real vulnerability. The following practices apply to using identity-side controls to restrict access to sensitive buckets in production:

- Use explicit `Deny` statements on `s3:*` (or on specific sensitive bucket ARNs) to hard-block principals that must never touch the data, independent of any Allow they may accumulate
- Attach permissions boundaries to scope what a principal can ever do, so a stray Allow cannot grant effective access beyond the boundary's intersection
- Prefer tools that compute effective permissions (Allow minus Deny, intersected with boundaries and SCPs) over tools that enumerate Allow statements alone
- Use IAM Access Analyzer and `simulate-principal-policy` to validate that a principal's effective access matches intent after denies and boundaries are applied
- Audit principals that carry a broad Allow alongside a deny or boundary; these are confusing to reviewers and to tooling and should be simplified where possible
- Alert on changes that remove an inline deny or widen a permissions boundary on principals that hold latent S3 Allow statements

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `s3:GetObject` -- object retrieval from the sensitive bucket; an AccessDenied for the deny-blocked or boundary-blocked users confirms the identity-side controls are in force (requires S3 data event logging)
- `s3:ListBucket` -- bucket listing requests; monitor for enumeration attempts, including denied ones from the blocked users
- `iam:PutUserPolicy` -- inline policy changes on these users; critical if an existing `Deny` statement is removed from `explicit-deny-reader`
- `iam:PutUserPermissionsBoundary` -- permissions boundary changes; critical if the EC2-only boundary on `boundary-excludes-s3` is widened or detached
- `iam:DeleteUserPermissionsBoundary` -- boundary removal; would unmask the latent S3 Allow on `boundary-excludes-s3`

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [T1530 - Data from Cloud Storage Object](https://attack.mitre.org/techniques/T1530/) -- MITRE ATT&CK technique page
- [IAM policy evaluation logic](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html) -- how explicit denies and permissions boundaries affect effective permissions
- [Permissions boundaries for IAM entities](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_boundaries.html) -- AWS documentation
