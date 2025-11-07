# Privilege Escalation via iam:DeleteAccessKey + iam:CreateAccessKey

**Category:** Privilege Escalation
**Sub-Category:** credential-access
**Path Type:** one-hop
**Target:** to-bucket
**Environments:** prod
**Pathfinding.cloud ID:** iam-003
**Technique:** Bypassing AWS 2-key limit by deleting an existing access key before creating a new one for a user with S3 bucket access

## Overview

This scenario demonstrates a sophisticated variation of the `iam:CreateAccessKey` privilege escalation technique that overcomes AWS's built-in security control limiting users to a maximum of two access keys. When an attacker has both `iam:DeleteAccessKey` and `iam:CreateAccessKey` permissions on a target user who already has two active access keys, the standard key creation approach would fail. However, by first deleting one of the existing keys and then creating a new one, the attacker bypasses this limit and gains access to the target user's credentials.

This attack pattern is particularly dangerous because it targets users who already have S3 bucket access permissions. In real-world environments, service accounts and automation users often have both access keys actively in use for different applications or services. The deletion of an existing key might cause a service disruption, but it also provides the attacker with fresh credentials that can be used to access sensitive data stored in S3 buckets.

The combination of these two permissions creates a powerful privilege escalation path that CSPM tools must detect. While many security tools flag `iam:CreateAccessKey` as a risk, fewer recognize that the pairing with `iam:DeleteAccessKey` enables an attacker to bypass AWS's native control mechanism. Detection systems should specifically monitor for sequential DeleteAccessKey/CreateAccessKey operations on the same user, as this pattern indicates potential credential theft in progress.

## Understanding the attack scenario

### Principals in the attack path

- `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-dakcak-to-bucket-starting-user` (Scenario-specific starting user with DeleteAccessKey and CreateAccessKey permissions)
- `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-dakcak-to-bucket-target-user` (Target user with S3 bucket access and 2 existing access keys)
- `arn:aws:s3:::pl-sensitive-data-PROD_ACCOUNT-SUFFIX` (Target S3 bucket with sensitive data)

### Attack Path Diagram

```mermaid
graph LR
    A[pl-prod-dakcak-to-bucket-starting-user] -->|iam:ListAccessKeys| B[List Existing Keys]
    B -->|iam:DeleteAccessKey| C[Delete One Key]
    C -->|iam:CreateAccessKey| D[pl-prod-dakcak-to-bucket-target-user]
    D -->|New Credentials| E[S3 Bucket Access]

    style A fill:#ff9999,stroke:#333,stroke-width:2px
    style B fill:#ffcc99,stroke:#333,stroke-width:2px
    style C fill:#ffcc99,stroke:#333,stroke-width:2px
    style D fill:#ffcc99,stroke:#333,stroke-width:2px
    style E fill:#99ff99,stroke:#333,stroke-width:2px
```

### Attack Steps

1. **Initial Access**: Start as `pl-prod-dakcak-to-bucket-starting-user` (credentials provided via Terraform outputs)
2. **List Access Keys**: Use `iam:ListAccessKeys` to discover that the target user already has 2 active access keys (AWS maximum)
3. **Delete Access Key**: Use `iam:DeleteAccessKey` to delete one of the existing access keys, freeing up a slot
4. **Create Access Key**: Use `iam:CreateAccessKey` to create a new access key for the target user (which would have failed without the deletion step)
5. **Switch Context**: Configure AWS CLI with the newly created access key and secret key
6. **Verification**: Verify S3 bucket access by listing objects and reading sensitive data from the bucket

### Scenario specific resources created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-dakcak-to-bucket-starting-user` | Scenario-specific starting user with iam:DeleteAccessKey and iam:CreateAccessKey permissions |
| `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-dakcak-to-bucket-target-user` | Target user with 2 pre-existing access keys and S3 bucket read permissions |
| `arn:aws:iam::PROD_ACCOUNT:policy/pl-prod-dakcak-to-bucket-starting-policy` | Policy granting DeleteAccessKey and CreateAccessKey permissions on target user |
| `arn:aws:s3:::pl-sensitive-data-PROD_ACCOUNT-SUFFIX` | Target S3 bucket containing sensitive data |

## Executing the attack

### Using the automated demo_attack.sh

To demonstrate the privilege escalation path, run the provided demo script:

```bash
cd modules/scenarios/single-account/privesc-one-hop/to-bucket/iam-deleteaccesskey+createaccesskey
./demo_attack.sh
```

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Demonstrate the 2-key limit and bypass technique
4. Verify successful privilege escalation to bucket access
5. Output standardized test results for automation

### Cleaning up the attack artifacts

After demonstrating the attack, clean up the access keys created during the demo:

```bash
cd modules/scenarios/single-account/privesc-one-hop/to-bucket/iam-deleteaccesskey+createaccesskey
./cleanup_attack.sh
```

The cleanup script will remove the access key created during the demonstration and restore the original access key that was deleted, returning the target user to its pre-attack state while preserving the deployed infrastructure.

## Detection and prevention


### MITRE ATT&CK Mapping

- **Tactic**: TA0004 - Privilege Escalation, TA0003 - Persistence
- **Technique**: T1098.001 - Account Manipulation: Additional Cloud Credentials


## Prevention recommendations

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
