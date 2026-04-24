# Glue Job Update + Trigger to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Update existing Glue job to use privileged role and malicious script, then create trigger for automated execution with persistence
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_glue_006_iam_passrole_glue_updatejob_glue_createtrigger`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** glue-006
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1053 - Scheduled Task/Job, T1565.001 - Data Manipulation: Stored Data Manipulation

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-glue-006-to-admin-starting-user` IAM user to the `pl-prod-glue-006-to-admin-target-role` administrative role by updating an existing Glue job's execution role and script to malicious ones, then creating a scheduled trigger with `--start-on-creation` to execute the job automatically and attach `AdministratorAccess` to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-glue-006-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-glue-006-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-glue-006-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::{account_id}:role/pl-prod-glue-006-to-admin-target-role` -- pass the admin role to the Glue job during update
- `glue:UpdateJob` on `*` -- update existing Glue job to use admin role and malicious script
- `glue:CreateTrigger` on `*` -- create scheduled trigger with `--start-on-creation` to execute job immediately

**Helpful** (`pl-prod-glue-006-to-admin-starting-user`):
- `glue:GetJob` -- retrieve job details and verify configuration
- `glue:GetTrigger` -- monitor trigger state and verify activation
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
plabs enable glue-006-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-006-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-glue-006-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-glue-006-to-admin-initial-role` | Initial non-privileged role that the job starts with |
| `arn:aws:iam::{account_id}:role/pl-prod-glue-006-to-admin-target-role` | Administrative role passed to Glue job during update |
| `arn:aws:iam::{account_id}:policy/pl-prod-glue-006-to-admin-passrole-policy` | Policy allowing PassRole on target role, glue:UpdateJob, and glue:CreateTrigger |
| `arn:aws:glue:{region}:{account_id}:job/pl-glue-006-to-admin-job` | Pre-existing Glue job that will be modified during attack |
| `arn:aws:s3:::pl-glue-scripts-glue-006-{account_id}-{suffix}` | S3 bucket containing benign and malicious scripts |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/glue-006-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Display the current job configuration (initial benign state)
4. Update the existing Glue job to use the admin role and malicious script
5. Pass the admin role to the Glue job as its new execution role
6. Create a SCHEDULED trigger with `--start-on-creation` for automatic execution
7. Wait for the trigger to activate and execute the job (typically 1-2 minutes)
8. Verify successful privilege escalation by testing admin permissions
9. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions


**Note on Costs**: AWS Glue Python shell jobs cost approximately $0.44 per DPU-hour. This demo runs briefly (~30 seconds) and costs less than $0.01 per execution. The trigger is scheduled but will be cleaned up immediately after the demo. Total estimated cost: **~$0.10/month** for occasional testing.

#### Resources Created by Attack Script

- Glue trigger (`pl-glue-006-to-admin-trigger`) attached to the existing Glue job with a scheduled cron (every minute) and `StartOnCreation=true`
- `AdministratorAccess` managed policy attached to `pl-prod-glue-006-to-admin-starting-user`
- Modified Glue job configuration (execution role changed to admin role, script location changed to malicious script)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo glue-006-iam-passrole+glue-updatejob+glue-createtrigger
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-006-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

After demonstrating the attack, clean up the Glue trigger, restore the job configuration, and remove the attached policy.

The cleanup script:
- Removes the AdministratorAccess policy attachment from the starting user
- Deletes the Glue trigger (stops scheduled execution)
- Restores the Glue job to its original benign configuration (initial role and script)
- Verifies all cleanup actions completed successfully

**Important**: Always run cleanup after testing to remove the persistent trigger and restore the job to its original state. The Glue job itself is preserved (as part of the infrastructure) but restored to its benign configuration.

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup glue-006-iam-passrole+glue-updatejob+glue-createtrigger
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-006-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable glue-006-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `glue-006-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user with `iam:PassRole` permission on privileged roles
- IAM user with `glue:UpdateJob` and `glue:CreateTrigger` permissions (especially dangerous combination)
- Combination of PassRole and Glue update permissions enabling privilege escalation
- IAM role with administrative permissions that can be passed to Glue services
- Glue trust policy allowing the Glue service to assume privileged roles
- Privilege escalation path from user to admin via Glue job modification and trigger automation
- Pre-existing Glue jobs with write access by non-admin users (modification risk)

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

- **Monitor CloudTrail for Glue job updates and trigger creation**: Alert on `UpdateJob` and `CreateTrigger` API calls, especially when:
  - The execution role is changed to a more privileged role
  - Script location is modified to point to external or suspicious buckets
  - Combined with PassRole on privileged roles
  - Triggers are created with `StartOnCreation=true` immediately after job updates
  - Jobs use inline scripts or scripts from non-standard S3 locations
  - Execution intervals are suspiciously frequent (every minute)
  - Jobs are updated by users who don't typically work with Glue

- **Restrict glue:UpdateJob and glue:CreateTrigger permissions**: Only grant these permissions to users who legitimately need to modify ETL workflows (data engineers, DevOps). Consider these actions more sensitive than read-only Glue permissions:
  ```json
  {
    "Effect": "Deny",
    "Action": ["glue:UpdateJob", "glue:CreateTrigger"],
    "Resource": "*",
    "Condition": {
      "StringNotLike": {
        "aws:PrincipalArn": "arn:aws:iam::*:role/DataEngineeringTeam*"
      }
    }
  }
  ```

