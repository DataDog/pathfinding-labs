# DataPipeline Job Creation to Bucket

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Create Data Pipeline with passed role to read sensitive S3 data the starting user cannot access directly; exfiltrate to attacker-controlled S3 bucket in separate account
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_bucket_iam_passrole_datapipeline_pipeline`
* **CTF Flag Location:** s3-object
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** datapipeline-001
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0009 - Collection, TA0010 - Exfiltration
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1578 - Modify Cloud Compute Infrastructure, T1530 - Data from Cloud Storage Object

## Objective

Your objective is to exfiltrate sensitive data from `pl-sensitive-data-datapipeline-001-{account_id}-{suffix}` -- a bucket the starting user has no direct IAM access to — by passing the pipeline role to AWS Data Pipeline and running a shell command on an EC2 instance that reads and ships the data to your attacker-controlled exfil bucket.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-datapipeline-001-to-bucket-starting-user`
- **Target resource (victim):** `arn:aws:s3:::pl-sensitive-data-datapipeline-001-{account_id}-{suffix}`
- **Exfil destination (attacker-controlled):** `arn:aws:s3:::pl-exfil-bucket-datapipeline-001-{attacker_account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-datapipeline-001-to-bucket-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-datapipeline-001-to-bucket-pipeline-role` -- allows passing the pipeline role to the Data Pipeline service
- `datapipeline:CreatePipeline` on `*` -- create a new Data Pipeline
- `datapipeline:PutPipelineDefinition` on `*` -- define a ShellCommandActivity with arbitrary commands
- `datapipeline:ActivatePipeline` on `*` -- activate the pipeline, triggering EC2 instance launch

**Helpful** (`pl-prod-datapipeline-001-to-bucket-starting-user`):
- `datapipeline:DescribePipelines` -- view pipeline status and configuration
- `datapipeline:GetPipelineDefinition` -- retrieve pipeline definition for verification
- `s3:ListBucket` -- list objects in buckets for verification

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable datapipeline-001-to-bucket
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `datapipeline-001-to-bucket` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-datapipeline-001-to-bucket-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-datapipeline-001-to-bucket-pipeline-role` | Read-only pipeline role with s3:GetObject on sensitive bucket |
| `arn:aws:iam::{account_id}:policy/pl-prod-datapipeline-001-to-bucket-starting-user-policy` | Policy granting Data Pipeline and iam:PassRole permissions |
| `arn:aws:iam::{account_id}:policy/pl-prod-datapipeline-001-to-bucket-pipeline-policy` | Policy granting s3:GetObject on sensitive bucket |
| `arn:aws:s3:::pl-sensitive-data-datapipeline-001-{account_id}-{suffix}` | Sensitive data bucket containing secret data (the attack target) |
| `arn:aws:s3:::pl-sensitive-data-datapipeline-001-{account_id}-{suffix}/flag.txt` | CTF flag object stored in the sensitive bucket |
| `arn:aws:s3:::pl-exfil-bucket-datapipeline-001-{attacker_account_id}-{suffix}` | Attacker-controlled exfil bucket (deployed in attacker account, NOT a victim misconfiguration) |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create the Data Pipeline with shell command activity
4. Activate the pipeline and wait for EC2 instance launch
5. Verify successful data exfiltration from the sensitive bucket


#### Resources Created by Attack Script

- Data Pipeline with ShellCommandActivity
- Ephemeral EC2 instance launched by the pipeline
- Exfiltrated data file written to the exfil bucket

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo iam-passrole+datapipeline-pipeline-to-bucket
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `datapipeline-001-to-bucket` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup iam-passrole+datapipeline-pipeline-to-bucket
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `datapipeline-001-to-bucket` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable datapipeline-001-to-bucket
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `datapipeline-001-to-bucket` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- User/role has `iam:PassRole` permission on roles with access to sensitive S3 buckets, combined with `datapipeline:CreatePipeline`, `datapipeline:PutPipelineDefinition`, and `datapipeline:ActivatePipeline` permissions, enabling arbitrary command execution via ShellCommandActivity
- Combination of `iam:PassRole` with compute service creation permissions creates a data exfiltration path to sensitive S3 buckets — the attacker does not need admin access, only read access via the passed role
- IAM role with `s3:GetObject` on a sensitive bucket is passable to a compute service by an unprivileged user, creating an indirect read path

#### Prevention Recommendations

- Restrict `iam:PassRole` to specific roles using resource-level conditions (`"Resource": "arn:aws:iam::ACCOUNT:role/specific-role"`) and use the `iam:PassedToService` condition key to limit which services can receive roles (e.g., `"Condition": {"StringEquals": {"iam:PassedToService": "datapipeline.amazonaws.com"}}`)
- Limit `datapipeline:CreatePipeline`, `datapipeline:PutPipelineDefinition`, and `datapipeline:ActivatePipeline` to specific users/roles; use SCPs to block Data Pipeline entirely in production accounts if not needed
- Require encryption for all data at rest and in transit; use VPC Endpoint policies to restrict bucket access to specific VPCs
- Use SCPs with `aws:PrincipalOrgID` conditions on sensitive S3 buckets to prevent cross-account reads even through transitive role access
- Periodically review all principals with `iam:PassRole` permissions using IAM Access Analyzer; flag any that can pass roles with access to sensitive data to compute services
- Implement the following SCP to deny Data Pipeline creation outside approved accounts:
  ```json
  {
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Deny",
        "Action": [
          "datapipeline:CreatePipeline",
          "datapipeline:PutPipelineDefinition"
        ],
        "Resource": "*",
        "Condition": {
          "StringNotEquals": {
            "aws:PrincipalAccount": "APPROVED_ACCOUNT_ID"
          }
        }
      }
    ]
  }
  ```

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `datapipeline:CreatePipeline` -- new Data Pipeline created; investigate when followed by PutPipelineDefinition and ActivatePipeline
- `datapipeline:PutPipelineDefinition` -- pipeline definition set; inspect the pipeline definition JSON for `resourceRole` values containing privileged role ARNs — this is the CloudTrail signal for PassRole to Data Pipeline; high severity when the definition contains a ShellCommandActivity targeting S3 buckets
- `datapipeline:ActivatePipeline` -- pipeline activated, triggering EC2 instance launch and command execution
- `ec2:RunInstances` -- EC2 instance launched by the Data Pipeline service role
- `s3:GetObject` -- objects read from the sensitive data bucket by the pipeline EC2 instance
- `s3:PutObject` -- objects written cross-account to attacker-controlled exfil bucket; detect cross-account S3 writes from EC2 instances launched by Data Pipeline

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [Bishop Fox - AWS IAM Privilege Escalation Techniques](https://bishopfox.com/blog/privilege-escalation-in-aws) -- documented by Rhino Security Labs
- [AWS Data Pipeline Security Best Practices](https://docs.aws.amazon.com/datapipeline/latest/DeveloperGuide/dp-security-best-practices.html)
