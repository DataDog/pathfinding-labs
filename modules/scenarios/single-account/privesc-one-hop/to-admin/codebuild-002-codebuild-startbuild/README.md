# CodeBuild Build Start to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Exploit existing CodeBuild project with privileged role using buildspec-override
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_codebuild_002_codebuild_startbuild`
* **Schema Version:** 4.6.0
* **Pathfinding.cloud ID:** codebuild-002
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1651 - Cloud Administration Command

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-codebuild-002-to-admin-starting-user` IAM user to the `pl-prod-codebuild-002-to-admin-project-role` administrative role by triggering a build on the existing `pl-prod-codebuild-002-to-admin-existing-project` CodeBuild project with a malicious `--buildspec-override` that attaches `AdministratorAccess` to the starting user.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-codebuild-002-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-codebuild-002-to-admin-project-role`

### Starting Permissions

**Required** (`pl-prod-codebuild-002-to-admin-starting-user`):
- `codebuild:StartBuild` on `*` -- trigger a build on the existing project with a buildspec override

**Helpful** (`pl-prod-codebuild-002-to-admin-starting-user`):
- `codebuild:ListProjects` -- discover existing CodeBuild projects with privileged roles
- `codebuild:BatchGetProjects` -- view project details including service role ARN
- `codebuild:BatchGetBuilds` -- monitor build execution status and verify success
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
plabs enable codebuild-002-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `codebuild-002-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-codebuild-002-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:codebuild:{region}:{account_id}:project/pl-prod-codebuild-002-to-admin-existing-project` | Pre-existing CodeBuild project with privileged role |
| `arn:aws:iam::{account_id}:role/pl-prod-codebuild-002-to-admin-project-role` | Privileged role with AdministratorAccess attached to CodeBuild project |
| `arn:aws:iam::{account_id}:policy/pl-prod-codebuild-002-to-admin-user-policy` | Policy granting codebuild:StartBuild, codebuild:ListProjects, codebuild:BatchGetProjects, and codebuild:BatchGetBuilds |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/codebuild-002-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

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

- `AdministratorAccess` managed policy attached to `pl-prod-codebuild-002-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo codebuild-002-codebuild-startbuild
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `codebuild-002-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup codebuild-002-codebuild-startbuild
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `codebuild-002-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable codebuild-002-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `codebuild-002-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- **Overly Permissive CodeBuild Access**: Users/roles with broad `codebuild:StartBuild` permissions on projects with privileged roles
- **Privileged CodeBuild Service Roles**: CodeBuild projects with administrative or sensitive IAM permissions
- **Buildspec Override Risk**: Projects that allow buildspec overrides combined with privileged service roles
- **Privilege Escalation Path**: Automated detection of the complete attack chain from user to admin via CodeBuild
- **Missing Project Constraints**: `codebuild:StartBuild` permissions without resource-based restrictions to specific projects
- **Dangerous Service Role Combinations**: CodeBuild roles with IAM modification permissions (AttachUserPolicy, PutUserPolicy, etc.)

#### Prevention Recommendations

- **Restrict codebuild:StartBuild**: Limit `codebuild:StartBuild` to specific projects using resource-based conditions: `"Resource": "arn:aws:codebuild:*:*:project/specific-safe-project"`
- **Least Privilege Service Roles**: Ensure CodeBuild service roles follow least privilege and cannot modify IAM permissions
- **Disable Buildspec Override**: Set project configuration to disallow buildspec overrides for projects with privileged roles
- **CloudTrail Monitoring**: Alert on `StartBuild` API calls with buildspec overrides on privileged projects, and monitor `AttachUserPolicy`/`PutUserPolicy` calls from CodeBuild service principals
- **Service Control Policies**: Implement SCPs to prevent CodeBuild service roles from modifying IAM policies: `Deny iam:AttachUserPolicy, iam:PutUserPolicy, iam:AttachRolePolicy, iam:PutRolePolicy when aws:PrincipalServiceName = codebuild.amazonaws.com`
- **IAM Access Analyzer**: Use AWS IAM Access Analyzer to identify privilege escalation paths involving CodeBuild projects
- **Project Review Process**: Regularly audit CodeBuild projects to identify those with privileged service roles and restrict access accordingly
- **Separation of Concerns**: Avoid attaching administrative roles to CodeBuild projects; use least-privilege roles specific to build requirements

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `CodeBuild: StartBuild` -- Build triggered with buildspec override; critical when targeting projects with privileged service roles
- `IAM: AttachUserPolicy` -- Managed policy attached to a user; high severity when AdministratorAccess is attached from a CodeBuild service principal

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
