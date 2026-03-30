# Privilege Escalation via Launch Template Modification

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Pathfinding.cloud ID:** ec2-005
* **Technique:** Modifying EC2 launch templates to change instance profiles and inject malicious user data for next instance launch
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate`
* **Schema Version:** 1.0.0
* **Attack Path:** starting_user → (CreateLaunchTemplateVersion with existing admin role + malicious user data) → (ModifyLaunchTemplate default version) → Next instance launch uses admin role → User data adds AdministratorAccess to starting user → admin access
* **Attack Principals:** `arn:aws:iam::{account_id}:user/pl-prod-ec2-005-to-admin-starting-user`; `arn:aws:iam::{account_id}:role/pl-prod-ec2-005-to-admin-lowpriv-role`; `arn:aws:iam::{account_id}:role/pl-prod-ec2-005-to-admin-target-role`
* **Required Permissions:** `ec2:CreateLaunchTemplateVersion` on `*`; `ec2:ModifyLaunchTemplate` on `*`
* **Helpful Permissions:** `iam:ListRoles` (Discover available privileged roles already configured in existing templates); `ec2:DescribeLaunchTemplates` (Discover existing launch templates to target); `ec2:DescribeLaunchTemplateVersions` (View existing template configuration before modification); `autoscaling:DescribeAutoScalingGroups` (Identify which ASGs use the target launch template); `ec2:DescribeInstances` (Monitor instance launch and verify user data execution); `sts:GetCallerIdentity` (Verify privilege escalation was successful)
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1578 - Modify Cloud Compute Infrastructure

## Attack Overview

This scenario demonstrates a sophisticated privilege escalation technique where an attacker with permissions to modify EC2 launch templates can change an existing administrative role configuration and inject malicious user data that will be executed when the next EC2 instance is launched. The combination of `ec2:CreateLaunchTemplateVersion` and `ec2:ModifyLaunchTemplate` permissions creates a powerful attack path that allows an attacker to "pre-stage" privilege escalation that activates automatically.

EC2 launch templates are commonly used with Auto Scaling Groups (ASGs) to define instance configuration including AMI, instance type, security groups, and crucially - the IAM instance profile and user data script. When an attacker can create a new version of a launch template and set it as the default, they control what configuration will be used for all future instance launches. This is particularly dangerous in environments with auto-scaling policies or scheduled instance launches, where the malicious configuration may activate without any further attacker interaction.

The attack works by creating a new launch template version that references an existing administrative IAM role (already configured in the template) and user data containing a script that grants the attacker's starting user administrative permissions. Notably, this attack does NOT require `iam:PassRole` permissions because the attacker is simply referencing a role that already exists in a previous template version. When the next instance launches (either through manual action, auto-scaling, or scheduled tasks), the instance receives full administrative permissions via its instance profile, and the user data script immediately modifies IAM policies to grant the attacker persistent admin access. This is a one-hop privilege escalation because the attacker goes directly from limited permissions to admin access through the compromised instance's actions.

### MITRE ATT&CK Mapping

- **Tactic**: TA0004 - Privilege Escalation, TA0003 - Persistence
- **Technique**: T1098.001 - Account Manipulation: Additional Cloud Credentials
- **Technique**: T1578 - Modify Cloud Compute Infrastructure

### Principals in the attack path

- `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-ec2-005-to-admin-starting-user` (Scenario-specific starting user with template modification permissions)
- `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-ec2-005-to-admin-lowpriv-role` (Low-privilege role in original launch template)
- `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-ec2-005-to-admin-target-role` (Administrative role passed to modified launch template)

### Attack Path Diagram

```mermaid
graph LR
    A[pl-prod-ec2-005-to-admin-starting-user] -->|CreateLaunchTemplateVersion| B[New Template Version]
    B -->|Contains target-role + malicious user data| C[Modified Template]
    A -->|ModifyLaunchTemplate| C
    C -->|Next instance launch| D[EC2 Instance with Admin Role]
    D -->|User data executes| E[Grants admin to starting-user]
    E -->|Effective Administrator| F[Starting User with Admin Access]

    style A fill:#ff9999,stroke:#333,stroke-width:2px
    style B fill:#ffcc99,stroke:#333,stroke-width:2px
    style C fill:#ffcc99,stroke:#333,stroke-width:2px
    style D fill:#ffcc99,stroke:#333,stroke-width:2px
    style E fill:#ffcc99,stroke:#333,stroke-width:2px
    style F fill:#99ff99,stroke:#333,stroke-width:2px
