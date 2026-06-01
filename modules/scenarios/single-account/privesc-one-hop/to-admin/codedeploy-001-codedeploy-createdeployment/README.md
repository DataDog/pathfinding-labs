# AWS CodeDeploy CreateDeployment to Admin via Existing Admin EC2 Instance Profile

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** ~$0.01/hr (t3.micro EC2 instance)
* **Cost Estimate When Demo Executed:** ~$0.01/hr (no additional resources created)
* **Technique:** Principal with codedeploy:CreateDeployment can escalate privileges by deploying a malicious revision whose lifecycle hooks execute as the target EC2 instance's admin instance profile
* **Pathfinding.cloud ID:** codedeploy-001
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_codedeploy_001_codedeploy_createdeployment`
* **Schema Version:** 4.7.1
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0002 - Execution
* **MITRE Techniques:** T1072 - Software Deployment Tools, T1078.004 - Valid Accounts: Cloud Accounts
* **CTF Flag Location:** ssm-parameter
* **Required Preconditions:**
  - aws_instance: A pre-existing EC2 instance with a privileged instance profile and CodeDeploy agent installed
  - aws_codedeploy_deployment_group: A CodeDeploy application and deployment group targeting the privileged EC2 instance

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-codedeploy-001-to-admin-starting-user` IAM user to the `pl-prod-codedeploy-001-to-admin-ec2-role` administrative role by staging a malicious CodeDeploy revision in an attacker-controlled S3 bucket and triggering its lifecycle hook scripts to execute as the EC2 instance's admin instance profile.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-codedeploy-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/codedeploy-001-to-admin`

### Starting Permissions

**Required** (`pl-prod-codedeploy-001-to-admin-starting-user`):
- `codedeploy:CreateDeployment` on `*` -- trigger a deployment to the target deployment group
- `codedeploy:GetDeploymentConfig` on `*` -- read deployment configuration required by CreateDeployment
- `codedeploy:RegisterApplicationRevision` on `*` -- register the malicious revision before deploying
- `codedeploy:GetApplicationRevision` on `*` -- verify the revision is registered correctly

**Helpful** (`pl-prod-codedeploy-001-to-admin-starting-user`):
- `codedeploy:GetDeployment` -- monitor deployment status to know when the lifecycle hook has executed
- `codedeploy:ListDeployments` -- enumerate recent deployments for the target deployment group
- `codedeploy:GetDeploymentGroup` -- discover the target deployment group configuration including its target EC2 instances
- `codedeploy:GetApplication` -- read the CodeDeploy application to confirm its name and associated deployment groups
- `codedeploy:ListDeploymentInstances` -- list which EC2 instances are targeted by a deployment
- `codedeploy:GetDeploymentInstance` -- retrieve per-instance deployment lifecycle event status

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable codedeploy-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `codedeploy-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
|-----|---------|
| `arn:aws:iam::{account_id}:user/pl-prod-codedeploy-001-to-admin-starting-user` | Starting IAM user with CodeDeploy permissions |
| `arn:aws:iam::{account_id}:role/pl-prod-codedeploy-001-to-admin-ec2-role` | EC2 instance role with AdministratorAccess |
| `arn:aws:ec2:{region}:{account_id}:instance/{instance_id}` | EC2 instance running the CodeDeploy agent with the admin instance profile |
| `arn:aws:codedeploy:{region}:{account_id}:application:pl-prod-codedeploy-001-to-admin-app` | CodeDeploy application targeting the EC2 instance |
| `arn:aws:codedeploy:{region}:{account_id}:deploymentgroup:pl-prod-codedeploy-001-to-admin-app/pl-prod-codedeploy-001-to-admin-dg` | CodeDeploy deployment group |
| `arn:aws:iam::{account_id}:role/pl-prod-codedeploy-001-to-admin-deploy-svc-role` | IAM role used by the CodeDeploy service to coordinate deployments |
| `arn:aws:s3:::pl-attacker-codedeploy-001-revision-{account_id}` | Attacker-controlled S3 bucket staging the malicious revision ZIP |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/codedeploy-001-to-admin` | CTF flag (SSM Parameter Store) |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:

