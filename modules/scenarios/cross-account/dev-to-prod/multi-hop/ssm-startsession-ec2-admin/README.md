# Dev to Prod via SSM StartSession to EC2 with Admin Role

* **Category:** Privilege Escalation
* **Path Type:** cross-account
* **Target:** to-admin
* **Environments:** dev, prod
* **Cost Estimate:** $8/mo
* **Cost Estimate When Demo Executed:** $8/mo
* **Technique:** Cross-account privesc: dev user assumes a prod pivot role, exploits ssm:StartSession to access an EC2 instance with an admin instance profile, then retrieves admin credentials via IMDS
* **Terraform Variable:** `enable_cross_account_dev_to_prod_multi_hop_ssm_startsession_ec2_admin`
* **Schema Version:** 4.7.1
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0008 - Lateral Movement
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1021.007 - Remote Services: Cloud Services, T1552.005 - Unsecured Credentials: Cloud Instance Metadata API
* **CTF Flag Location:** ssm-parameter
* **Required Preconditions:**
  - aws_instance: EC2 instance running in the prod account with SSM agent active and an admin IAM instance profile attached

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-dev-ssm-ec2-starting-user` IAM user in the dev account to the `pl-prod-ssm-ec2-admin-role` administrative role in the prod account by assuming a cross-account pivot role, issuing SSM commands to an EC2 instance with an admin instance profile, and extracting credentials from the Instance Metadata Service (IMDS).

- **Start:** `arn:aws:iam::{dev_account_id}:user/pl-dev-ssm-ec2-starting-user`
- **Destination resource:** `arn:aws:ssm:{region}:{prod_account_id}:parameter/pathfinding-labs/flags/ssm-startsession-ec2-admin-to-admin`

### Starting Permissions

**Required** (`pl-dev-ssm-ec2-starting-user`):
- `sts:AssumeRole` on `arn:aws:iam::{prod_account_id}:role/pl-prod-ssm-ec2-pivot-role` -- cross-account assumption of the prod pivot role

**Required** (`pl-prod-ssm-ec2-pivot-role`):
- `ssm:StartSession` on `arn:aws:ec2:*:{prod_account_id}:instance/*` -- open an interactive session on EC2 instances managed by SSM
- `ssm:SendCommand` on `arn:aws:ec2:*:{prod_account_id}:instance/*` -- execute shell commands on EC2 instances via SSM
- `ssm:SendCommand` on `arn:aws:ssm:*::document/AWS-RunShellScript` -- use the built-in shell execution document
- `ssm:GetCommandInvocation` on `*` -- poll command execution results

**Helpful** (`pl-dev-ssm-ec2-starting-user`):
- `iam:ListRoles` -- discover assumable roles in the prod account

**Helpful** (`pl-prod-ssm-ec2-pivot-role`):
- `ec2:DescribeInstances` -- enumerate instances and find the target instance ID
- `ssm:DescribeInstanceInformation` -- find SSM-managed instances eligible for a session

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable ssm-startsession-ec2-admin-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ssm-startsession-ec2-admin-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
|-----|---------|
| `arn:aws:iam::{prod_account_id}:role/pl-prod-ssm-ec2-pivot-role` | Prod pivot role trusted by the dev starting user; holds SSM permissions targeting the EC2 instance |
| `arn:aws:iam::{prod_account_id}:role/pl-prod-ssm-ec2-admin-role` | Admin IAM role attached as an instance profile to the EC2 instance |
| `arn:aws:ec2:{region}:{prod_account_id}:instance/{instance_id}` | EC2 instance with SSM agent running and admin instance profile attached |
| `arn:aws:ssm:{region}:{prod_account_id}:parameter/pathfinding-labs/flags/ssm-startsession-ec2-admin-to-admin` | CTF flag stored in SSM Parameter Store; readable with admin permissions |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:

1. **Verification**: Confirm the starting dev user identity and permissions
2. **Cross-Account Role Assumption**: Assume `pl-prod-ssm-ec2-pivot-role` in the prod account using the dev user credentials
3. **Instance Discovery**: Enumerate EC2 instances in prod and identify `pl-prod-ssm-ec2-instance`
4. **SSM Availability Check**: Confirm the instance is reachable via SSM using `ssm:DescribeInstanceInformation`
5. **Remote Command Execution**: Send a shell script to the instance via `ssm:SendCommand` using the `AWS-RunShellScript` document
6. **IMDS Credential Retrieval**: The shell script uses IMDSv2 to fetch the instance role name and temporary credentials for `pl-prod-ssm-ec2-admin-role`
7. **Flag Capture**: The shell script reads the CTF flag from SSM Parameter Store using the instance role's admin credentials and returns the output
8. **Result Polling**: Poll `ssm:GetCommandInvocation` until the command completes and print the flag

#### Resources Created by Attack Script

- No persistent AWS resources are created; the script sends a transient SSM command that exits cleanly after retrieving the flag

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo ssm-startsession-ec2-admin
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ssm-startsession-ec2-admin
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable ssm-startsession-ec2-admin-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ssm-startsession-ec2-admin-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- `pl-prod-ssm-ec2-pivot-role` holds `ssm:SendCommand` and `ssm:StartSession` on EC2 instances without any tag-based or resource-level conditions, allowing it to target any SSM-managed instance in the prod account
- `pl-prod-ssm-ec2-admin-role` is attached as an instance profile to `pl-prod-ssm-ec2-instance` and carries `AdministratorAccess` — an EC2 instance profile with wildcard admin permissions is a high-severity misconfiguration
- The cross-account trust on `pl-prod-ssm-ec2-pivot-role` permits assumption by the dev account without an MFA condition or `aws:PrincipalOrgID` constraint, allowing any dev account credential that can reach this role to escalate into prod
- Graph-based IAM analysis should surface the full chain: dev user → cross-account assume → pivot role → SSM to EC2 → IMDS credential extraction → admin role

#### Prevention Recommendations

- Restrict `ssm:SendCommand` and `ssm:StartSession` with `ssm:resourceTag` or `aws:ResourceTag` conditions so each role can only target instances with specific tags (e.g., `Environment: dev`)
- Apply least-privilege to EC2 instance profiles — never attach `AdministratorAccess` or wildcard policies to compute resources; scope instance roles to the minimum permissions the application actually needs
- Require MFA or `aws:MultiFactorAuthPresent` conditions on cross-account `sts:AssumeRole` calls for prod account roles trusted by dev or operations accounts
- Use Service Control Policies (SCPs) at the AWS Organization level to restrict cross-account role assumption to specific known principal ARNs or organization units
- Enable SSM Session Manager logging to CloudWatch Logs and S3 so all session activity is captured and alertable
- Use IAM Access Analyzer to surface cross-account trust relationships and generate fine-grained least-privilege policies for instance profile roles

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `sts:AssumeRole` -- cross-account role assumption from the dev account into `pl-prod-ssm-ec2-pivot-role`; alert when a dev account principal assumes a prod account role with SSM permissions
- `ssm:StartSession` -- interactive session initiated on an EC2 instance; high severity when the calling principal is a cross-account assumed-role session
- `ssm:SendCommand` -- remote shell command sent to an EC2 instance; inspect `requestParameters.documentName` for `AWS-RunShellScript` and correlate with the preceding cross-account `AssumeRole` event
- `ssm:GetCommandInvocation` -- attacker polling for command results; correlates with the preceding `SendCommand` event to indicate active exploitation rather than automated tooling
- `sts:AssumeRole` -- the instance's EC2 role (`pl-prod-ssm-ec2-admin-role`) being used from an unusual source; IMDS-issued credentials are sourced from the instance's IP — flag if those credentials are subsequently used from a different IP or principal

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [T1021.007 - Remote Services: Cloud Services](https://attack.mitre.org/techniques/T1021/007/) -- MITRE ATT&CK technique page for cloud remote services abuse
- [T1552.005 - Unsecured Credentials: Cloud Instance Metadata API](https://attack.mitre.org/techniques/T1552/005/) -- MITRE ATT&CK technique page for IMDS credential harvesting
- [AWS SSM Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html) -- AWS documentation for SSM Session Manager
- [IMDSv2 Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-instance-metadata-service.html) -- AWS documentation on instance metadata and IMDSv2
