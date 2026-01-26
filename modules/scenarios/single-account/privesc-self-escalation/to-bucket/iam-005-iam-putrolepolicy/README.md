# One-Hop Privilege Escalation: iam:PutRolePolicy

* **Category:** Privilege Escalation
* **Sub-Category:** self-escalation
* **Path Type:** self-escalation
* **Target:** to-bucket
* **Environments:** prod
* **Pathfinding.cloud ID:** iam-005
* **Technique:** Role with iam:PutRolePolicy on itself can add inline policy granting S3 bucket access

## Overview

This scenario demonstrates privilege escalation where a role with `iam:PutRolePolicy` on itself can modify its own inline policy to gain S3 bucket access, then assume a target role with bucket permissions. This is a self-escalation scenario where the starting role first adds permissions to itself before accessing the target bucket.

## Understanding the attack scenario

### Principals in the attack path

- `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-iam-005-to-bucket-starting-user`
- `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-iam-005-to-bucket-starting-role`
- `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-iam-005-to-bucket-target-role`
- `arn:aws:s3:::pl-prod-iam-005-to-bucket-ACCOUNT_ID-SUFFIX`

### Attack Path Diagram

```mermaid
graph LR
    A[pl-prod-iam-005-to-bucket-starting-user] -->|sts:AssumeRole| B[pl-prod-iam-005-to-bucket-starting-role]
    B -->|iam:PutRolePolicy on self| B
    B -->|sts:AssumeRole| C[pl-prod-iam-005-to-bucket-target-role]
    C -->|s3:GetObject, s3:PutObject| D[pl-prod-iam-005-to-bucket]
    D -->|Access Sensitive Data| E[Sensitive Bucket Access]
```

### Attack Steps

1. **Initial Access**: `pl-prod-iam-005-to-bucket-starting-user` assumes the role `pl-prod-iam-005-to-bucket-starting-role` to begin the scenario
2. **Self-Escalation**: Use `iam:PutRolePolicy` to add an inline policy to the starting role (self) granting S3 bucket access
3. **Assume Target Role**: Assume the `pl-prod-iam-005-to-bucket-target-role` which has S3 permissions
4. **Access S3 Bucket**: Read and download sensitive data from the target bucket

### Scenario specific resources created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-iam-005-to-bucket-starting-user` | Starting user with AssumeRole permission |
| `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-iam-005-to-bucket-starting-role` | Starting role with PutRolePolicy permission on itself |
| `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-iam-005-to-bucket-target-role` | Target role with S3 bucket permissions |
| `arn:aws:iam::PROD_ACCOUNT:policy/pl-prod-iam-005-to-bucket-access-policy` | Grants S3 read/write access to target bucket |
| `arn:aws:s3:::pl-prod-iam-005-to-bucket-ACCOUNT_ID-SUFFIX` | Target S3 bucket containing sensitive data |
| `arn:aws:s3:::pl-prod-iam-005-to-bucket-ACCOUNT_ID-SUFFIX/sensitive-data.txt` | Sensitive file in the target bucket |

## Executing the attack

### Using the automated demo_attack.sh

To demonstrate the privilege escalation path, run the provided demo script:

```bash
cd modules/scenarios/single-account/privesc-self-escalation/to-bucket/iam-005-iam-putrolepolicy
./demo_attack.sh
```

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Verify successful privilege escalation to bucket access
4. Output standardized test results for automation

### Cleaning up the attack artifacts

After demonstrating the attack, clean up the inline policy added during the demo:

```bash
cd modules/scenarios/single-account/privesc-self-escalation/to-bucket/iam-005-iam-putrolepolicy
./cleanup_attack.sh
```

## Detection and prevention


### MITRE ATT&CK Mapping

- **Tactic**: Privilege Escalation, Collection
- **Technique**: T1078.004 - Valid Accounts: Cloud Accounts
- **Sub-technique**: T1530 - Data from Cloud Storage Object


## Prevention recommendations

- Avoid granting `iam:PutRolePolicy` permissions on roles (especially on self)
- Use resource-based conditions to restrict which roles can be modified
- Implement SCPs to prevent privilege escalation techniques
- Monitor CloudTrail for `PutRolePolicy` API calls on the same role followed by `AssumeRole` and S3 access
- Enable MFA requirements for sensitive operations
- Use IAM Access Analyzer to identify privilege escalation paths
- Implement S3 bucket policies that restrict access even for privileged roles
- Enable S3 access logging to track data access patterns

