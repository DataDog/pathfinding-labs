# Privilege Escalation via iam:PassRole + glue:CreateJob + glue:CreateTrigger

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Pass privileged role to AWS Glue job and create trigger for automated execution with persistence
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_glue_004_iam_passrole_glue_createjob_glue_createtrigger`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** glue-004
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1053 - Scheduled Task/Job

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-glue-004-to-admin-starting-user` IAM user to the `pl-prod-glue-004-to-admin-target-role` administrative role by passing that role to a new AWS Glue job and creating a scheduled trigger with `--start-on-creation` that automatically executes the job and attaches `AdministratorAccess` to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-glue-004-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-glue-004-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-glue-004-to-admin-starting-user`):
- `iam:PassRole` on `*` -- pass the admin target role to Glue as the job execution role
- `glue:CreateJob` on `*` -- create a Glue Python shell job with the admin role attached
- `glue:CreateTrigger` on `*` -- create a scheduled trigger that fires the job automatically

**Helpful** (`pl-prod-glue-004-to-admin-starting-user`):
- `glue:GetJob` -- retrieve job details and verify configuration
- `glue:GetTrigger` -- monitor trigger state and verify activation
- `glue:GetJobRun` -- get details about a specific job run
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
plabs enable enable_single_account_privesc_one_hop_to_admin_glue_004_iam_passrole_glue_createjob_glue_createtrigger
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
| `arn:aws:iam::{account_id}:user/pl-prod-glue-004-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-glue-004-to-admin-target-role` | Administrative role passed to Glue job |
| `arn:aws:iam::{account_id}:policy/pl-prod-glue-004-to-admin-passrole-policy` | Policy allowing PassRole on target role, glue:CreateJob, and glue:CreateTrigger |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create a Glue Python shell job with inline credential escalation script
4. Pass the admin role to the Glue job as its execution role
5. Create a SCHEDULED trigger with `--start-on-creation` for automatic execution
6. Wait for the trigger to activate and execute the job (typically 1-2 minutes)
7. Verify successful privilege escalation by testing admin permissions
8. Output standardized test results for automation

**Note on Costs**: AWS Glue Python shell jobs cost approximately $0.44 per DPU-hour. This demo runs briefly (~30 seconds) and costs less than $0.01 per execution. The trigger is scheduled but will be cleaned up immediately after the demo. Total estimated cost: **~$0.10/month** for occasional testing.

#### Resources Created by Attack Script

- A Glue Python shell job with inline script that attaches `AdministratorAccess` to the starting user
- A scheduled Glue trigger (every minute) with `--start-on-creation` that auto-executes the job
- An `AdministratorAccess` policy attachment on the starting user

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo glue-004-iam-passrole+glue-createjob+glue-createtrigger
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup glue-004-iam-passrole+glue-createjob+glue-createtrigger
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_glue_004_iam_passrole_glue_createjob_glue_createtrigger
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

- IAM user with `iam:PassRole` permission on privileged roles
- IAM user with `glue:CreateJob` and `glue:CreateTrigger` permissions
- Combination of PassRole and Glue permissions enabling privilege escalation
- IAM role with administrative permissions that can be passed to Glue services
- Glue trust policy allowing the Glue service to assume privileged roles
- Privilege escalation path from user to admin via Glue job creation and trigger automation
- Scheduled triggers that execute jobs with elevated privileges (persistence indicator)

#### Prevention Recommendations

- **Restrict PassRole permissions**: Never grant `iam:PassRole` with wildcards. Use resource-based conditions to limit which roles can be passed and to which services:
  ```json
  {
    "Effect": "Allow",
    "Action": "iam:PassRole",
    "Resource": "arn:aws:iam::*:role/specific-glue-etl-role",
    "Condition": {
      "StringEquals": {
        "iam:PassedToService": "glue.amazonaws.com"
      }
    }
  }
  ```

- **Implement SCPs to prevent privilege escalation**: Use Service Control Policies to deny PassRole on administrative roles to Glue services:
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

- **Monitor CloudTrail for Glue job and trigger creation**: Alert on `CreateJob` and `CreateTrigger` API calls, especially when combined with PassRole on privileged roles, triggers are created with `StartOnCreation=true`, jobs use inline scripts, execution intervals are suspiciously frequent (every minute), or jobs are created by users who don't typically work with Glue.

- **Restrict glue:CreateJob and glue:CreateTrigger permissions**: Only grant these permissions to users who legitimately need to create ETL workflows (data engineers). This is particularly important for trigger creation, which enables persistence.

- **Use IAM Access Analyzer**: Enable IAM Access Analyzer to automatically detect privilege escalation paths involving PassRole and Glue services. Review findings regularly and remediate identified risks.

- **Implement least privilege for Glue roles**: When creating IAM roles for Glue services, grant only the minimum permissions required for the specific ETL tasks. Avoid using administrative policies like `AdministratorAccess` on Glue service roles. Use resource-specific permissions (e.g., S3 bucket access only).

- **Require MFA for sensitive operations**: Implement MFA requirements for operations like `glue:CreateJob`, `glue:CreateTrigger`, and `iam:PassRole` to add an additional layer of security against compromised credentials.

- **Block inline scripts via SCP**: Consider using SCPs to require Glue jobs to use scripts from specific S3 buckets rather than inline scripts, making it harder to inject malicious code:
  ```json
  {
    "Effect": "Deny",
    "Action": "glue:CreateJob",
    "Resource": "*",
    "Condition": {
      "Null": {
        "glue:ScriptLocation": "true"
      }
    }
  }
  ```

- **Monitor IAM policy changes from Glue service principal**: Set up CloudWatch alarms for IAM policy modifications (`AttachUserPolicy`, `AttachRolePolicy`, `PutUserPolicy`, `PutRolePolicy`) where the source is the Glue service principal. This can indicate abuse of Glue jobs for privilege escalation.

- **Limit trigger scheduling frequencies**: Implement organizational policies or SCPs that prevent creation of triggers with very frequent schedules (e.g., every minute), as these are often indicators of abuse rather than legitimate ETL workflows.

- **Tag and monitor Glue resources**: Apply mandatory tagging to Glue jobs and triggers, and monitor for resources created without proper tags or by unauthorized users. Use AWS Config rules to enforce tagging policies and detect anomalous Glue resource creation patterns.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PassRole` -- role passed to Glue service; critical when the passed role has administrative permissions
- `Glue: CreateJob` -- new Glue job created; high severity when combined with a privileged execution role or inline script
- `Glue: CreateTrigger` -- Glue trigger created; critical when `StartOnCreation=true` or schedule is very frequent (e.g., every minute)
- `IAM: AttachUserPolicy` -- managed policy attached to IAM user; critical when source is the Glue service principal
- `IAM: AttachRolePolicy` -- managed policy attached to IAM role; critical when originating from Glue service principal

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
