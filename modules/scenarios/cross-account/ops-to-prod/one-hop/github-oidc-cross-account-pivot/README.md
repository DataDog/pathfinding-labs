# GitHub Actions OIDC to Cross-Account S3 via Ops-to-Prod Pivot

* **Category:** Privilege Escalation
* **Path Type:** cross-account
* **Target:** to-bucket
* **Environments:** operations, prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** GitHub repo write access enables OIDC assumption of an ops role that pivots cross-account to a prod role with S3 read access on a sensitive bucket.
* **Terraform Variable:** `enable_cross_account_ops_to_prod_github_oidc_pivot`
* **Schema Version:** 4.6.0
* **CTF Flag Location:** s3-object
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0008 - Lateral Movement
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1550.001 - Use Alternate Authentication Material: Application Access Token

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the GitHub Actions OIDC identity for the configured repository to the `pl-prod-goidc-pivot-flag-{account_id}-{suffix}` S3 bucket in the prod account by using OIDC federation to assume `pl-ops-goidc-pivot-deployer-role` in the operations account and then pivoting cross-account to `pl-prod-goidc-pivot-deployer-role` to read sensitive objects.

- **Start:** GitHub Actions workflow in `{github_repo}` (OIDC federation, no static AWS credentials required)
- **Destination resource:** `arn:aws:s3:::pl-prod-goidc-pivot-flag-{account_id}-{suffix}`

### Starting Permissions

**Required** (`GitHub Actions (repo: {github_repo})`):
- `sts:AssumeRoleWithWebIdentity` on `arn:aws:iam::{operations_account_id}:role/pl-ops-goidc-pivot-deployer-role` -- OIDC token issued by GitHub Actions is accepted by the ops account OIDC provider; the trust policy uses a wildcard on the `sub` claim allowing any ref in the repo

**Required** (`pl-ops-goidc-pivot-deployer-role`):
- `sts:AssumeRole` on `arn:aws:iam::{prod_account_id}:role/pl-prod-goidc-pivot-deployer-role` -- ops deployer role is explicitly trusted by the prod deployer role, enabling cross-account pivot

**Required** (`pl-prod-goidc-pivot-deployer-role`):
- `s3:GetObject` on `arn:aws:s3:::pl-prod-goidc-pivot-flag-{account_id}-{suffix}/*` -- read access to all objects in the sensitive flag bucket
- `s3:ListBucket` on `arn:aws:s3:::pl-prod-goidc-pivot-flag-{account_id}-{suffix}` -- list bucket contents to discover object keys

**Helpful** (`pl-ops-goidc-pivot-deployer-role`):
- `sts:GetCallerIdentity` -- verify OIDC assumption succeeded before pivoting
- `iam:ListRoles` -- discover assumable roles in the prod account
- `s3:ListAllMyBuckets` -- enumerate buckets accessible after cross-account pivot

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew tap DataDog/pathfinding-labs https://github.com/DataDog/pathfinding-labs
   brew install DataDog/pathfinding-labs/plabs
   ```
   Or with Go 1.25+ installed:
   ```bash
   go install github.com/DataDog/pathfinding-labs/cmd/plabs@latest
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

> **Per-scenario configuration required:** Before deploying, set the GitHub repository that should be trusted to assume the ops deployer role:
> ```bash
> plabs config github-oidc-cross-account-pivot set github_repo org/repo
> ```
> Replace `org/repo` with your actual GitHub organization and repository name (e.g., `my-org/my-deploy-repo`).

### Deploy with plabs non-interactive

```bash
plabs enable github-oidc-cross-account-pivot-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `github-oidc-cross-account-pivot-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{operations_account_id}:oidc-provider/token.actions.githubusercontent.com` | GitHub Actions OIDC provider in the operations account; trust policy uses wildcard sub-claim |
| `arn:aws:iam::{operations_account_id}:role/pl-ops-goidc-pivot-deployer-role` | Ops account role assumable via GitHub OIDC; has cross-account AssumeRole to prod |
| `arn:aws:iam::{prod_account_id}:role/pl-prod-goidc-pivot-deployer-role` | Prod account role trusted by ops deployer role; has S3 read access to the flag bucket |
| `arn:aws:s3:::pl-prod-goidc-pivot-flag-{account_id}-{suffix}` | Prod S3 bucket containing `sensitive-data.txt` with legacy flag content |
| `s3://pl-prod-goidc-pivot-flag-{account_id}-{suffix}/flag.txt` | CTF flag object; read with `aws s3 cp s3://...flag.txt -` once prod role credentials are held |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve scenario configuration (GitHub repo, account IDs) from Terraform outputs
2. Construct and display the GitHub Actions workflow YAML that exploits the OIDC trust
3. Assume `pl-ops-goidc-pivot-deployer-role` in the operations account using a GitHub Actions OIDC token (or simulate the token exchange locally using the configured AWS profile)
4. Verify ops role identity with `sts:GetCallerIdentity`
5. Use the ops role to call `sts:AssumeRole` and pivot to `pl-prod-goidc-pivot-deployer-role` in the prod account
6. Verify prod role identity to confirm cross-account pivot succeeded
7. List and read the contents of `sensitive-data.txt` from the flag bucket
8. Read `flag.txt` from the flag bucket to capture the CTF flag

