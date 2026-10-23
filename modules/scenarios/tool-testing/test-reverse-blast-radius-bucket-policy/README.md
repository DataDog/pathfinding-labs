# Reverse Blast Radius with Bucket Policy Grants and Denies

* **Category:** Tool Testing
* **Sub-Category:** edge-case-detection
* **Path Type:** one-hop
* **Target:** to-bucket
* **Points:** 20
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Tool testing scenario validating that reverse blast radius for a bucket honors the bucket resource policy in both directions: access granted only by the bucket policy is found, and access denied by the bucket policy is withheld even from an administrator
* **Terraform Variable:** `enable_tool_testing_test_reverse_blast_radius_bucket_policy`
* **Schema Version:** 4.9.0
* **MITRE Tactics:** TA0009 - Collection
* **MITRE Techniques:** T1530 - Data from Cloud Storage Object

## Objective

Your objective is to learn how to validate that a security tool answers a reverse blast radius query for the `pl-sensitive-data-rbr-bp-{account_id}-{suffix}` bucket by honoring the bucket resource policy in both directions: it finds `pl-prod-rbr-bp-policy-granted-role` (read/write granted only by the bucket policy) and the one-hop `pl-prod-rbr-bp-starting-user`, while withholding `pl-prod-rbr-bp-denied-reader` and even the administrator `pl-prod-rbr-bp-denied-admin` because the bucket policy explicitly denies their ARNs.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-rbr-bp-starting-user`, `arn:aws:iam::{account_id}:user/pl-prod-rbr-bp-identity-reader`, `arn:aws:iam::{account_id}:user/pl-prod-rbr-bp-denied-reader`, and `arn:aws:iam::{account_id}:user/pl-prod-rbr-bp-denied-admin`
- **Destination resource:** `arn:aws:s3:::pl-sensitive-data-rbr-bp-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-rbr-bp-starting-user`):
- `sts:AssumeRole` on `arn:aws:iam::{account_id}:role/pl-prod-rbr-bp-policy-granted-role` -- assume the role whose only bucket access comes from the bucket policy (the one-hop case)

**Required** (`pl-prod-rbr-bp-identity-reader`):
- `s3:GetObject` on `arn:aws:s3:::pl-sensitive-data-rbr-bp-*/*` -- explicit identity-policy permission to read objects in the target bucket
- `s3:ListBucket` on `arn:aws:s3:::pl-sensitive-data-rbr-bp-*` -- explicit identity-policy permission to list the target bucket

### Expected Results

**What this lab tests:** whether a reverse-blast-radius answer for a bucket honors the bucket resource policy in both directions -- access granted only by the bucket policy is found, and access denied by the bucket policy is withheld even from an administrator.

**Graph a correct tool should build**

| From | Edge | To |
|---|---|---|
| `pl-prod-rbr-bp-policy-granted-role` | can_read | `pl-sensitive-data-rbr-bp-{account_id}-{suffix}` |
| `pl-prod-rbr-bp-policy-granted-role` | can_write | `pl-sensitive-data-rbr-bp-{account_id}-{suffix}` |
| `pl-prod-rbr-bp-identity-reader` | can_read | `pl-sensitive-data-rbr-bp-{account_id}-{suffix}` |
| `pl-prod-rbr-bp-starting-user` | can_assume | `pl-prod-rbr-bp-policy-granted-role` |
| `pl-prod-rbr-bp-denied-admin` | is_admin | true |

**Expected answers**

| Case | Question | Must include | Must not include |
|---|---|---|---|
| rbr-bp-001 | Who can read the bucket directly (0 hops)? | `pl-prod-rbr-bp-policy-granted-role`, `pl-prod-rbr-bp-identity-reader` | `pl-prod-rbr-bp-denied-reader`, `pl-prod-rbr-bp-denied-admin` |
| rbr-bp-002 | Who can read it by assuming exactly one role (1 hop)? | `pl-prod-rbr-bp-starting-user` | `pl-prod-rbr-bp-denied-reader`, `pl-prod-rbr-bp-denied-admin` |

**Why:**
- **rbr-bp-001:** policy-granted-role has no S3 in its identity policy; its read/write come only from the bucket policy Allow. identity-reader reads via its own identity policy. denied-reader's identity policy allows reading, but the bucket-policy Deny on its ARN overrides the Allow. denied-admin has AdministratorAccess, but an explicit resource-policy Deny overrides admin, so it cannot read this bucket.
- **rbr-bp-002:** starting-user holds only sts:AssumeRole on policy-granted-role and reaches the bucket by assuming it.

**Why (continued — deny-vs-admin):** denied-admin is the key case. Once a tool models administrators as having implicit access to every resource, that implicit access must still be removed by an explicit resource-policy Deny. A tool that adds admin-to-resource edges without checking bucket-policy denies will wrongly report denied-admin as a reader.

**Proven by:** `demo_attack.sh`, which reads the bucket as policy-granted-role (via assume-role) and as identity-reader, and confirms denied-reader and denied-admin receive AccessDenied despite their identity permissions.

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable test-reverse-blast-radius-bucket-policy-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-bucket-policy-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-bp-starting-user` | Holds only `sts:AssumeRole` on policy-granted-role; reaches the bucket at one hop (access keys provided) |
| `arn:aws:iam::{account_id}:role/pl-prod-rbr-bp-policy-granted-role` | No S3 in its identity policy; read/write come only from the bucket policy Allow. Trust policy allows only starting-user to assume it |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-bp-identity-reader` | Reads via its own identity policy (`s3:GetObject`, `s3:ListBucket`); the bucket policy is silent about it (access keys provided) |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-bp-denied-reader` | Identity policy allows reading, but the bucket policy Denies its ARN -- effective access is none (access keys provided) |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-bp-denied-admin` | Holds `AdministratorAccess`, but the bucket policy Denies its ARN -- an explicit resource-policy Deny overrides admin (access keys provided) |
| `arn:aws:s3:::pl-sensitive-data-rbr-bp-{account_id}-{suffix}` | Target bucket; its bucket policy Allows policy-granted-role and explicitly Denies the two denied principals by ARN |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve credentials, the region, and the bucket name from Terraform outputs
2. As `starting-user`, assume `policy-granted-role` and, with the returned session credentials, list and read the bucket successfully -- proving access that comes only from the bucket policy, at one hop
3. As `identity-reader`, list and read the bucket successfully through its own identity policy
4. As `denied-reader`, confirm that read and list are both denied even though its identity policy allows them, because the bucket policy Denies its ARN
5. As `denied-admin`, confirm that read and list are both denied despite `AdministratorAccess`, because an explicit resource-policy Deny overrides admin
6. Print the observed access matrix and the expected reverse blast radius truth table: `can_read` directly = policy-granted-role, identity-reader; `can_read` at 1 hop = starting-user; denied-reader and denied-admin in neither. The script exits non-zero if any observed result differs from the expected ground truth

#### Resources Created by Attack Script

- Temporary role-session credentials for `policy-granted-role` held only in environment variables for the duration of the demo (not persisted)
- No objects are written to the bucket; the demo performs read and list operations only

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo test-reverse-blast-radius-bucket-policy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-bucket-policy-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup test-reverse-blast-radius-bucket-policy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-bucket-policy-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable test-reverse-blast-radius-bucket-policy-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-bucket-policy-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

A security analysis platform or CSPM tool answering a reverse blast radius query on the target bucket must combine identity policies and the bucket resource policy, and it must apply an explicit resource-policy Deny even against principals it would otherwise treat as administrators. The tool should identify:

1. **Resource-policy-only grant**: `pl-prod-rbr-bp-policy-granted-role` can read and write the bucket solely through the bucket policy Allow, with no S3 statement in its identity policy
2. **Identity-policy grant**: `pl-prod-rbr-bp-identity-reader` can read the bucket through its own identity policy, with the bucket policy silent about it
3. **One-hop reachability**: `pl-prod-rbr-bp-starting-user` reaches the bucket by assuming policy-granted-role (depth 1)
4. **Resource-policy Deny over identity Allow**: `pl-prod-rbr-bp-denied-reader` has an identity Allow but is denied by the bucket policy, so it has no access
5. **Resource-policy Deny over administrator**: `pl-prod-rbr-bp-denied-admin` holds `AdministratorAccess` but is denied by the bucket policy, so it has no access to this bucket

**Expected Query Results:**

Query: "Who can read bucket `pl-sensitive-data-rbr-bp-{account_id}-{suffix}` directly (0 hops)?"

```
- arn:aws:iam::{account_id}:role/pl-prod-rbr-bp-policy-granted-role (bucket policy grant)
- arn:aws:iam::{account_id}:user/pl-prod-rbr-bp-identity-reader (identity policy grant)
```

Query: "Who can read bucket `pl-sensitive-data-rbr-bp-{account_id}-{suffix}` by assuming exactly one role (1 hop)?"

```
- arn:aws:iam::{account_id}:user/pl-prod-rbr-bp-starting-user (assumes policy-granted-role)
```

`pl-prod-rbr-bp-denied-reader` and `pl-prod-rbr-bp-denied-admin` must appear in neither answer.

**Tool Testing Focus:**

This scenario specifically tests:

1. **Resource-policy grants in both directions**: Does the tool find access that comes only from the bucket policy, not just identity policies?
2. **Deny beats identity Allow**: Does the tool remove `denied-reader` even though its identity policy clearly allows reading?
3. **Deny beats administrator**: Does the tool remove `denied-admin` despite `AdministratorAccess`, rather than blindly adding an admin-to-every-resource edge?
4. **Hop depth**: Does the tool distinguish the 0-hop readers from the 1-hop `starting-user`?
5. **Determinism**: Because the Deny names specific ARNs (not deny-all-except), the expected answer is identical in every account, with no deployer exemption.

**Expected Tool Behavior:**

Passing tools:
- Return policy-granted-role and identity-reader for the 0-hop read answer
- Return starting-user for the 1-hop read answer
- Exclude both denied-reader and denied-admin from every answer

Failing tools:
- Omit policy-granted-role because it has no S3 statement in its identity policy
- Include denied-reader because its identity policy allows reading, missing the bucket-policy Deny
- Include denied-admin because it is an administrator, missing that an explicit resource-policy Deny overrides admin

#### Prevention Recommendations

This is a tool-testing scenario that validates detection capability rather than a real vulnerability. The following practices apply to managing bucket resource policies in production:

- Use S3 bucket policies with explicit `Deny` statements naming specific principal ARNs to lock sensitive buckets even against administrators, and remember that a resource-policy `Deny` always overrides any identity-based `Allow`
- Prefer naming the specific ARNs you want to deny over deny-all-except patterns, which can accidentally exempt the deploying principal and produce non-deterministic access
- Treat every principal with `AdministratorAccess` or `Action: *` as a potential reader of all S3 data unless a resource-policy Deny explicitly removes that access
- Use IAM Access Analyzer and tools that support reverse blast radius queries that combine identity and resource policies to answer "who can access this bucket?"
- Audit for principals that read a bucket only through its bucket policy, since their access is invisible from their identity policies alone
- Alert on `s3:GetObject` and `s3:PutObject` against sensitive buckets from principals the bucket policy was intended to deny

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `sts:AssumeRole` -- `starting-user` assuming `policy-granted-role`; the role session is what actually reaches the bucket
- `s3:GetObject` -- object retrieval from the sensitive bucket; monitor for reads by principals the bucket policy was meant to deny (requires S3 data event logging)
- `s3:ListBucket` -- bucket listing requests; monitor for enumeration of bucket contents
- `s3:PutObject` -- object written to the sensitive bucket; monitor for unexpected writers (requires S3 data event logging)
- `s3:PutBucketPolicy` -- changes to the bucket policy; critical when a Deny on a sensitive principal is removed or weakened

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [T1530 - Data from Cloud Storage Object](https://attack.mitre.org/techniques/T1530/) -- MITRE ATT&CK technique page
- [Bucket policies for Amazon S3](https://docs.aws.amazon.com/AmazonS3/latest/userguide/bucket-policies.html) -- AWS documentation
- [IAM policy evaluation logic](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html) -- how an explicit Deny overrides any Allow, identity or resource-based
