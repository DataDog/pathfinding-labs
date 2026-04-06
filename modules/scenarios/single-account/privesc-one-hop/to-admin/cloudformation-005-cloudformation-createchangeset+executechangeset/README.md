# CloudFormation Change Set Execution to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Principal with cloudformation:CreateChangeSet and ExecuteChangeSet can inherit admin permissions from existing CloudFormation stack's service role
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_cloudformation_005_cloudformation_createchangeset_executechangeset`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** cloudformation-005
* **MITRE Tactics:** TA0004 - Privilege Escalation
* **MITRE Techniques:** T1098.003 - Account Manipulation: Additional Cloud Roles

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-cloudformation-005-to-admin-starting-user` IAM user to the `pl-prod-cloudformation-005-to-admin-escalated-role` administrative role by creating and executing a malicious CloudFormation change set against a stack with an administrative service role, causing CloudFormation to create a new IAM role with full administrator access on your behalf.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-cloudformation-005-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-cloudformation-005-to-admin-escalated-role`

### Starting Permissions

**Required** (`pl-prod-cloudformation-005-to-admin-starting-user`):
- `cloudformation:CreateChangeSet` on `*` -- create a change set against the target stack
- `cloudformation:ExecuteChangeSet` on `*` -- execute the change set, triggering the stack's service role to create resources

**Helpful** (`pl-prod-cloudformation-005-to-admin-starting-user`):
- `cloudformation:DescribeChangeSet` -- view change set details and verify creation
- `cloudformation:DescribeStacks` -- discover existing CloudFormation stacks to target
- `cloudformation:DescribeStackResource` -- view stack resources and service role information

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_cloudformation_005_cloudformation_createchangeset_executechangeset
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
| `arn:aws:iam::{account_id}:user/pl-prod-cloudformation-005-to-admin-starting-user` | Scenario-specific starting user with access keys and CloudFormation ChangeSet permissions |
| `arn:aws:cloudformation:{region}:{account_id}:stack/pl-prod-cloudformation-005-to-admin-target-stack/*` | Existing CloudFormation stack with privileged service role (target for exploitation) |
| `arn:aws:iam::{account_id}:role/pl-prod-cloudformation-005-to-admin-stack-role` | CloudFormation service role with AdministratorAccess attached to target stack |
| `arn:aws:iam::{account_id}:role/pl-prod-cloudformation-005-to-admin-escalated-role` | Admin role created by demo attack script via change set execution |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Demonstrate creating a change set that adds a new admin IAM role
4. Execute the change set using the stack's privileged service role
5. Verify successful privilege escalation by assuming the new role
6. Output standardized test results for automation

#### Resources Created by Attack Script

- New IAM role (`pl-prod-cloudformation-005-to-admin-escalated-role`) with AdministratorAccess, created via change set execution using the stack's privileged service role
- CloudFormation change set (`pl-prod-cloudformation-005-escalation-changeset`) on the target stack
- Temporary malicious template file at `/tmp/malicious-changeset-template.json`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo cloudformation-005-cloudformation-createchangeset+executechangeset
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup cloudformation-005-cloudformation-createchangeset+executechangeset
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_cloudformation_005_cloudformation_createchangeset_executechangeset
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

- IAM principal has both `cloudformation:CreateChangeSet` and `cloudformation:ExecuteChangeSet` permissions, enabling privilege escalation via stacks with privileged service roles
- CloudFormation stack service role has `AdministratorAccess` or other broad administrative permissions attached
- CloudFormation stack service role permissions are not scoped to the minimum required for the stack's resources
- IAM principal with change set permissions has no resource-level restriction (wildcard `*` on both actions)

#### Prevention Recommendations

- Implement least privilege for CloudFormation permissions - avoid granting `cloudformation:CreateChangeSet` and `cloudformation:ExecuteChangeSet` together unless absolutely necessary
- Use resource-based conditions to restrict change set operations to specific stacks: `"Condition": {"StringEquals": {"aws:ResourceTag/Environment": "dev"}}`
- Review CloudFormation stack service roles and minimize permissions - avoid using AdministratorAccess for stack service roles
- Implement Service Control Policies (SCPs) to prevent change set execution on stacks with privileged service roles from non-admin principals
- Enable MFA requirements for sensitive CloudFormation operations using condition keys like `aws:MultiFactorAuthPresent`
- Use IAM Access Analyzer to identify CloudFormation stacks with overly permissive service roles
- Consider using stack policies to prevent modifications to critical infrastructure resources
- Review and audit the AWS managed policy `SecretsManagerReadWrite` - consider creating a custom policy without CloudFormation permissions if change set operations aren't required
- Establish approval workflows for change set execution on production stacks using AWS Service Catalog or custom automation

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `CloudFormation: CreateChangeSet` — Change set created against an existing stack; high severity when the stack has a privileged service role attached
- `CloudFormation: ExecuteChangeSet` — Change set executed; critical when the stack's service role has administrative permissions, as all resource changes are performed under that role
- `IAM: CreateRole` — New IAM role created; investigate when the caller is CloudFormation and the assumed role has administrative permissions
- `STS: AssumeRole` — Role assumption following change set execution; watch for the newly created escalated role being assumed shortly after stack update completes

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
