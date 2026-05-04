# CodeBuild Project Creation + Batch Build to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Pass a privileged role to CodeBuild and execute buildspec to grant self admin access
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_codebuild_004_iam_passrole_codebuild_createproject_codebuild_startbuildbatch`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** codebuild-004
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1651 - Cloud Administration Command

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-codebuild-004-to-admin-starting-user` IAM user to the `pl-prod-codebuild-004-to-admin-target-role` administrative role by creating a CodeBuild project with a privileged service role and executing a malicious build batch buildspec that attaches AdministratorAccess to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-codebuild-004-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-codebuild-004-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-codebuild-004-to-admin-starting-user`):
- `codebuild:CreateProject` on `*` -- create a new CodeBuild project with the privileged service role
- `codebuild:StartBuildBatch` on `*` -- trigger the build batch that executes the malicious buildspec
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-codebuild-004-to-admin-target-role` -- pass the privileged target role to the CodeBuild project

**Helpful** (`pl-prod-codebuild-004-to-admin-starting-user`):
- `iam:ListRoles` -- discover available privileged roles to pass to CodeBuild
- `codebuild:ListProjects` -- list existing CodeBuild projects
- `codebuild:BatchGetBuildBatches` -- monitor build batch execution status

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable codebuild-004-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `codebuild-004-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-codebuild-004-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-codebuild-004-to-admin-target-role` | Privileged role with iam:AttachUserPolicy permission, trusted by CodeBuild service |
| `arn:aws:iam::{account_id}:policy/pl-prod-codebuild-004-to-admin-user-policy` | Policy granting codebuild:CreateProject, codebuild:StartBuildBatch, and iam:PassRole to starting user |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/codebuild-004-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Retrieve starting user credentials from Terraform outputs
2. Verify the starting user identity and confirm absence of admin permissions
3. Create a CodeBuild project configured with the privileged `pl-prod-codebuild-004-to-admin-target-role` as its service role, embedding a malicious inline buildspec
4. Start a build batch execution that runs the buildspec with the target role's permissions
5. Wait for the build batch to complete and for IAM policy propagation
6. Verify administrator access has been granted to the starting user
7. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions

#### Resources Created by Attack Script

- A CodeBuild project (`pl-privesc-codebuild-batch-demo`) configured with the privileged target role
- An attached `AdministratorAccess` managed policy on the starting user (after successful escalation)

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo codebuild-004-iam-passrole+codebuild-createproject+codebuild-startbuildbatch
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `codebuild-004-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup codebuild-004-iam-passrole+codebuild-createproject+codebuild-startbuildbatch
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `codebuild-004-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable codebuild-004-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `codebuild-004-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- **Dangerous Permission Combination**: User/role with both `codebuild:CreateProject` and `iam:PassRole` permissions
- **Overly Permissive Service Roles**: CodeBuild service roles with powerful IAM permissions (`iam:AttachUserPolicy`, `iam:PutUserPolicy`, etc.)
- **Privilege Escalation Path**: Automated detection of the complete attack chain from user to admin via CodeBuild
- **Missing Constraints**: `iam:PassRole` permission without resource-based restrictions
- **Service Trust Relationships**: Roles that can be assumed by CodeBuild without additional conditions

#### Prevention Recommendations

- **Restrict iam:PassRole**: Limit `iam:PassRole` to specific, least-privilege roles using resource-based conditions: `"Resource": "arn:aws:iam::*:role/specific-safe-role"`
- **Separate Permissions**: Avoid granting `codebuild:CreateProject` and `iam:PassRole` to the same principal
- **Service Role Controls**: Ensure CodeBuild service roles follow least privilege and cannot modify IAM permissions
- **Service Control Policies**: Implement SCPs to prevent CodeBuild service roles from modifying IAM policies: `Deny iam:AttachUserPolicy, iam:PutUserPolicy, iam:AttachRolePolicy, iam:PutRolePolicy when aws:PrincipalServiceName = codebuild.amazonaws.com`
- **IAM Access Analyzer**: Use AWS IAM Access Analyzer to identify privilege escalation paths involving CodeBuild
- **Require Approval for Service Roles**: Implement approval workflows for creating service roles that can be passed to compute services
- **Condition Keys**: Use IAM condition keys to restrict CodeBuild project creation to specific source repositories or environments

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `CodeBuild: CreateProject` -- New CodeBuild project created; alert when combined with a privileged service role and an inline buildspec
- `CodeBuild: StartBuildBatch` -- Build batch execution triggered; monitor for custom buildspec overrides that execute IAM-modifying commands
- `IAM: AttachUserPolicy` -- Managed policy attached to a user; critical when `AdministratorAccess` is the policy and the caller is a CodeBuild service principal (`codebuild.amazonaws.com`)
- `STS: AssumeRole` -- CodeBuild assumes the passed service role at build start; alert when the assumed role has IAM administrative permissions

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
