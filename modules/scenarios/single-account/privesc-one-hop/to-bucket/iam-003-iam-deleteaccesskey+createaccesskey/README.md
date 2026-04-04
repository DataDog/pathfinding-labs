# IAM Access Key Rotation to Bucket

* **Category:** Privilege Escalation
* **Sub-Category:** credential-access
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Bypassing AWS 2-key limit by deleting an existing access key before creating a new one for a user with S3 bucket access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_bucket_iam_003_iam_deleteaccesskey_createaccesskey`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** iam-003
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-iam-003-to-bucket-starting-user` IAM user to the `pl-prod-iam-003-to-bucket-target-user` IAM user by deleting one of the target user's two existing access keys to bypass the AWS 2-key limit and then creating a new access key, using the resulting credentials to read sensitive data from the target S3 bucket.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-iam-003-to-bucket-starting-user`
- **Destination resource:** `arn:aws:s3:::pl-sensitive-data-iam-003-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-iam-003-to-bucket-starting-user`):
- `iam:DeleteAccessKey` on `arn:aws:iam::*:user/pl-prod-iam-003-to-bucket-target-user` -- delete an existing key to free up a slot
- `iam:CreateAccessKey` on `arn:aws:iam::*:user/pl-prod-iam-003-to-bucket-target-user` -- create a new access key for the target user

**Helpful** (`pl-prod-iam-003-to-bucket-starting-user`):
- `iam:ListAccessKeys` -- List existing access keys to identify which one to delete
- `iam:ListUsers` -- Discover users with S3 bucket access to target
- `iam:GetUser` -- View user details and attached policies
- `iam:ListAttachedUserPolicies` -- Identify users with S3 permissions

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_bucket_iam_003_iam_deleteaccesskey_createaccesskey
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
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-003-to-bucket-starting-user` | Scenario-specific starting user with iam:DeleteAccessKey and iam:CreateAccessKey permissions |
| `arn:aws:iam::{account_id}:user/pl-prod-iam-003-to-bucket-target-user` | Target user with 2 pre-existing access keys and S3 bucket read permissions |
| `arn:aws:iam::{account_id}:policy/pl-prod-iam-003-to-bucket-starting-policy` | Policy granting DeleteAccessKey and CreateAccessKey permissions on target user |
| `arn:aws:s3:::pl-sensitive-data-iam-003-{account_id}-{suffix}` | Target S3 bucket containing sensitive data |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Demonstrate the 2-key limit and bypass technique
4. Verify successful privilege escalation to bucket access
5. Output standardized test results for automation

#### Resources Created by Attack Script

- New access key for `pl-prod-iam-003-to-bucket-target-user` (created after deleting one of the two pre-existing keys)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-003-iam-deleteaccesskey+createaccesskey
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

After demonstrating the attack, clean up the access keys created during the demo. The cleanup script will remove the access key created during the demonstration and restore the original access key that was deleted, returning the target user to its pre-attack state while preserving the deployed infrastructure.

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-003-iam-deleteaccesskey+createaccesskey
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_bucket_iam_003_iam_deleteaccesskey_createaccesskey
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

- IAM user `pl-prod-iam-003-to-bucket-starting-user` has both `iam:DeleteAccessKey` and `iam:CreateAccessKey` permissions on `pl-prod-iam-003-to-bucket-target-user`, enabling bypass of the AWS 2-key limit
- A privilege escalation path exists: starting user can create credentials for a user with S3 bucket read access
- The target user `pl-prod-iam-003-to-bucket-target-user` has both active access keys at maximum capacity, increasing the impact of a delete-then-create attack
- The combination of `iam:DeleteAccessKey` + `iam:CreateAccessKey` on the same target resource should be flagged as a credential theft risk, distinct from either permission alone

#### Prevention Recommendations

- Implement least privilege principles - avoid granting both `iam:DeleteAccessKey` and `iam:CreateAccessKey` permissions unless absolutely necessary for legitimate key rotation workflows
- Use resource-based conditions to restrict which users can have access keys manipulated: `"Condition": {"StringNotEquals": {"aws:username": ["service-account-1", "service-account-2"]}}`
- Implement Service Control Policies (SCPs) to prevent access key deletion and creation on privileged accounts or sensitive service accounts
- Monitor CloudTrail for sequential `DeleteAccessKey` followed by `CreateAccessKey` API calls on the same user within a short time window - this is a strong indicator of malicious activity
- Enable MFA requirements for sensitive IAM operations using condition keys like `aws:MultiFactorAuthPresent` to require MFA for access key management operations
- Use IAM Access Analyzer to identify principals with permissions to manipulate access keys for users with sensitive permissions (S3 access, admin access, etc.)
- Implement automated alerting on access key deletion events, especially for service accounts and users with data access permissions, using CloudWatch Events or EventBridge
- Consider using IAM roles with temporary credentials instead of IAM users with long-lived access keys for S3 bucket access
- Deploy CSPM rules that specifically detect the combination of DeleteAccessKey + CreateAccessKey permissions on the same resource, as this combination enables bypassing the 2-key limit
- Implement automated key rotation procedures that use a controlled service with audit logging rather than granting key management permissions to individual users

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: DeleteAccessKey` -- Existing access key deleted for a user; when followed immediately by CreateAccessKey on the same user, indicates 2-key limit bypass and potential credential theft
- `IAM: CreateAccessKey` -- New access key created for an IAM user; critical when the target user has S3 bucket access permissions
- `S3: GetObject` -- Object retrieved from the sensitive S3 bucket; indicates the newly created credentials were used for data access
- `S3: ListBucket` -- Bucket contents listed; used to enumerate sensitive data after gaining target user credentials

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
