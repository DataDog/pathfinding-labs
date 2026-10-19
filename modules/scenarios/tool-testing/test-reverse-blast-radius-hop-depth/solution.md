# Solution: Reverse Blast Radius by Hop Depth to Bucket

This scenario validates that a security tool can answer "who can read this bucket" correctly when the answer depends on how many `sts:AssumeRole` hops you are willing to follow. Reverse blast radius queries usually take a hop limit. If that limit is treated as an exact depth, a query for 0 hops returns only the principals that hold the permission directly. A query for 1 hop returns the principals one assume-role away, but not the direct ones. Deeper chains need yet another query.

A complete answer therefore needs one query per depth, or a single cumulative "up to N hops" query with N at least as deep as your longest role chain. That is easy to get wrong. An analyst who runs one query and sees a short list can easily conclude the bucket is better protected than it really is. In real environments, deployment pipelines, break-glass roles, and service roles routinely chain two or three assumptions deep, and the principals at the far end are the ones nobody remembers granting access.

## The Challenge

You have credentials for three IAM users and need to understand who can reach a single bucket:

- `pl-prod-rbr-hd-user-a` -- direct `s3:GetObject` and `s3:ListBucket` on the bucket (depth 0)
- `pl-prod-rbr-hd-user-b` -- only `sts:AssumeRole` on `pl-prod-rbr-hd-role-r1` (depth 1)
- `pl-prod-rbr-hd-user-c` -- only `sts:AssumeRole` on `pl-prod-rbr-hd-role-r2`, which can assume `role-r1` (depth 2)

Two roles complete the graph. `pl-prod-rbr-hd-role-r1` holds the S3 permissions directly and trusts only user-b and role-r2. `pl-prod-rbr-hd-role-r2` has no S3 permissions, only `sts:AssumeRole` on role-r1, and trusts only user-c. The target is `pl-sensitive-data-rbr-hd-{account_id}-{suffix}`. Your goal is to prove with real calls who can read it and at what depth, then compare that to what your security tool reports.

## Reconnaissance

Start by confirming who you are for each set of credentials:

```bash
export AWS_ACCESS_KEY_ID="<user_a_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<user_a_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity --query 'Arn' --output text
# Expected: arn:aws:iam::{account_id}:user/pl-prod-rbr-hd-user-a
```

`sts:GetCallerIdentity` is the only reconnaissance permission the lab grants. The graph is documented, so the rest of the work is proving it. Before exploiting anything, note the predicted truth table so you can check it against reality:

| Query | Expected principals |
| -- | -- |
| Exactly 0 hops | user-a, role-r1 |
| Exactly 1 hop | user-b, role-r2 |
| Exactly 2 hops | user-c |
| Up to 1 hop | user-a, role-r1, user-b, role-r2 |
| Up to 2 hops | user-a, role-r1, user-b, role-r2, user-c |

## Exploitation

### Hop 0: Direct access (user-a and role-r1)

As user-a, read the bucket with no role assumption:

```bash
aws s3 ls "s3://pl-sensitive-data-rbr-hd-{account_id}-{suffix}/"
aws s3 cp "s3://pl-sensitive-data-rbr-hd-{account_id}-{suffix}/sensitive-data.txt" /tmp/rbr-hd-sensitive.txt
```

This works because user-a's own policy grants the S3 actions. Role-r1 holds the same permissions, so any session for it can do the same. You will see that when the later hops land on it. Both user-a and role-r1 are depth 0.

### Hop 1: One assume-role away (user-b and role-r2)

Switch to user-b. First confirm it cannot read the bucket directly:

```bash
aws s3 ls "s3://pl-sensitive-data-rbr-hd-{account_id}-{suffix}/"
# Expected: An error occurred (AccessDenied)
```

User-b has no S3 permissions, but it can assume role-r1, whose trust policy names it explicitly:

