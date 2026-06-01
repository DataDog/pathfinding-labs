# GameLift Fleet to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** ~$1/mo (EC2 charges while GameLift fleet is active during demo; fleet is deleted by cleanup script)
* **Technique:** Upload a malicious game server build and create a GameLift fleet with an admin instance role using `SHARED_CREDENTIAL_FILE` to execute arbitrary code with the admin role's credentials
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_gamelift_001_iam_passrole_gamelift_createbuild_gamelift_createfleet`
* **Schema Version:** 4.6.1
* **Pathfinding.cloud ID:** gamelift-001
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1578 - Modify Cloud Compute Infrastructure

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-gamelift-001-to-admin-starting-user` IAM user to the `pl-prod-gamelift-001-to-admin-admin-role` administrative role by uploading a malicious game server build and creating a GameLift fleet that runs it under the admin role's credentials via the `SHARED_CREDENTIAL_FILE` credential provider.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-gamelift-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-gamelift-001-to-admin-admin-role`

### Starting Permissions

**Required** (`pl-prod-gamelift-001-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-gamelift-001-to-admin-admin-role` -- allows passing the admin role to GameLift as the fleet instance role (condition: `iam:PassedToService` = `gamelift.amazonaws.com`)
- `gamelift:CreateBuild` on `*` -- allows registering a new GameLift build entry and initiating the upload workflow
- `gamelift:RequestUploadCredentials` on `*` -- called internally by `aws gamelift upload-build` to obtain temporary S3 credentials for uploading the build artifact; required for the upload to succeed
- `gamelift:CreateFleet` on `*` -- allows creating a GameLift fleet that runs the malicious build under the admin instance role

**Helpful** (`pl-prod-gamelift-001-to-admin-starting-user`):
- `gamelift:DescribeBuild` -- monitor build status and confirm the build reaches `READY` state before creating the fleet
- `gamelift:DescribeFleetAttributes` -- monitor fleet status during provisioning and confirm the fleet enters `ACTIVE` or `ERROR` state after the exploit runs
- `gamelift:ListFleets` -- enumerate existing fleets in the account for reconnaissance
- `gamelift:DescribeInstances` -- list EC2 instances in the fleet during provisioning
- `gamelift:GetComputeAccess` -- obtain SSH access to fleet instances (useful for debugging)
- `iam:ListAttachedUserPolicies` -- verify privilege escalation success by confirming `AdministratorAccess` has been attached to the starting user

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew tap DataDog/pathfinding-labs https://github.com/DataDog/pathfinding-labs
   brew install DataDog/pathfinding-labs/plabs
   ```
   Or with Go 1.25+ installed:
   ```bash
   go install github.com/DataDog/pathfinding-labs/cmd/plabs@latest
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable gamelift-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gamelift-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-gamelift-001-to-admin-starting-user` | Scenario-specific starting user with access keys, `iam:PassRole`, and GameLift permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-gamelift-001-to-admin-admin-role` | Administrative role (trusts `gamelift.amazonaws.com`) passed as the fleet instance role |
| Inline policy `pl-prod-gamelift-001-to-admin-starting-user-policy` on `pl-prod-gamelift-001-to-admin-starting-user` | Grants `iam:PassRole`, `gamelift:CreateBuild`, `gamelift:RequestUploadCredentials`, `gamelift:CreateFleet`, and helpful recon permissions |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/gamelift-001-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Prepare a malicious game server build (a bash script as the server executable)
4. Upload the build to GameLift using `aws gamelift upload-build`
5. Create a GameLift fleet with the admin role as the instance role and `SHARED_CREDENTIAL_FILE` as the credential provider
6. Wait for the fleet to provision and the game server process to execute (5-15 minutes)
7. Verify successful privilege escalation by confirming `AdministratorAccess` is attached to the starting user
8. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions

**Note:** This scenario incurs EC2 charges while the GameLift fleet is active. Run the cleanup script promptly after the demonstration.

#### Resources Created by Attack Script

- GameLift build (`pl-prod-gamelift-001-to-admin-build`) containing the malicious game server script
- GameLift fleet (`pl-prod-gamelift-001-to-admin-fleet`) provisioning EC2 instances under the admin role
- `AdministratorAccess` managed policy attached to `pl-prod-gamelift-001-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo gamelift-001-iam-passrole+gamelift-createbuild+gamelift-createfleet
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gamelift-001-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup gamelift-001-iam-passrole+gamelift-createbuild+gamelift-createfleet
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gamelift-001-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable gamelift-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `gamelift-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user with `iam:PassRole` permission on a role that has administrative permissions (`AdministratorAccess` or equivalent) combined with `gamelift:CreateBuild` and `gamelift:CreateFleet`, forming a privilege escalation path
- IAM role with `AdministratorAccess` that trusts `gamelift.amazonaws.com` and can be passed to GameLift fleets as an instance role
- Privilege escalation path from IAM user to admin via GameLift fleet code execution

#### Prevention Recommendations

- Restrict `iam:PassRole` using the `iam:PassedToService` condition key to limit which services a role can be passed to (e.g., `"iam:PassedToService": "gamelift.amazonaws.com"`), then further restrict the resource ARN to non-privileged roles only
- Scope `iam:PassRole` resource constraints so that administrative roles (those with `AdministratorAccess` or broad IAM permissions) cannot be passed to any compute service
- Implement SCPs that deny `gamelift:CreateFleet` when the request includes an `instanceRoleArn` referencing a privileged role
- Use IAM Access Analyzer to automatically detect privilege escalation paths involving `iam:PassRole` and GameLift fleet creation
- Audit all IAM roles whose trust policy includes `gamelift.amazonaws.com` as a principal; ensure none carry administrative permissions
- Grant `gamelift:CreateBuild` and `gamelift:CreateFleet` only to roles with a demonstrated need; treat these as high-risk permissions when combined with `iam:PassRole`

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `gamelift:CreateBuild` -- new GameLift build registered; precursor event establishing the upload target before fleet creation
- `gamelift:CreateFleet` -- GameLift fleet created; inspect `requestParameters.instanceRoleArn` — a privileged role ARN here is the CloudTrail signal for PassRole abuse via GameLift; high severity when the role has administrative permissions
- `iam:AttachUserPolicy` -- managed policy attached to an IAM user from within a GameLift fleet instance; critical when the policy is `AdministratorAccess` and the caller identity is the fleet instance role

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS GameLift Instance Role Documentation](https://docs.aws.amazon.com/gamelift/latest/developerguide/gamelift-sdk-server-resources.html) -- explains how `instanceRoleArn` and `SHARED_CREDENTIAL_FILE` make role credentials available to game server processes
- [AWS IAM PassRole Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html) -- explains PassRole mechanics and how to restrict it with `iam:PassedToService`
- [Rhino Security Labs - AWS IAM Privilege Escalation Methods](https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation/) -- comprehensive overview of IAM privilege escalation techniques including PassRole patterns
- [pathfinding.cloud/paths/gamelift-001](https://pathfinding.cloud/paths/gamelift-001) -- documented attack path for this scenario
