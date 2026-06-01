# Privilege Escalation via iam:PassRole + amplify:CreateApp + amplify:CreateBranch + amplify:StartJob

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Creating an Amplify app connected to a CodeCommit repository containing a malicious amplify.yml build spec that executes shell commands with an admin service role
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_amplify_001_iam_passrole_amplify_createapp_amplify_createbranch_amplify_startjob`
* **Schema Version:** 4.6.1
* **Pathfinding.cloud ID:** amplify-001
* **CTF Flag Location:** ssm-parameter
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1578 - Modify Cloud Compute Infrastructure

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-amplify-001-to-admin-starting-user` IAM user to the `pl-prod-amplify-001-to-admin-admin-role` administrative role by pushing a malicious `amplify.yml` build spec to a CodeCommit repository and creating an Amplify app with the admin role as its service role, causing the build container to execute IAM commands with administrative credentials.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-amplify-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-amplify-001-to-admin-admin-role`

### Starting Permissions

**Required** (`pl-prod-amplify-001-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-amplify-001-to-admin-admin-role` -- allows passing the admin role to the Amplify service as the app's service role; abuse is visible in `requestParameters.iamServiceRoleArn` of the `amplify:CreateApp` CloudTrail event
- `amplify:CreateApp` on `*` -- allows creating an Amplify application connected to the CodeCommit repository with the admin role as the service role
- `amplify:CreateBranch` on `*` -- allows creating a branch in the Amplify app pointing to the repository branch containing the malicious build spec
- `amplify:StartJob` on `*` -- allows triggering a build job that executes the malicious build spec with the admin role's credentials
- `codecommit:GitPush` on `arn:aws:codecommit:*:*:pl-prod-amplify-001-to-admin-repo` -- push the malicious `amplify.yml` build spec to the CodeCommit repository that the Amplify app will clone during builds
- `codecommit:GitPull` on `arn:aws:codecommit:*:*:pl-prod-amplify-001-to-admin-repo` -- required by the git clone operation when authenticating with the CodeCommit credential helper
- `codecommit:GetRepository` on `arn:aws:codecommit:*:*:pl-prod-amplify-001-to-admin-repo` -- `amplify:CreateApp` validates that the caller can read the repository before accepting the app config; without this the create call is rejected with `UnauthorizedException` before any service-role logic runs
- `codecommit:GetRepositoryTriggers` on `arn:aws:codecommit:*:*:pl-prod-amplify-001-to-admin-repo` -- Amplify reads existing repo triggers as the caller during `CreateApp` so it can add its build-notification trigger without clobbering existing ones
- `codecommit:PutRepositoryTriggers` on `arn:aws:codecommit:*:*:pl-prod-amplify-001-to-admin-repo` -- Amplify writes the CodeCommit→SNS trigger as the caller during `CreateApp` so future pushes auto-trigger builds
- `sns:CreateTopic` on `arn:aws:sns:*:*:amplify_codecommit_topic` -- Amplify auto-creates the shared `amplify_codecommit_topic` SNS topic (used to fan out CodeCommit push notifications to all Amplify apps in the account) as the caller during `CreateApp`
- `sns:Subscribe` on `arn:aws:sns:*:*:amplify_codecommit_topic` -- Amplify subscribes itself to the topic as the caller during `CreateApp`; without it the create succeeds partially but the subscription wiring fails

**Helpful** (`pl-prod-amplify-001-to-admin-starting-user`):
- `amplify:GetJob` -- monitor build job status and verify completion
- `amplify:ListApps` -- list existing Amplify applications
- `iam:ListAttachedUserPolicies` -- verify privilege escalation success by listing attached policies

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable amplify-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `amplify-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-amplify-001-to-admin-starting-user` | Scenario-specific starting user with access keys, PassRole, and Amplify permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-amplify-001-to-admin-admin-role` | Administrative role trusting `amplify.amazonaws.com`; passed as the Amplify app service role |
| `arn:aws:codecommit:{region}:{account_id}:pl-prod-amplify-001-to-admin-repo` | Empty CodeCommit repository; the attacker pushes the malicious `amplify.yml` here during the demo |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/amplify-001-to-admin` | CTF flag stored in SSM Parameter Store; retrievable by any admin-equivalent principal |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Clone the CodeCommit repository and push a malicious `amplify.yml` build spec
4. Create an Amplify app connected to the repository, passing the admin role via `iam:PassRole`
5. Create a branch and start a build job that executes with admin role credentials
6. Wait for the Amplify build to complete (typically 2--5 minutes)
7. Verify successful privilege escalation by confirming `AdministratorAccess` is attached to the starting user
8. Capture the CTF flag from SSM Parameter Store using the newly gained admin permissions

#### Resources Created by Attack Script

- Amplify application `pl-prod-amplify-001-to-admin-app` connected to the CodeCommit repository
- Amplify branch `main` in the above application
- Amplify build job triggered on the `main` branch
- `AdministratorAccess` managed policy attached to `pl-prod-amplify-001-to-admin-starting-user`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo amplify-001-iam-passrole+amplify-createapp+amplify-createbranch+amplify-startjob
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `amplify-001-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup amplify-001-iam-passrole+amplify-createapp+amplify-createbranch+amplify-startjob
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `amplify-001-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable amplify-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `amplify-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user with `iam:PassRole` permission on a role that has administrative permissions (`AdministratorAccess` or equivalent) and trusts `amplify.amazonaws.com`
- IAM user with `amplify:CreateApp` and `amplify:StartJob` permissions combined with `iam:PassRole` on an admin role, forming a privilege escalation path via CI/CD build execution
- IAM role with `AdministratorAccess` or broad IAM permissions that trusts `amplify.amazonaws.com` as a service principal, making it passable to Amplify applications
- Privilege escalation path from IAM user to admin via Amplify app creation and build job execution

