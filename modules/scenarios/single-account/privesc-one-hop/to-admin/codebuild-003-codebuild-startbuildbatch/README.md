# CodeBuild Batch Build Start to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Technique:** Exploit existing CodeBuild project with buildspec-override to execute privileged commands
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_codebuild_003_codebuild_startbuildbatch`
* **Schema Version:** 4.0.0
* **Pathfinding.cloud ID:** codebuild-003
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1651 - Cloud Administration Command

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-codebuild-003-to-admin-starting-user` IAM user to the `pl-prod-codebuild-003-to-admin-target-role` administrative role by starting a CodeBuild batch build against an existing project using `--buildspec-override` to inject a malicious buildspec that executes with the project's privileged service role permissions.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-codebuild-003-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-codebuild-003-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-codebuild-003-to-admin-starting-user`):
- `codebuild:StartBuildBatch` on `*` -- trigger a batch build with a buildspec override against the existing target project

**Helpful** (`pl-prod-codebuild-003-to-admin-starting-user`):
- `codebuild:ListProjects` -- discover existing CodeBuild projects to exploit
- `codebuild:BatchGetProjects` -- view project details including the attached service role
- `codebuild:BatchGetBuildBatches` -- monitor build batch execution status
- `iam:ListUsers` -- verify admin access after escalation

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_codebuild_003_codebuild_startbuildbatch
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
| `arn:aws:iam::{account_id}:user/pl-prod-codebuild-003-to-admin-starting-user` | Scenario-specific starting user with access keys and codebuild:StartBuildBatch permission |
| `arn:aws:codebuild:{region}:{account_id}:project/pl-prod-codebuild-003-to-admin-target-project` | Existing CodeBuild project configured for batch builds |
| `arn:aws:iam::{account_id}:role/pl-prod-codebuild-003-to-admin-target-role` | Service role with iam:AttachUserPolicy permission, attached to CodeBuild project |
| `arn:aws:iam::{account_id}:policy/pl-prod-codebuild-003-to-admin-starting-user-policy` | Grants codebuild:StartBuildBatch, ListProjects, BatchGetProjects, and BatchGetBuildBatches permissions |
| `arn:aws:iam::{account_id}:policy/pl-prod-codebuild-003-to-admin-target-role-policy` | Grants iam:AttachUserPolicy permission to the service role |

### Guided Walkthrough

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Guided Walkthrough](guided_walkthrough.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Demonstrate buildspec-override injection
4. Verify successful privilege escalation to administrator
5. Output standardized test results for automation

#### Resources Created by Attack Script

- `AdministratorAccess` managed policy attached to `pl-prod-codebuild-003-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo codebuild-003-codebuild-startbuildbatch
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup codebuild-003-codebuild-startbuildbatch
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_codebuild_003_codebuild_startbuildbatch
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

- **Overly Permissive Service Roles**: CodeBuild service roles with IAM modification permissions (iam:AttachUserPolicy, iam:PutUserPolicy, iam:AttachRolePolicy)
- **Buildspec Override Risk**: Users or roles with codebuild:StartBuildBatch permission on projects with privileged service roles
- **Privilege Escalation Path**: Detection of the complete attack path from StartBuildBatch → privileged service role → IAM modification
- **IAM Policy Attachments from CodeBuild**: Unusual IAM policy modifications originating from CodeBuild service role sessions

#### Prevention Recommendations

- **Restrict StartBuildBatch Permissions**: Limit `codebuild:StartBuildBatch` to trusted administrators only, or use resource-based conditions to restrict which projects can be accessed
- **Enforce Buildspec Source**: Configure CodeBuild projects to require buildspecs from source control (GitHub, CodeCommit) and disable buildspec overrides
- **Apply Least Privilege to Service Roles**: CodeBuild service roles should never have IAM modification permissions unless absolutely required for legitimate CI/CD operations
- **Use SCPs**: Implement Service Control Policies to prevent CodeBuild service roles from modifying IAM policies or attaching policies to principals
- **IAM Access Analyzer**: Use IAM Access Analyzer to identify privilege escalation paths involving CodeBuild and service roles
- **Resource Tagging**: Tag CodeBuild projects with privilege levels and enforce tag-based conditional access policies

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `CodeBuild: StartBuildBatch` -- Batch build started; critical when `buildspec-override` parameter is present on projects with privileged service roles
- `IAM: AttachUserPolicy` -- Managed policy attached to an IAM user; high severity when originating from a CodeBuild service role session

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
