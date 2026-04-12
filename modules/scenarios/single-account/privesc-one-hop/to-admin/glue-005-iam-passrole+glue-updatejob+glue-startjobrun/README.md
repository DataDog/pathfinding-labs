# Glue Job Update + Run to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Modify existing Glue Job to use privileged role and malicious script for privilege escalation
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_glue_005_iam_passrole_glue_updatejob_glue_startjobrun`
* **Schema Version:** 4.1.1
* **Pathfinding.cloud ID:** glue-005
* **MITRE Tactics:** TA0004 - Privilege Escalation
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1565.001 - Data Manipulation: Stored Data Manipulation

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-glue-005-to-admin-starting-user` IAM user to the `pl-prod-glue-005-to-admin-target-role` administrative role by modifying an existing Glue job to use an admin IAM role and a malicious script, then triggering execution to attach `AdministratorAccess` to yourself.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-glue-005-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-glue-005-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-glue-005-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::{account_id}:role/pl-prod-glue-005-to-admin-target-role` -- pass the admin role to the Glue job during update
- `glue:UpdateJob` on `*` -- update existing Glue job to use admin role and malicious script
- `glue:StartJobRun` on `*` -- execute the updated Glue job with admin privileges

**Helpful** (`pl-prod-glue-005-to-admin-starting-user`):
- `glue:GetJob` -- retrieve job details and verify configuration
- `glue:GetJobRun` -- get details about a specific job run
- `glue:GetJobRuns` -- list job runs to monitor execution status
- `sts:GetCallerIdentity` -- verify current identity and account ID
- `iam:ListUsers` -- verify admin access after privilege escalation

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable glue-005-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-005-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-glue-005-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-glue-005-to-admin-initial-role` | Initial non-privileged role that the Glue job starts with (only AWSGlueServiceRole permissions) |
| `arn:aws:iam::{account_id}:role/pl-prod-glue-005-to-admin-target-role` | Administrative role that will be passed to the job during update |
| `arn:aws:iam::{account_id}:policy/pl-prod-glue-005-to-admin-passrole-policy` | Policy allowing PassRole on target role, glue:UpdateJob, and glue:StartJobRun |
| `arn:aws:s3:::pl-glue-scripts-glue-005-{account_id}-{suffix}/benign_script.py` | Original benign Python script that the job starts with |
| `arn:aws:s3:::pl-glue-scripts-glue-005-{account_id}-{suffix}/escalation_script.py` | Malicious Python script that performs privilege escalation |
| `arn:aws:glue:{region}:{account_id}:job/pl-glue-005-to-admin-job` | Pre-existing Glue Python shell job that will be updated during the attack |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Display the current (benign) configuration of the pre-existing Glue job
4. Update the Glue job to use the admin role and malicious script
5. Start the job execution manually
6. Wait for the job to complete (typically 1-2 minutes)
7. Verify successful privilege escalation by demonstrating admin access


#### Resources Created by Attack Script

