# Reverse Blast Radius Assume-Role Edge Correctness

* **Category:** Tool Testing
* **Sub-Category:** edge-case-detection
* **Path Type:** one-hop
* **Target:** to-bucket
* **Points:** 30
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Tool testing scenario validating that the can-assume edge is only drawn when BOTH the caller's identity policy and the role trust policy allow the assumption (and that a root-trust role defers to identity policies)
* **Terraform Variable:** `enable_tool_testing_test_reverse_blast_radius_assume_role_edges`
* **Schema Version:** 4.9.0
* **MITRE Tactics:** TA0009 - Collection
* **MITRE Techniques:** T1530 - Data from Cloud Storage Object

## Objective

Your objective is to learn how to validate that a security tool draws the `sts:AssumeRole` edge correctly by demonstrating that only `pl-prod-rbr-are-both` and `pl-prod-rbr-are-root-with-identity` can assume one of the bucket-reading roles (`pl-prod-rbr-are-target-role` and `pl-prod-rbr-are-target-role-root`) and reach the `pl-sensitive-data-rbr-are-{account_id}-{suffix}` bucket, while `pl-prod-rbr-are-identity-only`, `pl-prod-rbr-are-trust-only`, and `pl-prod-rbr-are-root-no-identity` each satisfy only half of the same-account assume-role requirement and cannot.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-rbr-are-both` (identity + explicit trust) and `arn:aws:iam::{account_id}:user/pl-prod-rbr-are-root-with-identity` (identity + root trust), plus three users that each satisfy only one half of the requirement
- **Destination resource:** `arn:aws:s3:::pl-sensitive-data-rbr-are-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-rbr-are-both`):
- `sts:AssumeRole` on `arn:aws:iam::{account_id}:role/pl-prod-rbr-are-target-role` -- identity permission to assume the bucket-reading role, whose trust policy also names this user (both halves satisfied)

**Required** (`pl-prod-rbr-are-root-with-identity`):
- `sts:AssumeRole` on `arn:aws:iam::{account_id}:role/pl-prod-rbr-are-target-role-root` -- identity permission to assume the root-trust bucket-reading role, whose `root` trust defers to this identity permission (both halves satisfied)

**Required** (`pl-prod-rbr-are-identity-only`):
- `sts:AssumeRole` on `arn:aws:iam::{account_id}:role/pl-prod-rbr-are-target-role` -- identity permission only; `target-role`'s trust policy does NOT name this user, so the assumption is denied

**Required** (`pl-prod-rbr-are-trust-only`):
- `sts:GetCallerIdentity` -- harmless recon only; this user is named in `target-role`'s trust policy but holds no identity `sts:AssumeRole` permission, so the assumption is denied

**Required** (`pl-prod-rbr-are-root-no-identity`):
- `sts:GetCallerIdentity` -- harmless recon only; this user is covered by `target-role-root`'s `root` trust but holds no identity `sts:AssumeRole` permission, which the root trust defers to, so the assumption is denied

### Expected Results

**What this lab tests:** whether a tool draws the can_assume edge only when both halves of a same-account AssumeRole are satisfied (caller identity permission AND role trust), and treats a root-trust role as deferring to identity policies.

**Graph a correct tool should build**

| From | Edge | To |
|---|---|---|
| `pl-prod-rbr-are-target-role` | can_read | `pl-sensitive-data-rbr-are-{account_id}-{suffix}` |
| `pl-prod-rbr-are-target-role-root` | can_read | `pl-sensitive-data-rbr-are-{account_id}-{suffix}` |
| `pl-prod-rbr-are-both` | can_assume | `pl-prod-rbr-are-target-role` |
| `pl-prod-rbr-are-root-with-identity` | can_assume | `pl-prod-rbr-are-target-role-root` |

**Expected answers**

| Case | Question | Must include | Must not include |
|---|---|---|---|
| rbr-are-001 | Who can read the bucket directly (0 hops)? | `pl-prod-rbr-are-target-role`, `pl-prod-rbr-are-target-role-root` | `pl-prod-rbr-are-both`, `pl-prod-rbr-are-identity-only`, `pl-prod-rbr-are-trust-only`, `pl-prod-rbr-are-root-with-identity`, `pl-prod-rbr-are-root-no-identity` |
| rbr-are-002 | Who can read it by assuming exactly one role (1 hop)? | `pl-prod-rbr-are-both`, `pl-prod-rbr-are-root-with-identity` | `pl-prod-rbr-are-identity-only`, `pl-prod-rbr-are-trust-only`, `pl-prod-rbr-are-root-no-identity` |

**Why:**
- **rbr-are-001:** only the two target roles hold S3 read on the bucket; the five users hold no S3 directly.
- **rbr-are-002:** are-both has identity sts:AssumeRole AND is named in target-role's trust. are-root-with-identity has identity sts:AssumeRole on target-role-root, whose root trust defers to that identity permission. are-identity-only has the identity permission but is not trusted (false positive if a tool reads only identity policies). are-trust-only is trusted but lacks the identity permission (false positive if a tool reads only trust policies). are-root-no-identity is covered by root trust but has no identity permission, so it still cannot assume.

**Proven by:** `demo_attack.sh`, which attempts the assume-and-read as each of the five users and confirms only are-both and are-root-with-identity succeed.

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable test-reverse-blast-radius-assume-role-edges-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-assume-role-edges-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-are-both` | Satisfies both halves (identity `sts:AssumeRole` + named in `target-role` trust); can assume and read (access keys provided) |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-are-identity-only` | Has identity `sts:AssumeRole` on `target-role` but is not named in its trust; cannot assume (access keys provided) |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-are-trust-only` | Named in `target-role` trust but has no identity `sts:AssumeRole`; cannot assume (access keys provided) |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-are-root-with-identity` | Has identity `sts:AssumeRole` on `target-role-root`, whose `root` trust defers to it; can assume and read (access keys provided) |
| `arn:aws:iam::{account_id}:user/pl-prod-rbr-are-root-no-identity` | Covered by `target-role-root` `root` trust but has no identity `sts:AssumeRole`; cannot assume (access keys provided) |
| `arn:aws:iam::{account_id}:role/pl-prod-rbr-are-target-role` | Reads the bucket; trust names exactly `are-both` and `are-trust-only` |
| `arn:aws:iam::{account_id}:role/pl-prod-rbr-are-target-role-root` | Reads the bucket; trust grants to account `root`, deferring the decision to identity policies |
| `arn:aws:s3:::pl-sensitive-data-rbr-are-{account_id}-{suffix}` | Target S3 bucket containing `sensitive-data.txt`; no bucket policy |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve the five users' credentials, the two role ARNs, and the bucket name from Terraform outputs
2. As `are-both`, assume `target-role` and read the bucket, confirming both halves (identity + explicit trust) succeed
3. As `are-root-with-identity`, assume `target-role-root` and read the bucket, confirming identity permission plus root trust succeeds
4. As `are-identity-only`, attempt to assume `target-role` and confirm it is denied (identity permission present, but trust does not name the user)
5. As `are-trust-only`, attempt to assume `target-role` and confirm it is denied (trust names the user, but no identity permission)
6. As `are-root-no-identity`, attempt to assume `target-role-root` and confirm it is denied (root trust defers to an identity permission that is absent)
7. Print the observed assume-role result per user (the script exits non-zero if any observation differs from expectation)

The crux of this lab is that a same-account `sts:AssumeRole` requires BOTH an identity-based permission on the caller AND a trust policy on the role that allows the caller, and that a trust policy granting to the account `root` defers entirely to identity policies. A tool that reads only identity policies falsely includes `are-identity-only`; a tool that reads only trust policies falsely includes `are-trust-only` and `are-root-no-identity`.

#### Resources Created by Attack Script

- Temporary STS session credentials for `target-role` (assumed by `are-both`) and `target-role-root` (assumed by `are-root-with-identity`); these expire on their own
- Temporary file `/tmp/rbr-are-sensitive.txt` downloaded from the sensitive bucket (removed by the cleanup script)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo test-reverse-blast-radius-assume-role-edges
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-assume-role-edges-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup test-reverse-blast-radius-assume-role-edges
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-assume-role-edges-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable test-reverse-blast-radius-assume-role-edges-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `test-reverse-blast-radius-assume-role-edges-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

