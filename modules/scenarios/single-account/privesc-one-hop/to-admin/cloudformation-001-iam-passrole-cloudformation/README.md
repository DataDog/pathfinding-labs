# One-Hop Privilege Escalation: iam:PassRole + cloudformation:CreateStack

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** CloudFormation stack creation with privileged service role to create escalated IAM roles
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_cloudformation_001_iam_passrole_cloudformation`
* **Schema Version:** 3.0.0
* **Pathfinding.cloud ID:** cloudformation-001
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-cloudformation-001-to-admin-starting-user` IAM user to the `pl-prod-cloudformation-001-to-admin-escalated-role` administrative role by passing a privileged CloudFormation service role and creating a stack with a malicious template that provisions a new admin role you can assume.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-cloudformation-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-cloudformation-001-to-admin-escalated-role`

### Starting Permissions

**Required:**
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-cloudformation-001-to-admin-cfn-role` -- allows passing the admin service role to CloudFormation
- `cloudformation:CreateStack` on `*` -- allows creating a CloudFormation stack with the passed service role

**Helpful:**
- `cloudformation:DescribeStacks` -- monitor stack creation progress
- `iam:ListRoles` -- discover available privileged roles to pass
- `cloudformation:DeleteStack` -- clean up attack artifacts

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_cloudformation_001_iam_passrole_cloudformation
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
| `arn:aws:iam::{account_id}:user/pl-prod-cloudformation-001-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-cloudformation-001-to-admin-cfn-role` | Privileged role with AdministratorAccess, trusted by cloudformation.amazonaws.com |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create a CloudFormation stack with a malicious template
4. Pass the admin role to CloudFormation as the service role
5. Create a new escalated IAM role via CloudFormation
6. Assume the newly created role
7. Verify successful privilege escalation
8. Output standardized test results for automation

#### Resources Created by Attack Script

- A CloudFormation stack containing a malicious template
- `pl-prod-cloudformation-001-to-admin-escalated-role` — new IAM role with AdministratorAccess created by the stack

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo cloudformation-001-iam-passrole-cloudformation
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup cloudformation-001-iam-passrole-cloudformation
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_cloudformation_001_iam_passrole_cloudformation
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

- User with ability to pass privileged roles to CloudFormation (`iam:PassRole` on admin roles + `cloudformation:CreateStack`)
- Combined permissions creating privilege escalation path (PassRole + CreateStack on same principal)
- User with unrestricted CloudFormation stack creation capabilities
- Potential for privilege escalation via CloudFormation service abuse
- CloudFormation service role with IAM creation permissions
- `iam:PassRole` permission with wildcards or broad resource specifications targeting CloudFormation-trusted roles
- Roles trusted by cloudformation.amazonaws.com with `iam:CreateRole` or `iam:AttachRolePolicy` permissions

#### Prevention Recommendations

- **Restrict PassRole permissions**: Never grant `iam:PassRole` with wildcards. Use resource-based conditions to limit which roles can be passed and to which services (use `iam:PassedToService` condition key to restrict to specific services)
- **Limit CloudFormation service roles**: CloudFormation service roles should follow least privilege. Avoid granting them administrative IAM permissions
- **Separate CloudFormation permissions**: Avoid granting `cloudformation:CreateStack` and `cloudformation:UpdateStack` to principals that have `iam:PassRole` on privileged roles
- **Implement permission boundaries**: Use IAM permission boundaries to prevent roles from being passed to CloudFormation if they contain sensitive IAM creation permissions
- **Use SCPs**: Implement Service Control Policies to prevent passing of admin roles to infrastructure services (CloudFormation, Terraform Cloud, etc.)
- **Require stack policies**: Enforce CloudFormation stack policies that restrict IAM resource creation or require approval workflows
- **Template validation**: Implement automated CloudFormation template scanning to detect IAM resources with overly permissive policies
- **Use IAM Access Analyzer**: Leverage IAM Access Analyzer to identify privilege escalation paths involving CloudFormation
- **Require MFA**: Enforce MFA for sensitive operations like creating CloudFormation stacks with privileged service roles
- **Implement approval workflows**: Use AWS Service Catalog or custom approval gates for CloudFormation deployments with elevated permissions

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `IAM: PassRole` — Role passed to CloudFormation as a service role; critical when the passed role has elevated IAM permissions
- `CloudFormation: CreateStack` — New CloudFormation stack created; high severity when a privileged service role is specified
- `CloudFormation: UpdateStack` — Existing stack updated; monitor for IAM resource additions with privileged policies
- `STS: AssumeRole` — Role assumption following stack creation; suspicious when the assumed role was recently created via CloudFormation

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS Documentation - IAM PassRole](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html) -- AWS documentation on how iam:PassRole works and its security implications
- [AWS CloudFormation Service Role](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/using-iam-servicerole.html) -- AWS documentation on CloudFormation service roles
- [Rhino Security Labs - AWS IAM Privilege Escalation Methods](https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation/) -- comprehensive overview of IAM privilege escalation techniques
- [AWS Security Best Practices for CloudFormation](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/security-best-practices.html) -- AWS security guidance for CloudFormation deployments
