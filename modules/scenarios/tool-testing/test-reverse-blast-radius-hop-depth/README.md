# Reverse Blast Radius by Hop Depth to Bucket

* **Category:** Tool Testing
* **Sub-Category:** reverse-blast-radius
* **Path Type:** multi-hop
* **Target:** to-bucket
* **Points:** 30
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Tool testing scenario validating that reverse blast radius queries return principals at every hop depth (direct, 1 hop, 2 hops) and showing that a query limited to N hops omits shallower and deeper principals
* **Terraform Variable:** `enable_tool_testing_test_reverse_blast_radius_hop_depth`
* **Schema Version:** 4.9.0
* **MITRE Tactics:** TA0009 - Collection, TA0004 - Privilege Escalation
* **MITRE Techniques:** T1530 - Data from Cloud Storage Object, T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to validate that a security tool answers "who can read this bucket" correctly at every hop depth by demonstrating that `pl-prod-rbr-hd-user-a` and `pl-prod-rbr-hd-role-r1` can read the `pl-sensitive-data-rbr-hd-{account_id}-{suffix}` bucket directly, while `pl-prod-rbr-hd-user-b`, `pl-prod-rbr-hd-role-r2`, and `pl-prod-rbr-hd-user-c` can only reach it through one or two `sts:AssumeRole` hops into `pl-prod-rbr-hd-role-r1`.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-rbr-hd-user-a` (depth 0), `arn:aws:iam::{account_id}:user/pl-prod-rbr-hd-user-b` (depth 1), and `arn:aws:iam::{account_id}:user/pl-prod-rbr-hd-user-c` (depth 2)
- **Destination resource:** `arn:aws:s3:::pl-sensitive-data-rbr-hd-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-rbr-hd-user-a`):
- `s3:GetObject` on `arn:aws:s3:::pl-sensitive-data-rbr-hd-*/*` -- direct permission to read objects from the target bucket (depth 0)
- `s3:ListBucket` on `arn:aws:s3:::pl-sensitive-data-rbr-hd-*` -- direct permission to list the target bucket (depth 0)

**Required** (`pl-prod-rbr-hd-role-r1`):
- `s3:GetObject` on `arn:aws:s3:::pl-sensitive-data-rbr-hd-*/*` -- direct permission to read objects from the target bucket (depth 0; inherited by every principal that can assume this role)
- `s3:ListBucket` on `arn:aws:s3:::pl-sensitive-data-rbr-hd-*` -- direct permission to list the target bucket (depth 0)

**Required** (`pl-prod-rbr-hd-user-b`):
- `sts:AssumeRole` on `arn:aws:iam::{account_id}:role/pl-prod-rbr-hd-role-r1` -- one hop to the bucket-reading role (depth 1)

**Required** (`pl-prod-rbr-hd-role-r2`):
- `sts:AssumeRole` on `arn:aws:iam::{account_id}:role/pl-prod-rbr-hd-role-r1` -- one hop to the bucket-reading role (depth 1)

**Required** (`pl-prod-rbr-hd-user-c`):
- `sts:AssumeRole` on `arn:aws:iam::{account_id}:role/pl-prod-rbr-hd-role-r2` -- first of two hops to the bucket-reading role (depth 2)

**Helpful** (`pl-prod-rbr-hd-user-a`):
- `sts:GetCallerIdentity` -- verify current identity

### Expected Results

**What this lab tests:** whether a reverse-blast-radius query for a bucket returns the right principals at each hop depth, and whether a query limited to one depth silently omits principals at other depths.

**Graph a correct tool should build**

| From | Edge | To |
|---|---|---|
| `pl-prod-rbr-hd-user-a` | can_read | `pl-sensitive-data-rbr-hd-{account_id}-{suffix}` |
| `pl-prod-rbr-hd-role-r1` | can_read | `pl-sensitive-data-rbr-hd-{account_id}-{suffix}` |
| `pl-prod-rbr-hd-user-b` | can_assume | `pl-prod-rbr-hd-role-r1` |
| `pl-prod-rbr-hd-role-r2` | can_assume | `pl-prod-rbr-hd-role-r1` |
| `pl-prod-rbr-hd-user-c` | can_assume | `pl-prod-rbr-hd-role-r2` |

**Expected answers**

| Case | Question | Must include | Must not include |
|---|---|---|---|
| rbr-hd-001 | Who can read the bucket directly (0 hops)? | `pl-prod-rbr-hd-user-a`, `pl-prod-rbr-hd-role-r1` | `pl-prod-rbr-hd-user-b`, `pl-prod-rbr-hd-role-r2`, `pl-prod-rbr-hd-user-c` |
| rbr-hd-002 | Who can read it by assuming exactly one role (1 hop)? | `pl-prod-rbr-hd-user-b`, `pl-prod-rbr-hd-role-r2` | `pl-prod-rbr-hd-user-a`, `pl-prod-rbr-hd-user-c` |
| rbr-hd-003 | Who can read it by chaining exactly two roles (2 hops)? | `pl-prod-rbr-hd-user-c` | `pl-prod-rbr-hd-user-a`, `pl-prod-rbr-hd-user-b` |
| rbr-hd-004 | Who can read it by any means, up to 2 hops? | all five principals | (none) |

**Why:**
- **rbr-hd-001:** only user-a and role-r1 hold `s3:GetObject`/`s3:ListBucket` on the bucket; the others hold only `sts:AssumeRole`.
- **rbr-hd-002:** user-b and role-r2 each assume role-r1, which reads the bucket. user-a has access but assumes nothing, so a 1-hop-only query correctly omits it -- which is exactly why one depth is not a complete answer.
- **rbr-hd-003:** user-c reaches the bucket only through role-r2 and then role-r1.
- **rbr-hd-004:** all five can read the bucket; the complete answer is the union across depths 0, 1, and 2.

**Proven by:** `demo_attack.sh`, which reads the bucket as user-a directly, then as user-b and user-c only after the required `sts:AssumeRole` hops, failing each direct read that should be denied.

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable test-reverse-blast-radius-hop-depth-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-hop-depth-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-hd-user-a` | Depth 0 user with direct S3 read permissions on the bucket (access keys provided) |
| `arn:aws:iam::{account_id}:role/pl-prod-rbr-hd-role-r1` | Depth 0 role with direct S3 read permissions; trusts only user-b and role-r2 |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-hd-user-b` | Depth 1 user with only `sts:AssumeRole` on role-r1 (access keys provided) |
| `arn:aws:iam::{account_id}:role/pl-prod-rbr-hd-role-r2` | Depth 1 role with only `sts:AssumeRole` on role-r1; trusts only user-c |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-hd-user-c` | Depth 2 user with only `sts:AssumeRole` on role-r2 (access keys provided) |
| `arn:aws:s3:::pl-sensitive-data-rbr-hd-{account_id}-{suffix}` | Target S3 bucket containing `sensitive-data.txt`; no bucket policy |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve credentials and the bucket name from Terraform outputs
2. As user-a (depth 0), list and read the bucket directly
3. As user-b, confirm that direct bucket access is denied, then assume role-r1 (1 hop) and read the bucket; the role-r1 session also proves role-r1 reads the bucket with no further hop (depth 0)
4. As user-c, confirm that direct bucket access is denied, then assume role-r2 (hop 1), confirm role-r2 itself is denied, chain into role-r1 (hop 2) and read the bucket; this proves role-r2 is depth 1 and user-c is depth 2
5. Print the observed hop depth per principal (the script exits non-zero if any observation differs from expectation)
6. Print the expected reverse blast radius results per depth: exactly 0 hops = user-a, role-r1; exactly 1 hop = user-b, role-r2; exactly 2 hops = user-c; cumulative <= 1 hop = user-a, role-r1, user-b, role-r2; cumulative <= 2 hops = all five principals

