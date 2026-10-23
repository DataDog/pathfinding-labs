# Solution: Reverse Blast Radius with Identity-Side Access Blocks

This scenario is the resource-access analog of classifying who is really an administrator once denies and boundaries are in play. A reverse blast radius query -- "who can read this bucket?" -- is only as good as the IAM evaluation behind it. The easy part is collecting Allow statements that name the bucket. The hard part is subtracting everything that nullifies those Allows on the identity side: explicit denies and permissions boundaries.

That gap matters in practice. A principal can carry a perfectly good `s3:GetObject` Allow and still have zero effective access to your most sensitive bucket, because an inline `Deny` overrides it, or because a permissions boundary never permitted S3 in the first place. A tool that lists Allow statements at face value will name that principal as a reader, inflating the blast radius with false positives. Teams that rely on those answers to scope access or triage an incident end up chasing principals that cannot actually touch the data.

This lab gives you a fixed truth table to test a tool against. Three users all hold the same bucket-read Allow. One is unobstructed, one is overridden by an explicit deny, and one is capped by a permissions boundary. Only the first can actually read the bucket.

## The Challenge

You have credentials for these principals:

- `pl-prod-rbr-isb-plain-reader` -- an unobstructed `s3:GetObject` and `s3:ListBucket` Allow on the bucket. This is the control
- `pl-prod-rbr-isb-explicit-deny-reader` -- the same read Allow, plus an inline `Deny` on `s3:*`
- `pl-prod-rbr-isb-boundary-excludes-s3` -- the same read Allow, but with an EC2-only permissions boundary attached

The target is the `pl-sensitive-data-rbr-isb-{account_id}-{suffix}` bucket, which has no bucket policy -- so every access decision comes from the identity side. Your goal is to confirm the real access matrix and then check that your security tool reports only the principal with effective access.

## Reconnaissance

Start by confirming who you are for each set of credentials:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# Expected: arn:aws:iam::{account_id}:user/pl-prod-rbr-isb-plain-reader
```

Then look at what each principal actually has. On the surface, all three inline policies carry the same `LooksLikeAReader` Allow:

```bash
aws iam get-user-policy --user-name pl-prod-rbr-isb-plain-reader \
  --policy-name pl-prod-rbr-isb-plain-reader-policy

aws iam get-user-policy --user-name pl-prod-rbr-isb-explicit-deny-reader \
  --policy-name pl-prod-rbr-isb-explicit-deny-reader-policy
# Note the second statement: an explicit Deny on s3:*

aws iam get-user-policy --user-name pl-prod-rbr-isb-boundary-excludes-s3 \
  --policy-name pl-prod-rbr-isb-boundary-excludes-s3-policy
# The Allow is identical to plain-reader's -- the catch is elsewhere
```

The deny-reader gives itself away in its own policy: a second statement denies `s3:*` on `*`. The boundary-blocked user hides its catch outside the inline policy, in a permissions boundary:

```bash
aws iam get-user --user-name pl-prod-rbr-isb-boundary-excludes-s3 \
  --query 'User.PermissionsBoundary'

aws iam get-policy-version \
  --policy-arn arn:aws:iam::{account_id}:policy/pl-prod-rbr-isb-ec2-only-boundary \
  --version-id v1
# The boundary permits only ec2:Describe* -- no S3 at all
```

Effective permissions are the intersection of the boundary and the identity policy. The identity policy allows S3, but the boundary never does, so the intersection has no S3.

## Exploitation

### The control: plain-reader

As `plain-reader`, list and read the bucket. Both succeed because nothing on the identity side obstructs the Allow:

```bash
aws s3 ls "s3://pl-sensitive-data-rbr-isb-{account_id}-{suffix}/"
aws s3 cp "s3://pl-sensitive-data-rbr-isb-{account_id}-{suffix}/sensitive-data.txt" -
```

This is the one effective read edge in the lab.

### Blocked by an explicit deny: explicit-deny-reader

As `explicit-deny-reader`, attempt the same operations. Both are denied, even though the user holds the exact same read Allow as plain-reader:

```bash
aws s3 ls "s3://pl-sensitive-data-rbr-isb-{account_id}-{suffix}/"
aws s3 cp "s3://pl-sensitive-data-rbr-isb-{account_id}-{suffix}/sensitive-data.txt" -
# Expected: AccessDenied on both
```

An explicit deny always wins. No matter how many Allow statements accumulate, the `Deny` on `s3:*` removes every S3 action from this user's effective permissions.

### Blocked by a permissions boundary: boundary-excludes-s3

As `boundary-excludes-s3`, attempt the same operations. Both are denied, because the EC2-only boundary caps the user's effective permissions to actions the boundary also permits:

```bash
aws s3 ls "s3://pl-sensitive-data-rbr-isb-{account_id}-{suffix}/"
aws s3 cp "s3://pl-sensitive-data-rbr-isb-{account_id}-{suffix}/sensitive-data.txt" -
# Expected: AccessDenied on both
```

The identity policy says yes to S3; the boundary says no. The intersection is no.

## Verification

The real access matrix is now confirmed with live calls. This is what a correct tool should return.

Query: "Who can read `pl-sensitive-data-rbr-isb-{account_id}-{suffix}`?"

```
- arn:aws:iam::{account_id}:user/pl-prod-rbr-isb-plain-reader
```

`pl-prod-rbr-isb-explicit-deny-reader` and `pl-prod-rbr-isb-boundary-excludes-s3` must appear in neither this answer nor any write answer. If your tool returns all three, it is reading Allow statements at face value and not applying denies and boundaries. If it returns plain-reader plus exactly one of the other two, it handles one identity-side control but not the other -- a split result tells you which evaluation step is missing.

## What Happened

You saw that a bucket-read Allow is not the same as effective read access. All three users carried the identical Allow, but only one of them could actually read the bucket. The explicit deny and the permissions boundary each nullified the Allow on the identity side, and they are easy to miss for any tool that stops at "does a policy grant this action?" without finishing the evaluation.

In real environments this is exactly how teams use denies and boundaries to hard-block sensitive data from principals that would otherwise have access. A reverse blast radius answer that ignores those controls overstates exposure and sends responders after principals that cannot touch the data. This lab gives you a repeatable truth table to check whether your tooling computes effective permissions -- Allow minus explicit deny, intersected with boundaries -- or merely collects Allow statements.