#### Prevention Recommendations

- Restrict `iam:PassRole` using the `iam:PassedToService` condition key to limit which services a role can be passed to (e.g., `"iam:PassedToService": "amplify.amazonaws.com"`) -- combine this with a resource condition scoped to non-privileged Amplify service roles
- Scope `iam:PassRole` resource constraints to deny passing roles with `AdministratorAccess` or broad IAM permissions to any CI/CD service including Amplify
- Implement SCPs that deny `amplify:CreateApp` when the request includes an `iamServiceRoleArn` referencing a privileged role
- Use IAM Access Analyzer to automatically detect privilege escalation paths involving `iam:PassRole` and Amplify app creation
- Grant `amplify:CreateApp` and `amplify:StartJob` only to roles or users with a demonstrated need; treat these as high-risk permissions in any IAM policy
- Audit all roles with `amplify.amazonaws.com` in their trust policy to ensure they follow least privilege and do not carry administrative permissions

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `amplify:CreateApp` -- Amplify application created; inspect `requestParameters.iamServiceRoleArn` for a privileged role ARN, which is the CloudTrail signal for PassRole abuse via Amplify; high severity when the role has administrative permissions
- `amplify:CreateBranch` -- branch added to an Amplify app; correlate with a preceding `CreateApp` call from the same principal to identify the build-setup phase of this attack
- `amplify:StartJob` -- build job triggered; correlate with a preceding `CreateApp` referencing a privileged service role to identify the execution phase
- `iam:AttachUserPolicy` -- managed policy attached to an IAM user; critical when the policy is `AdministratorAccess` and the caller credentials belong to an Amplify service role

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS Amplify Service Roles Documentation](https://docs.aws.amazon.com/amplify/latest/userguide/how-to-service-role-amplify-console.html) -- explains how Amplify service roles work and why they must trust `amplify.amazonaws.com`
- [AWS IAM PassRole Documentation](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_passrole.html) -- explains PassRole mechanics and how to restrict it with `iam:PassedToService`
- [Rhino Security Labs - AWS IAM Privilege Escalation Methods](https://rhinosecuritylabs.com/aws/aws-privilege-escalation-methods-mitigation/) -- comprehensive overview of IAM privilege escalation techniques including PassRole patterns
- [pathfinding.cloud/paths/amplify-001](https://pathfinding.cloud/paths/amplify-001) -- documented attack path for this scenario
