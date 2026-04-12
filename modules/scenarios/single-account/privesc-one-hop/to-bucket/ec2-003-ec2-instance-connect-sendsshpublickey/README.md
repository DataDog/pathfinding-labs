# EC2 Instance Connect SSH to Bucket

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $8/mo
* **Cost Estimate When Demo Executed:** $8/mo
* **Technique:** SSH into EC2 instance via Instance Connect and extract IAM role credentials from IMDS for S3 bucket access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey`
* **Schema Version:** 4.1.1
* **Pathfinding.cloud ID:** ec2-003
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access, TA0009 - Collection
* **MITRE Techniques:** T1552.005 - Unsecured Credentials: Cloud Instance Metadata API, T1078.004 - Valid Accounts: Cloud Accounts, T1530 - Data from Cloud Storage Object

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-ec2-003-to-bucket-starting-user` IAM user to the `pl-sensitive-data-ec2-003-{account_id}-{suffix}` S3 bucket by pushing a temporary SSH public key to an EC2 instance via EC2 Instance Connect, SSHing into the instance, and extracting the attached IAM role's temporary credentials from the Instance Metadata Service (IMDS).

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-ec2-003-to-bucket-starting-user`
- **Destination resource:** `arn:aws:s3:::pl-sensitive-data-ec2-003-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-ec2-003-to-bucket-starting-user`):
- `ec2-instance-connect:SendSSHPublicKey` on `arn:aws:ec2:*:{account_id}:instance/{target_instance_id}` -- push a temporary SSH public key to the target EC2 instance

**Helpful** (`pl-prod-ec2-003-to-bucket-starting-user`):
- `ec2:DescribeInstances` -- discover EC2 instances with S3 bucket access roles attached
- `iam:GetInstanceProfile` -- view the instance profile to determine which role is attached
- `iam:GetRole` -- view role permissions and confirm S3 bucket access
- `s3:ListBucket` -- verify S3 access after credential extraction

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable ec2-003-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ec2-003-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-ec2-003-to-bucket-starting-user` | Scenario-specific starting user with access keys and ec2-instance-connect:SendSSHPublicKey permission |
| `arn:aws:iam::{account_id}:policy/pl-prod-ec2-003-to-bucket-starting-user-policy` | Policy granting SendSSHPublicKey, DescribeInstances, GetInstanceProfile, and GetRole permissions |
| `arn:aws:ec2:{region}:{account_id}:instance/i-xxxxxxxxx` | EC2 instance (Amazon Linux 2023) with Instance Connect enabled and bucket access role attached |
| `arn:aws:iam::{account_id}:role/pl-prod-ec2-003-to-bucket-ec2-bucket-role` | IAM role attached to EC2 instance with S3 bucket read access |
| `arn:aws:iam::{account_id}:instance-profile/pl-prod-ec2-003-to-bucket-ec2-bucket-profile` | Instance profile linking the IAM role to the EC2 instance |
| `arn:aws:s3:::pl-sensitive-data-ec2-003-{account_id}-{suffix}` | Target S3 bucket containing sensitive data files |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Generate a temporary SSH key pair
3. Push the public key to the EC2 instance using EC2 Instance Connect
4. Establish SSH connection within the 60-second window
5. Extract IAM role credentials from IMDSv2
6. Use the extracted credentials to access the S3 bucket
7. Verify successful data exfiltration


#### Resources Created by Attack Script

- Temporary SSH key pair (private key written to `/tmp/pathfinding_ec2_003_key` during demo)
- Downloaded S3 objects from the sensitive data bucket

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo ec2-003-ec2-instance-connect-sendsshpublickey
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ec2-003-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ec2-003-ec2-instance-connect-sendsshpublickey
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ec2-003-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable ec2-003-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ec2-003-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- User with `ec2-instance-connect:SendSSHPublicKey` on an EC2 instance that has a privileged IAM role attached — this is a one-hop privilege escalation path
- EC2 instances with IAM roles that have broad S3 access (especially `s3:GetObject` on sensitive buckets) and EC2 Instance Connect enabled
- SendSSHPublicKey permissions granted without resource ARN restrictions or `ec2:osuser` condition constraints
- Instances where IMDSv1 is enabled (no `http-tokens: required`), making IMDS credential theft easier
- Security groups allowing inbound SSH (port 22) from broad IP ranges (0.0.0.0/0) on instances with privileged roles attached

#### Prevention Recommendations

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
- **Enforce IMDSv2** on all EC2 instances by setting `http-tokens: required` in instance metadata options, so credential queries require a session token that cannot be trivially forwarded
- **Use AWS Systems Manager Session Manager instead of SSH** for remote access — it provides better auditing and does not require open port 22 or EC2 Instance Connect
- **Apply least privilege to instance profiles** — EC2 instances should only have access to the specific S3 buckets and objects they need, not broad `s3:GetObject` on sensitive data buckets
- **Use SCPs to prevent overly broad SendSSHPublicKey permissions** across your AWS Organization
- **Enable GuardDuty** to detect unusual API activity from EC2 instances, including anomalous S3 access patterns originating from IMDS-extracted credentials

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `EC2InstanceConnect: SendSSHPublicKey` -- SSH public key pushed to an instance via EC2 Instance Connect; critical when the target instance has a privileged IAM role attached
- `EC2: DescribeInstances` -- reconnaissance call to list instances; suspicious when followed immediately by `SendSSHPublicKey`
- `IAM: GetInstanceProfile` -- retrieval of instance profile details; used to identify roles attached to EC2 instances
- `IAM: GetRole` -- role permission lookup; used to confirm the instance role has S3 or other privileged access
- `S3: ListBucket` -- bucket listing from EC2 instance role credentials; suspicious when the instance does not normally access that bucket
- `S3: GetObject` -- object download from the sensitive data bucket; high severity when accessed via extracted IMDS credentials

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
