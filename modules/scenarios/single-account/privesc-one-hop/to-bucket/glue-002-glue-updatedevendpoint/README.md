# Privilege Escalation via glue:UpdateDevEndpoint

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $634/mo
* **Pathfinding.cloud ID:** glue-002
* **Technique:** Add SSH public key to existing Glue dev endpoint and access S3 buckets with the endpoint's attached role
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_bucket_glue_002_glue_updatedevendpoint`
* **Schema Version:** 1.0.0
* **Attack Path:** starting_user → (glue:UpdateDevEndpoint) → Add SSH key to existing dev endpoint → SSH access → (aws s3 cp) → sensitive bucket access
* **Attack Principals:** `arn:aws:iam::{account_id}:user/pl-prod-glue-002-to-bucket-starting-user`; `arn:aws:iam::{account_id}:role/pl-prod-glue-002-to-bucket-target-role`; `arn:aws:s3:::pl-sensitive-data-glue-002-{account_id}-{suffix}`
* **Required Permissions:** `glue:UpdateDevEndpoint` on `*`
* **Helpful Permissions:** `glue:GetDevEndpoint` (Retrieve endpoint details including address for SSH connection); `glue:GetDevEndpoints` (List existing endpoints to identify targets with privileged roles); `s3:ListBuckets` (Discover target buckets after escalation)
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

## Attack Overview

This scenario demonstrates a privilege escalation vulnerability where a user has permission to update an existing AWS Glue Development Endpoint. Unlike the `glue:CreateDevEndpoint` scenario, the attacker doesn't need `iam:PassRole` permissions since the role is already attached to the pre-existing endpoint.

The attack leverages `glue:UpdateDevEndpoint` to add the attacker's SSH public key to an existing development endpoint that has a privileged IAM role attached. Once the SSH key is added, the attacker can SSH into the endpoint and use the attached role's credentials to access sensitive S3 buckets. This is particularly dangerous because Glue dev endpoints often have broad S3 permissions to support ETL development workflows.

AWS Glue Development Endpoints are Apache Spark environments used for developing, testing, and debugging ETL (Extract, Transform, Load) scripts. They persist until explicitly deleted, providing attackers with a stable environment for credential access and lateral movement.

### MITRE ATT&CK Mapping

- **Tactic**: TA0004 - Privilege Escalation
- **Technique**: T1098.001 - Account Manipulation: Additional Cloud Credentials
- **Sub-technique**: Adding SSH credentials to cloud compute resources
- **Technique**: T1021.004 - Remote Services: SSH
- **Sub-technique**: SSH access to cloud development environments

### Principals in the attack path

- `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-glue-002-to-bucket-starting-user` (Scenario-specific starting user)
- `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-glue-002-to-bucket-target-role` (Pre-existing Glue dev endpoint role with S3 access)
- `arn:aws:s3:::pl-sensitive-data-glue-002-PROD_ACCOUNT-SUFFIX` (Sensitive S3 bucket containing valuable data)

### Attack Path Diagram

```mermaid
graph LR
    A[pl-prod-glue-002-to-bucket-starting-user] -->|glue:UpdateDevEndpoint| B[Pre-existing Dev Endpoint]
    B -->|Add SSH public key| C[Endpoint with Attacker Access]
    C -->|SSH connection| D[pl-prod-glue-002-to-bucket-target-role]
    D -->|s3:GetObject| E[pl-sensitive-data-glue-002 bucket]

    style A fill:#ff9999,stroke:#333,stroke-width:2px
    style B fill:#ffcc99,stroke:#333,stroke-width:2px
    style C fill:#ffcc99,stroke:#333,stroke-width:2px
    style D fill:#ffcc99,stroke:#333,stroke-width:2px
    style E fill:#99ff99,stroke:#333,stroke-width:2px
```

### Attack Steps

1. **Initial Access**: Start as `pl-prod-glue-002-to-bucket-starting-user` (credentials provided via Terraform outputs)
2. **Generate SSH Key Pair**: Create a new SSH key pair locally (attacker-controlled)
3. **Update Dev Endpoint**: Use `glue:UpdateDevEndpoint` to add the attacker's SSH public key to the existing endpoint
4. **Wait for Update**: Wait for the endpoint update to propagate (typically 2-5 minutes)
5. **SSH Connection**: SSH into the dev endpoint using the private key and the endpoint's address
6. **Extract Credentials**: Once connected, extract IAM role credentials from the instance metadata service
7. **Access S3**: Use the extracted credentials to access the sensitive S3 bucket
8. **Verification**: Download objects from the sensitive bucket to confirm access

### Scenario specific resources created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-glue-002-to-bucket-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::PROD_ACCOUNT:policy/pl-prod-glue-002-to-bucket-starting-policy` | Grants `glue:UpdateDevEndpoint`, `glue:GetDevEndpoint`, and `glue:GetDevEndpoints` permissions |
| `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-glue-002-to-bucket-target-role` | Privileged role attached to the dev endpoint with S3 bucket access |
| `arn:aws:glue:REGION:PROD_ACCOUNT:devEndpoint/pl-prod-glue-002-to-bucket-endpoint` | Pre-existing Glue dev endpoint with the target role attached |
| `arn:aws:s3:::pl-sensitive-data-glue-002-PROD_ACCOUNT-SUFFIX` | Sensitive S3 bucket containing test data |

## Attack Lab

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

### Executing the automated demo_attack script

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

#### Resources created by attack script

- SSH key pair generated locally for the demonstration
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

## Detecting Misconfiguration (CSPM)

### What CSPM tools should detect

A properly configured Cloud Security Posture Management (CSPM) tool should identify:

1. **Overly Permissive Glue Permissions**
   - IAM principals with `glue:UpdateDevEndpoint` on `*` resources
   - Lack of resource-based conditions restricting which endpoints can be updated

2. **Privilege Escalation Path**
   - User can update dev endpoint → Dev endpoint has privileged role → Role has S3 access
   - Detection should show the full attack path from user to sensitive bucket

3. **High-Risk Glue Configuration**
   - Development endpoints with broad S3 permissions
   - Endpoints without network access restrictions (public subnet placement)
   - Lack of encryption for dev endpoints

4. **Missing Preventive Controls**
   - No SCP restrictions on Glue dev endpoint operations
   - Absence of resource tags for endpoint ownership and approval
   - No CloudTrail monitoring for `UpdateDevEndpoint` API calls

### Prevention recommendations

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

## Detection Abuse (CloudSIEM)

### CloudTrail events to monitor

- `Glue: UpdateDevEndpoint` — Dev endpoint updated; critical when a new SSH public key is added, indicating an attacker gaining access to the endpoint's role credentials
- `Glue: GetDevEndpoint` — Endpoint details retrieved; may indicate reconnaissance to discover endpoint addresses and configurations
- `Glue: GetDevEndpoints` — All endpoints listed; low-privilege enumeration that often precedes an update attack
- `S3: GetObject` — Objects accessed from the sensitive bucket; high severity when sourced from a Glue endpoint IP after an `UpdateDevEndpoint` event

### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
