# Guided Walkthrough: Cross-Account Privilege Escalation - Dev to Prod Simple Role Assumption

This scenario demonstrates a cross-account privilege escalation vulnerability where a user in the dev account has permission to assume an administrative role in the production account. This represents a common misconfiguration in multi-account AWS environments where non-production accounts are granted excessive trust relationships with production accounts.

The attack exploits a trust policy in the prod account that explicitly trusts a specific user in the dev account (not just the dev account's `:root`). When the dev user assumes the prod role, they gain full administrative access to the production environment, effectively crossing the security boundary between lower-trust (dev) and higher-trust (prod) environments.

This is particularly dangerous because it violates the principle that production accounts should have stricter access controls than development accounts. A compromise of the dev account, which typically has looser security controls, directly leads to production account compromise.

## The Challenge

You have obtained credentials for `pl-dev-xsare-to-admin-starting-user`, an IAM user in the dev account. Your goal is to gain administrative access in the production account — a completely separate AWS account that should have stronger security controls.

The target is `pl-prod-xsare-to-admin-target-role` in the prod account, which has `AdministratorAccess`. The question is: can you reach it from where you are?

## Reconnaissance

First, let's establish who we are and get our bearings.

```bash
export AWS_ACCESS_KEY_ID="<starting_user_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<starting_user_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

This confirms you're operating as `pl-dev-xsare-to-admin-starting-user` in the dev account. Now let's verify that you don't already have any direct admin access in the prod account — attempting an admin-only operation like listing IAM users should fail:

```bash
aws iam list-users --max-items 1
```

As expected, that fails. You're in the dev account and have no permissions in prod — yet.

Now for the interesting part: check what cross-account capabilities this user has. If you can enumerate the IAM policies attached to this user, you'd find an explicit `sts:AssumeRole` permission targeting a role ARN in the prod account. A CSPM tool or IAM Access Analyzer would surface this as a cross-account privilege escalation path.

## Exploitation

The trust policy on `pl-prod-xsare-to-admin-target-role` explicitly lists the dev account starting user as a trusted principal. This means you can call `sts:AssumeRole` against that role directly — no extra steps needed.

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::{prod_account_id}:role/pl-prod-xsare-to-admin-target-role \
  --role-session-name xsare-attack-session \
  --query 'Credentials' \
  --output json
```

This returns a set of temporary credentials: `AccessKeyId`, `SecretAccessKey`, and `SessionToken`. Export them to switch your identity to the prod role:

```bash
export AWS_ACCESS_KEY_ID="<AccessKeyId from response>"
export AWS_SECRET_ACCESS_KEY="<SecretAccessKey from response>"
export AWS_SESSION_TOKEN="<SessionToken from response>"
```

## Verification

With the prod role credentials active, confirm you're now in the production account:

```bash
aws sts get-caller-identity
```

The `Account` field should show the prod account ID, and the `Arn` should reference `pl-prod-xsare-to-admin-target-role`. Now try the same admin operation that failed before:

```bash
aws iam list-users --max-items 3 --output table
```

It works. You have full `AdministratorAccess` in the prod account, starting from a dev account user.

## What Happened

You crossed from the dev account to the prod account in a single `sts:AssumeRole` call. The prod role's trust policy had been misconfigured to explicitly trust a specific IAM user from a less-controlled environment. There was no MFA requirement, no external ID, no time restriction — just an open door.

In a real environment, this attack path means that anyone who compromises a developer's AWS credentials gains immediate, unrestricted access to production. Dev accounts are typically less secured — developers have broader access, secrets management may be looser, and workstations are more exposed to phishing. The security boundary between dev and prod that organizations rely on to protect production data becomes meaningless the moment a trust relationship like this exists.

IAM Access Analyzer is specifically designed to detect this kind of cross-account access and will flag the prod role as having external access when it trusts a principal from another account in the same organization.

## Capture the Flag

With the prod admin role credentials still active, read the CTF flag from SSM Parameter Store:

```bash
aws ssm get-parameter \
  --name /pathfinding-labs/flags/dev-to-prod-simple-role-assumption-to-admin \
  --query 'Parameter.Value' \
  --output text
```

The flag is stored in the production account and is only accessible with the `ssm:GetParameter` permission, which is granted to the prod admin role via `AdministratorAccess`. Successfully reading it proves you have achieved administrative access in the production account.
