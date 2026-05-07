# EC2 Launch Template Modification to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Modifying EC2 launch templates to change instance profiles and inject malicious user data for next instance launch
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** ec2-005
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1578 - Modify Cloud Compute Infrastructure

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-ec2-005-to-admin-starting-user` IAM user to the `pl-prod-ec2-005-to-admin-target-role` administrative role by creating a new EC2 launch template version with malicious user data referencing an existing administrative instance profile, setting it as the default, and triggering an instance launch to execute the payload.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-ec2-005-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-ec2-005-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-ec2-005-to-admin-starting-user`):
- `ec2:CreateLaunchTemplateVersion` on `*` -- create a new launch template version with malicious user data
- `ec2:ModifyLaunchTemplate` on `*` -- set the malicious version as the template default

**Helpful** (`pl-prod-ec2-005-to-admin-starting-user`):
- `iam:ListRoles` -- discover available privileged roles already configured in existing templates
- `ec2:DescribeLaunchTemplates` -- discover existing launch templates to target
- `ec2:DescribeLaunchTemplateVersions` -- view existing template configuration before modification
- `autoscaling:DescribeAutoScalingGroups` -- identify which ASGs use the target launch template
- `ec2:DescribeInstances` -- monitor instance launch and verify user data execution
- `sts:GetCallerIdentity` -- verify privilege escalation was successful

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable ec2-005-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ec2-005-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-ec2-005-to-admin-starting-user` | Scenario-specific starting user with access keys and template modification permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-ec2-005-to-admin-lowpriv-role` | Low-privilege role initially configured in the launch template |
| `arn:aws:iam::{account_id}:role/pl-prod-ec2-005-to-admin-target-role` | Administrative role that will be passed to the modified launch template |
| `arn:aws:ec2:{region}:{account_id}:launch-template/pl-prod-ec2-005-to-admin-template` | EC2 launch template that can be modified to include admin role |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/ec2-005-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create a new launch template version with admin role and malicious user data
4. Modify the template to use the new malicious version as default
5. Launch an EC2 instance to demonstrate the privilege escalation
6. Verify successful privilege escalation
7. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions


**Cost Warning:** This demo launches a t3.micro spot instance which will incur small charges (~$0.01-0.05/hour). The cleanup script terminates all instances to minimize costs.

#### Resources Created by Attack Script

- New EC2 launch template version with admin role and malicious user data
- EC2 instance launched using the modified launch template
- IAM policy attachment granting AdministratorAccess to the starting user

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo ec2-005-ec2-createlaunchtemplateversion+ec2-modifylaunchtemplate
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ec2-005-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ec2-005-ec2-createlaunchtemplateversion+ec2-modifylaunchtemplate
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ec2-005-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable ec2-005-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ec2-005-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- **Launch Template Write Access**: Principal can create new launch template versions or modify existing templates that contain privileged roles
- **Existing Admin Roles in Templates**: Launch templates that reference administrative IAM instance profiles
- **Privilege Escalation Path**: Template modification permissions on templates with privileged roles creates escalation path
- **Dangerous Permission Combination**: `ec2:CreateLaunchTemplateVersion` + `ec2:ModifyLaunchTemplate` on templates with admin roles
- **Suspicious User Data**: New template versions containing IAM modification commands in user data
- **Instance Profile Changes**: Launch template modifications that update user data while keeping the same privileged instance profile

#### Prevention Recommendations

- Restrict who can modify launch templates that contain privileged instance profiles using resource-based IAM policies
- Use Service Control Policies (SCPs) to prevent launch template modifications in production environments unless from approved automation roles
- Implement resource tagging and condition keys to restrict which launch templates can be modified: `"Condition": {"StringEquals": {"aws:ResourceTag/Environment": "dev"}}`
- Use IAM Access Analyzer to identify principals with template modification permissions on templates containing privileged roles
- Enable MFA requirements for sensitive operations like launch template modifications using `aws:MultiFactorAuthPresent` condition
- Implement approval workflows for launch template changes using AWS Service Catalog or custom automation
- Use launch template versioning strategically: pin Auto Scaling Groups to specific versions rather than using `$Latest` or `$Default`
- Monitor EC2 user data for suspicious IAM-related commands using AWS Config rules or custom Lambda functions
- Implement least privilege: avoid granting wildcard permissions on EC2 resources; scope to specific launch template ARNs
- Consider using EC2 Image Builder with locked-down instance profiles instead of relying on user data for configuration
- Regularly audit existing launch templates to identify those with privileged instance profiles and restrict modification permissions
- Separate permissions: don't grant template modification permissions to principals who don't need to manage infrastructure

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `ec2:CreateLaunchTemplateVersion` -- new launch template version created; high severity when the template contains a privileged instance profile or when user data contains IAM-modification commands
- `ec2:ModifyLaunchTemplate` -- launch template default version changed; critical when the new default version was recently created and references an admin role
- `ec2:RunInstances` -- EC2 instance launched using a launch template; monitor for instances launched with administrative instance profiles shortly after template modification

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
