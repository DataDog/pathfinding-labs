# Step Functions State Machine Execution to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Pass an admin role to a Step Functions state machine that calls IAM APIs via SDK service integration to attach AdministratorAccess to the starting user
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_stepfunctions_001_iam_passrole_states_createstatemachine_states_startexecution`
* **Schema Version:** 4.6.1
* **Pathfinding.cloud ID:** stepfunctions-001
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-stepfunctions-001-to-admin-starting-user` IAM user to the `pl-prod-stepfunctions-001-to-admin-admin-role` administrative role by creating a Step Functions state machine with the admin role as the execution role and a definition that calls `iam:AttachUserPolicy` via the AWS SDK service integration, then starting execution to attach `AdministratorAccess` to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-stepfunctions-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-stepfunctions-001-to-admin-admin-role`

### Starting Permissions

**Required** (`pl-prod-stepfunctions-001-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-stepfunctions-001-to-admin-admin-role` -- allows passing the admin role to the Step Functions service as the state machine execution role
- `states:CreateStateMachine` on `*` -- allows creating a new state machine with a definition that calls IAM APIs via SDK service integration
- `states:StartExecution` on `*` -- allows starting execution of the created state machine, triggering the IAM API call under the admin role's credentials

**Helpful** (`pl-prod-stepfunctions-001-to-admin-starting-user`):
- `states:DescribeExecution` -- poll execution status to verify the state machine completed successfully
- `states:DescribeStateMachine` -- verify the state machine was created with the correct definition and role
- `iam:ListAttachedUserPolicies` -- verify privilege escalation success by listing attached policies on the starting user

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable stepfunctions-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `stepfunctions-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-stepfunctions-001-to-admin-starting-user` | Scenario-specific starting user with access keys, PassRole, and Step Functions permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-stepfunctions-001-to-admin-admin-role` | Administrative role (trusts `states.amazonaws.com`) passed as the execution role to the state machine |
| `arn:aws:iam::{account_id}:policy/pl-prod-stepfunctions-001-to-admin-starting-user-policy` | Policy granting the starting user PassRole and Step Functions permissions |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/stepfunctions-001-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create a Step Functions state machine with the admin role as the execution role and a definition that calls `iam:AttachUserPolicy` via SDK service integration
4. Start execution of the state machine
5. Wait for the execution to complete
6. Verify successful privilege escalation by demonstrating admin access
7. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions

#### Resources Created by Attack Script

- Step Functions state machine with the admin role as the execution role
- `AdministratorAccess` managed policy attached to `pl-prod-stepfunctions-001-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo stepfunctions-001-iam-passrole+states-createstatemachine+states-startexecution
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup stepfunctions-001-iam-passrole+states-createstatemachine+states-startexecution
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable stepfunctions-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `stepfunctions-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user with `iam:PassRole` permission on a role that has administrative permissions
- IAM user with `states:CreateStateMachine` and `states:StartExecution` permissions combined with `iam:PassRole`, forming a privilege escalation path
- IAM role with `AdministratorAccess` or equivalent permissions that trusts `states.amazonaws.com` and can be passed to Step Functions state machines
- Privilege escalation path from IAM user to admin via Step Functions state machine execution

#### Prevention Recommendations

- Restrict `iam:PassRole` using the `iam:PassedToService` condition key to limit which services a role can be passed to (e.g., `"iam:PassedToService": "states.amazonaws.com"`), and further restrict which roles can be passed using resource constraints
- Avoid granting `states:CreateStateMachine` and `states:StartExecution` together unless absolutely necessary; this combination enables arbitrary AWS API execution when paired with `iam:PassRole`
- Audit all IAM roles with trust policies allowing `states.amazonaws.com` and ensure they follow least privilege -- admin roles should never trust the Step Functions service principal
- Implement SCPs that deny `states:CreateStateMachine` when the request includes `aws-sdk:iam:` actions in the state machine definition, or restrict `states:CreateStateMachine` to authorized automation principals only
- Use IAM Access Analyzer to automatically detect privilege escalation paths where users can pass privileged roles to Step Functions
- Enable AWS Config rules to alert when state machines are created with execution roles that carry administrative permissions

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `states:CreateStateMachine` -- new state machine created; inspect `requestParameters.roleArn` — a privileged role ARN here is the CloudTrail signal for PassRole abuse via Step Functions; high severity when the role has administrative permissions and the definition contains `aws-sdk:iam:` resource ARNs indicating IAM manipulation
- `states:StartExecution` -- state machine execution started; correlate with a preceding `CreateStateMachine` call from the same principal to identify abuse of newly created state machines
- `iam:AttachUserPolicy` -- managed policy attached to an IAM user; critical when the policy is `AdministratorAccess` and the caller is a Step Functions execution role assumed by the `states.amazonaws.com` service principal
- `iam:PutUserPolicy` -- inline policy added to an IAM user; monitor for policies granting broad permissions where the caller context is a Step Functions execution role

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS Step Functions SDK Service Integrations](https://docs.aws.amazon.com/step-functions/latest/dg/concepts-service-integrations.html) -- explains how state machines call AWS APIs directly via `arn:aws:states:::aws-sdk:{service}:{action}` resource ARNs
- [AWS IAM PassRole Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html) -- explains PassRole mechanics and how to restrict it with `iam:PassedToService`
- [Rhino Security Labs - AWS IAM Privilege Escalation Methods](https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation/) -- comprehensive overview of IAM privilege escalation techniques including PassRole patterns
- [pathfinding.cloud/paths/stepfunctions-001](https://pathfinding.cloud/paths/stepfunctions-001) -- documented attack path for this scenario
