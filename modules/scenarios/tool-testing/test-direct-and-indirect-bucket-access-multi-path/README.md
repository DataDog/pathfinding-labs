# Direct and Indirect Bucket Access via Multiple Reachability Paths

* **Category:** Tool Testing
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Tool testing scenario with 5 principals demonstrating direct S3 bucket access alongside two distinct indirect-access mechanisms (sts:AssumeRole and iam:UpdateAssumeRolePolicy trust-policy bypass) in a single module, to validate that graph/CSPM tools surface ALL reachable principals for a target bucket at once, not just the ones with direct policy grants
* **Terraform Variable:** `enable_tool_testing_test_direct_and_indirect_bucket_access_multi_path`
* **Schema Version:** 4.7.1
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0009 - Collection
* **MITRE Techniques:** T1548 - Abuse Elevation Control Mechanism, T1078.004 - Valid Accounts: Cloud Accounts, T1530 - Data from Cloud Storage Object

## Objective

Your objective is to learn how to validate that a security tool can enumerate all three independent reachability paths to a shared S3 bucket -- direct policy access from `pl-prod-dimp-user-direct`, indirect access from `pl-prod-dimp-user-assumer` via an already-trusting role, and indirect access from `pl-prod-dimp-user-trustbypass` via a role that must first be re-trusted through `iam:UpdateAssumeRolePolicy` -- all converging on the `pl-dimp-bucket-{account_id}-{suffix}` bucket.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-dimp-user-direct` (direct path), `arn:aws:iam::{account_id}:user/pl-prod-dimp-user-assumer` (indirect, no escalation needed), and `arn:aws:iam::{account_id}:user/pl-prod-dimp-user-trustbypass` (indirect, requires trust-policy escalation)
- **Destination resource:** `arn:aws:s3:::pl-dimp-bucket-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-dimp-user-direct`):
- `s3:GetObject` on `arn:aws:s3:::pl-dimp-bucket-{account_id}-{suffix}/*` -- direct permission to read objects from the target bucket
- `s3:PutObject` on `arn:aws:s3:::pl-dimp-bucket-{account_id}-{suffix}/*` -- direct permission to write objects to the target bucket
- `s3:ListBucket` on `arn:aws:s3:::pl-dimp-bucket-{account_id}-{suffix}` -- direct permission to list the target bucket

**Required** (`pl-prod-dimp-user-assumer`):
- `sts:AssumeRole` on `arn:aws:iam::{account_id}:role/pl-prod-dimp-role-trusted` -- can assume a role that already trusts it and already has bucket access; no escalation step required

**Required** (`pl-prod-dimp-role-trusted`):
- `s3:GetObject` on `arn:aws:s3:::pl-dimp-bucket-{account_id}-{suffix}/*` -- inherited by `pl-prod-dimp-user-assumer` via role assumption
- `s3:PutObject` on `arn:aws:s3:::pl-dimp-bucket-{account_id}-{suffix}/*` -- inherited by `pl-prod-dimp-user-assumer` via role assumption
- `s3:ListBucket` on `arn:aws:s3:::pl-dimp-bucket-{account_id}-{suffix}` -- inherited by `pl-prod-dimp-user-assumer` via role assumption

**Required** (`pl-prod-dimp-user-trustbypass`):
- `iam:UpdateAssumeRolePolicy` on `arn:aws:iam::{account_id}:role/pl-prod-dimp-role-untrusted` -- can rewrite the role's trust policy to add itself as a trusted principal
- `sts:AssumeRole` on `arn:aws:iam::{account_id}:role/pl-prod-dimp-role-untrusted` -- can assume the role only after the trust policy has been rewritten to include it

**Required** (`pl-prod-dimp-role-untrusted`):
- `s3:GetObject` on `arn:aws:s3:::pl-dimp-bucket-{account_id}-{suffix}/*` -- inherited by `pl-prod-dimp-user-trustbypass` after the trust-policy rewrite
- `s3:PutObject` on `arn:aws:s3:::pl-dimp-bucket-{account_id}-{suffix}/*` -- inherited by `pl-prod-dimp-user-trustbypass` after the trust-policy rewrite
- `s3:ListBucket` on `arn:aws:s3:::pl-dimp-bucket-{account_id}-{suffix}` -- inherited by `pl-prod-dimp-user-trustbypass` after the trust-policy rewrite

**Helpful** (`pl-prod-dimp-user-direct`):
- `sts:GetCallerIdentity` -- verify assumed identity

**Helpful** (`pl-prod-dimp-user-assumer`):
- `sts:GetCallerIdentity` -- verify assumed identity

**Helpful** (`pl-prod-dimp-user-trustbypass`):
- `sts:GetCallerIdentity` -- verify assumed identity

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable test-direct-and-indirect-bucket-access-multi-path
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-direct-and-indirect-bucket-access-multi-path` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-dimp-user-direct` | User with a direct IAM policy grant on the target bucket (access keys provided) |
| `arn:aws:iam::{account_id}:user/pl-prod-dimp-user-assumer` | User whose only path to the bucket is `sts:AssumeRole` on an already-trusting role (access keys provided) |
| `arn:aws:iam::{account_id}:role/pl-prod-dimp-role-trusted` | Role with bucket access whose trust policy already permits `pl-prod-dimp-user-assumer` |
| `arn:aws:iam::{account_id}:user/pl-prod-dimp-user-trustbypass` | User that must rewrite a role's trust policy before it can assume it (access keys provided) |
| `arn:aws:iam::{account_id}:role/pl-prod-dimp-role-untrusted` | Role with bucket access whose trust policy initially trusts only `ec2.amazonaws.com` |
| `arn:aws:s3:::pl-dimp-bucket-{account_id}-{suffix}` | Target S3 bucket reachable via all three paths |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve credentials for all three starting users and the bucket name from Terraform outputs
2. Verify `pl-prod-dimp-user-direct`'s identity and demonstrate direct bucket read/write/list access
3. Verify `pl-prod-dimp-user-assumer`'s identity, confirm it lacks direct bucket access, assume `pl-prod-dimp-role-trusted` (whose trust policy already permits it), and demonstrate bucket access via the assumed role
4. Verify `pl-prod-dimp-user-trustbypass`'s identity, confirm the initial `sts:AssumeRole` attempt against `pl-prod-dimp-role-untrusted` fails (the role trusts only `ec2.amazonaws.com`), call `iam:UpdateAssumeRolePolicy` to add itself as a trusted principal, wait for IAM propagation, then successfully assume the role and demonstrate bucket access
5. Print a summary comparing all three reachability paths and the expected "who can access this bucket" result set

#### Resources Created by Attack Script

- `/tmp/dimp-direct.txt` -- object downloaded from the bucket using `pl-prod-dimp-user-direct`'s direct credentials
- `/tmp/dimp-trusted-role.txt` -- object downloaded from the bucket using `pl-prod-dimp-role-trusted`'s assumed credentials
- `/tmp/dimp-untrusted-role.txt` -- object downloaded from the bucket using `pl-prod-dimp-role-untrusted`'s assumed credentials (post trust-policy rewrite)
- Modified trust policy on `pl-prod-dimp-role-untrusted` (adds `pl-prod-dimp-user-trustbypass` as a trusted principal; reverted by cleanup)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo test-direct-and-indirect-bucket-access-multi-path
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-direct-and-indirect-bucket-access-multi-path` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup test-direct-and-indirect-bucket-access-multi-path
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-direct-and-indirect-bucket-access-multi-path` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable test-direct-and-indirect-bucket-access-multi-path
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-direct-and-indirect-bucket-access-multi-path` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

A properly configured graph-based security tool or CSPM platform performing a reverse blast radius query on the bucket should identify all three independent reachability paths, not just the direct one:

1. **Direct Access Path**: `pl-prod-dimp-user-direct` has a direct IAM policy grant on the bucket
2. **Indirect Access Path (no escalation needed)**: `pl-prod-dimp-user-assumer` can reach the bucket via `sts:AssumeRole` on `pl-prod-dimp-role-trusted`, a role whose trust policy already names it -- this access is live today, with no additional action required
3. **Indirect Access Path (escalation required)**: `pl-prod-dimp-user-trustbypass` holds `iam:UpdateAssumeRolePolicy` and `sts:AssumeRole` on `pl-prod-dimp-role-untrusted`, a role whose trust policy currently names only `ec2.amazonaws.com` -- this is a *latent* path that only becomes exercisable once the user actively rewrites the trust policy. A tool that only models today's trust relationships and ignores the identity-based permission to *change* those trust relationships will completely miss this principal.
4. **Complete Access List**: When asked "Who has access to `pl-dimp-bucket-{account_id}-{suffix}`?", the tool should return all three starting users plus both intermediate roles

**Expected Query Results:**

Query: "Who can access bucket `pl-dimp-bucket-{account_id}-{suffix}`?"

Expected Response:
```
- arn:aws:iam::{account_id}:user/pl-prod-dimp-user-direct       (direct access)
- arn:aws:iam::{account_id}:user/pl-prod-dimp-user-assumer      (indirect via role/pl-prod-dimp-role-trusted, no escalation needed)
- arn:aws:iam::{account_id}:role/pl-prod-dimp-role-trusted      (direct access)
- arn:aws:iam::{account_id}:user/pl-prod-dimp-user-trustbypass  (indirect via role/pl-prod-dimp-role-untrusted, requires trust-policy self-modification)
- arn:aws:iam::{account_id}:role/pl-prod-dimp-role-untrusted    (direct access)
```

**Tool Testing Focus:**

This scenario specifically tests:

1. **Graph Traversal Capability**: Can the tool traverse existing `sts:AssumeRole` + trust-policy relationships to identify indirect access that requires no further action?
2. **Privilege-Escalation-Aware Traversal**: Can the tool recognize that `iam:UpdateAssumeRolePolicy` on a role, combined with `sts:AssumeRole` on that same role, constitutes a reachable path even though the role's *current* trust policy excludes the user?
3. **Complete Path Enumeration**: Does the tool identify ALL principals with access -- direct, indirect-and-live, and indirect-but-requiring-escalation -- in a single query, rather than surfacing only a subset?
4. **False Dead-End Avoidance**: Does the tool incorrectly treat `pl-prod-dimp-role-untrusted`'s initial trust policy (which excludes `pl-prod-dimp-user-trustbypass`) as proof that the user cannot reach the role, ignoring the user's ability to modify that trust policy itself?

**Expected Tool Behavior:**

Passing tools:
- Identify all three starting users as having bucket access, distinguishing direct vs. indirect
- Distinguish the two indirect mechanisms: role assumption via an already-correct trust policy vs. role assumption that requires a trust-policy rewrite first
- Include both `pl-prod-dimp-role-trusted` and `pl-prod-dimp-role-untrusted` as principals with direct access
- Flag `pl-prod-dimp-user-trustbypass`'s access as requiring an active privilege-escalation step, not treat it as already-granted

Failing tools:
- Only identify `pl-prod-dimp-user-direct` (direct access only)
- Identify `pl-prod-dimp-user-assumer` but miss `pl-prod-dimp-user-trustbypass` because the current trust policy on `pl-prod-dimp-role-untrusted` does not name it
- Fail to model `iam:UpdateAssumeRolePolicy` as a mechanism for gaining new trust relationships
- Provide incomplete results for "who has access" queries that omit any of the three starting principals

#### Prevention Recommendations

While this is a tool-testing scenario designed to validate detection capabilities rather than demonstrate a real vulnerability, the following best practices apply to managing S3 bucket access and IAM trust policies in production environments:

- Use AWS IAM Access Analyzer to continuously monitor and validate S3 bucket access permissions
- Restrict `iam:UpdateAssumeRolePolicy` to a small set of break-glass administrative principals; treat it as equivalent in sensitivity to `iam:AttachRolePolicy`
- Regularly audit IAM trust relationships to understand complete access paths to sensitive resources, including who can *modify* those trust relationships
- Use S3 bucket policies in addition to IAM policies to implement defense in depth
- Monitor CloudTrail for `iam:UpdateAssumeRolePolicy` calls against roles with access to sensitive resources
- Implement SCPs (Service Control Policies) at the organization level to deny `iam:UpdateAssumeRolePolicy` outside of designated administrative accounts or roles
- Use tools that support reverse blast radius queries capable of modeling privilege-escalation-dependent (not just currently-live) reachability

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `iam:UpdateAssumeRolePolicy` -- trust policy modification on `pl-prod-dimp-role-untrusted`; critical when the modified role has access to sensitive resources
- `sts:AssumeRole` -- role assumption by `pl-prod-dimp-user-assumer` on `pl-prod-dimp-role-trusted`, and by `pl-prod-dimp-user-trustbypass` on `pl-prod-dimp-role-untrusted` following the trust-policy rewrite
- `s3:GetObject` -- object retrieval from the target bucket; monitor for access by unexpected principals or assumed-role sessions
- `s3:PutObject` -- object writes to the target bucket; monitor for writes from unexpected principals or assumed-role sessions
- `s3:ListBucket` -- bucket listing requests; monitor for enumeration from all three reachability paths

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
