# EC2 Instance Connect SSH to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $8/mo
* **Cost Estimate When Demo Executed:** $8/mo
* **Technique:** SSH into EC2 instance with privileged role and extract credentials via IMDS
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_ec2_003_ec2_instance_connect_sendsshpublickey`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** ec2-003
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access
* **MITRE Techniques:** T1552.005 - Unsecured Credentials: Cloud Instance Metadata API, T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-ec2-003-to-admin-starting-user` IAM user to the `pl-prod-ec2-003-to-admin-ec2-admin-role` administrative role by using `ec2-instance-connect:SendSSHPublicKey` to push a temporary SSH public key to an EC2 instance with an attached admin role, SSH into the instance, and extract the role's temporary credentials from the Instance Metadata Service (IMDS).

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-ec2-003-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-ec2-003-to-admin-ec2-admin-role`

### Starting Permissions

**Required** (`pl-prod-ec2-003-to-admin-starting-user`):
- `ec2-instance-connect:SendSSHPublicKey` on `arn:aws:ec2:*:{account_id}:instance/{target_instance_id}` -- push a temporary SSH public key to the target EC2 instance

**Helpful** (`pl-prod-ec2-003-to-admin-starting-user`):
- `ec2:DescribeInstances` -- discover EC2 instances with privileged roles attached via instance profiles
- `iam:GetInstanceProfile` -- view instance profile to determine attached role permissions
- `iam:GetRole` -- view role permissions and policies

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable ec2-003-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ec2-003-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-ec2-003-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:policy/pl-prod-ec2-003-to-admin-policy` | Allows `ec2-instance-connect:SendSSHPublicKey`, `ec2:DescribeInstances`, and read-only IAM discovery |
| `arn:aws:iam::{account_id}:role/pl-prod-ec2-003-to-admin-ec2-admin-role` | Admin role attached to the EC2 instance profile |
| `arn:aws:ec2:{region}:{account_id}:instance/i-xxxxxxxxx` | EC2 instance with the admin role attached via instance profile |
| `arn:aws:ec2:{region}:{account_id}:security-group/sg-xxxxxxxxx` | Security group allowing SSH access (port 22) |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/ec2-003-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Generate a temporary SSH key pair
4. Push the public key to the EC2 instance using `ec2-instance-connect:SendSSHPublicKey`
5. Establish an SSH connection to the instance
6. Extract role credentials from IMDSv2
7. Verify successful privilege escalation to administrator access
8. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions


#### Resources Created by Attack Script

- Temporary SSH key pair (`/tmp/pathfinding_eic_key` and `/tmp/pathfinding_eic_key.pub`) created during the demo
- `AdministratorAccess` managed policy attached to `pl-prod-ec2-003-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo ec2-003-ec2-instance-connect-sendsshpublickey
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ec2-003-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ec2-003-ec2-instance-connect-sendsshpublickey
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ec2-003-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable ec2-003-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ec2-003-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- **Privilege Escalation Path**: EC2 instances with privileged IAM roles accessible via EC2 Instance Connect
- **Overly Permissive SendSSHPublicKey**: Users/roles with `ec2-instance-connect:SendSSHPublicKey` permission on instances with admin roles
- **High-Privilege Instance Profiles**: EC2 instances with administrative or highly privileged IAM roles attached
- **Unrestricted SSH Access**: Security groups allowing SSH (port 22) from wide CIDR ranges (e.g., 0.0.0.0/0)
- **IMDSv1 Usage**: Instances still using IMDSv1 (which is more vulnerable to credential theft)
- **Missing Resource Constraints**: IAM policies allowing `SendSSHPublicKey` without resource-based restrictions

#### Prevention Recommendations

1. **Restrict SendSSHPublicKey Permission**: Use resource-based constraints to limit which instances can receive SSH keys:
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

2. **Implement Least Privilege for Instance Profiles**: Avoid attaching administrative roles to EC2 instances. Use specific, scoped permissions instead.

3. **Use AWS Systems Manager Session Manager**: Replace SSH access with Session Manager, which provides auditable, credential-free access without requiring open ports:
   - No need for SSH keys or EC2 Instance Connect
   - All sessions logged to CloudTrail and S3
   - Fine-grained access control via IAM policies
   - No inbound security group rules required

4. **Enforce IMDSv2**: Require IMDSv2 (session-oriented) on all EC2 instances to make credential theft more difficult:
   ```bash
   aws ec2 modify-instance-metadata-options \
     --instance-id i-1234567890abcdef0 \
     --http-tokens required \
     --http-put-response-hop-limit 1
   ```

5. **Restrict SSH Access via Security Groups**: Limit SSH access (port 22) to specific, known IP ranges or VPN endpoints. Never use `0.0.0.0/0` for privileged instances.

6. **Implement SCPs for High-Security Environments**: Use Service Control Policies to prevent `ec2-instance-connect:SendSSHPublicKey` in production accounts:
   ```json
   {
     "Effect": "Deny",
     "Action": "ec2-instance-connect:SendSSHPublicKey",
     "Resource": "*",
     "Condition": {
       "StringEquals": {
         "aws:RequestedRegion": ["us-east-1", "us-west-2"]
       }
     }
   }
   ```

7. **Use IAM Access Analyzer**: Regularly scan for privilege escalation paths involving EC2 instances with overly permissive roles.

8. **Consider VPC Endpoints for IMDS**: In highly sensitive environments, use VPC endpoints and network segmentation to restrict IMDS access patterns.

9. **Separate Development and Production**: Use different AWS accounts for development and production. Restrict EC2 Instance Connect to development accounts only.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `EC2InstanceConnect: SendSSHPublicKey` -- SSH public key pushed to an EC2 instance via Instance Connect; high severity when the target instance has a privileged role attached
- `STS: AssumeRole` -- role assumed using temporary credentials retrieved from IMDS; alert when the role ARN matches an instance profile role being used from an unexpected source IP

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
