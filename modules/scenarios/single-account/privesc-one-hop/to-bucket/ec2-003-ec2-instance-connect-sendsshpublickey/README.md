# Privilege Escalation via ec2-instance-connect:SendSSHPublicKey to S3 Bucket

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $8/mo
* **Pathfinding.cloud ID:** ec2-003
* **Technique:** SSH into EC2 instance via Instance Connect and extract IAM role credentials from IMDS for S3 bucket access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey`
* **Schema Version:** 1.0.0
* **Attack Path:** starting_user → (ec2-instance-connect:SendSSHPublicKey) → EC2 instance → (IMDS credential extraction) → S3 bucket access
* **Attack Principals:** `arn:aws:iam::{account_id}:user/pl-prod-ec2-003-to-bucket-starting-user`; `arn:aws:ec2:{region}:{account_id}:instance/i-xxxxxxxxx`; `arn:aws:iam::{account_id}:role/pl-prod-ec2-003-to-bucket-ec2-bucket-role`; `arn:aws:s3:::pl-sensitive-data-ec2-003-{account_id}-{suffix}`
* **Required Permissions:** `ec2-instance-connect:SendSSHPublicKey` on `arn:aws:ec2:*:{account_id}:instance/{target_instance_id}`
* **Helpful Permissions:** `ec2:DescribeInstances` (Discover EC2 instances with S3 bucket access); `iam:GetInstanceProfile` (View instance profile to determine attached role permissions); `iam:GetRole` (View role permissions and S3 bucket access); `s3:ListBucket` (Verify S3 access after credential extraction)
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access, TA0009 - Collection
* **MITRE Techniques:** T1552.005 - Unsecured Credentials: Cloud Instance Metadata API, T1078.004 - Valid Accounts: Cloud Accounts, T1530 - Data from Cloud Storage Object

## Attack Overview

EC2 Instance Connect provides a secure way to connect to EC2 instances by pushing temporary SSH public keys that remain valid for 60 seconds. However, if a user has the `ec2-instance-connect:SendSSHPublicKey` permission on an instance with a privileged IAM role attached, they can SSH into the instance and extract the role's temporary credentials from the Instance Metadata Service (IMDS).

This scenario demonstrates a privilege escalation path where a low-privileged user leverages EC2 Instance Connect to access an EC2 instance that has an IAM role with S3 bucket access. Once on the instance, the attacker extracts the role credentials via IMDSv2 and uses them to access sensitive data in an S3 bucket. This technique is particularly dangerous because it combines legitimate AWS services (EC2 Instance Connect and IMDS) to bypass IAM restrictions, and the 60-second window for the SSH key makes detection challenging.

The attack highlights the importance of restricting `ec2-instance-connect:SendSSHPublicKey` permissions and carefully evaluating which IAM roles are attached to EC2 instances, especially those accessible via Instance Connect. Organizations should treat EC2 Instance Connect permissions with the same scrutiny as direct IAM role assumption permissions, as they provide an indirect path to role credentials.

### MITRE ATT&CK Mapping

- **Tactic**: TA0004 - Privilege Escalation, TA0006 - Credential Access, TA0009 - Collection
- **Technique**: T1552.005 - Unsecured Credentials: Cloud Instance Metadata API
- **Technique**: T1078.004 - Valid Accounts: Cloud Accounts
- **Technique**: T1530 - Data from Cloud Storage Object

### Principals in the attack path

- `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-ec2-003-to-bucket-starting-user` (Scenario-specific starting user)
- `arn:aws:ec2:REGION:PROD_ACCOUNT:instance/i-xxxxxxxxx` (EC2 instance with bucket access role)
- `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-ec2-003-to-bucket-ec2-bucket-role` (IAM role attached to EC2 instance with S3 bucket access)
- `arn:aws:s3:::pl-sensitive-data-ec2-003-PROD_ACCOUNT-SUFFIX` (Target S3 bucket with sensitive data)

### Attack Path Diagram

```mermaid
graph LR
    A[pl-prod-ec2-003-to-bucket-starting-user] -->|ec2-instance-connect:SendSSHPublicKey| B[EC2 Instance]
    B -->|SSH Connection<br/>60-second window| C[Instance Shell Access]
    C -->|IMDSv2 Query| D[pl-prod-ec2-003-to-bucket-ec2-bucket-role<br/>Credentials]
    D -->|s3:GetObject<br/>s3:ListBucket| E[S3 Bucket:<br/>pl-sensitive-data-ec2-003]

    style A fill:#ff9999,stroke:#333,stroke-width:2px
    style B fill:#ffcc99,stroke:#333,stroke-width:2px
    style C fill:#ffcc99,stroke:#333,stroke-width:2px
    style D fill:#ffcc99,stroke:#333,stroke-width:2px
    style E fill:#99ff99,stroke:#333,stroke-width:2px
