# Guided Walkthrough: Reverse Blast Radius: Direct and Indirect S3 Access Through Admin

This tool testing scenario is designed to validate whether Cloud Security Posture Management (CSPM) tools and IAM analysis platforms can correctly answer the critical question: "Who has access to this S3 bucket?" The scenario creates two distinct access paths to the same sensitive S3 bucket — one through direct IAM permissions and another through administrative role assumption.

Many security tools excel at identifying direct permission grants but fail to recognize that principals with administrative access (such as the AWS-managed AdministratorAccess policy) implicitly have access to ALL resources in the account, including specific S3 buckets. This creates blind spots in reverse blast radius analysis, where security teams believe they have a complete picture of who can access sensitive data when in fact they're missing principals with indirect access through broad administrative permissions.

This scenario enables security teams to test their tooling's ability to perform comprehensive reverse blast radius analysis. Tools should identify both user1 (with explicit S3 permissions) and user2 (with access via an administrative role) when querying "who can access this bucket?" Failure to detect the administrative path represents a significant gap in security visibility that could lead to incomplete access reviews, flawed least-privilege implementations, and undetected privilege escalation paths.

## The Challenge

You are given credentials for two IAM users:

- **user1** (`pl-prod-rbr-admin-user1`): an IAM user with explicit S3 permissions scoped to the target bucket
- **user2** (`pl-prod-rbr-admin-user2`): an IAM user with no direct S3 permissions but with the ability to assume `pl-prod-rbr-admin-role3`, an administrative role carrying the AWS-managed AdministratorAccess policy

Your goal is to demonstrate that both principals can read objects from `pl-sensitive-data-rbr-admin-{account_id}-{suffix}`, and to verify that your security tooling detects both access paths when performing reverse blast radius analysis on the bucket.

## Reconnaissance

First, orient yourself. Confirm you know who you're operating as before performing any sensitive actions:

```bash
aws sts get-caller-identity
```

For user1, enumerate what S3 permissions are attached directly:

```bash
aws iam list-attached-user-policies --user-name pl-prod-rbr-admin-user1
aws iam list-user-policies --user-name pl-prod-rbr-admin-user1
```

For user2, the direct S3 permissions will come back empty. Instead, look for what roles user2 can assume:

```bash
aws iam list-attached-user-policies --user-name pl-prod-rbr-admin-user2
aws iam list-user-policies --user-name pl-prod-rbr-admin-user2
```

You'll find an assume-role policy pointing at `pl-prod-rbr-admin-role3`. Check what that role has attached:

```bash
aws iam list-attached-role-policies --role-name pl-prod-rbr-admin-role3
```

The output will show `AdministratorAccess` — the AWS-managed policy granting `*:*` on all resources.

## Exploitation

### Path 1: Direct Access (user1)

Configure your AWS CLI with user1's credentials (retrieved from Terraform outputs), then list all available buckets:

```bash
aws s3api list-buckets --query 'Buckets[*].Name' --output text
```

You'll see `pl-sensitive-data-rbr-admin-{account_id}-{suffix}` in the list. List its contents:

```bash
aws s3 ls s3://pl-sensitive-data-rbr-admin-{account_id}-{suffix}/
```

Read the sensitive object directly — no role assumption needed, because user1's policy grants `s3:GetObject` explicitly:

```bash
aws s3 cp s3://pl-sensitive-data-rbr-admin-{account_id}-{suffix}/sensitive-data.txt -
```

Path 1 is straightforward and most security tools will detect this direct grant.

### Path 2: Indirect Access via Admin Role (user2)

Switch to user2's credentials. Verify that user2 has no direct S3 access first — attempting to list the bucket should be denied:

```bash
aws s3 ls s3://pl-sensitive-data-rbr-admin-{account_id}-{suffix}/
```

Expected: `AccessDenied`. Now assume the administrative role:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::{account_id}:role/pl-prod-rbr-admin-role3 \
  --role-session-name rbr-admin-test \
  --query 'Credentials' \
  --output json
```

Export the returned credentials:

```bash
export AWS_ACCESS_KEY_ID=<AccessKeyId>
export AWS_SECRET_ACCESS_KEY=<SecretAccessKey>
export AWS_SESSION_TOKEN=<SessionToken>
```

Confirm your new identity:

```bash
aws sts get-caller-identity
```

Now, even though no explicit S3 policy is attached to this role, AdministratorAccess grants `*:*` — including full S3 access. List the bucket:

```bash
aws s3 ls s3://pl-sensitive-data-rbr-admin-{account_id}-{suffix}/
```

Read the same sensitive object:

```bash
aws s3 cp s3://pl-sensitive-data-rbr-admin-{account_id}-{suffix}/sensitive-data.txt -
```

Path 2 succeeds just as Path 1 did — but via an entirely different (and less obvious) access route.

## Verification

To confirm both paths work, you can re-run `aws sts get-caller-identity` before each S3 operation to show the different identities accessing the same bucket. A complete test run looks like:

1. user1 identity → `s3:ListBucket` succeeds → `s3:GetObject` succeeds
2. user2 identity → `s3:ListBucket` denied → `sts:AssumeRole` succeeds → role3 identity → `s3:ListBucket` succeeds → `s3:GetObject` succeeds

Both reach the same destination. The key question is: does your security tool report both?

## What Happened

This scenario exposes a common blind spot in reverse blast radius analysis. Starting from a sensitive S3 bucket and asking "who has access?" should produce a list that includes both user1 (obvious — explicit S3 grant) and user2 (non-obvious — implicit access via an administrative role in the same account).

The pattern is widespread in real AWS environments: engineering leads and break-glass accounts often hold AdministratorAccess, and that policy silently grants full access to every resource in the account, including sensitive data stores that appear to have tightly scoped bucket policies. Security teams that rely on direct-grant analysis alone will consistently under-report the blast radius of high-privilege principals, leading to incomplete incident response, flawed access reviews, and a false sense of least-privilege compliance.