A properly configured security analysis platform or CSPM tool performing a reverse blast radius query on the bucket `pl-sensitive-data-rbr-are-{account_id}-{suffix}` should identify:

1. **Direct readers**: `pl-prod-rbr-are-target-role` and `pl-prod-rbr-are-target-role-root` hold `s3:GetObject` and `s3:ListBucket` on the bucket through their own IAM policies
2. **Both halves required**: a same-account `sts:AssumeRole` edge exists only when the caller's identity policy allows `sts:AssumeRole` on the role AND the role's trust policy allows the caller
3. **Only two users can assume**: `pl-prod-rbr-are-both` (identity + explicit trust) and `pl-prod-rbr-are-root-with-identity` (identity + root trust) can reach a bucket-reading role
4. **Root trust defers to identity**: a trust policy that grants to `arn:aws:iam::{account_id}:root` does not by itself grant assumption; the caller still needs an identity `sts:AssumeRole` permission, which is why `pl-prod-rbr-are-root-no-identity` cannot assume

**Expected Query Results (truth table):**

| Query | Expected principals |
| -- | -- |
| Direct bucket readers (0 hops) | target-role, target-role-root |
| Can assume a reader via exactly one hop | are-both, are-root-with-identity |
| Identity permission but no trust (false positive) | are-identity-only -- must NOT appear |
| Trust but no identity permission (false positive) | are-trust-only, are-root-no-identity -- must NOT appear |

