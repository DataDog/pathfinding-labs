# Guided Walkthrough: Reverse Blast Radius Query Detection (Direct and Indirect S3 Access)

This scenario is specifically designed to validate that Cloud Security Posture Management (CSPM) tools and security analysis platforms can accurately answer the critical question: "Who has access to this S3 bucket?" Modern security tools must identify not only direct IAM permissions that grant bucket access, but also indirect access paths through role assumption chains.

The scenario creates two distinct access paths to the same sensitive S3 bucket. The first path provides direct IAM permissions to a user, granting immediate access to the bucket. The second path involves an intermediate role assumption — a user can assume a role, and that role has the same S3 bucket permissions. Both users should appear in any "reverse blast radius" query asking "who can access this bucket?"

This test is essential for validating security tool accuracy because many tools fail to traverse the complete graph of IAM relationships. A tool that only reports direct permissions would miss half the risk surface, failing to identify users who can reach the bucket through role assumption. Organizations rely on these queries to understand their true attack surface, make access decisions, and respond to incidents. This scenario provides a definitive test case: if a security tool cannot identify both users as having bucket access, it has incomplete visibility into the environment's IAM topology.

## The Challenge

You start with credentials for two IAM users:

- `pl-prod-rbr-di-user1` — This user has direct `s3:GetObject` and `s3:ListBucket` permissions attached to their identity.
- `pl-prod-rbr-di-user2` — This user has no direct S3 permissions, but can assume `pl-prod-rbr-di-role3`, which does have the same S3 permissions.

Your goal is to demonstrate that both users can access the `pl-sensitive-data-rbr-di-{account_id}-{suffix}` bucket — user1 directly, user2 via role assumption — and confirm that a security tool performing a reverse blast radius query on the bucket returns both principals.

## Reconnaissance

First, let's confirm what we're working with. Using read-only credentials, verify the account:

```bash
aws sts get-caller-identity --query 'Account' --output text
```

Now confirm user1's identity:

```bash
# Switch to user1 credentials
export AWS_ACCESS_KEY_ID="<user1_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<user1_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity --query 'Arn' --output text
# Expected: arn:aws:iam::{account_id}:user/pl-prod-rbr-di-user1
```

You can also browse what buckets are visible (user1 may not have `s3:ListAllMyBuckets`, but it's worth checking):

```bash
aws s3 ls
```

## Exploitation

### Path 1: Direct Access (user1)

With user1's credentials active, list the objects in the sensitive bucket:

```bash
aws s3 ls "s3://pl-sensitive-data-rbr-di-{account_id}-{suffix}/"
```

Download an object to confirm full read access:

```bash
aws s3 cp "s3://pl-sensitive-data-rbr-di-{account_id}-{suffix}/sensitive-data.txt" /tmp/sensitive-user1.txt
cat /tmp/sensitive-user1.txt
```

This succeeds immediately — user1's IAM user policy grants `s3:GetObject` and `s3:ListBucket` directly. No role assumption is required.

### Path 2: Indirect Access (user2 via role3)

Switch to user2's credentials:

```bash
export AWS_ACCESS_KEY_ID="<user2_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<user2_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity --query 'Arn' --output text
# Expected: arn:aws:iam::{account_id}:user/pl-prod-rbr-di-user2
```

Try to access the bucket directly — this should fail:

```bash
aws s3 ls "s3://pl-sensitive-data-rbr-di-{account_id}-{suffix}/"
# Expected: An error occurred (AccessDenied)
```

User2 has no direct S3 permissions. However, user2 can assume `pl-prod-rbr-di-role3`. The role's trust policy explicitly allows `pl-prod-rbr-di-user2` as a trusted principal. Assume it:

```bash
CREDENTIALS=$(aws sts assume-role \
    --role-arn "arn:aws:iam::{account_id}:role/pl-prod-rbr-di-role3" \
    --role-session-name rbr-test \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')
```

Now list the bucket using role3's credentials:

```bash
aws s3 ls "s3://pl-sensitive-data-rbr-di-{account_id}-{suffix}/"
```

Download an object:

```bash
aws s3 cp "s3://pl-sensitive-data-rbr-di-{account_id}-{suffix}/sensitive-data.txt" /tmp/sensitive-role3.txt
cat /tmp/sensitive-role3.txt
```

This succeeds because `pl-prod-rbr-di-role3` holds the same `s3:GetObject` and `s3:ListBucket` permissions as user1.

## Verification

Both paths are now confirmed:

1. `pl-prod-rbr-di-user1` accessed the bucket directly (no role assumption).
2. `pl-prod-rbr-di-user2` accessed the bucket indirectly by assuming `pl-prod-rbr-di-role3`.

The definitive test is to ask your security tool: "Who can access `pl-sensitive-data-rbr-di-{account_id}-{suffix}`?" A complete answer must include all three of the following:

```
- arn:aws:iam::{account_id}:user/pl-prod-rbr-di-user1  (direct IAM permissions)
- arn:aws:iam::{account_id}:user/pl-prod-rbr-di-user2  (indirect via role assumption)
- arn:aws:iam::{account_id}:role/pl-prod-rbr-di-role3  (direct IAM permissions on the role itself)
```

If your tool returns only user1 and role3, it is not traversing the role trust relationship to trace back to user2. If it returns only user1, it is not analyzing role permissions at all.

## What Happened

This scenario exposed a common gap in security tool IAM analysis: the difference between who directly holds a permission and who can effectively exercise it. User2 never had S3 permissions in their own policy, but by holding `sts:AssumeRole` on a role that does, they are functionally equivalent to user1 from the bucket's perspective.

In real environments, this pattern is pervasive. Service roles, deployment pipelines, and cross-account trust relationships all create indirect access paths that only appear when a tool traverses the full IAM graph. Blast radius queries that stop at direct permissions give organizations a false sense of how contained their sensitive resources truly are. This scenario gives you a reproducible, verifiable test case to measure whether your tooling has the graph traversal depth required to answer "who has access to X" accurately.