```

### Attack Steps

1. **Initial Access**: Start as `pl-prod-ec2-003-to-bucket-starting-user` with `ec2-instance-connect:SendSSHPublicKey` permission (credentials provided via Terraform outputs)
2. **Generate SSH Key Pair**: Create a temporary SSH key pair for authentication
3. **Push Public Key**: Use `ec2-instance-connect:SendSSHPublicKey` to push the public key to the target EC2 instance (valid for 60 seconds)
4. **Establish SSH Connection**: Connect to the EC2 instance via SSH within the 60-second window
5. **Extract Role Credentials**: Query the Instance Metadata Service (IMDSv2) from within the instance to retrieve temporary IAM role credentials
6. **Configure AWS CLI**: Use the extracted credentials (AccessKeyId, SecretAccessKey, SessionToken) to configure AWS CLI
7. **Access S3 Bucket**: Use the role credentials to list and download objects from the sensitive S3 bucket
8. **Verification**: Verify successful S3 bucket access and data exfiltration

### Scenario specific resources created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-ec2-003-to-bucket-starting-user` | Scenario-specific starting user with access keys and ec2-instance-connect:SendSSHPublicKey permission |
| `arn:aws:iam::PROD_ACCOUNT:policy/pl-prod-ec2-003-to-bucket-starting-user-policy` | Policy granting SendSSHPublicKey, DescribeInstances, GetInstanceProfile, and GetRole permissions |
| `arn:aws:ec2:REGION:PROD_ACCOUNT:instance/i-xxxxxxxxx` | EC2 instance (Amazon Linux 2023) with Instance Connect enabled and bucket access role attached |
| `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-ec2-003-to-bucket-ec2-bucket-role` | IAM role attached to EC2 instance with S3 bucket read access |
| `arn:aws:iam::PROD_ACCOUNT:instance-profile/pl-prod-ec2-003-to-bucket-ec2-bucket-profile` | Instance profile linking the IAM role to the EC2 instance |
| `arn:aws:s3:::pl-sensitive-data-ec2-003-PROD_ACCOUNT-SUFFIX` | Target S3 bucket containing sensitive data files |

## Attack Lab

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `space` to enable it
4. Press `d` to deploy

### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Generate a temporary SSH key pair
3. Push the public key to the EC2 instance using EC2 Instance Connect
4. Establish SSH connection within the 60-second window
5. Extract IAM role credentials from IMDSv2
6. Use the extracted credentials to access the S3 bucket
7. Verify successful data exfiltration
8. Output standardized test results for automation

#### Resources created by attack script

- Temporary SSH key pair (private key written to local disk during demo)
- Downloaded S3 objects from the sensitive data bucket

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo ec2-003-ec2-instance-connect-sendsshpublickey
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ec2-003-ec2-instance-connect-sendsshpublickey
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Detecting Misconfiguration (CSPM)

### What CSPM tools should detect

A properly configured Cloud Security Posture Management (CSPM) tool should identify:

1. **Overly Permissive EC2 Instance Connect Permissions**: User with `ec2-instance-connect:SendSSHPublicKey` on instances with privileged IAM roles
2. **Sensitive Instance Profiles**: EC2 instances with IAM roles that have broad S3 access (especially `s3:GetObject` on sensitive buckets)
3. **Missing Resource Constraints**: SendSSHPublicKey permissions without resource ARN restrictions or condition keys
4. **Lack of OS User Restrictions**: SendSSHPublicKey permissions without `ec2:osuser` condition constraints
5. **IMDSv1 Enabled**: Instances using IMDSv1 instead of IMDSv2 (makes credential theft easier)
6. **Missing Network Restrictions**: Security groups allowing SSH (port 22) from broad IP ranges on instances with privileged roles
7. **Privilege Escalation Path**: One-hop path from low-privileged user to S3 bucket access via EC2 Instance Connect

### Prevention recommendations

- **Restrict SendSSHPublicKey with resource-based constraints**:
  ```json
  {
    "Effect": "Allow",
    "Action": "ec2-instance-connect:SendSSHPublicKey",
    "Resource": "arn:aws:ec2:REGION:ACCOUNT_ID:instance/i-specificinstance",
    "Condition": {
      "StringEquals": {
        "ec2:osuser": "ec2-user"
      }
    }
  }
  ```
- **Use security groups to restrict SSH access** to known IP ranges or VPN endpoints, not 0.0.0.0/0
- **Monitor CloudTrail for SendSSHPublicKey events**, especially to instances with privileged roles attached
- **Implement IMDSv2** (session-oriented metadata service) to make credential theft more difficult by requiring a session token
- **Use AWS Systems Manager Session Manager instead of SSH** for remote access - it provides better auditing and doesn't expose ports
- **Alert on unusual SSH connections** to sensitive instances, especially those with S3 or admin access roles
- **Consider disabling EC2 Instance Connect** on instances with privileged roles if SSH access is not required
- **Use VPC endpoints for S3** to restrict which instances can access specific buckets
- **Apply least privilege to instance profiles** - instances should only have access to the specific S3 buckets and objects they need
- **Implement S3 bucket policies** that restrict access based on source VPC or VPC endpoints
- **Use SCPs to prevent overly broad SendSSHPublicKey permissions** across your AWS Organization
- **Enable GuardDuty** to detect unusual API activity from EC2 instances, including anomalous S3 access patterns

## Detection Abuse (CloudSIEM)

### CloudTrail events to monitor

- `EC2: SendSSHPublicKey` — SSH public key pushed to an instance via EC2 Instance Connect; critical when the target instance has a privileged IAM role attached
- `EC2: DescribeInstances` — Reconnaissance call to list instances; suspicious when followed immediately by `SendSSHPublicKey`
- `IAM: GetInstanceProfile` — Retrieval of instance profile details; used to identify roles attached to EC2 instances
- `IAM: GetRole` — Role permission lookup; used to confirm the instance role has S3 or other privileged access
- `S3: ListBucket` — Bucket listing from EC2 instance role credentials; suspicious when the instance does not normally access that bucket
- `S3: GetObject` — Object download from the sensitive data bucket; high severity when accessed via extracted IMDS credentials

### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
