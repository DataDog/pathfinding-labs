# Privilege Escalation via cloudformation:UpdateStack

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Pathfinding.cloud ID:** cloudformation-002
* **Technique:** Modifying existing CloudFormation stack to create admin role using stack's elevated service role
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_cloudformation_002_cloudformation_updatestack`
* **Schema Version:** 1.0.0
* **Attack Path:** starting_user → (cloudformation:UpdateStack) → stack (with admin service role) → creates escalated admin role → (sts:AssumeRole) → admin access
* **Attack Principals:** `arn:aws:iam::{account_id}:user/pl-prod-cloudformation-002-to-admin-starting-user`; `arn:aws:iam::{account_id}:role/pl-prod-cloudformation-002-to-admin-stack-role`; `arn:aws:iam::{account_id}:role/pl-prod-cloudformation-002-to-admin-escalated-role`
* **Required Permissions:** `cloudformation:UpdateStack` on `arn:aws:cloudformation:*:*:stack/pl-prod-cloudformation-002-to-admin-stack/*`
* **Helpful Permissions:** `cloudformation:DescribeStacks` (View stack details and verify stack configuration); `cloudformation:GetTemplate` (Retrieve current stack template for modification); `iam:GetRole` (Verify the escalated role was created by the stack update); `sts:AssumeRole` (Assume the escalated role created by stack update)
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0003 - Persistence
* **MITRE Techniques:** T1098 - Account Manipulation, T1098.001 - Account Manipulation: Additional Cloud Credentials

## Attack Overview

This scenario demonstrates a sophisticated privilege escalation vulnerability where a user with `cloudformation:UpdateStack` permission can modify an existing CloudFormation stack that has an administrative service role attached. CloudFormation stacks execute with the permissions of their service role, which often requires elevated privileges to manage infrastructure. By updating the stack template to include new IAM resources, an attacker can leverage the stack's elevated permissions to create resources they couldn't create directly.

In production environments, CloudFormation stacks frequently have administrative or near-administrative service roles to allow them to provision and manage diverse AWS resources. DevOps teams may grant developers `cloudformation:UpdateStack` permissions for legitimate infrastructure updates, but this creates an indirect privilege escalation path. The attacker doesn't need direct IAM permissions to create roles or policies - they only need the ability to modify a stack that already has those permissions.

This attack is particularly insidious because it appears as legitimate infrastructure management activity. The CloudFormation stack update follows normal change management processes, making it difficult to distinguish from authorized infrastructure modifications. Organizations often overlook this privilege escalation vector because the UpdateStack permission seems less dangerous than direct IAM permissions, yet it provides equivalent access through the stack's service role.

### MITRE ATT&CK Mapping

- **Tactic**: TA0004 - Privilege Escalation, TA0003 - Persistence
- **Technique**: T1098 - Account Manipulation
- **Sub-technique**: T1098.001 - Account Manipulation: Additional Cloud Credentials

### Principals in the attack path

- `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-cloudformation-002-to-admin-starting-user` (Scenario-specific starting user with limited permissions)
- `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-cloudformation-002-to-admin-stack-role` (CloudFormation service role with administrative permissions)
- `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-cloudformation-002-to-admin-escalated-role` (Admin role created by stack update)

### Attack Path Diagram

```mermaid
graph LR
    A[pl-prod-cloudformation-002-to-admin-starting-user] -->|cloudformation:UpdateStack| B[CloudFormation Stack]
    B -->|Executes with| C[pl-prod-cloudformation-002-to-admin-stack-role]
    C -->|iam:CreateRole| D[pl-prod-cloudformation-002-to-admin-escalated-role]
    A -->|sts:AssumeRole| D
    D -->|Administrator Access| E[Effective Administrator]

    style A fill:#ff9999,stroke:#333,stroke-width:2px
    style B fill:#ffcc99,stroke:#333,stroke-width:2px
    style C fill:#ffcc99,stroke:#333,stroke-width:2px
    style D fill:#ffcc99,stroke:#333,stroke-width:2px
    style E fill:#99ff99,stroke:#333,stroke-width:2px
```

### Attack Steps

1. **Initial Access**: Start as `pl-prod-cloudformation-002-to-admin-starting-user` (credentials provided via Terraform outputs)
2. **Retrieve Existing Template**: Use `cloudformation:GetTemplate` to download the current stack template
3. **Modify Template**: Add a new IAM role resource to the template with AdministratorAccess policy and a trust relationship allowing the starting user to assume it
4. **Update Stack**: Use `cloudformation:UpdateStack` to apply the modified template, leveraging the stack's admin service role to create the new role
5. **Assume Escalated Role**: Use `sts:AssumeRole` to assume the newly created admin role
6. **Verification**: Verify administrator access by listing IAM users or performing other admin-level actions

### Scenario specific resources created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-cloudformation-002-to-admin-starting-user` | Scenario-specific starting user with access keys and cloudformation:UpdateStack permission |
| `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-cloudformation-002-to-admin-stack-role` | CloudFormation service role with AdministratorAccess used by the stack |
| `arn:aws:cloudformation:*:PROD_ACCOUNT:stack/pl-prod-cloudformation-002-to-admin-stack/*` | CloudFormation stack that can be updated by the starting user |
| `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-cloudformation-002-to-admin-escalated-role` | Admin role created during stack update (created by demo script) |

## Attack Lab

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_cloudformation_002_cloudformation_updatestack
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
3. Verify successful privilege escalation
4. Output standardized test results for automation

#### Resources created by attack script

- New IAM role (`pl-prod-cloudformation-002-to-admin-escalated-role`) with `AdministratorAccess` policy, created via CloudFormation stack update

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo cloudformation-002-cloudformation-updatestack
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

After demonstrating the attack, clean up the IAM role and stack modifications created during the demo.

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup cloudformation-002-cloudformation-updatestack
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_cloudformation_002_cloudformation_updatestack
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Detecting Misconfiguration (CSPM)

### What CSPM tools should detect

- IAM principal has `cloudformation:UpdateStack` permission on a stack with an administrative service role attached
- CloudFormation stack service role has `AdministratorAccess` or equivalent IAM write permissions, creating a privilege escalation path for any user who can update the stack
- Privilege escalation path detected: starting user can create IAM roles and policies indirectly via CloudFormation stack update

### Prevention recommendations

- Implement least privilege principles for CloudFormation service roles - avoid granting AdministratorAccess when more granular permissions suffice
- Restrict `cloudformation:UpdateStack` permissions to specific users/roles who require infrastructure management capabilities
- Use CloudFormation stack policies to prevent modifications to sensitive resources: `"Effect": "Deny", "Principal": "*", "Action": "Update:*", "Resource": "LogicalResourceId/SensitiveRole"`
- Implement Service Control Policies (SCPs) to restrict CloudFormation stack updates that create or modify IAM resources
- Monitor CloudTrail for `UpdateStack` API calls, especially those that modify stacks with elevated service roles
- Use resource-based conditions to limit UpdateStack permissions to specific stacks: `"Condition": {"StringEquals": {"cloudformation:StackId": "arn:aws:cloudformation:*:*:stack/approved-stack/*"}}`
- Enable CloudFormation drift detection and alerts to identify unauthorized stack modifications
- Require MFA for CloudFormation updates using condition keys like `aws:MultiFactorAuthPresent`
- Use IAM Access Analyzer to identify and remediate privilege escalation paths involving CloudFormation permissions
- Implement change approval workflows for CloudFormation stack updates that modify IAM resources
- Regularly audit CloudFormation service roles and reduce permissions to the minimum required for stack operations

## Detection Abuse (CloudSIEM)

### CloudTrail events to monitor

- `CloudFormation: UpdateStack` — CloudFormation stack update executed; high severity when the stack has an elevated service role and the update modifies IAM resources
- `IAM: CreateRole` — New IAM role created; critical when triggered by a CloudFormation stack execution with an administrative service role
- `IAM: AttachRolePolicy` — Managed policy attached to a role; critical when `AdministratorAccess` or other high-privilege policies are attached via CloudFormation
- `STS: AssumeRole` — Role assumption; investigate when the assumed role was recently created by a CloudFormation stack update

### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
