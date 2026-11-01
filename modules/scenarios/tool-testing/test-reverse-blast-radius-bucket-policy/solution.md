# Solution: Reverse Blast Radius with Bucket Policy Grants and Denies

This scenario tests whether a security tool reads an S3 bucket policy in both directions when it answers "who can access this bucket?" A bucket policy can grant access to a principal that has no matching identity policy, and it can take access away from a principal that clearly has one -- including an administrator. A reverse blast radius answer that only follows identity policies, or that layers an "admins can reach everything" rule on top without checking resource-policy denies, will get this bucket wrong in both directions.

The stakes are real. Teams lock down their most sensitive buckets with explicit `Deny` statements naming the principals that must never touch the data, and they rely on those denies holding even against administrators. At the same time, a bucket policy grant is a common way to hand a service role access without ever editing its identity policy. If a tool cannot see either of those, its blast radius answer understates risk in one place and overstates access in another.

This lab replaces two older labs, exclusive-resource-policy and resource-policy-bypass, and fixes their biggest weakness: the old exclusive-resource-policy lab used a deny-all-except pattern that accidentally exempted whoever deployed it, so the "correct" answer changed from account to account. Here the bucket policy Denies two specific principal ARNs. There is no deployer exemption and the expected answer is deterministic in every account.

## The Challenge

You have credentials for four principals, and there is a fifth principal -- a role -- whose access you will confirm by assuming it:

- `pl-prod-rbr-bp-starting-user` -- only `sts:AssumeRole` on policy-granted-role, no S3 of its own
- `pl-prod-rbr-bp-policy-granted-role` -- no S3 in its identity policy; its bucket access comes only from the bucket policy. Trusts starting-user
- `pl-prod-rbr-bp-identity-reader` -- explicit `s3:GetObject` and `s3:ListBucket` through its own identity policy; the bucket policy is silent about it
- `pl-prod-rbr-bp-denied-reader` -- an identity policy that allows reading, but the bucket policy Denies its ARN
- `pl-prod-rbr-bp-denied-admin` -- the `AdministratorAccess` managed policy, but the bucket policy Denies its ARN

The target is the `pl-sensitive-data-rbr-bp-{account_id}-{suffix}` bucket. Your goal is to confirm the real access matrix and then check that your security tool reports it correctly: the two genuine readers found, the one-hop reacher found, and both denied principals withheld -- even the administrator.

## Reconnaissance

Start by looking at the bucket policy, since it is the whole point of this lab:

```bash
aws s3api get-bucket-policy \
  --bucket "pl-sensitive-data-rbr-bp-{account_id}-{suffix}" \
  --query Policy --output text
```

You will see two statements. The first Allows `pl-prod-rbr-bp-policy-granted-role` to `s3:GetObject`, `s3:PutObject`, and `s3:ListBucket`. The second Denies `s3:*` to both `pl-prod-rbr-bp-denied-reader` and `pl-prod-rbr-bp-denied-admin`. Note that the Deny names those two ARNs specifically -- it is not a deny-all-except pattern, so nobody else is caught by it and nobody is exempted by who deployed the lab.

Now look at the principals' identity policies. The role has no S3 statement naming the bucket:

```bash
aws iam list-role-policies --role-name pl-prod-rbr-bp-policy-granted-role
aws iam get-role-policy \
  --role-name pl-prod-rbr-bp-policy-granted-role \
  --policy-name pl-prod-rbr-bp-policy-granted-role-policy
# Expected: only s3:ListAllMyBuckets, nothing that names this bucket
```

The denied-admin, meanwhile, has the managed `AdministratorAccess` policy and nothing bucket-specific:

```bash
aws iam list-attached-user-policies --user-name pl-prod-rbr-bp-denied-admin
# Expected: AdministratorAccess
```

So before running anything, you already know what a correct answer has to do: find the role whose grant lives only in the bucket policy, and withhold the two denied ARNs even though one of them is an administrator.

## Exploitation

### The bucket-policy grant: policy-granted-role

Starting-user cannot touch S3 directly. Assume policy-granted-role and operate as the role:

```bash
aws sts assume-role \
  --role-arn "arn:aws:iam::{account_id}:role/pl-prod-rbr-bp-policy-granted-role" \
  --role-session-name rbr-bp-starting-user \
  --query 'Credentials' --output json
# Export the returned AccessKeyId, SecretAccessKey, and SessionToken
```

With the role's session credentials exported, list and read the bucket:

