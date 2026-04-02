# Guided Walkthrough: Exclusive S3 Bucket Access Through Restrictive Resource Policy

This scenario demonstrates how a role with minimal IAM permissions can access an S3 bucket through a restrictive resource-based policy that explicitly denies access to everyone else, creating an exclusive access scenario.

The attack path shows how an attacker who has compromised a user with only the ability to assume a single role can still reach highly sensitive data. The twist is that the role's IAM identity policy grants almost nothing — only `s3:ListAllMyBuckets`. But the target bucket's resource policy contains an exclusive grant: full read/write access for this role, plus an explicit `Deny` for every other principal. Standard IAM analysis tools will look at the role and see minimal permissions; they will miss the S3 access completely.

This pattern represents a real-world security blind spot. Operators sometimes create exclusive-access resource policies as a simple access control mechanism — "only this role can touch this bucket" — without realising that the role's identity policy doesn't need to say anything about S3 for the access to work. The result is that effective permissions reviews that focus only on identity policies will systematically underreport the blast radius of this role.

## The Challenge

You start as `pl-pathfinding-starting-user-prod`, an IAM user in the prod account with one useful capability: it can assume the `pl-exclusive-bucket-access-role` role.

That role's identity policy contains exactly one statement: `s3:ListAllMyBuckets` on `*`. That's it. No `s3:GetObject`, no `s3:PutObject`, no bucket-specific access.

Your goal is to read and write objects in `pl-exclusive-sensitive-data-bucket-{account_id}`.

## Reconnaissance

First, confirm your starting identity:

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

You should see `pl-pathfinding-starting-user-prod` in the ARN. Now let's see what roles this user can assume:

```bash
aws iam list-roles --query 'Roles[?contains(RoleName, `exclusive`)].{Name:RoleName,Arn:Arn}'
```

You'll find `pl-exclusive-bucket-access-role`. At first glance it looks harmless — but before writing it off, check what S3 buckets exist in the account:

```bash
# This will fail — the starting user doesn't have s3:ListAllMyBuckets
aws s3 ls
```

That denial makes sense. But once you're inside the role, the picture changes.

## Exploitation

### Step 1: Assume the exclusive bucket access role

```bash
CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::{account_id}:role/pl-exclusive-bucket-access-role \
  --role-session-name exclusive-access-demo \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$CREDS" | jq -r '.Credentials.SessionToken')
```

You're now operating as `pl-exclusive-bucket-access-role`.

### Step 2: Enumerate S3 buckets

The role has `s3:ListAllMyBuckets`, so listing buckets works:

```bash
aws s3 ls
```

You'll see `pl-exclusive-sensitive-data-bucket-{account_id}` in the output.

### Step 3: Access the exclusive bucket

Try to list objects in the bucket. This is where it gets interesting — the role's identity policy has no S3 bucket-level or object-level permission, yet the resource policy on the bucket grants it:

```bash
aws s3 ls s3://pl-exclusive-sensitive-data-bucket-{account_id}
```

This succeeds. Now read a sensitive file:

```bash
aws s3 cp s3://pl-exclusive-sensitive-data-bucket-{account_id}/sensitive-data.txt .
cat sensitive-data.txt
```

### Step 4: Confirm write access

You can also write to the bucket:

```bash
echo "attacker-controlled data" > /tmp/test-upload.txt
aws s3 cp /tmp/test-upload.txt s3://pl-exclusive-sensitive-data-bucket-{account_id}/test-upload.txt
```

That upload succeeds because the resource policy grants `s3:PutObject` to this role.

### Step 5: Inspect the bucket policy

Retrieve the bucket policy to understand the exclusive-access structure:

```bash
aws s3api get-bucket-policy \
  --bucket pl-exclusive-sensitive-data-bucket-{account_id} \
  --query Policy \
  --output text | jq '.'
```

You'll see two statements:

1. **AllowExclusiveBucketAccessRole** — grants `s3:ListBucket`, `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` to `pl-exclusive-bucket-access-role`
2. **DenyAllOtherAccess** — denies those same actions to `Principal: "*"` where `aws:PrincipalArn` is not equal to `pl-exclusive-bucket-access-role`

This is the exclusive-access pattern: allow one principal, deny everyone else. From an effective-permissions standpoint, the role's access to this bucket is entirely invisible unless you examine the bucket policy directly.

## Verification

To confirm that other principals are actually blocked, switch to a different set of credentials (such as the readonly user) and attempt to list the bucket:

```bash
# Switch to readonly credentials
export AWS_ACCESS_KEY_ID=<readonly_access_key_id>
export AWS_SECRET_ACCESS_KEY=<readonly_secret_access_key>
unset AWS_SESSION_TOKEN

aws s3 ls s3://pl-exclusive-sensitive-data-bucket-{account_id}
# Expected: AccessDenied
```

The explicit `Deny` in the bucket policy overrides any IAM permissions the readonly user might have, including admin-level permissions. The exclusive pattern enforces hard isolation.

## What Happened

The `pl-exclusive-bucket-access-role` role appears to have negligible S3 access from the identity policy side — only `s3:ListAllMyBuckets`. But effective permissions in AWS are the union of identity policies and resource policies, subject to any explicit denies. The bucket's resource policy contains an explicit `Allow` for this role that covers `s3:ListBucket`, `s3:GetObject`, `s3:PutObject`, and `s3:DeleteObject`. Because there is no explicit deny on the identity policy side for those specific actions against that specific bucket, AWS evaluates the resource policy allow as sufficient — and grants access.

This is a real gap in how many teams review permissions. IAM analysis tools that enumerate role policies and report "this role can only list S3 buckets" are giving an incomplete picture. Attackers (and defenders) need to consider resource policies as part of the effective-permissions calculation. In this scenario, assuming one low-looking role was all that stood between the starting user and full read/write control of a sensitive data store.
