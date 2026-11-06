# Solution: S3 Read/Write/Delete Permission Edge Granularity

This scenario is not an attack in the traditional sense -- there is no privilege to escalate and no misconfiguration to exploit. Instead, it is a precision benchmark for the access-modeling layer of your graph or CSPM tool. Most tools that build "who can access this bucket" edges collapse S3 permissions into a single boolean: does this principal have access, yes or no. That collapse hides a critical distinction -- `s3:GetObject`, `s3:PutObject`, and `s3:DeleteObject` are three independent grants that can be issued in any combination, and a principal that can write to a bucket cannot necessarily read from it or delete from it.

This distinction matters in real environments in both directions. Under-inference misses a genuine risk: a tool that only checks for `s3:GetObject` when building bucket-access edges will completely miss a write-only or delete-only principal, silently underreporting who can modify or destroy data in a sensitive bucket. Over-inference creates false alarms and miscalibrated risk scores: a tool that assumes any S3 permission implies full CRUD will flag a strictly read-only principal as having destructive capability it was never granted, wasting analyst time chasing a risk that doesn't exist.

## The Challenge

You start as `pl-prod-rwd-starting-user`, an IAM user whose only real capability is `sts:AssumeRole` into the four role-based test principals in this scenario. The eight actual test subjects are split into four permission tiers, each represented once as an IAM user and once as an IAM role:

- `pl-prod-rwd-user-read-only` / `pl-prod-rwd-role-read-only` -- `s3:GetObject` + `s3:ListBucket` only
- `pl-prod-rwd-user-write-only` / `pl-prod-rwd-role-write-only` -- `s3:PutObject` only
- `pl-prod-rwd-user-delete-only` / `pl-prod-rwd-role-delete-only` -- `s3:DeleteObject` only
- `pl-prod-rwd-user-read-write-delete` / `pl-prod-rwd-role-read-write-delete` -- full `s3:GetObject` + `s3:PutObject` + `s3:DeleteObject` + `s3:ListBucket`

All eight principals target the same bucket, `pl-rwd-bucket-{account_id}-{suffix}`, which is pre-seeded with a single object (`seed-object.txt`) so that the read-only and delete-only tiers have something to act on. Nothing needs to be escalated here -- your job is to confirm each principal can do exactly what it was granted, and nothing more, then check whether your security tooling agrees.

## Reconnaissance

Start by confirming your own identity and checking what the starting user itself can see:

```bash
export AWS_ACCESS_KEY_ID="<starting_user_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<starting_user_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

The starting user has no direct S3 permissions of its own -- confirm that:

```bash
aws s3 ls s3://pl-rwd-bucket-<account_id>-<suffix>/
# Expected: AccessDenied -- the starting user has no S3 permissions
```

Now inspect how each of the eight test principals is actually configured. For each principal, list its inline and attached policies and note exactly which of `s3:GetObject`, `s3:PutObject`, and `s3:DeleteObject` appear:

```bash
aws iam list-user-policies --user-name pl-prod-rwd-user-read-only
aws iam get-user-policy --user-name pl-prod-rwd-user-read-only --policy-name <policy-name>

aws iam list-role-policies --role-name pl-prod-rwd-role-write-only
aws iam get-role-policy --role-name pl-prod-rwd-role-write-only --policy-name <policy-name>
```

You'll see that each of the four tiers grants a strictly non-overlapping subset of the three actions -- no principal outside the read-write-delete tier has more than one of the three granted.

## Exploitation

There is no escalation step here -- "exploitation" in this scenario means exercising each principal's already-granted access and confirming the tool under test builds an edge that matches it exactly.

### Testing the read-only tier

```bash
export AWS_ACCESS_KEY_ID="<user_read_only_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<user_read_only_secret_access_key>"
unset AWS_SESSION_TOKEN

aws s3 cp s3://pl-rwd-bucket-<account_id>-<suffix>/seed-object.txt -
# Expected: succeeds, prints the seed content

aws s3 cp test.txt s3://pl-rwd-bucket-<account_id>-<suffix>/test.txt
# Expected: AccessDenied

aws s3api delete-object --bucket pl-rwd-bucket-<account_id>-<suffix> --key seed-object.txt
# Expected: AccessDenied
```

Repeat with `pl-prod-rwd-role-read-only`, assumed first via `sts:AssumeRole` from the starting user's credentials. The results should be identical -- read succeeds, write and delete are both denied.

### Testing the write-only tier

```bash
export AWS_ACCESS_KEY_ID="<user_write_only_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<user_write_only_secret_access_key>"
unset AWS_SESSION_TOKEN