```bash
aws s3 ls "s3://pl-sensitive-data-rbr-bp-{account_id}-{suffix}/"
aws s3 cp "s3://pl-sensitive-data-rbr-bp-{account_id}-{suffix}/sensitive-data.txt" -
```

Both succeed. The role has no S3 statement in its identity policy -- this access exists only because the bucket policy Allows the role's ARN. This proves two edges at once: policy-granted-role reads the bucket at 0 hops, and starting-user reaches it at 1 hop by assuming the role.

### The identity grant: identity-reader

Switch back to your long-term credentials and operate as identity-reader. Its read access comes from its own identity policy, with the bucket policy silent about it:

```bash
aws s3 ls "s3://pl-sensitive-data-rbr-bp-{account_id}-{suffix}/"
aws s3 cp "s3://pl-sensitive-data-rbr-bp-{account_id}-{suffix}/sensitive-data.txt" -
```

Both succeed. This is the control for the identity side -- the access most tools detect without trouble.

### Deny over identity Allow: denied-reader

Operate as denied-reader. Its identity policy allows `s3:GetObject` and `s3:ListBucket`, so on paper it is a reader:

```bash
aws s3 ls "s3://pl-sensitive-data-rbr-bp-{account_id}-{suffix}/"
aws s3 cp "s3://pl-sensitive-data-rbr-bp-{account_id}-{suffix}/sensitive-data.txt" -
# Expected: AccessDenied on both
```

Both are denied. The bucket policy Denies this ARN, and in AWS policy evaluation an explicit `Deny` -- identity or resource-based -- always overrides any `Allow`. A tool that reports denied-reader as a reader based on its identity policy alone is wrong.

### Deny over administrator: denied-admin

This is the case that matters most. Operate as denied-admin, which holds full `AdministratorAccess`:

```bash
aws s3 ls "s3://pl-sensitive-data-rbr-bp-{account_id}-{suffix}/"
aws s3 cp "s3://pl-sensitive-data-rbr-bp-{account_id}-{suffix}/sensitive-data.txt" -
# Expected: AccessDenied on both
```

Both are denied, despite administrator permissions. Once a tool starts modeling administrators as having implicit access to every resource -- which is correct in general -- it must still subtract access that an explicit resource-policy Deny removes. An explicit `Deny` on the ARN beats `Action: *`. A tool that adds an admin-to-every-resource edge without checking bucket-policy denies will wrongly list denied-admin as a reader of this bucket.

## Verification

The real access matrix is now confirmed with live calls. This is what a correct tool should return.

Query: "Who can read `pl-sensitive-data-rbr-bp-{account_id}-{suffix}` directly (0 hops)?"

```
- arn:aws:iam::{account_id}:role/pl-prod-rbr-bp-policy-granted-role
- arn:aws:iam::{account_id}:user/pl-prod-rbr-bp-identity-reader
```

Query: "Who can read `pl-sensitive-data-rbr-bp-{account_id}-{suffix}` by assuming exactly one role (1 hop)?"

```
- arn:aws:iam::{account_id}:user/pl-prod-rbr-bp-starting-user
```

`pl-prod-rbr-bp-denied-reader` and `pl-prod-rbr-bp-denied-admin` must appear in neither answer. If your tool omits policy-granted-role, it is reading only identity policies and missing bucket-policy grants. If it includes denied-reader, it is missing that a resource-policy Deny overrides an identity Allow. If it includes denied-admin, it is layering an "admins reach everything" rule on top without subtracting resource-policy denies. Because the Deny names specific ARNs, every one of these answers is identical in every account where you deploy the lab.

## What Happened

You confirmed that a bucket's resource policy works in both directions. It gave policy-granted-role read and write access that its identity policy never mentions, and it took access away from denied-reader and denied-admin even though their identity policies -- one of them administrator-level -- clearly allowed it. The explicit `Deny` won every time, exactly as AWS policy evaluation requires.

In real environments this is how teams protect their most sensitive data: a tight bucket policy that both scopes who can get in and hard-denies the principals who must stay out, trusting that the deny holds even against an administrator. A reverse blast radius tool that cannot see the resource-policy grant understates who can reach the data, and one that cannot apply the resource-policy deny overstates it -- and overstating an administrator as a reader of a bucket they are explicitly denied is a particularly misleading error during an access review or incident scope. This lab gives you a deterministic truth table to check whether your tooling gets both directions right.