The "exactly N hops" and "up to N hops" distinction is the crux of this lab. A query for exactly 0 hops returns only the direct principals. A query for exactly 1 hop returns the principals one assume-role away but not the direct ones. Deeper chains need another query. A complete answer needs one query per depth, or a single cumulative "up to 2 hops" query.

#### Resources Created by Attack Script

- Temporary STS session credentials for role-r1 (assumed by user-b and by the role-r2 session) and role-r2 (assumed by user-c); these expire on their own
- Temporary file `/tmp/rbr-hd-sensitive.txt` downloaded from the sensitive bucket (removed by the cleanup script)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo test-reverse-blast-radius-hop-depth
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-hop-depth-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup test-reverse-blast-radius-hop-depth
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-hop-depth-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable test-reverse-blast-radius-hop-depth-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-hop-depth-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

A properly configured security analysis platform or CSPM tool performing a reverse blast radius query on the bucket `pl-sensitive-data-rbr-hd-{account_id}-{suffix}` should identify:

1. **Depth 0 (direct)**: `pl-prod-rbr-hd-user-a` and `pl-prod-rbr-hd-role-r1` hold `s3:GetObject` and `s3:ListBucket` on the bucket through their own IAM policies
2. **Depth 1**: `pl-prod-rbr-hd-user-b` (user-b -> role-r1) and `pl-prod-rbr-hd-role-r2` (role-r2 -> role-r1) reach the bucket through one `sts:AssumeRole` hop
3. **Depth 2**: `pl-prod-rbr-hd-user-c` (user-c -> role-r2 -> role-r1) reaches the bucket through two chained `sts:AssumeRole` hops
4. **Both sides of each hop**: the identity policy on the caller allows `sts:AssumeRole` and the role trust policy names the caller