1. Retrieve starting user credentials from Terraform outputs
2. Confirm the starting user cannot read the SSM flag (prove-can't step)
3. Wait for the CodeDeploy agent to finish starting on the EC2 instance (~5 minutes after `plabs apply` completes)
4. Build a revision JSON payload pointing to the malicious revision ZIP in the attacker-controlled S3 bucket
5. Call `codedeploy:CreateDeployment` targeting `pl-prod-codedeploy-001-to-admin-dg` with the attacker revision
6. Poll deployment status until the deployment succeeds or fails
7. Wait 15 seconds for IAM managed policy attachment propagation
8. Confirm the starting user now has AdministratorAccess and can read the SSM flag (prove-can step) — the lifecycle hook has executed `iam:AttachUserPolicy` attaching `AdministratorAccess` to the starting user

#### Resources Created by Attack Script

- The AWS managed policy `AdministratorAccess` (`arn:aws:iam::aws:policy/AdministratorAccess`) attached to `pl-prod-codedeploy-001-to-admin-starting-user` by the CodeDeploy lifecycle hook executing as the admin EC2 instance profile

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo codedeploy-001-codedeploy-createdeployment
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup codedeploy-001-codedeploy-createdeployment
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable codedeploy-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `codedeploy-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- IAM user `pl-prod-codedeploy-001-to-admin-starting-user` has `codedeploy:CreateDeployment` scoped to `*` — any deployment group in the account is a valid target, including those backed by admin-role EC2 instances
- EC2 instance with `AdministratorAccess` instance profile (`pl-prod-codedeploy-001-to-admin-ec2-role`) is enrolled in a CodeDeploy deployment group (`pl-prod-codedeploy-001-to-admin-dg`)
- The combination of a principal with `codedeploy:CreateDeployment` and at least one CodeDeploy deployment group whose target instances hold a privileged instance profile constitutes a complete privilege escalation path — no `iam:PassRole` needed
- CodeDeploy deployment role (`pl-prod-codedeploy-001-to-admin-deploy-svc-role`) can be leveraged by any principal who can trigger a deployment, not just those with `iam:PassRole` on it
- Attacker-controlled S3 bucket (`pl-attacker-codedeploy-001-revision-{account_id}`) is whitelisted as a revision source by the bucket policy — CSPM should flag deployment groups that accept revisions from buckets in external AWS accounts

#### Prevention Recommendations

- Scope `codedeploy:CreateDeployment` to specific CodeDeploy application ARNs using the `codedeploy:Application` condition key rather than allowing `*` — limit who can deploy to any group
- Use IAM condition keys (e.g., `codedeploy:DeploymentGroupArn`) to restrict `codedeploy:CreateDeployment` to a named set of trusted deployment groups
- Avoid attaching `AdministratorAccess` or other overly broad managed policies to EC2 instance profiles used as CodeDeploy targets; follow least-privilege and scope to only the permissions the application actually requires
- Require that CodeDeploy revisions originate from specific trusted S3 buckets in the same AWS account; reject revisions from external accounts using S3 bucket policies and CodeDeploy deployment group configuration
- Enable CodeDeploy deployment notifications and alert on deployments whose revision source is an S3 bucket in an account other than the deploying account
- Periodically enumerate all CodeDeploy deployment groups and cross-reference target instance profiles against the set of privileged IAM roles; treat any overlap as a high-severity finding

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `codedeploy:CreateDeployment` -- a new deployment was triggered; high severity when the revision source is an S3 bucket in an external AWS account or an unexpected bucket name
- `codedeploy:RegisterApplicationRevision` -- a revision was registered before deployment; inspect `requestParameters.revision.s3Location.bucket` for external accounts
- `iam:AttachUserPolicy` -- a managed policy was attached to a user; critical when the source is EC2 instance profile credentials (AssumedRole session for the instance profile role) rather than a human or CI/CD actor — especially when the attached policy is `AdministratorAccess`
- `sts:AssumeRole` -- not directly observable for instance profile credential use, but EC2 instance profile credential calls will show as `arn:aws:sts::{account_id}:assumed-role/pl-prod-codedeploy-001-to-admin-ec2-role/i-*` in CloudTrail — correlate unexpected `iam:AttachUserPolicy` calls from this role ARN pattern
- `ssm:GetParameter` -- flag parameter read; correlate with the deployment timeline to identify exploitation

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [pathfinding.cloud/paths/codedeploy-001](https://pathfinding.cloud/paths/codedeploy-001) -- Pathfinding Labs path entry for CodeDeploy CreateDeployment privilege escalation
- [AWS CodeDeploy AppSpec reference](https://docs.aws.amazon.com/codedeploy/latest/userguide/reference-appspec-file.html) -- AppSpec file format and lifecycle hook documentation
- [MITRE ATT&CK T1072 - Software Deployment Tools](https://attack.mitre.org/techniques/T1072/) -- MITRE technique covering abuse of software deployment infrastructure
- [MITRE ATT&CK T1078.004 - Valid Accounts: Cloud Accounts](https://attack.mitre.org/techniques/T1078/004/) -- MITRE technique covering use of cloud service credentials
