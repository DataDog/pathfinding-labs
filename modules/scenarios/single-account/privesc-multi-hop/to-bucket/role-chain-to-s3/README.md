# role-chain-to-s3

* **Category:** Privilege Escalation
* **Sub-Category:** principal-access
* **Path Type:** multi-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Three-hop role assumption chain to reach S3 bucket access
* **Terraform Variable:** `enable_single_account_privesc_multi_hop_to_bucket_role_chain_to_s3`
* **Schema Version:** 4.0.0
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0008 - Lateral Movement, TA0009 - Collection
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1530 - Data from Cloud Storage Object

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-pathfinding-starting-user-prod` IAM user to the `pl-prod-role-chain-destination-{account_id}` S3 bucket by traversing a three-hop role assumption chain through `pl-prod-initial-role`, `pl-prod-intermediate-role`, and `pl-prod-s3-access-role`.

- **Start:** `arn:aws:iam::{account_id}:user/pl-pathfinding-starting-user-prod`
- **Destination resource:** `arn:aws:s3:::pl-prod-role-chain-destination-{account_id}`

### Starting Permissions

**Required** (`pl-pathfinding-starting-user-prod`):
- `sts:AssumeRole` on `arn:aws:iam::*:role/*` -- allows the starting user to begin traversing the role chain

**Helpful** (`pl-pathfinding-starting-user-prod`):
- `iam:ListRoles` -- discover available roles in the account to identify chain candidates
- `iam:GetRole` -- view role trust policies to map the chain path
- `s3:ListBucket` -- verify bucket access after completing the chain

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_multi_hop_to_bucket_role_chain_to_s3
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `space` to enable it
4. Press `d` to deploy

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
|-----|---------|
| `arn:aws:iam::{PROD_ACCOUNT}:user/pl-prod-role-chain-user` | IAM user that can directly assume the intermediate role (alternate entry point) |
| `arn:aws:iam::{PROD_ACCOUNT}:role/pl-prod-initial-role` | First-hop role; trusted by all prod account users with `sts:AssumeRole` |
| `arn:aws:iam::{PROD_ACCOUNT}:role/pl-prod-intermediate-role` | Second-hop role; trusted by the initial role and the chain user |
| `arn:aws:iam::{PROD_ACCOUNT}:role/pl-prod-s3-access-role` | Third-hop role; holds full S3 access to the destination bucket |
| `arn:aws:s3:::pl-prod-role-chain-destination-{PROD_ACCOUNT}` | Destination S3 bucket with sensitive data; accessible only via the full role chain |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Read starting user credentials from Terraform outputs
2. Assume `pl-prod-initial-role` as the first hop
3. Use the initial role credentials to assume `pl-prod-intermediate-role` as the second hop
4. Use the intermediate role credentials to assume `pl-prod-s3-access-role` as the third hop
5. List and access the contents of the destination S3 bucket to confirm full access

#### Resources Created by Attack Script

- Temporary STS session credentials for each hop (in-memory only; not persisted)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo role-chain-to-s3
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup role-chain-to-s3
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_multi_hop_to_bucket_role_chain_to_s3
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM role (`pl-prod-initial-role`) trusts the entire prod account (`sts:AssumeRole` for `arn:aws:iam::{account_id}:root` or all users); any principal in the account can begin the chain
- Transitive role assumption chain of depth 3 leading to S3 data access; CSPM tools performing multi-hop graph analysis should flag this as a privilege escalation path to sensitive data
- `pl-prod-s3-access-role` has overly broad S3 permissions (`s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket`) on the sensitive bucket and is reachable transitively from low-privilege starting principals
- The intermediate role (`pl-prod-intermediate-role`) is trusted by both the initial role and by a specific IAM user, creating two distinct paths to the same sensitive resource — increasing blast radius

#### Prevention Recommendations

- Apply the principle of least privilege to role trust policies; avoid trusting the entire account (`arn:aws:iam::{account_id}:root`) unless strictly necessary
- Restrict `sts:AssumeRole` with IAM conditions (e.g., `aws:PrincipalTag`, `sts:ExternalId`, or `aws:SourceAccount`) to limit which principals can initiate role chains
- Perform transitive graph analysis on role trust policies to detect multi-hop escalation paths that are invisible when evaluating roles individually
- Limit S3 access permissions on roles that are reachable via chained assumptions; prefer scoped-down resource-based policies on the bucket itself
- Use AWS IAM Access Analyzer to generate access previews and detect overly permissive cross-principal trust relationships
- Regularly audit role trust policies, especially for roles that grant access to sensitive S3 buckets, to ensure no unintended trust chains have accumulated over time

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `STS: AssumeRole` -- Role assumption recorded; three sequential `AssumeRole` calls from the same originating identity within a short time window is a strong indicator of role chain traversal
- `S3: GetObject` -- Object retrieved from the sensitive bucket; especially suspicious when the requesting principal is a role assumed via a chain of `AssumeRole` calls
- `S3: ListBucket` -- Bucket contents listed; baseline recon step after gaining S3 access via a role chain
- `STS: GetCallerIdentity` -- Identity verification call; commonly used by attackers to confirm which role they currently hold at each hop

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
