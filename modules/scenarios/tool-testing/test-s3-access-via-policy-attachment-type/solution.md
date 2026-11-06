# Solution: S3 Access via Inline and Managed Policy Attachment Types

This scenario is not an attack in the traditional sense -- there is no privilege to escalate and no misconfiguration to exploit. Instead, it is a benchmark for the policy-parsing layer of your graph or CSPM tool. AWS gives you two independent ways to attach a permission to a principal: write the policy document directly on the principal (an inline policy), or write it as a standalone `aws_iam_policy` resource and attach it separately (a managed policy). Both mechanisms produce identical effective permissions at evaluation time, but they live in different API objects and require different enumeration calls to discover.

This distinction matters enormously in real environments. A tool that only walks `iam:ListAttachedUserPolicies` / `iam:ListAttachedRolePolicies` (managed policies) while ignoring `iam:ListUserPolicies` / `iam:ListRolePolicies` (inline policies) -- or vice versa -- will silently undercount who has access to a sensitive resource. Worse, teams often use inline policies specifically for one-off or legacy grants that never get revisited, making them an easy blind spot for tools tuned only against managed-policy attachments.

## The Challenge

You start as `pl-prod-patn-starting-user`, an IAM user whose only real capability is `sts:AssumeRole` into the two role-based test principals in this scenario. The four actual test subjects are:

- `pl-prod-patn-user-inline` -- an IAM user with full read/write bucket access granted via an inline policy
- `pl-prod-patn-user-managed` -- an IAM user with the same access granted via a customer-managed policy attachment
- `pl-prod-patn-role-inline` -- an IAM role with the same access granted via an inline policy
- `pl-prod-patn-role-managed` -- an IAM role with the same access granted via a customer-managed policy attachment

All four already hold `s3:GetObject`, `s3:PutObject`, `s3:ListBucket` on `pl-patn-bucket-{account_id}-{suffix}`, plus `s3:ListAllMyBuckets` for enumeration. Nothing needs to be escalated -- your job is to confirm that all four resolve to the same effective access, then check whether your security tooling agrees.

## Reconnaissance

Start by confirming your own identity and checking what the starting user itself can see:

```bash
export AWS_ACCESS_KEY_ID="<starting_user_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<starting_user_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

The starting user has no direct S3 permissions of its own -- its only job is to assume the two role-based test principals. Confirm that:

```bash
aws s3 ls s3://pl-patn-bucket-<account_id>-<suffix>/
# Expected: AccessDenied -- the starting user has no S3 permissions
```

Now look at how each of the four test principals is actually configured. For the two IAM users, check both attachment mechanisms:

```bash
aws iam list-user-policies --user-name pl-prod-patn-user-inline
aws iam list-attached-user-policies --user-name pl-prod-patn-user-inline

aws iam list-user-policies --user-name pl-prod-patn-user-managed
aws iam list-attached-user-policies --user-name pl-prod-patn-user-managed
```

You'll see `pl-prod-patn-user-inline` has a policy document returned by `list-user-policies` (inline) and nothing from `list-attached-user-policies`, while `pl-prod-patn-user-managed` shows the reverse -- an empty inline list and a customer-managed policy ARN in the attached list. The same pattern repeats for the two roles using `list-role-policies` and `list-attached-role-policies`.

## Exploitation

There is no escalation step here -- "exploitation" in this scenario means exercising each principal's already-granted access and confirming it behaves identically regardless of mechanism.

### Testing the IAM users

Both IAM users already have their own access keys provisioned as Terraform outputs. Export each in turn and exercise the bucket:

```bash
export AWS_ACCESS_KEY_ID="<user_inline_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<user_inline_secret_access_key>"
unset AWS_SESSION_TOKEN

aws s3 ls s3://pl-patn-bucket-<account_id>-<suffix>/
aws s3 cp test.txt s3://pl-patn-bucket-<account_id>-<suffix>/test.txt
aws s3 cp s3://pl-patn-bucket-<account_id>-<suffix>/test.txt -
```

Repeat with `pl-prod-patn-user-managed`'s credentials. Both should succeed identically -- the inline document and the managed attachment resolve to the same effective statement at evaluation time.

### Testing the IAM roles

The two roles require an `sts:AssumeRole` hop from the starting user first:

```bash
export AWS_ACCESS_KEY_ID="<starting_user_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<starting_user_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts assume-role \
  --role-arn arn:aws:iam::<account_id>:role/pl-prod-patn-role-inline \
  --role-session-name test-session
```

Export the returned temporary credentials and repeat the same three S3 calls. Then assume `pl-prod-patn-role-managed` and repeat once more:

```bash
export AWS_ACCESS_KEY_ID="<temp_access_key>"
export AWS_SECRET_ACCESS_KEY="<temp_secret_key>"
export AWS_SESSION_TOKEN="<temp_session_token>"

aws s3 ls s3://pl-patn-bucket-<account_id>-<suffix>/
aws s3 cp test.txt s3://pl-patn-bucket-<account_id>-<suffix>/test.txt
aws s3 cp s3://pl-patn-bucket-<account_id>-<suffix>/test.txt -
```

Clean up the test object each time so the bucket is left empty between runs:

```bash
aws s3 rm s3://pl-patn-bucket-<account_id>-<suffix>/test.txt
```

## Verification

By the end of the walkthrough you should have four successful `list` + `put` + `get` sequences against the bucket -- one per test principal -- despite the fact that two used direct user credentials and two required an `sts:AssumeRole` hop, and despite the fact that two are governed by inline policy documents and two by customer-managed policy attachments.

The real verification, though, is pointing your graph/CSPM tool at this account and confirming it reports all four principals as having access to `pl-patn-bucket-{account_id}-{suffix}`. If it reports fewer than four -- most commonly missing one of the inline-policy principals, since inline policies require a separate enumeration call from managed policy attachments -- you've found a gap in its policy-parsing engine.

## What Happened

This scenario deliberately splits an identical access grant across the two ways AWS lets you attach a permission to a principal, and across the two principal types (user and role) that can hold permissions. The runtime behavior is indistinguishable: all four principals can list, read, and write the same bucket. But the API surface a security tool must walk to discover that access differs -- `list-user-policies`/`list-role-policies` for inline documents versus `list-attached-user-policies`/`list-attached-role-policies` for managed attachments.

In production environments, this exact gap causes real blast-radius miscalculations. A team that standardized on managed policies for new grants but never migrated legacy inline policies will have a security tool that only sees half the picture -- confidently reporting an accurate-looking but incomplete list of who can reach a sensitive bucket. Benchmarking your tooling against known-answer scenarios like this one is the only reliable way to catch that kind of silent blind spot before it matters in an incident.