**Expected Query Results (truth table):**

| Query | Expected principals |
| -- | -- |
| Exactly 0 hops | user-a, role-r1 |
| Exactly 1 hop | user-b, role-r2 |
| Exactly 2 hops | user-c |
| Up to 1 hop (cumulative) | user-a, role-r1, user-b, role-r2 |
| Up to 2 hops (cumulative) | user-a, role-r1, user-b, role-r2, user-c |

**Exactly N vs. up to N:** a tool that treats the hop count as an exact depth returns a disjoint set per query. A 0-hop query returns only the direct principals. A 1-hop query returns user-b and role-r2 but NOT user-a and role-r1, because those need zero hops. A 2-hop query returns only user-c. Anyone who runs a single query at one depth gets a partial answer. The complete answer is the union of every depth, which is what a cumulative "up to N hops" query returns. Tools and analysts need to know which semantics a query uses, and must pick N at least as large as the deepest chain in the environment (2 here).

**Tool Testing Focus:**

1. **Depth Semantics**: Does the tool document and implement hop limits as "exactly N" or "up to N", and does the result match?
2. **Multi-Hop Traversal**: Does the tool follow role chaining (user-c -> role-r2 -> role-r1) rather than stopping after one assume-role edge?
3. **Direct Principals at Depth 0**: Does a 0-hop query still return the roles and users that hold the permission themselves?
4. **Completeness**: Does a cumulative query with enough hops return all five principals?

**Expected Tool Behavior:**

Passing tools:
- Return exactly user-a and role-r1 for 0 hops, user-b and role-r2 for 1 hop, and user-c for 2 hops (or the cumulative equivalents)
- Return all five principals when the hop limit is 2 or more
- Make clear which hop depth each principal was found at

Failing tools:
- Return only direct principals regardless of the hop setting
- Return user-b and role-r2 but silently drop user-c at 2 hops
- Mix depths so that a 1-hop query includes direct principals without saying so
- Cap traversal at one assume-role edge

#### Prevention Recommendations

This is a tool-testing scenario, so the guidance below applies to managing access to sensitive buckets in real environments:

- Treat any role that holds sensitive S3 permissions as reachable by everything that can assume it, directly or transitively, and review its trust policy accordingly
- Restrict role trust policies to specific principal ARNs (as this lab does) rather than account root, and add conditions such as `aws:PrincipalOrgID`, `sts:ExternalId`, or MFA where applicable
- Avoid role chains deeper than necessary; every extra assume-role hop widens the set of principals that can reach the bucket and is easy to miss during review
- Use IAM Access Analyzer and policy simulation to validate who can reach critical buckets, including through role chaining
- Run reverse blast radius queries for sensitive resources with a hop limit at least as deep as your longest role chain, and confirm whether your tool uses "exactly N" or "up to N" semantics
- Use SCPs or permission boundaries to cap which roles can be assumed from which principals

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `sts:AssumeRole` -- role assumption into `pl-prod-rbr-hd-role-r1` by user-b or by a role-r2 session, and into `pl-prod-rbr-hd-role-r2` by user-c; monitor for chained assumptions where the caller is itself an assumed-role session
- `s3:GetObject` -- object retrieval from the sensitive bucket; monitor for access by unexpected principals or assumed-role sessions
- `s3:ListBucket` -- bucket listing requests; monitor for enumeration of bucket contents from direct principals and assumed-role sessions

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [T1530 - Data from Cloud Storage Object](https://attack.mitre.org/techniques/T1530/) -- MITRE ATT&CK technique for collecting data from cloud storage
- [T1078.004 - Valid Accounts: Cloud Accounts](https://attack.mitre.org/techniques/T1078/004/) -- MITRE ATT&CK technique for abusing valid cloud credentials