#### Resources Created by Attack Script

- Temporary STS session credentials for `pl-ops-goidc-pivot-deployer-role` (expire automatically)
- Temporary STS session credentials for `pl-prod-goidc-pivot-deployer-role` (expire automatically)
- No persistent artifacts created; all credentials are ephemeral

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo github-oidc-cross-account-pivot
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

This scenario does not create persistent attack artifacts. All STS session credentials are ephemeral and expire automatically. No cleanup script is needed.

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup github-oidc-cross-account-pivot
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable github-oidc-cross-account-pivot-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `github-oidc-cross-account-pivot-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- **Wildcard OIDC Sub-Claim**: The `pl-ops-goidc-pivot-deployer-role` trust policy accepts any `sub` claim matching `repo:{github_repo}:*`, allowing any branch, tag, or pull request trigger in the repo to assume the role -- not just protected branches
- **OIDC Role with Cross-Account Pivot**: An IAM role in the operations account is assumable via an external OIDC provider AND has `sts:AssumeRole` permission on a role in a different account, forming a two-hop path from GitHub to prod
- **CI/CD Identity with Prod Data Access**: The prod deployer role has direct `s3:GetObject` on a sensitive bucket and is reachable from an external CI/CD system, creating a path from any repository write access to production data exfiltration
- **No Condition Keys on OIDC Trust**: The trust policy does not restrict `token.actions.githubusercontent.com:sub` to a specific branch (e.g., `repo:{github_repo}:ref:refs/heads/main`) or environment, allowing feature branches and forks with write access to trigger the assumption
- **Cross-Account Trust Without External ID**: The prod role trusts the ops role without requiring an external ID, making the trust unconditional once the ops role is assumed

#### Prevention Recommendations

- **Pin the OIDC sub-claim to a protected branch or environment**: Replace `repo:{github_repo}:*` with `repo:{github_repo}:ref:refs/heads/main` or use a GitHub Actions environment with required reviewers:
  ```json
  {
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:sub": "repo:org/repo:environment:production"
      }
    }
  }
  ```
- **Scope the ops role's cross-account permission**: Instead of allowing `sts:AssumeRole` on the prod role unconditionally, add an `aws:RequestedRegion` or tag-based condition, and consider whether the ops role truly needs cross-account access or whether a dedicated prod-side role with a more restrictive trust is sufficient
- **Use Service Control Policies to restrict OIDC role assumptions**: Apply an SCP that denies `sts:AssumeRoleWithWebIdentity` for roles with cross-account pivot capability, requiring explicit allowlisting through a change management process
- **Separate CI/CD deployment identities by environment**: Use distinct OIDC roles per environment (ops vs. prod) rather than a single role that chains across accounts; the prod deployment role should be assumable only by a prod-specific OIDC identity, not routed through the ops account
- **Enable IAM Access Analyzer with organization-level findings**: Access Analyzer will flag `pl-prod-goidc-pivot-deployer-role` as externally accessible (trusted by the ops account) and surface the full path from GitHub Actions to the prod bucket
- **Audit OIDC providers regularly**: Use `iam:ListOpenIDConnectProviders` and `iam:GetOpenIDConnectProvider` to inventory all OIDC providers and confirm that the audience and thumbprint are restricted to expected values; remove unused OIDC providers

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `sts:AssumeRoleWithWebIdentity` -- OIDC-based role assumption in the operations account; look for the `WebIdentityToken` issuer matching `token.actions.githubusercontent.com` and flag assumptions from unexpected repos or refs
- `sts:AssumeRole` -- Cross-account role assumption where the source account is the operations account and the target role is in prod; correlate with a preceding `AssumeRoleWithWebIdentity` event in the ops account to identify the full chain
- `s3:GetObject` -- Object retrieval from the flag bucket using credentials belonging to `pl-prod-goidc-pivot-deployer-role`; alert when the assumed-role session originates from a cross-account assumption chain rather than a known deployment pipeline

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [GitHub Actions: Configuring OpenID Connect in Amazon Web Services](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services) -- GitHub's official guidance on OIDC federation with AWS, including trust policy conditions
- [MITRE ATT&CK: T1078.004 - Valid Accounts: Cloud Accounts](https://attack.mitre.org/techniques/T1078/004/) -- technique covering abuse of valid cloud credentials
- [MITRE ATT&CK: T1550.001 - Use Alternate Authentication Material: Application Access Token](https://attack.mitre.org/techniques/T1550/001/) -- technique covering OIDC tokens and other non-password authentication material
- [AWS IAM: Creating OpenID Connect (OIDC) identity providers](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html) -- AWS documentation on configuring OIDC providers and trust policies
