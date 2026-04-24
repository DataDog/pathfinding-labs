# EC2 Spot Instance Request to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** EC2 Spot Instance launch with privileged role and user-data backdoor
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_ec2_004_iam_passrole_ec2_requestspotinstances`
* **Schema Version:** 4.6.0
* **CTF Flag Location:** ssm-parameter
* **Pathfinding.cloud ID:** ec2-004
* **MITRE Tactics:** TA0004 - Privilege Escalation
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1578 - Modify Cloud Compute Infrastructure

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-ec2-004-to-admin-starting-user` IAM user to the `pl-prod-ec2-004-to-admin-target-role` administrative role by requesting an EC2 Spot Instance with the admin instance profile attached and embedding a user-data script that attaches `AdministratorAccess` directly to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-ec2-004-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-ec2-004-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-ec2-004-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-ec2-004-to-admin-target-role` -- allows passing the admin role to an EC2 Spot Instance via instance profile
- `ec2:RequestSpotInstances` on `*` -- allows requesting a Spot Instance with the admin instance profile and a user-data backdoor

**Helpful** (`pl-prod-ec2-004-to-admin-starting-user`):
- `iam:ListRoles` -- discover available privileged roles
- `ec2:DescribeInstances` -- verify instance launch and get connection details
- `iam:ListInstanceProfiles` -- find instance profiles with privileged roles
- `ec2:DescribeSpotInstanceRequests` -- verify spot instance request and get instance details

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable ec2-004-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ec2-004-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-ec2-004-to-admin-starting-user` | Starting user with PassRole and RequestSpotInstances permissions (with access keys) |
| `arn:aws:iam::{account_id}:role/pl-prod-ec2-004-to-admin-target-role` | Admin role that EC2 Spot Instance uses to attach policy (trusts ec2.amazonaws.com) |
| `arn:aws:iam::{account_id}:instance-profile/pl-prod-ec2-004-to-admin-instance-profile` | Instance profile wrapping the admin role |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/ec2-004-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Verify successful privilege escalation
4. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions


#### Resources Created by Attack Script

- AdministratorAccess managed policy attached to the starting user
- EC2 Spot Instance launched with the admin instance profile (terminated by cleanup)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo ec2-004-iam-passrole+ec2-requestspotinstances
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ec2-004-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ec2-004-iam-passrole+ec2-requestspotinstances
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ec2-004-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable ec2-004-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ec2-004-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user has `iam:PassRole` permission targeting a role with administrative privileges
- IAM user has `ec2:RequestSpotInstances` permission combined with `iam:PassRole` — this combination enables privilege escalation via Spot Instance user-data
- Admin role (`pl-prod-ec2-004-to-admin-target-role`) is passable to EC2 Spot Instances and carries `iam:AttachUserPolicy` on all resources
- Instance profile wrapping an administrative role is accessible to the starting user via `iam:PassRole`

#### Prevention Recommendations

- Restrict `iam:PassRole` permissions with resource-based conditions to limit which roles can be passed and to which services
- Implement SCPs preventing EC2 Spot Instances from being launched with administrative IAM roles
- Apply the same restrictions to `ec2:RequestSpotInstances` as you would to `ec2:RunInstances` — they provide equivalent privilege escalation paths
- Alert on `IAM: AttachUserPolicy` and `IAM: PutUserPolicy` API calls, especially when invoked from EC2 instances
- Regularly audit EC2 instances (including Spot Instances) for excessive IAM permissions using IAM Access Analyzer
- Implement IAM permission boundaries on users to limit the maximum permissions that can be attached

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PassRole` — Starting user passes the admin role to the EC2 Spot Instance; critical when the target role has elevated permissions
- `EC2: RequestSpotInstances` — Spot Instance request launched with an administrative instance profile; high severity when combined with a preceding `PassRole` event
- `IAM: AttachUserPolicy` — AdministratorAccess managed policy attached to the starting user; critical when invoked from an EC2 instance metadata context

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