- Modified Glue job configuration (role changed to `pl-prod-glue-005-to-admin-target-role`, script changed to `escalation_script.py`)
- `AdministratorAccess` policy attached to `pl-prod-glue-005-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo glue-005-iam-passrole+glue-updatejob+glue-startjobrun
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-005-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup glue-005-iam-passrole+glue-updatejob+glue-startjobrun
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-005-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable glue-005-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-005-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user with `iam:PassRole` permission on privileged roles
- IAM user with `glue:UpdateJob` and `glue:StartJobRun` permissions
- Combination of PassRole and Glue update permissions enabling privilege escalation
- IAM role with administrative permissions that can be passed to Glue services
- Glue trust policy allowing the Glue service to assume privileged roles
- Privilege escalation path from user to admin via Glue job modification
- Glue jobs with roles that have excessive permissions (e.g., AdministratorAccess)
- Configuration drift: Glue job role or script changes from baseline configuration

#### Prevention Recommendations

- **Restrict PassRole permissions**: Limit `iam:PassRole` to only the specific roles and services needed. Use resource-level restrictions with conditions:
  ```json
  {
    "Effect": "Allow",
    "Action": "iam:PassRole",
    "Resource": "arn:aws:iam::*:role/approved-glue-roles-*",
    "Condition": {
      "StringEquals": {
        "iam:PassedToService": "glue.amazonaws.com"
      }
    }
  }
  ```

- **Implement SCPs to prevent privilege escalation**: Use Service Control Policies to deny PassRole on administrative roles:
  ```json
  {
    "Effect": "Deny",
    "Action": "iam:PassRole",
    "Resource": [
      "arn:aws:iam::*:role/*admin*",
      "arn:aws:iam::*:role/*Admin*"
    ],
    "Condition": {
      "StringEquals": {
        "iam:PassedToService": "glue.amazonaws.com"
      }
    }
  }
  ```

- **Separate CreateJob and UpdateJob permissions**: Grant `glue:CreateJob` and `glue:UpdateJob` to different personas. Data engineers who create new ETL jobs shouldn't necessarily have permission to modify all existing jobs:
  ```json
  {
    "Effect": "Allow",
    "Action": "glue:UpdateJob",
    "Resource": "arn:aws:glue:*:*:job/team-specific-prefix-*",
    "Condition": {
      "StringEquals": {
        "aws:RequestedRegion": "us-east-1"
      }
    }
  }
  ```

- **Implement configuration baselines**: Use AWS Config rules to track approved configurations for each Glue job — monitor for role ARN changes, alert on script location changes from trusted S3 buckets, detect jobs running with administrative policies, and enforce tagging requirements for all jobs.

- **Restrict script locations**: Use SCPs or IAM conditions to require all Glue job scripts to be stored in approved, audited S3 buckets:
  ```json
  {
    "Effect": "Deny",
    "Action": ["glue:CreateJob", "glue:UpdateJob"],
    "Resource": "*",
    "Condition": {
      "StringNotLike": {
        "glue:ScriptLocation": "s3://approved-glue-scripts-bucket/*"
      }
    }
  }
  ```

- **Implement least privilege for Glue roles**: Grant Glue service roles only the minimum permissions required for the specific ETL tasks. Avoid `AdministratorAccess` or `PowerUserAccess` on Glue service roles. Typical Glue jobs need S3 read/write access to specific buckets, Glue Data Catalog access, and CloudWatch Logs write access — not IAM permissions.

- **Use IAM Access Analyzer**: Enable IAM Access Analyzer to automatically detect privilege escalation paths involving PassRole and Glue services. Review findings regularly and remediate identified risks.

- **Audit Glue job execution**: Review CloudWatch Logs for Glue jobs to identify jobs making IAM API calls (unusual for ETL workloads), jobs accessing unexpected AWS services, and jobs with unusually short execution times that may indicate malicious use.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PassRole` -- Starting user passes the admin role to the Glue service; critical when the target role has elevated permissions
- `Glue: UpdateJob` -- Existing Glue job configuration modified; high severity when the `Role` or `ScriptLocation` parameter changes to a privileged value
- `Glue: StartJobRun` -- Job execution triggered; suspicious when immediately following an `UpdateJob` event (< 5 minutes)
- `IAM: AttachUserPolicy` -- AdministratorAccess policy attached to the starting user by the Glue job execution role; indicates successful privilege escalation
- `IAM: PutUserPolicy` -- Inline admin policy added to user from Glue service principal; alternative escalation method to watch

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS Glue UpdateJob API Documentation](https://docs.aws.amazon.com/glue/latest/webapi/API_UpdateJob.html) -- API reference for the UpdateJob call used in this attack
- [AWS Glue Jobs Documentation](https://docs.aws.amazon.com/glue/latest/dg/author-job.html) -- General Glue job authoring documentation
- [AWS Glue Python Shell Jobs](https://docs.aws.amazon.com/glue/latest/dg/add-job-python.html) -- Python shell job specifics
- [AWS IAM PassRole Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html) -- How iam:PassRole works and security implications
- [Rhino Security Labs - AWS IAM Privilege Escalation Methods](https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation/) -- Comprehensive reference for IAM privilege escalation techniques
- [MITRE ATT&CK - T1565.001 Data Manipulation: Stored Data Manipulation](https://attack.mitre.org/techniques/T1565/001/) -- MITRE technique page
