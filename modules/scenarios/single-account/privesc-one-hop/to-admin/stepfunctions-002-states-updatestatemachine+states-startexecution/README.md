# UpdateStateMachine + StartExecution on Existing Admin-Role State Machine

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Principal with states:UpdateStateMachine and states:StartExecution can replace an existing state machine's definition with malicious ASL that runs under the machine's pre-existing admin role — no iam:PassRole required
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_stepfunctions_002_states_updatestatemachine_states_startexecution`
* **Schema Version:** 4.7.1
* **Pathfinding.cloud ID:** stepfunctions-002
* **MITRE Tactics:** TA0004 - Privilege Escalation
* **MITRE Techniques:** T1098 - Account Manipulation, T1578 - Modify Cloud Compute Infrastructure
* **CTF Flag Location:** ssm-parameter
* **Required Preconditions:**
  - Step Functions State Machine: with an admin-equivalent IAM execution role already attached (UpdateStateMachine without changing roleArn does not trigger iam:PassRole)

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-stepfunctions-002-to-admin-starting-user` IAM user to the `pl-prod-stepfunctions-002-to-admin-statemachine-role` administrative role by replacing an existing state machine's benign definition with malicious ASL that attaches `AdministratorAccess` to the starting user — without ever needing `iam:PassRole`.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-stepfunctions-002-to-admin-starting-user`
- **Destination resource:** `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/stepfunctions-002-to-admin`

### Starting Permissions

**Required** (`pl-prod-stepfunctions-002-to-admin-starting-user`):
- `states:UpdateStateMachine` on `arn:aws:states:*:*:stateMachine/pl-prod-stepfunctions-002-to-admin-statemachine` -- replace the state machine's definition with attacker-authored ASL
- `states:StartExecution` on `arn:aws:states:*:*:stateMachine/pl-prod-stepfunctions-002-to-admin-statemachine` -- trigger the malicious execution that runs as the pre-existing admin role

**Helpful** (`pl-prod-stepfunctions-002-to-admin-starting-user`):
- `states:ListStateMachines` -- Discover existing state machines in the account
- `states:DescribeStateMachine` -- Inspect the state machine's current definition and role ARN
- `states:ListExecutions` -- Monitor execution status after StartExecution
- `states:DescribeExecution` -- Check whether the execution succeeded and AdministratorAccess was attached

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable stepfunctions-002-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `stepfunctions-002-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
|-----|---------|
| `arn:aws:iam::{account_id}:user/pl-prod-stepfunctions-002-to-admin-starting-user` | Starting IAM user with only states:UpdateStateMachine and states:StartExecution |
| `arn:aws:states:{region}:{account_id}:stateMachine/pl-prod-stepfunctions-002-to-admin-statemachine` | Pre-existing state machine with a benign initial definition and admin execution role attached |
| `arn:aws:iam::{account_id}:role/pl-prod-stepfunctions-002-to-admin-statemachine-role` | State machine execution role with AdministratorAccess — the privileged role abused by the attacker |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/stepfunctions-002-to-admin` | CTF flag stored as an SSM String parameter; readable only with admin-equivalent credentials |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:

1. Retrieve starting user credentials from Terraform outputs
2. Confirm the starting user is denied access to the SSM flag (proving no prior privilege)
3. Build a malicious ASL definition: a single `Task` state that calls `arn:aws:states:::aws-sdk:iam:attachUserPolicy` to attach `AdministratorAccess` to the starting user
4. Call `states:UpdateStateMachine` to replace the state machine's benign definition with the malicious ASL (no `iam:PassRole` required since `roleArn` is unchanged)
5. Call `states:StartExecution` to trigger the malicious execution, which runs as the pre-existing admin role
6. Wait 30 seconds for the IAM policy attachment to propagate
7. Confirm the starting user can now read the SSM flag, proving successful privilege escalation

#### Resources Created by Attack Script