```

### Attack Steps

1. **Initial Access**: Start as `pl-prod-ec2-005-to-admin-starting-user` (credentials provided via Terraform outputs)
2. **Enumerate Templates**: Use `ec2:DescribeLaunchTemplates` to discover existing launch templates
3. **Inspect Existing Templates**: Use `ec2:DescribeLaunchTemplateVersions` to identify templates that already have administrative roles configured
4. **Create Malicious Template Version**: Use `ec2:CreateLaunchTemplateVersion` with:
   - IAM instance profile referencing the existing admin role (NO PassRole required - just referencing existing configuration)
   - User data script that attaches AdministratorAccess policy to the starting user
5. **Set as Default**: Use `ec2:ModifyLaunchTemplate` to make the malicious version the default
6. **Trigger Instance Launch**: Launch a new EC2 instance using the modified template (or wait for auto-scaling/scheduled launch)
7. **Automated Escalation**: Instance launches with admin role and executes user data to grant admin to starting user
8. **Verification**: Verify administrator access by listing IAM users or performing other admin-level actions

### Scenario specific resources created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-ec2-005-to-admin-starting-user` | Scenario-specific starting user with access keys and template modification permissions |
| `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-ec2-005-to-admin-lowpriv-role` | Low-privilege role initially configured in the launch template |
| `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-ec2-005-to-admin-target-role` | Administrative role that will be passed to the modified launch template |
| `arn:aws:ec2:REGION:PROD_ACCOUNT:launch-template/pl-prod-ec2-005-to-admin-template` | EC2 launch template that can be modified to include admin role |

## Attack Lab

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `space` to enable it
4. Press `d` to deploy

### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create a new launch template version with admin role and malicious user data
4. Modify the template to use the new malicious version as default
5. Launch an EC2 instance to demonstrate the privilege escalation
6. Verify successful privilege escalation
7. Output standardized test results for automation

**Cost Warning:** This demo launches a t3.micro spot instance which will incur small charges (~$0.01-0.05/hour). The cleanup script terminates all instances to minimize costs.

#### Resources created by attack script

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
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ec2-005-ec2-createlaunchtemplateversion+ec2-modifylaunchtemplate
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Detecting Misconfiguration (CSPM)

### What CSPM tools should detect

A properly configured Cloud Security Posture Management (CSPM) tool should identify this vulnerability by detecting:

- **Launch Template Write Access**: Principal can create new launch template versions or modify existing templates that contain privileged roles
- **Existing Admin Roles in Templates**: Launch templates that reference administrative IAM instance profiles
- **Privilege Escalation Path**: Template modification permissions on templates with privileged roles creates escalation path
- **Dangerous Permission Combination**: `ec2:CreateLaunchTemplateVersion` + `ec2:ModifyLaunchTemplate` on templates with admin roles
- **Template Modification Events**: CloudTrail shows CreateLaunchTemplateVersion or ModifyLaunchTemplate API calls
- **Suspicious User Data**: New template versions containing IAM modification commands in user data
- **Instance Profile Changes**: Launch template modifications that update user data while keeping the same privileged instance profile

### Prevention recommendations

- Restrict who can modify launch templates that contain privileged instance profiles using resource-based IAM policies
- Use Service Control Policies (SCPs) to prevent launch template modifications in production environments unless from approved automation roles
- Implement resource tagging and condition keys to restrict which launch templates can be modified: `"Condition": {"StringEquals": {"aws:ResourceTag/Environment": "dev"}}`
- Monitor CloudTrail for `CreateLaunchTemplateVersion` and `ModifyLaunchTemplate` API calls, especially on templates with admin roles
- Use IAM Access Analyzer to identify principals with template modification permissions on templates containing privileged roles
- Enable MFA requirements for sensitive operations like launch template modifications using `aws:MultiFactorAuthPresent` condition
- Implement approval workflows for launch template changes using AWS Service Catalog or custom automation
- Use launch template versioning strategically: pin Auto Scaling Groups to specific versions rather than using `$Latest` or `$Default`
- Monitor EC2 user data for suspicious IAM-related commands using AWS Config rules or custom Lambda functions
- Implement least privilege: Avoid granting wildcard permissions on EC2 resources; scope to specific launch template ARNs
- Consider using EC2 Image Builder with locked-down instance profiles instead of relying on user data for configuration
- Regularly audit existing launch templates to identify those with privileged instance profiles and restrict modification permissions
- Separate permissions: Don't grant template modification permissions to principals who don't need to manage infrastructure

## Detection Abuse (CloudSIEM)

### CloudTrail events to monitor

- `EC2: CreateLaunchTemplateVersion` — New launch template version created; high severity when the template contains a privileged instance profile or when user data contains IAM-modification commands
- `EC2: ModifyLaunchTemplate` — Launch template default version changed; critical when the new default version was recently created and references an admin role
- `EC2: RunInstances` — EC2 instance launched using a launch template; monitor for instances launched with administrative instance profiles shortly after template modification

### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
