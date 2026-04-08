# Guided Walkthrough: Cross-Account Dev to Prod Root Trust Role Assumption

This scenario demonstrates a critical cross-account privilege escalation vulnerability where a production administrative role trusts the entire dev account via the `:root` principal, rather than trusting specific users or roles. This represents one of the most dangerous misconfigurations in multi-account AWS environments.

The attack exploits an overly permissive trust policy in the prod account that trusts `arn:aws:iam::{DEV_ACCOUNT}:root` instead of specific principal ARNs. When a trust policy uses the `:root` principal, it means **ANY** principal in that account can assume the role, as long as they have `sts:AssumeRole` permission. This is far more dangerous than trusting specific users or roles.

In this scenario, a user in the dev account with `sts:AssumeRole` permission can assume the production admin role and gain full administrative access. If ANY principal in the dev account is compromised, the attacker can immediately escalate to production admin privileges. This violates the fundamental security principle that production accounts should have stricter access controls than development accounts.

## The Challenge

You start as `pl-dev-xsarrt-to-admin-starting-user` in the dev account. This user has `sts:AssumeRole` permission. Your goal is to gain administrative access in the prod account by exploiting the `:root` trust policy on `pl-prod-xsarrt-to-admin-target-role`.

- **Start:** `arn:aws:iam::{dev_account_id}:user/pl-dev-xsarrt-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{prod_account_id}:role/pl-prod-xsarrt-to-admin-target-role`

## Reconnaissance

First, confirm your identity in the dev account:

```bash
aws sts get-caller-identity
```

You should see the dev account ID and the starting user ARN. Now, the key insight: is there a prod role that trusts the entire dev account? You can discover this by listing roles in the prod account if you have `iam:ListRoles`, or by simply knowing the target role ARN from the Terraform outputs:

```bash
# Check the trust policy of the target prod role (requires iam:GetRole in prod)
aws iam get-role --role-name pl-prod-xsarrt-to-admin-target-role
```

The trust policy will contain `arn:aws:iam::{DEV_ACCOUNT}:root` — meaning any dev principal with `sts:AssumeRole` can assume it.

## Exploitation

The vulnerability is straightforward once you understand the trust policy. Because the target role trusts `:root` of the entire dev account, your starting user qualifies as a trusted principal.

Assume the production admin role:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::{prod_account_id}:role/pl-prod-xsarrt-to-admin-target-role \
  --role-session-name cross-account-escalation
```

Extract the temporary credentials from the response and export them:

```bash
export AWS_ACCESS_KEY_ID=<AccessKeyId from response>
export AWS_SECRET_ACCESS_KEY=<SecretAccessKey from response>
export AWS_SESSION_TOKEN=<SessionToken from response>
```

## Verification

Verify you are now operating as the prod admin role:

```bash
aws sts get-caller-identity
```

You should see the prod account ID and the assumed role ARN. Now confirm administrative access:

```bash
aws iam list-users --max-items 3
```

If this succeeds, you have full administrative access to the production account.

## What Happened

You exploited an overly permissive cross-account trust policy. The prod admin role's trust policy contained `"Principal": {"AWS": "arn:aws:iam::{DEV_ACCOUNT}:root"}`, which is semantically equivalent to "any principal in the dev account." Because your starting user had `sts:AssumeRole` permission, one API call was all it took to gain production admin access.

The real-world risk here is severe: the blast radius of any dev account compromise extends directly to production administrative access. A phished developer, a leaked access key, or a vulnerable EC2 instance in dev can all lead to full production compromise. Replacing `:root` trust with explicit principal ARNs eliminates this entire attack surface.

**Why `:root` trust is dangerous:**

```json
// VULNERABLE: Trusts the entire dev account
{
  "Principal": {
    "AWS": "arn:aws:iam::{DEV_ACCOUNT}:root"
  }
}

// SAFER: Trusts only a specific approved role
{
  "Principal": {
    "AWS": "arn:aws:iam::{DEV_ACCOUNT}:role/specific-approved-role"
  }
}
```

With `:root` trust, compromise of ANY dev principal equals production admin access. With explicit trust, the attacker must compromise the one specific trusted principal.
