# EC2 Image Builder Pipeline to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Pass privileged instance profile to EC2 Image Builder infrastructure configuration and trigger a build whose component shell commands execute with admin credentials from IMDS to grant the starting user administrative access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_imagebuilder_001_iam_passrole_imagebuilder_createcomponent_imagebuilder_createimagerecipe_imagebuilder_createinfrastructureconfiguration_imagebuilder_createimage`
* **Schema Version:** 4.6.1
* **Pathfinding.cloud ID:** imagebuilder-001
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1578 - Modify Cloud Compute Infrastructure

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-imagebuilder-001-to-admin-starting-user` IAM user to the `pl-prod-imagebuilder-001-to-admin-admin-role` administrative role by creating an EC2 Image Builder pipeline with a malicious component whose shell commands execute on a build instance running the admin instance profile, using IMDS credentials to attach `AdministratorAccess` to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-imagebuilder-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-imagebuilder-001-to-admin-admin-role`

### Starting Permissions

**Required** (`pl-prod-imagebuilder-001-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-imagebuilder-001-to-admin-admin-role` -- allows passing the admin role's instance profile to the Image Builder infrastructure configuration (`requestParameters.instanceProfileName` in `imagebuilder:CreateInfrastructureConfiguration`)
- `imagebuilder:CreateComponent` on `*` -- allows creating a component with arbitrary shell commands that will execute on the build instance
- `imagebuilder:CreateImageRecipe` on `*` -- allows creating an image recipe that references the malicious component
- `imagebuilder:CreateInfrastructureConfiguration` on `*` -- allows creating an infrastructure configuration that specifies the admin instance profile
- `imagebuilder:CreateImage` on `*` -- allows triggering a build that launches an EC2 instance with the admin instance profile
- `imagebuilder:GetComponent` on `*` -- AWS-enforced dependent action required by `CreateImageRecipe`
- `imagebuilder:GetImage` on `*` -- AWS-enforced dependent action required by `CreateImageRecipe`
- `imagebuilder:GetImageRecipe` on `*` -- AWS-enforced dependent action required by `CreateImage`
- `imagebuilder:GetInfrastructureConfiguration` on `*` -- AWS-enforced dependent action required by `CreateImage`
- `imagebuilder:TagResource` on `*` -- AWS-enforced dependent action required by all `Create*` calls
- `ec2:DescribeImages` on `*` -- AWS-enforced dependent action required by `CreateImageRecipe`

**Helpful** (`pl-prod-imagebuilder-001-to-admin-starting-user`):
- `imagebuilder:ListImages` -- list existing image builds to monitor build status
- `iam:ListAttachedUserPolicies` -- verify privilege escalation success by listing attached policies on the starting user

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
plabs enable imagebuilder-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `imagebuilder-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-imagebuilder-001-to-admin-starting-user` | Scenario-specific starting user with access keys, `iam:PassRole`, and EC2 Image Builder permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-imagebuilder-001-to-admin-admin-role` | Administrative role (trusts `ec2.amazonaws.com`) passed as the instance profile to the build instance |
| `arn:aws:iam::{account_id}:instance-profile/pl-prod-imagebuilder-001-to-admin-admin-profile` | Instance profile wrapping the admin role; passed via `--instance-profile-name` in `CreateInfrastructureConfiguration` |
| Security group `pl-prod-imagebuilder-001-to-admin-build-sg` | Egress-only security group for the Image Builder build instance (outbound required for SSM agent and IMDS) |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/imagebuilder-001-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create a malicious Image Builder component with shell commands that retrieve admin credentials from IMDS
4. Create an image recipe referencing the malicious component and a base Amazon Linux 2023 AMI
5. Create an infrastructure configuration passing the admin instance profile
6. Trigger an image build that launches an EC2 build instance with admin role credentials
7. Wait for the build phase to execute (10-30+ minutes) and the component to run
8. Verify successful privilege escalation by listing policies attached to the starting user
9. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions

**Note:** This scenario incurs EC2 costs while the build instance is running. The build process takes 10-30+ minutes. Clean up promptly after the demonstration.

#### Resources Created by Attack Script

- EC2 Image Builder component containing malicious shell commands
- EC2 Image Builder image recipe referencing the malicious component
- EC2 Image Builder infrastructure configuration specifying the admin instance profile
- EC2 Image Builder image build (launches a temporary EC2 build instance)
- `AdministratorAccess` managed policy attached to `pl-prod-imagebuilder-001-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo imagebuilder-001-iam-passrole+imagebuilder-createcomponent+imagebuilder-createimagerecipe+imagebuilder-createinfrastructureconfiguration+imagebuilder-createimage
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `imagebuilder-001-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup imagebuilder-001-iam-passrole+imagebuilder-createcomponent+imagebuilder-createimagerecipe+imagebuilder-createinfrastructureconfiguration+imagebuilder-createimage
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `imagebuilder-001-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable imagebuilder-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `imagebuilder-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user with `iam:PassRole` permission on a role that has `AdministratorAccess` or equivalent permissions
- IAM user with `imagebuilder:CreateComponent`, `imagebuilder:CreateInfrastructureConfiguration`, and `iam:PassRole` in combination, forming a privilege escalation path via EC2 Image Builder
- IAM role with `AdministratorAccess` attached that trusts `ec2.amazonaws.com` and can be passed to Image Builder infrastructure configurations by unprivileged users
- Privilege escalation path from IAM user to admin via EC2 Image Builder pipeline creation

#### Prevention Recommendations

- Restrict `iam:PassRole` using the `iam:PassedToService` condition key; for Image Builder, scope to `ec2.amazonaws.com` combined with a resource condition limiting which roles can be passed (e.g., deny passing roles with `AdministratorAccess`)
- Implement SCPs that deny `imagebuilder:CreateInfrastructureConfiguration` when the request includes an `instanceProfileName` referencing a privileged instance profile
- Use IAM Access Analyzer to automatically detect privilege escalation paths involving `iam:PassRole` and Image Builder component creation
- Grant `imagebuilder:CreateComponent` and `imagebuilder:CreateInfrastructureConfiguration` only to principals with a demonstrated need; treat these as high-risk permissions in any policy that also includes `iam:PassRole`
- Apply permission boundaries to instance profile roles used with Image Builder to cap the maximum privileges available to build instances
- Enable AWS Config rules to alert when Image Builder infrastructure configurations are created with instance profiles that carry administrative permissions

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `imagebuilder:CreateComponent` -- new Image Builder component created; inspect the component document for shell commands that call IAM APIs (`iam:AttachUserPolicy`, `iam:PutRolePolicy`) or make IMDS requests; high severity when the creator also holds `iam:PassRole` on a privileged role
- `imagebuilder:CreateInfrastructureConfiguration` -- new infrastructure configuration created; inspect `requestParameters.instanceProfileName` for a privileged instance profile name — this is the CloudTrail signal that `iam:PassRole` was exercised to hand an admin role to Image Builder
- `imagebuilder:CreateImage` -- image build triggered; correlate with a preceding `CreateComponent` and `CreateInfrastructureConfiguration` from the same principal to identify a malicious pipeline setup
- `iam:AttachUserPolicy` -- managed policy attached to an IAM user from within an EC2 instance context (via IMDS credentials); critical when the policy is `AdministratorAccess` and the caller is an EC2 instance role

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS EC2 Image Builder Documentation](https://docs.aws.amazon.com/imagebuilder/latest/userguide/what-is-image-builder.html) -- explains how components, recipes, infrastructure configurations, and image builds work
- [AWS IAM PassRole Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html) -- explains PassRole mechanics and how to restrict it with `iam:PassedToService`
- [Rhino Security Labs - AWS IAM Privilege Escalation Methods](https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation/) -- comprehensive overview of IAM privilege escalation techniques including PassRole patterns
- [pathfinding.cloud/paths/imagebuilder-001](https://pathfinding.cloud/paths/imagebuilder-001) -- documented attack path for this scenario