**Tool Testing Focus:**

1. **Edge Correctness**: Does the tool draw a can_assume edge only when both the identity policy and the trust policy allow the assumption?
2. **Identity-Only False Positives**: Does the tool avoid drawing an edge for `are-identity-only`, whose identity policy allows assume but whose target role does not trust it?
3. **Trust-Only False Positives**: Does the tool avoid drawing an edge for `are-trust-only`, which is trusted but has no identity permission?
4. **Root Trust Semantics**: Does the tool treat a `root` trust as deferring to identity policies, correctly including `are-root-with-identity` but excluding `are-root-no-identity`?

**Expected Tool Behavior:**

Passing tools:
- Return exactly `target-role` and `target-role-root` as direct bucket readers
- Return exactly `are-both` and `are-root-with-identity` as the users that can reach the bucket via one assume-role hop
- Exclude `are-identity-only`, `are-trust-only`, and `are-root-no-identity` from any "who can read the bucket" answer

Failing tools:
- Include `are-identity-only` by reading only identity policies
- Include `are-trust-only` or `are-root-no-identity` by reading only trust policies
- Treat a `root` trust as granting assumption to the whole account regardless of identity policies

#### Prevention Recommendations

This is a tool-testing scenario, so the guidance below applies to managing role trust and assume-role access in real environments:

- Scope role trust policies to specific principal ARNs (as `target-role` does) rather than account `root`; a `root` trust silently delegates the decision to every identity policy in the account and is easy to misjudge
- Pair trust policies with conditions such as `aws:PrincipalOrgID`, `sts:ExternalId`, or MFA where applicable to tighten who can actually assume a role
- Remember that a same-account assume requires both halves -- an identity `sts:AssumeRole` grant and a matching trust -- so audit both sides when reviewing who can reach a sensitive role
- Prefer explicit principal ARNs in trust policies so that reverse blast radius reviews can enumerate exactly who is trusted
- Use IAM Access Analyzer and policy simulation (`aws iam simulate-principal-policy`) to validate effective assume-role access, including the root-trust-defers-to-identity case
- Alert on broad `sts:AssumeRole` identity grants (wildcard resources) that pair with `root`-trust roles, since together they widen the set of principals that can reach sensitive roles

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `sts:AssumeRole` -- role assumption into `pl-prod-rbr-are-target-role` or `pl-prod-rbr-are-target-role-root`; monitor both the successful assumptions by `are-both` and `are-root-with-identity` and the `AccessDenied` attempts by the three users that satisfy only one half
- `s3:GetObject` -- object retrieval from the sensitive bucket; monitor for access by unexpected assumed-role sessions
- `s3:ListBucket` -- bucket listing requests; monitor for enumeration of bucket contents from assumed-role sessions

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [T1530 - Data from Cloud Storage Object](https://attack.mitre.org/techniques/T1530/) -- MITRE ATT&CK technique for collecting data from cloud storage
- [How IAM roles differ from resource-based policies](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_compare-resource-policies.html) -- AWS documentation on how same-account assume-role evaluation combines identity and trust policies