- Temporary ASL definition JSON file written to `/tmp/` (cleaned up by the script)
- `AdministratorAccess` managed policy attached to `pl-prod-stepfunctions-002-to-admin-starting-user`
- Updated state machine definition on `pl-prod-stepfunctions-002-to-admin-statemachine` (benign definition restored by `cleanup_attack.sh`)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo stepfunctions-002-states-updatestatemachine+states-startexecution
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup stepfunctions-002-states-updatestatemachine+states-startexecution
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable stepfunctions-002-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `stepfunctions-002-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user `pl-prod-stepfunctions-002-to-admin-starting-user` has `states:UpdateStateMachine` on the state machine `pl-prod-stepfunctions-002-to-admin-statemachine` — combined with `states:StartExecution`, this constitutes a privilege escalation path without requiring `iam:PassRole`
- State machine `pl-prod-stepfunctions-002-to-admin-statemachine` has an execution role (`pl-prod-stepfunctions-002-to-admin-statemachine-role`) with `AdministratorAccess` — any principal with `states:UpdateStateMachine` on this resource can effectively assume admin without `iam:PassRole`
- The combination of `states:UpdateStateMachine + states:StartExecution` on a state machine whose execution role holds sensitive permissions is a standing privilege escalation risk, equivalent to a PassRole bypass
- `pl-prod-stepfunctions-002-to-admin-statemachine-role` grants `AdministratorAccess` to `states.amazonaws.com` — this service principal can perform any IAM action including `iam:AttachUserPolicy` and `iam:CreateRole`

#### Prevention Recommendations

- Apply SCPs or permission boundaries that block `states:UpdateStateMachine` for non-administrative IAM principals — or restrict it to state machines tagged as non-privileged
- Enforce tag-based IAM conditions (e.g., `aws:ResourceTag/sensitivity != high`) so that `states:UpdateStateMachine` cannot be exercised on state machines with sensitive execution roles
- Audit state machine execution roles for `AdministratorAccess` or wildcard IAM policies; grant only the minimum permissions required by the state machine's legitimate workload
- Use resource-based controls or AWS Config rules to alert when a state machine's execution role holds admin-equivalent policies
- Require `iam:PassRole` scoping: use an SCP or IAM condition on state machine creation and update operations to enforce that the execution role's permissions are limited to the state machine's intended actions
- Regularly review CloudTrail for `states:UpdateStateMachine` events and correlate any subsequent `iam:AttachUserPolicy` or `iam:AttachRolePolicy` events with `states.amazonaws.com` as the caller

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `states:UpdateStateMachine` -- state machine definition replaced; high severity when the new definition contains `aws-sdk:iam:*` resource references or other IAM SDK integrations
- `states:StartExecution` -- state machine execution triggered; correlate with recent `UpdateStateMachine` events on the same resource to detect exploitation attempts
- `iam:AttachUserPolicy` -- IAM policy attached to a user; critical when `userAgent` contains `states.amazonaws.com` or the `sourceIPAddress` field shows the Step Functions service endpoint — this indicates the attachment was performed by a state machine execution rather than a human operator
- `iam:AttachRolePolicy` -- IAM policy attached to a role; same service-principal correlation applies
- `ssm:GetParameter` -- SSM parameter accessed; alert when the parameter path matches `/pathfinding-labs/flags/*` and the caller is the starting user rather than an expected admin

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [https://pathfinding.cloud/paths/stepfunctions-002](https://pathfinding.cloud/paths/stepfunctions-002) -- Pathfinding.cloud path entry for this technique
- [https://attack.mitre.org/techniques/T1098/](https://attack.mitre.org/techniques/T1098/) -- MITRE ATT&CK T1098: Account Manipulation
- [https://attack.mitre.org/techniques/T1578/](https://attack.mitre.org/techniques/T1578/) -- MITRE ATT&CK T1578: Modify Cloud Compute Infrastructure
- [https://docs.aws.amazon.com/step-functions/latest/apireference/API_UpdateStateMachine.html](https://docs.aws.amazon.com/step-functions/latest/apireference/API_UpdateStateMachine.html) -- AWS API reference for UpdateStateMachine
- [https://docs.aws.amazon.com/step-functions/latest/dg/concepts-amazon-states-language.html](https://docs.aws.amazon.com/step-functions/latest/dg/concepts-amazon-states-language.html) -- Amazon States Language reference