aws s3 cp test.txt s3://pl-rwd-bucket-<account_id>-<suffix>/write-only-test.txt
# Expected: succeeds

aws s3 cp s3://pl-rwd-bucket-<account_id>-<suffix>/write-only-test.txt -
# Expected: AccessDenied -- write does not imply read, even of your own object

aws s3api delete-object --bucket pl-rwd-bucket-<account_id>-<suffix> --key write-only-test.txt
# Expected: AccessDenied -- write does not imply delete, even of your own object
```

Repeat with `pl-prod-rwd-role-write-only` via `sts:AssumeRole`. Both should show identical behavior: write succeeds, read and delete of that same object both fail.

### Testing the delete-only tier

```bash
export AWS_ACCESS_KEY_ID="<user_delete_only_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<user_delete_only_secret_access_key>"
unset AWS_SESSION_TOKEN

aws s3 cp s3://pl-rwd-bucket-<account_id>-<suffix>/seed-object.txt -
# Expected: AccessDenied

aws s3 cp test.txt s3://pl-rwd-bucket-<account_id>-<suffix>/test.txt
# Expected: AccessDenied

aws s3api delete-object --bucket pl-rwd-bucket-<account_id>-<suffix> --key delete-only-test.txt
# Expected: succeeds (against a disposable object left for this test)
```

Repeat with `pl-prod-rwd-role-delete-only` via `sts:AssumeRole`. Note that delete-only access is unusual in practice, but it isolates the third leg of the CRUD triangle cleanly -- a principal that can destroy data without ever being able to read or write it.

### Testing the full read-write-delete tier

```bash
export AWS_ACCESS_KEY_ID="<user_read_write_delete_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<user_read_write_delete_secret_access_key>"
unset AWS_SESSION_TOKEN

aws s3 ls s3://pl-rwd-bucket-<account_id>-<suffix>/
aws s3 cp s3://pl-rwd-bucket-<account_id>-<suffix>/seed-object.txt -
aws s3 cp test.txt s3://pl-rwd-bucket-<account_id>-<suffix>/rwd-test.txt
aws s3api delete-object --bucket pl-rwd-bucket-<account_id>-<suffix> --key rwd-test.txt
```

All four calls should succeed. Repeat with `pl-prod-rwd-role-read-write-delete` via `sts:AssumeRole` and confirm the same result.

Clean up after each write-capable test so the bucket is left in its pre-seeded state:

```bash
aws s3 rm s3://pl-rwd-bucket-<account_id>-<suffix>/write-only-test.txt 2>/dev/null || true
```

## Verification

By the end of the walkthrough you should have exercised all eight principals and observed exactly the access pattern each was granted: two principals that can only read, two that can only write, two that can only delete, and two that can do all three. No principal should have succeeded at an action outside its granted tier.

The real verification is pointing your graph/CSPM tool at this account and confirming it reports `can_read`, `can_write`, and `can_delete` for each principal that match this table exactly:

| Principal | can_read | can_write | can_delete |
|---|---|---|---|
| `pl-prod-rwd-user-read-only` / `pl-prod-rwd-role-read-only` | true | false | false |
| `pl-prod-rwd-user-write-only` / `pl-prod-rwd-role-write-only` | false | true | false |
| `pl-prod-rwd-user-delete-only` / `pl-prod-rwd-role-delete-only` | false | false | true |
| `pl-prod-rwd-user-read-write-delete` / `pl-prod-rwd-role-read-write-delete` | true | true | true |

Any deviation -- a `false` where the table says `true` is a false negative (missed access), and a `true` where the table says `false` is a false positive (over-inferred access) -- points to a specific gap in the tool's IAM-action-to-graph-edge mapping.

## What Happened

This scenario deliberately isolates the three primitive S3 data actions -- read, write, and delete -- across eight principals so that no combination is left untested, and repeats the test across both IAM users and IAM roles to rule out principal-type bias in the tool's evaluation logic. The runtime behavior of each principal is exactly as narrow or as broad as its policy states; there is no ambiguity or complex policy interaction to resolve.

In production environments, this exact gap is where blast-radius calculations quietly go wrong. A tool that treats "has some S3 permission" as equivalent to "can read this bucket" will overstate exposure for a write-only service account while understating it for the destructive delete-only principal it never modeled at all. Benchmarking your tooling against known-answer scenarios like this one -- where the expected answer for every principal is known in advance -- is the only reliable way to catch that kind of silent, precision-level blind spot before it affects an incident response decision.
