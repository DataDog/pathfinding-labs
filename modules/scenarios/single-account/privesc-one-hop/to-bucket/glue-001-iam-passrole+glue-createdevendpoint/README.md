# Glue Dev Endpoint Creation to Bucket

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $634/mo
* **Technique:** Pass privileged role to AWS Glue dev endpoint and access S3 buckets via SSH
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_bucket_glue_001_iam_passrole_glue_createdevendpoint`
* **CTF Flag Location:** s3-object
* **Schema Version:** 4.1.1
* **Pathfinding.cloud ID:** glue-001
* **MITRE Tactics:** TA0004 - Privilege Escalation
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1578 - Modify Cloud Compute Infrastructure

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-glue-001-to-bucket-starting-user` IAM user to the `pl-sensitive-data-glue-001-{account_id}-{suffix}` S3 bucket by passing a privileged IAM role to a newly created AWS Glue development endpoint and SSHing into that endpoint to execute S3 commands with the role's credentials.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-glue-001-to-bucket-starting-user`
- **Destination resource:** `arn:aws:s3:::pl-sensitive-data-glue-001-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-glue-001-to-bucket-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-glue-001-to-bucket-target-role` -- allows passing the target role to Glue
- `glue:CreateDevEndpoint` on `*` -- allows creating a Glue development endpoint that assumes the passed role

**Helpful** (`pl-prod-glue-001-to-bucket-starting-user`):
- `glue:GetDevEndpoint` -- check endpoint status and retrieve SSH connection details
- `iam:ListRoles` -- discover available privileged roles to pass to Glue
- `s3:ListBuckets` -- discover target buckets after escalation
- `glue:DeleteDevEndpoint` -- clean up created endpoints after demonstration

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew tap DataDog/pathfinding-labs https://github.com/DataDog/pathfinding-labs
   brew install DataDog/pathfinding-labs/plabs
   ```
   Or with Go 1.25+ installed:
   ```bash
   go install github.com/DataDog/pathfinding-labs/cmd/plabs@latest
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable glue-001-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-001-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-glue-001-to-bucket-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:policy/pl-prod-glue-001-to-bucket-starting-policy` | Allows `iam:PassRole` and `glue:CreateDevEndpoint` |
| `arn:aws:iam::{account_id}:role/pl-prod-glue-001-to-bucket-target-role` | Target role with S3 bucket read permissions |
| `arn:aws:iam::{account_id}:policy/pl-prod-glue-001-to-bucket-target-policy` | Grants `s3:GetObject` and `s3:ListBucket` on sensitive bucket |
| `arn:aws:s3:::pl-sensitive-data-glue-001-{account_id}-{suffix}` | Target sensitive S3 bucket containing sample data |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Generate an SSH key pair for endpoint access
3. Create a Glue development endpoint with the target role
4. Wait for the endpoint to become ready (5-10 minutes)
5. SSH into the endpoint and execute AWS S3 commands
6. Verify successful access to the sensitive S3 bucket
7. Automatically delete the endpoint and clean up resources


**Note:** Glue development endpoints cost approximately $2.20/hour while running. The script automatically cleans up the endpoint after demonstration. If the script is interrupted, manually delete the endpoint using `aws glue delete-dev-endpoint --endpoint-name pl-prod-gcd-escalation-endpoint`.

#### Resources Created by Attack Script

- Glue development endpoint (`pl-prod-gcd-escalation-endpoint`)
- Generated SSH key pair files (`/tmp/pl-glue-001-demo-key` and `/tmp/pl-glue-001-demo-key.pub`)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo glue-001-iam-passrole+glue-createdevendpoint
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-001-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup glue-001-iam-passrole+glue-createdevendpoint
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-001-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable glue-001-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-001-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- **Overly Permissive PassRole**: User/role has `iam:PassRole` permission on roles with sensitive permissions
- **Glue Service Escalation Path**: Combination of `iam:PassRole` and `glue:CreateDevEndpoint` that could lead to privilege escalation
- **Privileged Role for Glue**: IAM roles with S3 or admin permissions that can be passed to Glue services
- **Unrestricted Glue Access**: Principals with `glue:CreateDevEndpoint` without resource or condition constraints
- **S3 Access via Compute Services**: Detection of privilege escalation paths where compute services (Glue, Lambda, EC2) can access sensitive S3 buckets

#### Prevention Recommendations

- **Restrict PassRole permissions**: Use resource-level conditions to limit which roles can be passed to Glue services:
  ```json
  {
    "Effect": "Allow",
    "Action": "iam:PassRole",
    "Resource": "arn:aws:iam::*:role/GlueServiceRole-*",
    "Condition": {
      "StringEquals": {
        "iam:PassedToService": "glue.amazonaws.com"
      }
    }
  }
  ```

- **Implement SCPs**: Use Service Control Policies to prevent creation of Glue dev endpoints in production accounts:
  ```json
  {
    "Effect": "Deny",
    "Action": "glue:CreateDevEndpoint",
    "Resource": "*"
  }
  ```

- **Minimize Glue role permissions**: Ensure roles used by Glue dev endpoints follow least privilege principles and avoid S3 or admin access

- **Use IAM Access Analyzer**: Regularly scan for privilege escalation paths involving PassRole and Glue services

- **Require MFA**: Enforce MFA for creating Glue dev endpoints or passing roles to AWS services

- **Network restrictions**: Configure VPC endpoints and security groups to limit SSH access to Glue dev endpoints from trusted networks only

- **Consider alternatives**: For production environments, prefer AWS Glue jobs or notebooks with appropriate IAM roles instead of persistent dev endpoints

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `glue:CreateDevEndpoint` -- new Glue development endpoint created; inspect the `roleArn` field in request parameters — a privileged role ARN here is the CloudTrail signal for PassRole to Glue; critical when the role has S3 or admin permissions
- `glue:GetDevEndpoint` -- endpoint status queried; may indicate attacker polling for readiness
- `sts:AssumeRole` -- role assumed by Glue service principal (`glue.amazonaws.com`); indicates endpoint is using the passed role
- `s3:GetObject` -- objects retrieved from S3; high severity when the calling principal is a Glue endpoint role

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
