# Glue Dev Endpoint Update to Bucket

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $634/mo
* **Technique:** Add SSH public key to existing Glue dev endpoint and access S3 buckets with the endpoint's attached role
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** glue-002
* **MITRE Tactics:** TA0004 - Privilege Escalation
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1021.004 - Remote Services: SSH

---

## COST WARNING

**This scenario incurs AWS charges of approximately $2.20/hour (~$1,600/month) while deployed.**

AWS Glue Development Endpoints run continuously once created and bill per DPU (Data Processing Unit) hour. The endpoint created in this scenario uses the default 5 DPUs configuration.

**Recommendations:**
- Only deploy this scenario when actively testing
- Run `terraform destroy` immediately after completing testing
- Set up AWS billing alerts before deployment
- Monitor your AWS costs during testing

---

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-glue-002-to-bucket-starting-user` IAM user to the `pl-sensitive-data-glue-002-{account_id}-{suffix}` S3 bucket by adding an attacker-controlled SSH public key to a pre-existing Glue development endpoint that already has a privileged IAM role attached, then SSHing into the endpoint to obtain role credentials and access the bucket.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-glue-002-to-bucket-starting-user`
- **Destination resource:** `arn:aws:s3:::pl-sensitive-data-glue-002-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-glue-002-to-bucket-starting-user`):
- `glue:UpdateDevEndpoint` on `*` -- add an attacker SSH public key to an existing dev endpoint that already has a privileged role attached

**Helpful** (`pl-prod-glue-002-to-bucket-starting-user`):
- `glue:GetDevEndpoint` -- retrieve endpoint details including the public address needed for SSH connection
- `glue:GetDevEndpoints` -- list existing endpoints to identify targets with privileged roles
- `s3:ListBuckets` -- discover target buckets after obtaining role credentials

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint
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
| `arn:aws:iam::{account_id}:user/pl-prod-glue-002-to-bucket-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:policy/pl-prod-glue-002-to-bucket-starting-policy` | Grants `glue:UpdateDevEndpoint`, `glue:GetDevEndpoint`, and `glue:GetDevEndpoints` permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-glue-002-to-bucket-target-role` | Privileged role attached to the dev endpoint with S3 bucket access |
| `arn:aws:glue:{region}:{account_id}:devEndpoint/pl-prod-glue-002-to-bucket-endpoint` | Pre-existing Glue dev endpoint with the target role attached |
| `arn:aws:s3:::pl-sensitive-data-glue-002-{account_id}-{suffix}` | Sensitive S3 bucket containing test data |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Generate an SSH key pair for the demonstration
3. Update the dev endpoint with the attacker's public key
4. Wait for the endpoint to become ready
5. Establish an SSH connection to the endpoint
6. Extract IAM credentials from the instance metadata service
7. Access the sensitive S3 bucket using the extracted credentials
8. Verify successful privilege escalation
9. Output standardized test results for automation

**Note**: The demo script requires SSH client and AWS CLI to be installed. The endpoint takes approximately 2-5 minutes to update after adding the SSH key.

#### Resources Created by Attack Script

- SSH key pair generated locally for the demonstration (`/tmp/pl-glue-002-demo-key` and `/tmp/pl-glue-002-demo-key.pub`)
- Attacker's SSH public key added to the existing Glue dev endpoint

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo glue-002-glue-updatedevendpoint
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup glue-002-glue-updatedevendpoint
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint
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

- IAM principals with `glue:UpdateDevEndpoint` on `*` resources without resource-based conditions restricting which endpoints can be updated
- Privilege escalation path: user can update dev endpoint → dev endpoint has privileged role → role has S3 access; detection should show the full path from user to sensitive bucket
- Development endpoints with broad S3 permissions that exceed what ETL workflows require
- Glue dev endpoints deployed in public subnets without network access restrictions
- Absence of SCP restrictions on Glue dev endpoint operations

#### Prevention Recommendations

1. **Restrict glue:UpdateDevEndpoint permissions**
   ```json
   {
     "Effect": "Deny",
     "Action": "glue:UpdateDevEndpoint",
     "Resource": "*",
     "Condition": {
       "StringNotEquals": {
         "aws:PrincipalTag/GlueAdmin": "true"
       }
     }
   }
   ```

2. **Use resource-based conditions to limit endpoint access**
   - Implement IAM conditions that restrict which endpoints can be updated
   - Use `glue:ResourceTag` conditions to enforce endpoint ownership
   - Require specific tags on endpoints before allowing updates

3. **Implement SCPs to prevent unauthorized endpoint updates**
   ```json
   {
     "Effect": "Deny",
     "Action": [
       "glue:UpdateDevEndpoint",
       "glue:CreateDevEndpoint"
     ],
     "Resource": "*",
     "Condition": {
       "StringNotEquals": {
         "aws:RequestedRegion": ["us-east-1"]
       }
     }
   }
   ```

4. **Apply least privilege to Glue endpoint roles**
   - Limit S3 permissions to specific buckets required for ETL workflows
   - Avoid attaching `AdministratorAccess` or overly broad policies
   - Use S3 bucket policies with `aws:SourceVpce` conditions to restrict access

5. **Use VPC endpoints and private subnets for dev endpoints**
   - Deploy endpoints in private subnets without internet access
   - Use VPC endpoints for AWS service communication
   - Implement security groups that restrict SSH access to specific IP ranges

6. **Enable encryption for Glue dev endpoints**
   - Use AWS KMS for encrypting data at rest
   - Enable SSL/TLS for data in transit
   - Implement key policies that restrict who can use encryption keys

7. **Implement approval workflows for endpoint modifications**
   - Require change management tickets before endpoint updates
   - Use AWS Service Catalog to standardize endpoint creation
   - Implement AWS Systems Manager Change Manager for controlled updates

8. **Use IAM Access Analyzer to identify privilege escalation paths**
   - Regularly scan for paths from low-privilege principals to sensitive resources
   - Review findings related to Glue permissions and S3 access
   - Implement automated remediation for high-risk findings

9. **Consider using AWS Glue Studio notebooks instead**
   - Glue Studio notebooks provide similar functionality with better security controls
   - They automatically shut down after periods of inactivity (cost savings)
   - Integration with AWS IAM Identity Center for authentication
   - Better isolation between users and workloads

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `Glue: UpdateDevEndpoint` -- dev endpoint updated; critical when a new SSH public key is added, indicating an attacker gaining access to the endpoint's role credentials
- `Glue: GetDevEndpoint` -- endpoint details retrieved; may indicate reconnaissance to discover endpoint addresses and configurations
- `Glue: GetDevEndpoints` -- all endpoints listed; low-privilege enumeration that often precedes an update attack
- `S3: GetObject` -- objects accessed from the sensitive bucket; high severity when sourced from a Glue endpoint IP after an `UpdateDevEndpoint` event

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
