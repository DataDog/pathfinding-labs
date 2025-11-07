# One-Hop Privilege Escalation: iam:CreateLoginProfile

**Scenario Type:** One-Hop
* **Target:** S3 Bucket Access
* **Technique:** Console credential creation for bucket-access user via iam:CreateLoginProfile

## Overview

This scenario demonstrates a privilege escalation vulnerability where a user has permission to create login profiles (console passwords) for another IAM user with S3 bucket access. Unlike the to-admin variant which targets administrative privileges, this scenario focuses on data exfiltration - demonstrating that privilege escalation to sensitive data access can be just as critical as gaining admin rights.

The attacker uses programmatic access credentials with `iam:CreateLoginProfile` permission to create a console password for a target user who has permissions to access a sensitive S3 bucket. By creating console credentials for this user, the attacker can then log into the AWS Management Console and directly access sensitive data stored in S3 buckets. This path demonstrates that not all privilege escalation leads to admin access, yet the impact can be equally severe when sensitive data is the target.

## Understanding the attack scenario

### Principals in the attack path

- `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-clp-bucket-starting-user` (Scenario-specific starting user with programmatic access)
- `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-clp-bucket-hop1` (Target user with S3 bucket access, initially without console access)
- `arn:aws:s3:::pl-sensitive-data-clp-ACCOUNT_ID-SUFFIX` (Sensitive data bucket)

### Attack Path Diagram

```mermaid
graph LR
    A[pl-prod-clp-bucket-starting-user] -->|iam:CreateLoginProfile| B[pl-prod-clp-bucket-hop1]
    B -->|Console Login| C[AWS Console Access]
    C -->|s3:GetObject, s3:ListBucket| D[pl-sensitive-data-clp bucket]

    style A fill:#ff9999,stroke:#333,stroke-width:2px
    style B fill:#ffcc99,stroke:#333,stroke-width:2px
    style C fill:#ffcc99,stroke:#333,stroke-width:2px
    style D fill:#99ff99,stroke:#333,stroke-width:2px
```

### Attack Steps

1. **Initial Access**: Start as `pl-prod-clp-bucket-starting-user` (credentials provided via Terraform outputs)
2. **Create Login Profile**: Use `iam:CreateLoginProfile` to create a console password for the target user `pl-prod-clp-bucket-hop1`
3. **Console Login**: Log into the AWS Management Console using the target user's username and the newly created password
4. **Access S3 Bucket**: Navigate to the S3 console and access the sensitive data bucket `pl-sensitive-data-clp-*`
5. **Verification**: Read and download sensitive data using S3 read permissions

### Scenario specific resources created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-clp-bucket-starting-user` | Scenario-specific starting user with programmatic access and CreateLoginProfile permission |
| `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-clp-bucket-hop1` | Target user with S3 bucket access (initially no console password) |
| `pl-prod-clp-bucket-starting-user-policy` (inline policy) | Allows `iam:CreateLoginProfile` on `pl-prod-clp-bucket-hop1` only |
| `pl-prod-clp-bucket-hop1-s3-policy` (inline policy) | Grants S3 read access to sensitive bucket |
| `arn:aws:s3:::pl-sensitive-data-clp-ACCOUNT_ID-SUFFIX` | Target S3 bucket containing sensitive data |
| `arn:aws:s3:::pl-sensitive-data-clp-ACCOUNT_ID-SUFFIX/sensitive-data.txt` | Sensitive file in the target bucket |

## Executing the attack

### Using the automated demo_attack.sh

To demonstrate the privilege escalation path, run the provided demo script:

```bash
cd modules/scenarios/single-account/privesc-one-hop/to-bucket/iam-createloginprofile
./demo_attack.sh
```

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create a console password for the target user
4. Display console login URL and credentials
5. Verify successful privilege escalation to bucket access
6. Output standardized test results for automation

### Cleaning up the attack artifacts

After demonstrating the attack, clean up the login profile created during the demo:

```bash
cd modules/scenarios/single-account/privesc-one-hop/to-bucket/iam-createloginprofile
./cleanup_attack.sh
```

## Detection and prevention


### MITRE ATT&CK Mapping

- **Tactic**: Privilege Escalation (TA0004), Persistence (TA0003), Collection (TA0009)
- **Technique**: T1098.001 - Account Manipulation: Additional Cloud Credentials
- **Sub-technique**: T1530 - Data from Cloud Storage Object


## Prevention recommendations

- Avoid granting `iam:CreateLoginProfile` permissions on users with sensitive data access (S3, databases, etc.)
- Use resource-based conditions to restrict which users can have login profiles created: `"Condition": {"StringEquals": {"aws:username": "${aws:username}"}}`
- Implement SCPs to prevent login profile creation on users with data access roles
- Monitor CloudTrail for `CreateLoginProfile` API calls, especially on users with S3 permissions
- Enable MFA requirements for users with sensitive data access to mitigate credential compromise
- Use IAM Access Analyzer to identify privilege escalation paths to sensitive resources, not just admin access
- Implement S3 bucket policies that require MFA for object access
- Enable S3 access logging and CloudTrail data events to track data access patterns
- Consider using AWS Secrets Manager or Parameter Store instead of long-lived IAM user credentials
- Regularly audit IAM users for unexpected login profiles and console access
- Alert on unusual console login patterns, particularly for users that typically only use programmatic access
- Implement detective controls that flag console logins immediately following CreateLoginProfile API calls
