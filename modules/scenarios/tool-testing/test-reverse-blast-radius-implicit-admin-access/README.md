# Implicit Admin Access to Bucket

* **Category:** Tool Testing
* **Sub-Category:** reverse-blast-radius
* **Path Type:** one-hop
* **Target:** to-bucket
* **Points:** 20
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Tool testing scenario validating that reverse blast radius queries (who can read/write this bucket) include administrators whose access comes only from AdministratorAccess, with no S3-specific permissions
* **Terraform Variable:** `enable_tool_testing_test_reverse_blast_radius_implicit_admin_access`
* **Schema Version:** 4.9.0
* **MITRE Tactics:** TA0009 - Collection
* **MITRE Techniques:** T1530 - Data from Cloud Storage Object

## Objective

Your objective is to learn how to validate that a security tool includes implicit administrators in reverse blast radius answers by demonstrating that `pl-prod-rbr-ia-admin-user` and `pl-prod-rbr-ia-admin-role` can read and write the `pl-sensitive-data-rbr-ia-{account_id}-{suffix}` bucket purely through administrator permissions, alongside the explicit principals `pl-prod-rbr-ia-reader-user` and `pl-prod-rbr-ia-writer-user`.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-rbr-ia-reader-user`, `arn:aws:iam::{account_id}:user/pl-prod-rbr-ia-writer-user`, `arn:aws:iam::{account_id}:user/pl-prod-rbr-ia-admin-user`, and `arn:aws:iam::{account_id}:role/pl-prod-rbr-ia-admin-role`
- **Destination resource:** `arn:aws:s3:::pl-sensitive-data-rbr-ia-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-rbr-ia-reader-user`):
- `s3:GetObject` on `arn:aws:s3:::pl-sensitive-data-rbr-ia-*/*` -- explicit permission to read objects in the target bucket
- `s3:ListBucket` on `arn:aws:s3:::pl-sensitive-data-rbr-ia-*` -- explicit permission to list the target bucket

**Required** (`pl-prod-rbr-ia-writer-user`):
- `s3:PutObject` on `arn:aws:s3:::pl-sensitive-data-rbr-ia-*/*` -- explicit permission to write objects to the target bucket

**Required** (`pl-prod-rbr-ia-admin-user`):
- `*` on `*` -- AWS managed `AdministratorAccess` policy; no statement mentions S3 or this bucket

**Required** (`pl-prod-rbr-ia-admin-role`):
- `*` on `*` -- inline policy with `Action: *` on `Resource: *`; no statement mentions S3 or this bucket. The trust policy trusts only `ec2.amazonaws.com`, so no principal has an assume-role path into this role

**Helpful** (`pl-prod-rbr-ia-reader-user`):
- `sts:GetCallerIdentity` -- verify current identity

### Expected Results

**What this lab tests:** whether a reverse-blast-radius query for a bucket includes administrators whose access comes only from being an administrator, with no statement that names S3 or the bucket.

**Graph a correct tool should build**

| From | Edge | To |
|---|---|---|
| `pl-prod-rbr-ia-reader-user` | can_read | `pl-sensitive-data-rbr-ia-{account_id}-{suffix}` |
| `pl-prod-rbr-ia-writer-user` | can_write | `pl-sensitive-data-rbr-ia-{account_id}-{suffix}` |
| `pl-prod-rbr-ia-admin-user` | is_admin | true |
| `pl-prod-rbr-ia-admin-user` | can_read | `pl-sensitive-data-rbr-ia-{account_id}-{suffix}` |
| `pl-prod-rbr-ia-admin-user` | can_write | `pl-sensitive-data-rbr-ia-{account_id}-{suffix}` |
| `pl-prod-rbr-ia-admin-role` | is_admin | true |
| `pl-prod-rbr-ia-admin-role` | can_read | `pl-sensitive-data-rbr-ia-{account_id}-{suffix}` |
| `pl-prod-rbr-ia-admin-role` | can_write | `pl-sensitive-data-rbr-ia-{account_id}-{suffix}` |

**Expected answers**

| Case | Question | Must include | Must not include |
|---|---|---|---|
| rbr-ia-001 | Who can read the bucket directly? | `pl-prod-rbr-ia-reader-user`, `pl-prod-rbr-ia-admin-user`, `pl-prod-rbr-ia-admin-role` | `pl-prod-rbr-ia-writer-user`, `pl-prod-rbr-ia-no-access-user` |
| rbr-ia-002 | Who can write to the bucket directly? | `pl-prod-rbr-ia-writer-user`, `pl-prod-rbr-ia-admin-user`, `pl-prod-rbr-ia-admin-role` | `pl-prod-rbr-ia-reader-user`, `pl-prod-rbr-ia-no-access-user` |
| rbr-ia-003 | Which principals are administrators? | `pl-prod-rbr-ia-admin-user`, `pl-prod-rbr-ia-admin-role` | `pl-prod-rbr-ia-reader-user`, `pl-prod-rbr-ia-writer-user`, `pl-prod-rbr-ia-no-access-user` |

**Why:**
- **rbr-ia-001:** reader-user reads through an explicit statement; both admins can read every bucket because `Action: *` covers `s3:GetObject` and no bucket policy denies it. writer-user has only `s3:PutObject`; no-access-user has nothing.
- **rbr-ia-002:** writer-user writes through an explicit statement; both admins can write every bucket. reader-user can only read.
- **rbr-ia-003:** control for the two above. If this passes while they fail, the tool classifies admins correctly but does not turn that classification into resource access. admin-user uses a managed policy and admin-role an inline `*:*`, so a split result also shows which grant style was missed.

**Proven by:** `demo_attack.sh`, which reads and writes the bucket as each user with its own credentials, and uses `simulate-principal-policy` for the admin role (which nothing can assume), confirming each expected allow and deny.

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable test-reverse-blast-radius-implicit-admin-access-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-implicit-admin-access-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-ia-reader-user` | Explicit read access: `s3:GetObject` and `s3:ListBucket` on the target bucket (access keys provided) |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-ia-writer-user` | Explicit write access: `s3:PutObject` on the target bucket (access keys provided) |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-ia-admin-user` | Implicit access: `AdministratorAccess` managed policy, no S3 statements (access keys provided) |
| `arn:aws:iam::{account_id}:role/pl-prod-rbr-ia-admin-role` | Implicit access: inline `Action: *` on `Resource: *`, trust policy limited to `ec2.amazonaws.com` so nothing can assume it |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-ia-no-access-user` | Negative control with no policies; must not appear in any bucket access query (access keys provided) |
| `arn:aws:s3:::pl-sensitive-data-rbr-ia-{account_id}-{suffix}` | Target bucket containing test data, with no bucket policy |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve credentials, the region, and the bucket name from Terraform outputs
2. Confirm the identity of `reader-user`
3. As `writer-user`, write a probe object (`rbr-ia-demo/writer-probe.txt`) successfully and confirm that reading it back is denied
4. As `reader-user`, list the `rbr-ia-demo/` prefix and read the probe object successfully, and confirm that writing is denied
5. As `admin-user`, read the probe object and write `rbr-ia-demo/admin-probe.txt`; both succeed even though the user has no S3-specific permissions
6. As `no-access-user` (negative control), confirm that list, read, and write are all denied
7. Run `iam:SimulatePrincipalPolicy` for `admin-role` (which nothing can assume, so it is evaluated with the cleanup admin credentials) to confirm it is allowed `s3:GetObject` and `s3:PutObject` on the bucket objects
8. Print the observed access matrix and the expected reverse blast radius truth table: `can_read` = reader-user, admin-user, admin-role; `can_write` = writer-user, admin-user, admin-role; `no-access-user` in neither. The script exits non-zero if any observed result differs from the expected ground truth

#### Resources Created by Attack Script

- Probe objects written to the target bucket under the `rbr-ia-demo/` prefix: `rbr-ia-demo/writer-probe.txt` and `rbr-ia-demo/admin-probe.txt` (removed by the cleanup script)
- A temporary local file `/tmp/rbr-ia-probe-body.txt` used as the upload body (removed when the demo exits and again by the cleanup script)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo test-reverse-blast-radius-implicit-admin-access
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-implicit-admin-access-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup test-reverse-blast-radius-implicit-admin-access
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-implicit-admin-access-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable test-reverse-blast-radius-implicit-admin-access-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-implicit-admin-access-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

A security analysis platform or CSPM tool answering a reverse blast radius query on the target bucket should treat administrator status as access to every resource, even when the graph has no explicit edge from an administrator to the bucket. The tool should identify:

1. **Explicit read access**: `pl-prod-rbr-ia-reader-user` via `s3:GetObject` and `s3:ListBucket` statements naming the bucket
2. **Explicit write access**: `pl-prod-rbr-ia-writer-user` via an `s3:PutObject` statement naming the bucket
3. **Implicit administrator access (user)**: `pl-prod-rbr-ia-admin-user` via the `AdministratorAccess` managed policy, with no S3-specific statement
4. **Implicit administrator access (role)**: `pl-prod-rbr-ia-admin-role` via an inline `Action: *` on `Resource: *` policy, with no S3-specific statement and no principal able to assume it
5. **No false positives**: `pl-prod-rbr-ia-no-access-user` has no permissions and must not appear in either answer

**Expected Query Results:**

Query: "Who can read bucket `pl-sensitive-data-rbr-ia-{account_id}-{suffix}`?"

```
- arn:aws:iam::{account_id}:user/pl-prod-rbr-ia-reader-user (explicit)
- arn:aws:iam::{account_id}:user/pl-prod-rbr-ia-admin-user (implicit administrator)
- arn:aws:iam::{account_id}:role/pl-prod-rbr-ia-admin-role (implicit administrator)
```

Query: "Who can write to bucket `pl-sensitive-data-rbr-ia-{account_id}-{suffix}`?"

```
- arn:aws:iam::{account_id}:user/pl-prod-rbr-ia-writer-user (explicit)
- arn:aws:iam::{account_id}:user/pl-prod-rbr-ia-admin-user (implicit administrator)
- arn:aws:iam::{account_id}:role/pl-prod-rbr-ia-admin-role (implicit administrator)
```

**Tool Testing Focus:**

This scenario specifically tests:

1. **Administrator handling**: Does the tool include administrators in "who can access X" answers even though its graph deliberately does not create an edge from every administrator to every resource?
2. **Policy style coverage**: Does the tool recognize both a managed `AdministratorAccess` attachment and an inline `Action: *` wildcard as administrator-equivalent?
3. **Role without inbound edges**: Does the tool still report `admin-role` when no principal can assume it?
4. **Read versus write separation**: Does the tool keep `reader-user` out of the write answer and `writer-user` out of the read answer?
5. **Negative control**: Does the tool correctly exclude `no-access-user`?

**Expected Tool Behavior:**

Passing tools:
- Return all three principals for `can_read` and all three for `can_write`
- Distinguish explicit access from implicit administrator access
- Exclude `no-access-user` from both answers

Failing tools:
- Return only `reader-user` for `can_read` and only `writer-user` for `can_write`, omitting administrators
- Include `admin-user` but miss `admin-role` (or the reverse)
- Include `no-access-user`, `writer-user` in the read answer, or `reader-user` in the write answer

#### Prevention Recommendations

This is a tool-testing scenario that validates detection capability rather than a real vulnerability. The following practices apply to managing administrator access and sensitive buckets in production:

- Treat every principal with `AdministratorAccess` or `Action: *` on `Resource: *` as having access to all S3 data, and keep that set as small as possible
- Use IAM Access Analyzer and tools that support reverse blast radius queries to answer "who can access this bucket?" including implicit administrators
- Add S3 bucket policies with explicit denies (for example, deny all except approved principals via `aws:PrincipalArn` conditions) to restrict even administrators on sensitive buckets
- Use SCPs and permission boundaries to cap what administrator-style principals can do with sensitive data stores
- Audit roles with wildcard inline policies, which are easier to miss than managed `AdministratorAccess` attachments
- Alert on `s3:GetObject` and `s3:PutObject` against sensitive buckets from administrator principals

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `s3:GetObject` -- object retrieval from the sensitive bucket; monitor for access by administrator principals that have no business need for the data (requires S3 data event logging)
- `s3:PutObject` -- object written to the sensitive bucket; monitor for writes by unexpected principals (requires S3 data event logging)
- `s3:ListBucket` -- bucket listing requests; monitor for enumeration of bucket contents
- `iam:CreateAccessKey` -- new access keys for administrator users such as `pl-prod-rbr-ia-admin-user`

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [T1530 - Data from Cloud Storage Object](https://attack.mitre.org/techniques/T1530/) -- MITRE ATT&CK technique page
- [AWS managed policy: AdministratorAccess](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/AdministratorAccess.html) -- AWS documentation
