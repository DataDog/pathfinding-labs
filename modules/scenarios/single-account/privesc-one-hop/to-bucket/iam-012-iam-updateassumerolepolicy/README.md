# IAM Role Trust Policy Update to Bucket

* **Category:** Privilege Escalation
* **Sub-Category:** principal-access
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** User with iam:UpdateAssumeRolePolicy can modify role trust policy to assume role with S3 access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_bucket_iam_012_iam_updateassumerolepolicy`
* **Schema Version:** 4.1.1
* **Pathfinding.cloud ID:** iam-012
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0009 - Collection
* **MITRE Techniques:** T1098 - Account Manipulation, T1530 - Data from Cloud Storage Object

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-012-to-bucket-starting-role` IAM role to the `pl-prod-iam-012-to-bucket-target-role` and ultimately access the sensitive S3 bucket `pl-prod-iam-012-to-bucket-{account_id}-{resource_suffix}` by modifying the target role's trust policy using `iam:UpdateAssumeRolePolicy` and then assuming that role.

- **Start:** `arn:aws:iam::{account_id}:role/pl-prod-iam-012-to-bucket-starting-role`
- **Destination resource:** `arn:aws:s3:::pl-prod-iam-012-to-bucket-{account_id}-{resource_suffix}`

### Starting Permissions

**Required** (`pl-prod-iam-012-to-bucket-starting-user`):
- `iam:UpdateAssumeRolePolicy` on `arn:aws:iam::*:role/pl-prod-iam-012-to-bucket-target-role` -- modify the target role's trust policy to allow assumption by the starting role
- `sts:AssumeRole` on `arn:aws:iam::*:role/pl-prod-iam-012-to-bucket-target-role` -- assume the target role once its trust policy has been updated

**Helpful** (`pl-prod-iam-012-to-bucket-starting-user`):
- `iam:ListRoles` -- discover roles with S3 access
- `iam:GetRole` -- view the current trust policy before modification

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable iam-012-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-012-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-012-to-bucket-starting-user` | Starting user for the scenario |
| `arn:aws:iam::{account_id}:role/pl-prod-iam-012-to-bucket-starting-role` | Starting principal with UpdateAssumeRolePolicy permission |
| `arn:aws:iam::{account_id}:role/pl-prod-iam-012-to-bucket-target-role` | Target role with S3 bucket permissions |
| `arn:aws:s3:::pl-prod-iam-012-to-bucket-{account_id}-{resource_suffix}` | Target S3 bucket containing sensitive data |
| `arn:aws:s3:::pl-prod-iam-012-to-bucket-{account_id}-{resource_suffix}/sensitive-data.txt` | Sensitive file in the target bucket |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve starting user credentials from Terraform output
2. Assume the starting role (`pl-prod-iam-012-to-bucket-starting-role`)
3. Check the current trust policy of the target role and confirm role assumption is blocked
4. Use `iam:UpdateAssumeRolePolicy` to modify the target role's trust policy to allow assumption by the starting role
5. Wait 15 seconds for IAM changes to propagate
6. Assume the target role (`pl-prod-iam-012-to-bucket-target-role`)
7. List the contents of the sensitive S3 bucket
8. Download `sensitive-data.txt` from the bucket

#### Resources Created by Attack Script

- Modified trust policy on `pl-prod-iam-012-to-bucket-target-role` allowing the starting role to assume it
- Downloaded file at `/tmp/iam-012-sensitive-data.txt`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-012-iam-updateassumerolepolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-012-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-012-iam-updateassumerolepolicy
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-012-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable iam-012-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `iam-012-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM principal has `iam:UpdateAssumeRolePolicy` permission, enabling modification of role trust policies for privilege escalation
- Role trust policy can be modified to allow unintended principals to assume it
- Role with S3 bucket access (`pl-prod-iam-012-to-bucket-target-role`) has a trust policy modifiable by a lower-privileged principal
- Privilege escalation path exists: starting role → UpdateAssumeRolePolicy → target role → S3 access

#### Prevention Recommendations

- Avoid granting `iam:UpdateAssumeRolePolicy` permissions
- Use resource-based conditions to restrict which roles can have trust policies modified
- Implement SCPs to prevent trust policy modification for sensitive roles
- Monitor CloudTrail for `UpdateAssumeRolePolicy` API calls followed by `AssumeRole` and S3 access
- Enable MFA requirements for sensitive operations
- Use IAM Access Analyzer to identify privilege escalation paths
- Implement S3 bucket policies that restrict access even for privileged roles
- Enable S3 access logging to track data access patterns
- Use AWS Config rules to detect unauthorized trust policy changes

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: UpdateAssumeRolePolicy` -- Trust policy of a role was modified; critical when performed by a non-admin principal on a role with elevated permissions
- `STS: AssumeRole` -- Role assumption event; suspicious when the assuming principal recently modified the target role's trust policy
- `S3: GetObject` -- Object retrieved from S3; high severity when the accessing role was recently assumed via a modified trust policy
- `STS: GetCallerIdentity` -- Identity check often performed by attackers to verify successful role assumption

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