- **Use IAM Access Analyzer**: Enable IAM Access Analyzer to automatically detect privilege escalation paths involving PassRole and Glue services. Review findings regularly and remediate identified risks. Access Analyzer can identify when a principal can modify Glue jobs and pass privileged roles.

- **Implement least privilege for Glue roles**: When creating IAM roles for Glue services, grant only the minimum permissions required for the specific ETL tasks. Avoid using administrative policies like `AdministratorAccess` on Glue service roles. Use resource-specific permissions:
  ```json
  {
    "Effect": "Allow",
    "Action": [
      "s3:GetObject",
      "s3:PutObject"
    ],
    "Resource": [
      "arn:aws:s3:::specific-data-bucket/*"
    ]
  }
  ```

- **Require MFA for sensitive operations**: Implement MFA requirements for operations like `glue:UpdateJob`, `glue:CreateTrigger`, and `iam:PassRole` to add an additional layer of security against compromised credentials.

- **Protect script storage locations via S3 bucket policies**: Implement strict S3 bucket policies on buckets containing Glue scripts. Require that script modifications go through a code review process. Use S3 object versioning and CloudTrail data events to track script changes:
  ```json
  {
    "Effect": "Deny",
    "Principal": "*",
    "Action": "s3:PutObject",
    "Resource": "arn:aws:s3:::glue-scripts-bucket/*",
    "Condition": {
      "StringNotLike": {
        "aws:PrincipalArn": "arn:aws:iam::*:role/ApprovedScriptDeployer"
      }
    }
  }
  ```

- **Monitor IAM policy changes from Glue service principal**: Set up CloudWatch alarms for IAM policy modifications (`AttachUserPolicy`, `AttachRolePolicy`, `PutUserPolicy`, `PutRolePolicy`) where the source is the Glue service principal. This can indicate abuse of Glue jobs for privilege escalation:
  ```json
  {
    "filter-pattern": "{ ($.eventName = AttachUserPolicy || $.eventName = AttachRolePolicy) && $.userIdentity.principalId = \"*:AWSGlueServiceRole*\" }"
  }
  ```

- **Implement change control for production Glue jobs**: Require approval workflows or change tickets for updating production Glue jobs. Use resource tags to identify critical jobs and apply stricter controls. Consider using AWS Service Catalog or AWS CloudFormation StackSets to manage Glue job configurations as infrastructure-as-code.

- **Limit trigger scheduling frequencies**: Implement organizational policies or SCPs that prevent creation of triggers with very frequent schedules (e.g., every minute), as these are often indicators of abuse rather than legitimate ETL workflows:
  ```json
  {
    "Effect": "Deny",
    "Action": "glue:CreateTrigger",
    "Resource": "*",
    "Condition": {
      "StringLike": {
        "glue:Schedule": "*cron(* * * * ? *)*"
      }
    }
  }
  ```

- **Tag and monitor Glue resources**: Apply mandatory tagging to Glue jobs and triggers, and monitor for resources modified without proper tags or by unauthorized users. Use AWS Config rules to enforce tagging policies and detect anomalous Glue resource modification patterns.

- **Separate development and production Glue environments**: Use different AWS accounts or strict IAM boundaries to prevent development users from modifying production Glue jobs. This limits the blast radius of compromised credentials.

- **Enable AWS Config to track Glue configuration changes**: Use AWS Config to continuously monitor and record Glue job configurations. Create Config rules to alert when job execution roles are changed or when jobs are modified outside approved maintenance windows.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PassRole` -- role passed to Glue service; critical when the target role has elevated or administrative permissions
- `Glue: UpdateJob` -- existing Glue job configuration modified; high severity when the execution role is changed to a more privileged role or the script location is changed
- `Glue: CreateTrigger` -- new trigger created for a Glue job; critical when `StartOnCreation=true` is set immediately following a job update
- `IAM: AttachUserPolicy` -- managed policy attached to a user; critical when originating from the Glue service principal (`AWSGlueServiceRole`)
- `IAM: AttachRolePolicy` -- managed policy attached to a role; alert when source is the Glue service principal

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS Glue UpdateJob API Documentation](https://docs.aws.amazon.com/glue/latest/webapi/API_UpdateJob.html) -- official API reference for the UpdateJob call
- [AWS Glue CreateTrigger API Documentation](https://docs.aws.amazon.com/glue/latest/webapi/API_CreateTrigger.html) -- official API reference for the CreateTrigger call
- [IAM PassRole Permission Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html) -- AWS documentation on the iam:PassRole permission
- [Rhino Security Labs - AWS IAM Privilege Escalation Methods](https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation/) -- comprehensive overview of IAM privilege escalation techniques
- [MITRE ATT&CK T1078.004 - Valid Accounts: Cloud Accounts](https://attack.mitre.org/techniques/T1078/004/) -- MITRE technique page
- [MITRE ATT&CK T1053 - Scheduled Task/Job](https://attack.mitre.org/techniques/T1053/) -- MITRE technique page
- [MITRE ATT&CK T1565.001 - Data Manipulation: Stored Data Manipulation](https://attack.mitre.org/techniques/T1565/001/) -- MITRE technique page
