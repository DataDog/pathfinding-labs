# One-Hop Privilege Escalation: iam:AttachRolePolicy

* **Category:** Privilege Escalation
* **Sub-Category:** self-escalation
* **Path Type:** self-escalation
* **Target:** to-bucket
* **Environments:** prod
* **Pathfinding.cloud ID:** iam-009
* **Technique:** Role with iam:AttachRolePolicy on itself can attach policy granting S3 bucket access

## Overview

This scenario demonstrates privilege escalation where an attacker can attach managed policies to another role using `iam:AttachRolePolicy`, then assume that role to gain access to a sensitive S3 bucket. The attacker attaches the AWS-managed AmazonS3FullAccess policy to a role they can assume, granting them access to all S3 buckets in the account.

## Understanding the attack scenario

### Principals in the attack path

- `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-iam-009-to-bucket-starting-user`
- `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-iam-009-to-bucket-starting-role`
- `arn:aws:s3:::pl-prod-iam-009-to-bucket-ACCOUNT_ID-SUFFIX`

### Attack Path Diagram

```mermaid
graph LR
    A[pl-prod-iam-009-to-bucket-starting-user] -->|sts:AssumeRole| B[pl-prod-iam-009-to-bucket-starting-role]
    B -->|iam:AttachRolePolicy on self| B
    B -->|s3:GetObject, s3:PutObject| C[pl-prod-iam-009-to-bucket]
    C -->|Access Sensitive Data| D[Sensitive Bucket Access]
```

### Attack Steps

1. **Initial Access**: Use credentials for `pl-prod-iam-009-to-bucket-starting-user`
2. **Assume Starting Role**: Assume `pl-prod-iam-009-to-bucket-starting-role`
3. **Self-Escalation**: Use `iam:AttachRolePolicy` to attach S3 bucket access policy to self (the current role)
4. **Access S3 Bucket**: Read and download sensitive data from the target bucket

### Scenario specific resources created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-iam-009-to-bucket-starting-user` | Starting user with credentials |
| `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-iam-009-to-bucket-starting-role` | Starting role with AttachRolePolicy permission on itself |
| `arn:aws:iam::PROD_ACCOUNT:policy/pl-prod-iam-009-to-bucket-access-policy` | Grants S3 read/write access to target bucket (to be attached during escalation) |
| `arn:aws:s3:::pl-prod-iam-009-to-bucket-ACCOUNT_ID-SUFFIX` | Target S3 bucket containing sensitive data |
| `arn:aws:s3:::pl-prod-iam-009-to-bucket-ACCOUNT_ID-SUFFIX/sensitive-data.txt` | Sensitive file in the target bucket |

## Executing the attack

### Using the automated demo_attack.sh

To demonstrate the privilege escalation path, run the provided demo script:

```bash
cd modules/scenarios/single-account/privesc-self-escalation/to-bucket/iam-009-iam-attachrolepolicy
./demo_attack.sh
```

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Verify successful privilege escalation to bucket access
4. Output standardized test results for automation

### Cleaning up the attack artifacts

After demonstrating the attack, clean up the attached policy:

```bash
cd modules/scenarios/single-account/privesc-self-escalation/to-bucket/iam-009-iam-attachrolepolicy
./cleanup_attack.sh
```

## Detection and prevention


### MITRE ATT&CK Mapping

- **Tactic**: Privilege Escalation, Collection
- **Technique**: T1078.004 - Valid Accounts: Cloud Accounts
- **Sub-technique**: T1530 - Data from Cloud Storage Object


## Prevention recommendations

- Avoid granting `iam:AttachRolePolicy` permissions on other roles
- Use resource-based conditions to restrict which roles can be modified
- Implement SCPs to prevent privilege escalation techniques
- Monitor CloudTrail for `AttachRolePolicy` API calls followed by `AssumeRole` and S3 access
- Enable MFA requirements for sensitive operations
- Use IAM Access Analyzer to identify privilege escalation paths
- Restrict attachment of high-privilege AWS-managed policies like AmazonS3FullAccess
- Implement S3 bucket policies that restrict access even for privileged roles
- Enable S3 access logging to track data access patterns

