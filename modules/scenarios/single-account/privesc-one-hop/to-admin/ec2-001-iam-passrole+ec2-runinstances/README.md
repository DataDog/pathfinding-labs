# One-Hop Privilege Escalation: iam:PassRole + ec2:RunInstances

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** EC2 instance launch with privileged role and user-data backdoor
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_ec2_001_iam_passrole_ec2_runinstances`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** ec2-001
* **MITRE Tactics:** TA0004 - Privilege Escalation
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1578 - Modify Cloud Compute Infrastructure

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-ec2-001-to-admin-starting-user` IAM user to the `pl-prod-ec2-001-to-admin-target-role` administrative role by passing the admin role to a newly launched EC2 instance and using a user-data backdoor script to attach the `AdministratorAccess` managed policy directly to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-ec2-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-ec2-001-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-ec2-001-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-ec2-001-to-admin-target-role` -- allows passing the admin role to an EC2 instance
- `ec2:RunInstances` on `*` -- allows launching EC2 instances with the passed role

**Helpful** (`pl-prod-ec2-001-to-admin-starting-user`):
- `iam:ListRoles` -- discover available privileged roles to identify passable targets
- `ec2:DescribeInstances` -- verify instance launch and monitor instance state
- `iam:ListInstanceProfiles` -- find instance profiles wrapping privileged roles

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_ec2_001_iam_passrole_ec2_runinstances
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
| `arn:aws:iam::{account_id}:user/pl-prod-ec2-001-to-admin-starting-user` | Starting user with PassRole and RunInstances permissions (with access keys) |
| `arn:aws:iam::{account_id}:role/pl-prod-ec2-001-to-admin-target-role` | Admin role that EC2 instance uses to attach policy (trusts ec2.amazonaws.com) |
| `arn:aws:iam::{account_id}:instance-profile/pl-prod-ec2-001-to-admin-instance-profile` | Instance profile wrapping the admin role |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve starting user credentials and region from Terraform outputs
2. Verify the starting user identity and confirm no pre-existing admin access
3. Look up the latest Amazon Linux 2023 AMI and the default VPC/subnet
4. Prepare a user-data script that calls `iam:AttachUserPolicy` to attach `AdministratorAccess` to the starting user
5. Launch an EC2 instance with the admin instance profile (`pl-prod-ec2-001-to-admin-instance-profile`) passing the user-data payload
6. Poll until `AdministratorAccess` is confirmed attached to the starting user (up to 5 minutes)
7. Verify administrator access by listing IAM users

#### Resources Created by Attack Script

- EC2 instance tagged `pl-ec2-001-to-admin-demo-instance` launched with the admin instance profile
- `AdministratorAccess` managed policy attached to `pl-prod-ec2-001-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo ec2-001-iam-passrole+ec2-runinstances
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ec2-001-iam-passrole+ec2-runinstances
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_ec2_001_iam_passrole_ec2_runinstances
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

- IAM user has `iam:PassRole` permission scoped to a role with administrative privileges (`pl-prod-ec2-001-to-admin-target-role`)
- IAM user has `ec2:RunInstances` combined with `iam:PassRole`, enabling privilege escalation via compute
- EC2 instance profile wraps a role with `AdministratorAccess` or equivalent admin permissions
- No IAM permission boundary on the starting user to cap the maximum privileges that can be attained

#### Prevention Recommendations

- Restrict `iam:PassRole` permissions with resource-based conditions to limit which roles can be passed and to which services
- Implement SCPs preventing EC2 instances from being launched with administrative IAM roles
- Monitor CloudTrail for `PassRole` API calls combined with `RunInstances` events targeting privileged roles
- Alert on `AttachUserPolicy` and `PutUserPolicy` API calls, especially when invoked from EC2 instances
- Regularly audit EC2 instances for excessive IAM permissions using IAM Access Analyzer
- Use resource tagging and condition keys to enforce separation of duties between role creation and role assignment
- Implement IAM permission boundaries on users to limit the maximum permissions that can be attached

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PassRole` -- role passed to an EC2 instance; high severity when the target role has administrative permissions
- `EC2: RunInstances` -- EC2 instance launched; correlate with `PassRole` events to detect privilege escalation via user-data
- `IAM: AttachUserPolicy` -- managed policy attached to a user; critical when the policy is `AdministratorAccess` and the call originates from an EC2 instance metadata role

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
