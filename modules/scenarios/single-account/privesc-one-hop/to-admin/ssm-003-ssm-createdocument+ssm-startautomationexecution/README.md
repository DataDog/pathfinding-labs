# PassRole + SSM Automation ExecuteScript to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Create a custom SSM Automation document with a Python aws:executeScript step and start execution with an admin role as AutomationAssumeRole to attach AdministratorAccess to the starting user
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_ssm_003_ssm_createdocument_ssm_startautomationexecution`
* **Schema Version:** 4.7.0
* **Pathfinding.cloud ID:** ssm-003
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0005 - Defense Evasion
* **MITRE Techniques:** T1098 - Account Manipulation, T1651 - Cloud Administration Command

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-ssm-003-to-admin-starting-user` IAM user to administrator access by creating a custom SSM Automation document containing a Python `aws:executeScript` step that attaches `AdministratorAccess` to the starting user, then passing the `pl-prod-ssm-003-to-admin-automation-role` admin role as the `AutomationAssumeRole` — causing SSM to execute the script under that role's credentials with no EC2 instance or SSM agent required.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-ssm-003-to-admin-starting-user`
- **Destination resource:** `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/ssm-003-to-admin`

### Starting Permissions

**Required** (`pl-prod-ssm-003-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::{account_id}:role/pl-prod-ssm-003-to-admin-automation-role` -- allows passing the admin role to SSM Automation as the AutomationAssumeRole; the PassRole check happens at ssm:StartAutomationExecution call time
- `ssm:CreateDocument` on `*` -- register the custom Automation document containing the malicious aws:executeScript step
- `ssm:StartAutomationExecution` on `*` -- trigger the automation execution, passing the admin role and the target username as parameters

**Helpful** (`pl-prod-ssm-003-to-admin-starting-user`):
- `iam:ListRoles` -- discover IAM roles that trust ssm.amazonaws.com and are candidates for AutomationAssumeRole
- `iam:GetRole` -- inspect the trust policy of candidate roles to confirm they are assumable by SSM Automation
- `ssm:ListDocuments` -- enumerate existing SSM documents for situational awareness
- `ssm:DescribeDocument` -- inspect document schema and parameters
- `ssm:GetAutomationExecution` -- poll automation execution status to confirm the Python script ran successfully and AdministratorAccess was attached

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable ssm-003-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ssm-003-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-ssm-003-to-admin-starting-user` | Scenario-specific starting user with access keys and the three required permissions |
| `arn:aws:iam::{account_id}:policy/pl-prod-ssm-003-to-admin-starting-policy` | Inline policy granting `iam:PassRole` on the automation role, `ssm:CreateDocument`, and `ssm:StartAutomationExecution` |
| `arn:aws:iam::{account_id}:role/pl-prod-ssm-003-to-admin-automation-role` | Admin role trusted by ssm.amazonaws.com; passed as AutomationAssumeRole so SSM runs the Python script under its credentials |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/ssm-003-to-admin` | CTF flag stored in SSM Parameter Store; readable with AdministratorAccess |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve scenario credentials (starting user access keys and automation role ARN) from Terraform outputs
2. Verify the starting user's identity and confirm it cannot read the CTF flag
3. Write a custom SSM Automation document (schema version 0.3) with a Python `aws:executeScript` step that calls `iam:AttachUserPolicy` to attach `AdministratorAccess` to the starting user
4. Register the document using `ssm:CreateDocument` as the starting user
5. Start the automation execution using `ssm:StartAutomationExecution`, passing the admin role as `AutomationAssumeRole` and the starting username as a parameter — triggering the `iam:PassRole` check at call time
6. Poll for execution completion using the auditor credentials (`ssm:GetAutomationExecution`) until the status is `Success`
7. Wait 15 seconds for IAM policy propagation
8. Read the CTF flag from SSM Parameter Store using the original starting user credentials (which now carry `AdministratorAccess`)

#### Resources Created by Attack Script

- Transient SSM Automation document (created and left in account until `cleanup_attack.sh` removes it)
- `AdministratorAccess` managed policy attached to `pl-prod-ssm-003-to-admin-starting-user` (removed by `cleanup_attack.sh`)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo ssm-003-ssm-createdocument+ssm-startautomationexecution
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ssm-003-ssm-createdocument+ssm-startautomationexecution
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable ssm-003-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ssm-003-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- **IAM user with `iam:PassRole` to a role trusted by ssm.amazonaws.com**: The combination of `iam:PassRole` scoped to an SSM-trusted admin role plus `ssm:CreateDocument` and `ssm:StartAutomationExecution` is a complete privilege escalation path — CSPM should flag this triple as a critical finding regardless of individual permission risk scores.
- **IAM roles trusted by ssm.amazonaws.com with administrator-equivalent permissions**: Roles that can be assumed by `ssm.amazonaws.com` as a principal and hold `AdministratorAccess` or wildcard `*:*` inline policies create a ready-made AutomationAssumeRole for any attacker who holds `iam:PassRole` to it. These should be flagged as high-risk trust relationships.
- **Overly broad `ssm:CreateDocument` and `ssm:StartAutomationExecution` without resource constraints**: Granting these permissions on `*` rather than on specific document ARNs or with condition keys allows an attacker to register arbitrary documents and trigger executions with any role they can pass.
- **No SCP restricting `ssm:StartAutomationExecution` in combination with `iam:PassRole`**: Organizations without Service Control Policies preventing this combination at the account level cannot rely solely on account-level IAM to block this escalation path.

#### Prevention Recommendations

- **Restrict `iam:PassRole` with condition keys**: Use the `iam:PassedToService` condition to limit which services a principal can pass roles to, and scope the resource ARN to only roles specifically intended for automation:
  ```json
  {
    "Effect": "Allow",
    "Action": "iam:PassRole",
    "Resource": "arn:aws:iam::*:role/safe-automation-role-only",
    "Condition": {
      "StringEquals": {
        "iam:PassedToService": "ssm.amazonaws.com"
      }
    }
  }
  ```

- **Apply least privilege to SSM Automation execution roles**: Roles trusted by `ssm.amazonaws.com` should hold only the specific permissions required for the intended automation task — never `AdministratorAccess`. If admin-level operations are genuinely needed, scope them to specific resource ARNs and actions rather than using managed policies.

- **Restrict `ssm:CreateDocument` and `ssm:StartAutomationExecution` to specific document ARNs**: Where possible, scope these actions to approved document ARNs or use `aws:RequestedRegion` and resource tag conditions to prevent arbitrary document creation:
  ```json
  {
    "Effect": "Allow",
    "Action": "ssm:StartAutomationExecution",
    "Resource": "arn:aws:ssm:*:*:automation-definition/approved-doc-*:*"
  }
  ```

- **Implement SCPs blocking `ssm:CreateDocument` combined with `iam:PassRole` for non-automation principals**: Use AWS Organizations Service Control Policies to ensure only dedicated automation accounts or roles can create SSM documents and start executions.

- **Enable AWS Config rules for SSM Automation document content review**: Monitor the creation of new SSM Automation documents containing `aws:executeScript` steps, particularly in accounts where admin-trusted SSM roles exist.

- **Use IAM Access Analyzer to identify PassRole escalation paths**: Regularly scan for IAM users or roles that can pass any role trusted by `ssm.amazonaws.com` and hold `ssm:CreateDocument` + `ssm:StartAutomationExecution`. This triple constitutes a complete escalation path regardless of individual permission risk ratings.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `ssm:CreateDocument` -- new SSM document registered; high severity when the creating principal also holds `iam:PassRole` and `ssm:StartAutomationExecution`, or when the document content includes `aws:executeScript` steps
- `ssm:StartAutomationExecution` -- automation execution triggered; alert when `requestParameters.parameters.AutomationAssumeRole` contains a role ARN with administrator-equivalent permissions, indicating a role is being passed into automation
- `ssm:DeleteDocument` -- SSM document deleted shortly after creation and execution; common cleanup step indicating deliberate artifact removal after exploitation
- `iam:AttachUserPolicy` -- managed policy attached to an IAM user; critical when `requestParameters.policyArn` is `arn:aws:iam::aws:policy/AdministratorAccess` and the event source is an SSM Automation execution context
- `sts:AssumeRole` -- role assumed by `ssm.amazonaws.com`; correlate with a preceding `ssm:StartAutomationExecution` to identify automation executions that assume admin roles

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [https://pathfinding.cloud/paths/ssm-003](https://pathfinding.cloud/paths/ssm-003) -- Pathfinding.cloud path entry for PassRole + SSM Automation ExecuteScript to Admin
- [https://attack.mitre.org/techniques/T1651/](https://attack.mitre.org/techniques/T1651/) -- MITRE ATT&CK T1651: Cloud Administration Command
- [https://attack.mitre.org/techniques/T1098/](https://attack.mitre.org/techniques/T1098/) -- MITRE ATT&CK T1098: Account Manipulation
- [https://docs.aws.amazon.com/systems-manager/latest/userguide/automation-documents.html](https://docs.aws.amazon.com/systems-manager/latest/userguide/automation-documents.html) -- AWS documentation on SSM Automation documents and the aws:executeScript action type