```bash
CREDENTIALS=$(aws sts assume-role \
    --role-arn "arn:aws:iam::{account_id}:role/pl-prod-rbr-hd-role-r1" \
    --role-session-name rbr-hd-user-b \
    --query 'Credentials' --output json)

export AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS" | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS" | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$CREDENTIALS" | jq -r '.SessionToken')

aws s3 ls "s3://pl-sensitive-data-rbr-hd-{account_id}-{suffix}/"
```

The listing now succeeds, so user-b is a depth 1 principal. Role-r2 follows the same pattern: a role-r2 session calls `sts:AssumeRole` on role-r1 and gains the same access. That makes role-r2 depth 1 too.

### Hop 2: Two assume-roles away (user-c)

Switch to user-c and confirm direct access is denied. User-c cannot reach role-r1 in one step, because role-r1's trust policy does not name it. It can only assume role-r2:

```bash
unset AWS_SESSION_TOKEN
export AWS_ACCESS_KEY_ID="<user_c_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<user_c_secret_access_key>"

R2_CREDENTIALS=$(aws sts assume-role \
    --role-arn "arn:aws:iam::{account_id}:role/pl-prod-rbr-hd-role-r2" \
    --role-session-name rbr-hd-user-c \
    --query 'Credentials' --output json)

export AWS_ACCESS_KEY_ID=$(echo "$R2_CREDENTIALS" | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$R2_CREDENTIALS" | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$R2_CREDENTIALS" | jq -r '.SessionToken')
```

The role-r2 session still cannot read the bucket. It can, however, chain into role-r1, since role-r1 trusts role-r2:

```bash
R1_CREDENTIALS=$(aws sts assume-role \
    --role-arn "arn:aws:iam::{account_id}:role/pl-prod-rbr-hd-role-r1" \
    --role-session-name rbr-hd-user-c-chain \
    --query 'Credentials' --output json)

export AWS_ACCESS_KEY_ID=$(echo "$R1_CREDENTIALS" | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$R1_CREDENTIALS" | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$R1_CREDENTIALS" | jq -r '.SessionToken')

aws s3 ls "s3://pl-sensitive-data-rbr-hd-{account_id}-{suffix}/"
```

Two hops later, the listing succeeds. User-c is a depth 2 principal.

## Verification

Every claim in the truth table is now backed by a real call:

- user-a and role-r1 read the bucket with zero assume-role hops
- user-b and role-r2 read the bucket after one hop into role-r1
- user-c read the bucket only after two chained hops (role-r2, then role-r1)

Now run reverse blast radius queries in your security tool against the bucket and compare:

- **Exactly 0 hops** should return user-a and role-r1, and nothing else
- **Exactly 1 hop** should return user-b and role-r2, and NOT user-a or role-r1. That is correct "exactly N" behavior, not a bug, but it means this query alone is an incomplete answer
- **Exactly 2 hops** should return only user-c
- **Up to 1 hop** should return user-a, role-r1, user-b, and role-r2, and no user-c
- **Up to 2 hops** should return all five principals

If your tool silently stops at one assume-role edge, it will omit user-c. If it labels a 1-hop query as returning "everyone who can read the bucket", it has hidden the depth 0 principals. You should know which semantics your tool uses before trusting a short result list.

## What Happened

You walked a three-depth IAM graph and showed that the set of principals who can read one bucket changes with the question you ask. Five principals can read it: two directly, two after one hop, and one after two hops. Any single fixed-depth query shows at most two of them. The crux is the difference between "exactly N hops" and "up to N hops". The first gives a disjoint slice per depth, and only the second accumulates toward the real blast radius.

In real environments, the same pattern hides in plain sight: a pipeline role assumes a deployment role, which assumes a data-access role, and the principal at the start of the chain never shows up in a direct-permission review. When you evaluate a CSPM or graph tool for reverse blast radius, check the depth semantics, test with a hop limit at least as deep as your longest role chain, and use this lab as a repeatable test that the answer is complete.
