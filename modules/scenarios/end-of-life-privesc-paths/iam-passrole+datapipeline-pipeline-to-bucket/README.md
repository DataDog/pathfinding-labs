# DataPipeline Job Creation to Bucket

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-bucket
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Create Data Pipeline with passed role to exfiltrate S3 data, bypassing IAM restrictions via overly permissive bucket resource policy
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_bucket_iam_passrole_datapipeline_pipeline`
* **Schema Version:** 4.1.1
* **Pathfinding.cloud ID:** datapipeline-001
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0009 - Collection, TA0010 - Exfiltration
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1578 - Modify Cloud Compute Infrastructure, T1530 - Data from Cloud Storage Object

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-datapipeline-001-to-bucket-starting-user` IAM user to the `pl-exfil-bucket-datapipeline-001-{account_id}-{suffix}` S3 bucket by creating an AWS Data Pipeline with a passed read-only role and exploiting an overly permissive bucket resource policy to bypass IAM restrictions and exfiltrate sensitive data.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-datapipeline-001-to-bucket-starting-user`
- **Destination resource:** `arn:aws:s3:::pl-exfil-bucket-datapipeline-001-{account_id}-{suffix}`

### Starting Permissions

**Required** (`pl-prod-datapipeline-001-to-bucket-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-datapipeline-001-to-bucket-pipeline-role` -- allows passing the pipeline role to the Data Pipeline service
- `datapipeline:CreatePipeline` on `*` -- create a new Data Pipeline
- `datapipeline:PutPipelineDefinition` on `*` -- define a ShellCommandActivity with arbitrary commands
- `datapipeline:ActivatePipeline` on `*` -- activate the pipeline, triggering EC2 instance launch
- `s3:GetObject` on `arn:aws:s3:::pl-exfil-bucket-datapipeline-001-{account_id}-{suffix}/*` -- retrieve exfiltrated data from the exfil bucket after the pipeline runs

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
| `arn:aws:s3:::pl-sensitive-data-datapipeline-001-{account_id}-{suffix}` | Sensitive data bucket containing secret data |
| `arn:aws:s3:::pl-exfil-bucket-datapipeline-001-{account_id}-{suffix}` | Exfiltration bucket with overly permissive resource policy |

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
6. Output standardized test results for automation

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
- S3 bucket resource policy grants `s3:PutObject` to `Principal: "*"` (any AWS principal) without restrictive conditions, effectively bypassing IAM policy restrictions
- IAM policies restrict write access to the exfil bucket while the resource policy independently grants it, creating a mismatch that enables resource policy bypass
- Combination of `iam:PassRole` with compute service creation permissions creates a privilege escalation path to sensitive data buckets

#### Prevention Recommendations

- Restrict `iam:PassRole` to specific roles using resource-level conditions (`"Resource": "arn:aws:iam::ACCOUNT:role/specific-role"`) and use the `iam:PassedToService` condition key to limit which services can receive roles (e.g., `"Condition": {"StringEquals": {"iam:PassedToService": "datapipeline.amazonaws.com"}}`)
- Limit `datapipeline:CreatePipeline`, `datapipeline:PutPipelineDefinition`, and `datapipeline:ActivatePipeline` to specific users/roles; use SCPs to block Data Pipeline entirely in production accounts if not needed
- Never use `Principal: "*"` in production bucket policies without restrictive conditions such as `aws:PrincipalOrgID`, `aws:SourceIp`, or `aws:SourceVpc`; enable S3 Block Public Access at account and bucket level
- Require encryption for all data at rest and in transit; use VPC Endpoint policies to restrict bucket access to specific VPCs
- Periodically review all S3 bucket policies with IAM Access Analyzer to identify resources with overly broad access; audit all principals with `iam:PassRole` permissions
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

- `IAM: PassRole` -- role passed to Data Pipeline service; high severity when the role has access to sensitive S3 buckets
- `DataPipeline: CreatePipeline` -- new Data Pipeline created; investigate when combined with PassRole and PutPipelineDefinition
- `DataPipeline: PutPipelineDefinition` -- pipeline definition set, potentially including ShellCommandActivity with arbitrary commands
- `DataPipeline: ActivatePipeline` -- pipeline activated, triggering EC2 instance launch and command execution
- `EC2: RunInstances` -- EC2 instance launched by the Data Pipeline service role
- `S3: GetObject` -- objects read from the sensitive data bucket by the pipeline EC2 instance
- `S3: PutObject` -- objects written to the exfil bucket via resource policy bypass; critical when destination has permissive bucket policy

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [Bishop Fox - AWS IAM Privilege Escalation Techniques](https://bishopfox.com/blog/privilege-escalation-in-aws) -- documented by Rhino Security Labs
- [AWS Data Pipeline Security Best Practices](https://docs.aws.amazon.com/datapipeline/latest/DeveloperGuide/dp-security-best-practices.html)
