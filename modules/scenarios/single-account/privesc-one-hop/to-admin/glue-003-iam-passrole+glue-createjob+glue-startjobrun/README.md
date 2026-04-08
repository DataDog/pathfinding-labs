# Glue Job Creation + Run to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Pass privileged role to AWS Glue Job with inline Python script for privilege escalation
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_glue_003_iam_passrole_glue_createjob_glue_startjobrun`
* **Schema Version:** 4.1.1
* **Pathfinding.cloud ID:** glue-003
* **MITRE Tactics:** TA0004 - Privilege Escalation
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-glue-003-to-admin-starting-user` IAM user to the `pl-prod-glue-003-to-admin-target-role` administrative role by passing the admin role to a newly created AWS Glue Python shell job whose embedded script attaches `AdministratorAccess` back to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-glue-003-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-glue-003-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-glue-003-to-admin-starting-user`):
- `iam:PassRole` on `*` -- allows passing the admin target role to the Glue job at creation time
- `glue:CreateJob` on `*` -- allows creating the Glue Python shell job with the malicious script
- `glue:StartJobRun` on `*` -- allows triggering execution of the created job

**Helpful** (`pl-prod-glue-003-to-admin-starting-user`):
- `glue:GetJob` -- retrieve job details and verify configuration
- `glue:GetJobRun` -- get details about a specific job run to monitor execution status
- `glue:GetJobRuns` -- list job runs to monitor execution status
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
plabs enable glue-003-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-003-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-glue-003-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-glue-003-to-admin-target-role` | Administrative role passed to Glue job |
| `arn:aws:iam::{account_id}:policy/pl-prod-glue-003-to-admin-passrole-policy` | Policy allowing PassRole on target role, glue:CreateJob, and glue:StartJobRun |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create a Glue Python shell job with inline malicious code
4. Pass the admin role to the Glue job during creation
5. Start the job execution manually
6. Wait for the job to complete (typically 1-2 minutes)
7. Verify successful privilege escalation by demonstrating admin access
8. Output standardized test results for automation

#### Resources Created by Attack Script

- AWS Glue Python shell job with malicious Python script sourced from attacker-controlled S3
- AdministratorAccess policy attached to the starting user

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo glue-003-iam-passrole+glue-createjob+glue-startjobrun
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-003-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup glue-003-iam-passrole+glue-createjob+glue-startjobrun
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-003-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable glue-003-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-003-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user with `iam:PassRole` permission on privileged roles
- IAM user with `glue:CreateJob` and `glue:StartJobRun` permissions
- Combination of PassRole and Glue permissions enabling privilege escalation
- IAM role with administrative permissions that can be passed to Glue services
- Glue trust policy allowing the Glue service to assume privileged roles
- Privilege escalation path from user to admin via Glue job creation
- Glue jobs created with inline commands (higher risk than S3-stored scripts)

#### Prevention Recommendations

- **Restrict PassRole permissions**: Limit `iam:PassRole` to only the specific roles and services needed. Use resource-level restrictions:
  ```json
  {
    "Effect": "Allow",
    "Action": "iam:PassRole",
    "Resource": "arn:aws:iam::*:role/specific-glue-role",
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
    "Resource": "arn:aws:iam::*:role/*admin*",
    "Condition": {
      "StringEquals": {
        "iam:PassedToService": "glue.amazonaws.com"
      }
    }
  }
  ```

- **Require S3-stored scripts**: Enforce policies that deny `glue:CreateJob` when inline commands are used. Require all Glue job scripts to be stored in audited S3 buckets:
  ```json
  {
    "Effect": "Deny",
    "Action": "glue:CreateJob",
    "Resource": "*",
    "Condition": {
      "StringLike": {
        "glue:CommandName": "pythonshell"
      },
      "Null": {
        "glue:ScriptLocation": "true"
      }
    }
  }
  ```

- **Restrict glue:CreateJob and glue:StartJobRun permissions**: Only grant these permissions to users who legitimately need to create and run Glue jobs (data engineers, ETL developers). These are powerful permissions that should be tightly controlled.

- **Use IAM Access Analyzer**: Enable IAM Access Analyzer to automatically detect privilege escalation paths involving PassRole and Glue services. Review findings regularly and remediate identified risks.

- **Implement least privilege for Glue roles**: When creating IAM roles for Glue services, grant only the minimum permissions required for the specific ETL tasks. Avoid using administrative policies like `AdministratorAccess` or `PowerUserAccess` on Glue service roles. Typical Glue jobs need S3, Glue Data Catalog, and CloudWatch Logs access — not IAM permissions.

- **Tag and monitor Glue resources**: Apply mandatory tagging to Glue jobs and monitor for jobs created without proper tags or by unauthorized users. Use AWS Config rules to enforce tagging policies and detect jobs with administrative roles.

- **Separate Glue accounts**: Consider running production Glue workloads in dedicated AWS accounts with strict cross-account access controls, limiting the blast radius of compromised Glue permissions.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `Glue: CreateJob` -- New Glue job created; high severity when the job role is administrative or when inline commands are used instead of S3-stored scripts; the embedded iam:PassRole authorization check also appears in this event
- `Glue: StartJobRun` -- Glue job execution triggered; suspicious when immediately following job creation by a user who does not regularly use Glue
- `IAM: AttachUserPolicy` -- Policy attached to an IAM user; critical when the caller is the Glue service principal and the policy grants admin access
- `IAM: PutUserPolicy` -- Inline policy added to an IAM user; critical when executed by the Glue service principal

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS Glue Jobs Documentation](https://docs.aws.amazon.com/glue/latest/dg/author-job.html) -- official Glue job authoring reference
- [AWS Glue Python Shell Jobs](https://docs.aws.amazon.com/glue/latest/dg/add-job-python.html) -- Python shell job configuration details
- [AWS IAM PassRole Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html) -- how iam:PassRole works and why it matters
- [Rhino Security Labs - AWS IAM Privilege Escalation Methods](https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation/) -- survey of IAM privilege escalation techniques including PassRole patterns
