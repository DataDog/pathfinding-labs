# PassRole + EventBridge Scheduler: Universal Target Privilege Escalation

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Pass an admin role to an EventBridge Scheduler one-shot schedule targeting the universal target `arn:aws:scheduler:::aws-sdk:iam:attachUserPolicy`, causing the scheduler to call `iam:AttachUserPolicy` as the passed role and attach `AdministratorAccess` to the starting user
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_scheduler_001`
* **Schema Version:** 4.7.1
* **Pathfinding.cloud ID:** scheduler-001
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation
* **MITRE Techniques:** T1098 - Account Manipulation, T1648 - Serverless Execution
* **Required Preconditions:**
  - IAM Role: with AdministratorAccess and trust policy scoped to `scheduler.amazonaws.com`

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-scheduler-001-to-admin-starting-user` IAM user to the `pl-prod-scheduler-001-to-admin-scheduler-role` administrative role by creating a one-shot EventBridge Scheduler schedule with a universal target that invokes `iam:AttachUserPolicy` as the passed admin role, attaching `AdministratorAccess` to the starting user without any Lambda function, container, or EC2 instance.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-scheduler-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-scheduler-001-to-admin-scheduler-role`

### Starting Permissions

**Required** (`pl-prod-scheduler-001-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-scheduler-001-to-admin-scheduler-role` -- allows passing the admin role to the EventBridge Scheduler service as the schedule's execution role
- `scheduler:CreateSchedule` on `*` -- allows creating a new one-shot schedule with a universal target that invokes any AWS SDK action as the passed role

**Helpful** (`pl-prod-scheduler-001-to-admin-starting-user`):
- `iam:ListRoles` -- enumerate IAM roles to find the scheduler admin role to pass
- `iam:GetRole` -- inspect trust policies and attached policies on discovered roles
- `scheduler:ListSchedules` -- verify the schedule was created and check its status
- `scheduler:GetSchedule` -- inspect schedule configuration and confirm execution role

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable scheduler-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `scheduler-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-scheduler-001-to-admin-starting-user` | Scenario-specific starting user with access keys, `iam:PassRole`, and `scheduler:CreateSchedule` permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-scheduler-001-to-admin-scheduler-role` | Administrative role (trusts `scheduler.amazonaws.com`) passed as the execution role to the schedule |
| `arn:aws:iam::{account_id}:policy/pl-prod-scheduler-001-to-admin-starting-user-policy` | Inline policy granting the starting user PassRole and CreateSchedule permissions |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/scheduler-001-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Confirm the starting user cannot read the SSM flag (AccessDenied)
3. Compute a UTC timestamp 90 seconds in the future for the schedule's `at()` expression
4. Build the Target JSON referencing the universal target ARN `arn:aws:scheduler:::aws-sdk:iam:attachUserPolicy`, the scheduler role, and the input parameters (starting user name + `AdministratorAccess` policy ARN)
5. Call `scheduler:CreateSchedule` with `--action-after-completion DELETE` so the schedule self-deletes after firing
6. Wait 120 seconds for the schedule to fire and IAM policy propagation to complete
7. Read the SSM CTF flag as the starting user (now with `AdministratorAccess` attached) to confirm successful privilege escalation

#### Resources Created by Attack Script

- EventBridge Scheduler one-shot schedule (`pl-scheduler-001-escalation`) — auto-deleted after it fires via `--action-after-completion DELETE`
- `AdministratorAccess` managed policy attached to `pl-prod-scheduler-001-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo scheduler-001
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup scheduler-001
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable scheduler-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `scheduler-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user with `iam:PassRole` permission on a role that has administrative permissions and trusts `scheduler.amazonaws.com`
- IAM user with both `scheduler:CreateSchedule` and `iam:PassRole`, forming a privilege escalation path via EventBridge Scheduler universal targets
- IAM role with `AdministratorAccess` or equivalent permissions that trusts `scheduler.amazonaws.com` — admin roles should never trust the Scheduler service principal
- Privilege escalation path from IAM user to admin via EventBridge Scheduler universal target invocation

#### Prevention Recommendations

- Restrict `iam:PassRole` using the `iam:PassedToService` condition key to limit which services a role can be passed to (e.g., `"iam:PassedToService": "scheduler.amazonaws.com"`), and further constrain the specific role ARN using resource conditions
- Avoid granting `scheduler:CreateSchedule` to any principal that also holds `iam:PassRole` on a privileged role; the combination enables arbitrary AWS SDK invocation as that role
- Audit all IAM roles whose trust policies allow `scheduler.amazonaws.com` and enforce least privilege — roles trusted by Scheduler should be scoped to the minimum actions required for their legitimate scheduled jobs
- Implement SCPs that restrict `scheduler:CreateSchedule` to authorized automation accounts or require the schedule target ARN to match an approved service prefix (e.g., deny schedules targeting `arn:aws:scheduler:::aws-sdk:iam:*`)
- Use IAM Access Analyzer to detect privilege escalation paths where users can pass privileged roles to EventBridge Scheduler
- Enable AWS Config rules to alert when schedules are created with execution roles carrying administrative permissions

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `scheduler:CreateSchedule` -- new EventBridge schedule created; inspect `requestParameters.target.roleArn` — a privileged role ARN is the CloudTrail signal for PassRole abuse via Scheduler; critical when the target ARN contains `aws-sdk:iam:` indicating an IAM manipulation universal target
- `iam:AttachUserPolicy` -- managed policy attached to an IAM user; critical when the policy is `AdministratorAccess` and the caller is a Scheduler execution role assumed by the `scheduler.amazonaws.com` service principal; the `userAgent` field will show the EventBridge Scheduler service as the caller
- `iam:AttachRolePolicy` -- managed policy attached to an IAM role; monitor for the same Scheduler caller context pattern when the attacker chooses a role target instead of a user target

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS EventBridge Scheduler Universal Targets](https://docs.aws.amazon.com/scheduler/latest/UserGuide/managing-targets-universal.html) -- explains the `arn:aws:scheduler:::aws-sdk:{service}:{action}` target ARN format and how Scheduler invokes arbitrary AWS SDK APIs
- [AWS IAM PassRole Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html) -- explains PassRole mechanics and how to restrict it with `iam:PassedToService`
- [pathfinding.cloud/paths/scheduler-001](https://pathfinding.cloud/paths/scheduler-001) -- documented attack path for this scenario
