# AI-Assisted Cloud Intrusion: 8 Minutes to Admin

* **Category:** Attack Simulation
* **Path Type:** attack-simulation
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** ~$3/hr when GPU instance is running (p3.2xlarge); run cleanup_attack.sh immediately after demo
* **Source URL:** https://www.sysdig.com/blog/ai-assisted-cloud-intrusion-achieves-admin-access-in-8-minutes
* **Source Title:** AI-Assisted Cloud Intrusion Achieves Admin Access in 8 Minutes
* **Source Author:** Alessandro Brucato and Michael Clark (Sysdig Threat Research Team)
* **Source Date:** 2026-02-03
* **Technique:** Recreation of the Nov 2025 Sysdig TRT breach: IAM credentials embedded in a private S3 RAG bucket, Lambda code injection, and admin access achieved in under 8 minutes
* **Terraform Variable:** `enable_attack_simulation_sysdig_8_minutes_to_admin`
* **Schema Version:** 4.3.1
* **MITRE Tactics:** TA0001 - Initial Access, TA0007 - Discovery, TA0004 - Privilege Escalation, TA0003 - Persistence, TA0005 - Defense Evasion, TA0009 - Collection, TA0011 - Impact
* **MITRE Techniques:** T1552.001 - Credentials In Files, T1087.004 - Cloud Accounts, T1613 - Container and Resource Discovery, T1648 - Serverless Execution, T1098.001 - Additional Cloud Credentials, T1078.004 - Cloud Accounts, T1530 - Data from Cloud Storage Object, T1496 - Resource Hijacking

> **Cost Warning:** The demo script launches a `p3.2xlarge` GPU instance ($3.06/hr). Always run `plabs cleanup sysdig-8-minutes-to-admin` immediately after the demo completes. The instance is configured with a 2-hour auto-shutdown, but do not rely on this as your primary cost control.

## Objective

Your objective is to recreate the attack chain from [AI-Assisted Cloud Intrusion Achieves Admin Access in 8 Minutes](https://www.sysdig.com/blog/ai-assisted-cloud-intrusion-achieves-admin-access-in-8-minutes), where an attacker moved from the `pl-prod-8min-starting-user` IAM user to full administrative access by extracting embedded credentials from a private S3 RAG bucket, injecting malicious code into an over-privileged Lambda function, and using that function's execution role to create admin access keys — all in under eight minutes with AI assistance.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-8min-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:user/pl-prod-8min-frick`

### Starting Permissions

**Required** (`pl-prod-8min-starting-user`):
- `s3:ListBucket` on `arn:aws:s3:::pl-prod-8min-rag-data-{account_id}-{suffix}` -- enumerate the contents of the private RAG data bucket to find the embedded credentials file
- `s3:GetObject` on `arn:aws:s3:::pl-prod-8min-rag-data-{account_id}-{suffix}/*` -- download the RAG pipeline config file that contains embedded IAM credentials

**Required** (`pl-prod-8min-compromised-user`):
- `lambda:UpdateFunctionCode` on `arn:aws:lambda:*:*:function/pl-prod-8min-ec2-init` -- replace the Lambda function's code with a malicious payload that calls iam:CreateAccessKey
- `lambda:UpdateFunctionConfiguration` on `arn:aws:lambda:*:*:function/pl-prod-8min-ec2-init` -- modify function environment variables to pass target user names to the injected handler
- `lambda:InvokeFunction` on `arn:aws:lambda:*:*:function/pl-prod-8min-ec2-init` -- trigger the injected code to execute iam:CreateAccessKey using the function's privileged execution role

**Required** (`pl-prod-8min-ec2-init-role`):
- `iam:CreateAccessKey` on `arn:aws:iam::*:user/pl-prod-8min-frick` -- create new access keys for the admin user frick, granting full administrative access
- `iam:CreateAccessKey` on `arn:aws:iam::*:user/pl-prod-8min-admingh` -- the execution role also has this permission on admingh, which is a decoy (first injection attempt fails here)

**Helpful** (`pl-prod-8min-compromised-user`):
- `iam:ListUsers` -- discover admin user frick and other high-privilege accounts to target
- `iam:ListAccessKeys` -- enumerate existing access keys to understand credential posture
- `iam:ListAttachedUserPolicies` -- confirm frick has AdministratorAccess policy attached
- `iam:GetUser` -- get detailed info on targeted users
- `iam:ListRoles` -- discover assumable roles for lateral movement
- `iam:GetRole` -- inspect role trust policies to identify which roles can be assumed
- `lambda:ListFunctions` -- discover EC2-init Lambda function with the privileged execution role
- `lambda:GetFunction` -- view Lambda configuration to identify its execution role and permissions
- `s3:ListAllMyBuckets` -- enumerate all S3 buckets as data collection targets after escalation
- `bedrock:ListFoundationModels` -- enumerate available Bedrock models for unauthorized invocation
- `bedrock:GetModelInvocationLoggingConfiguration` -- verify Bedrock logging is disabled before invoking models
- `ssm:DescribeParameters` -- discover SSM parameters containing sensitive configuration
- `secretsmanager:ListSecrets` -- discover secrets available for data collection
- `sts:GetCallerIdentity` -- verify current identity at each stage of the attack chain
- `sts:AssumeRole` -- assume low-privilege roles (sysadmin, developer, account) for reconnaissance; post-escalation, frick assumes all 5 roles (adding netadmin, external) across 12 sessions for identity spreading

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable sysdig-8-minutes-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `sysdig-8-minutes-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-8min-starting-user` | Entry point user — has s3:ListBucket + s3:GetObject on the RAG bucket only |
| `arn:aws:s3:::pl-prod-8min-rag-data-{account_id}-{suffix}` | Private S3 bucket containing RAG pipeline data and an embedded credentials file |
| `arn:aws:iam::{account_id}:user/pl-prod-8min-compromised-user` | Second-stage user extracted from S3 — has Lambda R/W + IAM list + Bedrock list |
| `arn:aws:iam::{account_id}:role/pl-prod-8min-sysadmin-role` | Low-privilege assumable role (recon target, identity spreading) |
| `arn:aws:iam::{account_id}:role/pl-prod-8min-developer-role` | Low-privilege assumable role (recon target, identity spreading) |
| `arn:aws:iam::{account_id}:role/pl-prod-8min-account-role` | Low-privilege assumable role (recon target, identity spreading) |
| `arn:aws:iam::{account_id}:role/pl-prod-8min-netadmin-role` | Low-privilege assumable role (identity spreading only) |
| `arn:aws:iam::{account_id}:role/pl-prod-8min-external-role` | Low-privilege assumable role (identity spreading only) |
| `arn:aws:iam::{account_id}:user/pl-prod-8min-admingh` | Decoy user — no useful permissions (first injection attempt fails here) |
| `arn:aws:lambda:{region}:{account_id}:function/pl-prod-8min-ec2-init` | Over-privileged Lambda function — injection target |
| `arn:aws:iam::{account_id}:role/pl-prod-8min-ec2-init-role` | Lambda execution role with iam:CreateAccessKey on frick and admingh |
| `arn:aws:iam::{account_id}:user/pl-prod-8min-frick` | Admin target — has AdministratorAccess |
| `arn:aws:iam::{account_id}:user/pl-prod-8min-rocker` | Secondary persistence target — has BedrockFullAccess |
| `arn:aws:iam::{account_id}:user/pl-prod-8min-azureadmanager` | Identity spreading target — Azure AD integration service account |
| `arn:aws:iam::{account_id}:user/pl-prod-8min-deploy-svc` | Identity spreading target — deployment service account |
| `arn:aws:iam::{account_id}:user/pl-prod-8min-monitoring` | Identity spreading target — monitoring service account |
| `arn:aws:iam::{account_id}:user/pl-prod-8min-ci-runner` | Identity spreading target — CI/CD runner service account |
| `arn:aws:secretsmanager:{region}:{account_id}:secret:pl-prod-8min-db-credentials` | Data collection target — simulates database credentials |
| `arn:aws:ssm:{region}:{account_id}:parameter/pl/8min/api-key` | Data collection target — simulates API key in SSM |

### Modifications from Original Attack

The following changes were made to the original November 2025 attack to make it suitable for a self-hosted lab environment:

- **Credentials location changed from public to private S3**: In the original attack, IAM credentials were discovered in a publicly accessible S3 bucket. In this lab, the bucket is private and requires the `pl-prod-8min-starting-user` credentials as an explicit entry point.
- **GPU instance downsized**: The original attack launched a `p4d.24xlarge` instance for ML model training. This lab uses a `p3.2xlarge` (cheapest p-series at $3.06/hr) to keep costs manageable. The instance still launches and auto-terminates after 2 hours.
- **Cross-account movement simplified to failed attempts**: The original attack included failed cross-account role assumption attempts against hallucinated account IDs. In this lab those attempts are simulated — the demo script runs the `sts:AssumeRole` calls against placeholder account IDs and shows the `AccessDenied` errors as they appeared in the original.
- **Bedrock invocations reduced to 3 models**: The original attack invoked numerous Bedrock models. This lab demos three (Claude Haiku, Nova Lite, and DeepSeek R1) to demonstrate the pattern without incurring significant inference costs.
- **Lambda injection target renamed**: The original function name from the blog post has been replaced with `pl-prod-8min-ec2-init` to fit the Pathfinding Labs naming convention.

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The demo script follows the chronological order of the original attack, including reconnaissance, failed attempts, and AI-assisted decision making as described in the Sysdig TRT blog post. The script will:

The script will:

1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Verify successful privilege escalation

#### Resources Created by Attack Script

- Access keys for `pl-prod-8min-frick` (admin user) — created via Lambda injection
- 12 role assumption sessions across 5 roles (sysadmin, account, netadmin, developer, external)
- IAM user `backdoor-admin` with AdministratorAccess attached
- Access keys for `backdoor-admin`
- Access keys for `pl-prod-8min-rocker`
- Access keys for `pl-prod-8min-azureadmanager`, `pl-prod-8min-deploy-svc`, `pl-prod-8min-monitoring`, `pl-prod-8min-ci-runner`
- EC2 key pair `pl-8min-gpu-key` (used for GPU instance)
- EC2 security group `pl-8min-gpu-sg` with all inbound ports open to 0.0.0.0/0
- EC2 `p3.2xlarge` GPU instance with 2-hour auto-shutdown

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo sysdig-8-minutes-to-admin
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `sysdig-8-minutes-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

> **Run this immediately after the demo.** The GPU instance costs ~$3.06/hr and must be terminated manually if the auto-shutdown user data fails.

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup sysdig-8-minutes-to-admin
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `sysdig-8-minutes-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable sysdig-8-minutes-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `sysdig-8-minutes-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- **IAM credentials embedded in S3 object data**: The file `config/rag-pipeline-config.json` in the RAG bucket contains plaintext IAM access keys. CSPM tools that scan S3 object contents for credential patterns should flag this.
- **Lambda execution role with iam:CreateAccessKey on users**: `pl-prod-8min-ec2-init-role` has `iam:CreateAccessKey` on `pl-prod-8min-frick` (AdministratorAccess). A Lambda execution role with the ability to create credentials for admin users is a privilege escalation path — no compute role should hold `iam:CreateAccessKey` on privileged users.
- **Over-permissive Lambda execution role**: `pl-prod-8min-ec2-init-role` can create access keys for IAM users from a Lambda function context. IAM Analyzer's unused access findings should surface this if the function has never legitimately called `iam:CreateAccessKey`.
- **User with Lambda write access (UpdateFunctionCode + UpdateFunctionConfiguration)**: `pl-prod-8min-compromised-user` has write access to the Lambda function's code and configuration. Any principal that can update Lambda code on a function with a privileged execution role has an indirect privilege escalation path.
- **User (rocker) with unrestricted Bedrock access**: `pl-prod-8min-rocker` has `BedrockFullAccess`. Broad AI service access without logging or guardrails is a cost/data exfiltration risk.
- **Secrets Manager and SSM parameters without resource-based access controls**: The `pl-prod-8min-db-credentials` secret and `/pl/8min/api-key` parameter are accessible to the compromised-user after escalation. Sensitive parameters should require explicit resource-based policies and logging.
- **Multiple IAM roles with overly broad trust policies**: Five roles (`sysadmin`, `account`, `netadmin`, `developer`, `external`) trust the account root, allowing any principal with `sts:AssumeRole` to assume them. After gaining admin access, the attacker exploits this to spread across 12 role sessions — a technique that distributes CloudTrail activity across identities and complicates incident response.
- **Pre-existing service account users without access key rotation or monitoring**: Four service accounts (`azureadmanager`, `deploy-svc`, `monitoring`, `ci-runner`) exist with no access key rotation enforcement. The attacker creates access keys for all of them to establish persistence across multiple identities.

#### Prevention Recommendations

- **Scan S3 object contents for secrets**: Use Amazon Macie or a third-party DLP tool to detect plaintext credentials embedded in data files. Enable Macie on all buckets that handle pipeline configurations, model training data, or application configs.
- **Restrict iam:CreateAccessKey to identity-management roles only**: No Lambda execution role, EC2 instance profile, or application role should have `iam:CreateAccessKey` on users with elevated permissions. Use SCPs to enforce this at the organization level:
  ```json
  {
    "Effect": "Deny",
    "Action": "iam:CreateAccessKey",
    "Resource": "*",
    "Condition": {
      "ArnNotLike": {
        "aws:PrincipalArn": "arn:aws:iam::*:role/identity-management-*"
      }
    }
  }
  ```
- **Apply least privilege to Lambda execution roles**: Lambda functions should have only the permissions required for their stated purpose. An EC2 initialization function has no legitimate reason to create IAM access keys. Use IAM Access Analyzer to detect unused permissions in execution roles.
- **Restrict lambda:UpdateFunctionCode to deployment pipelines only**: Principals that are not CI/CD pipelines should not have `lambda:UpdateFunctionCode` or `lambda:UpdateFunctionConfiguration` on production functions. Gate these permissions behind MFA conditions or SCP deny rules for human principals.
- **Enable Bedrock model invocation logging**: Configure Bedrock to log all `InvokeModel` calls to CloudWatch Logs. Unauthorized model usage for IP theft or prompt injection is undetectable without invocation logs.
- **Use IAM roles for applications instead of long-lived IAM user credentials**: The original attack succeeded because a long-lived access key was embedded in a config file. Workloads running in AWS should use IAM roles with short-lived credentials (EC2 instance profiles, ECS task roles, Lambda execution roles) — never static IAM user keys.
- **Enforce access key rotation and maximum key age for service accounts**: The attacker created access keys for 5 pre-existing service accounts (`rocker`, `azureadmanager`, `deploy-svc`, `monitoring`, `ci-runner`) to establish persistence across multiple identities. SCPs or AWS Config rules that enforce maximum access key age and limit the number of active keys per user reduce the window for identity-spreading persistence.
- **Limit role trust policies to specific principals**: The 5 assumable roles in this account trust `:root`, allowing any principal with `sts:AssumeRole` to assume them. Restricting trust policies to the specific principals that need each role reduces the blast radius when a single admin account is compromised.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `S3: GetObject` -- object retrieval from data pipeline buckets; flag when the object key matches patterns like `*config*`, `*credentials*`, `*secret*`, or `*key*`
- `IAM: ListUsers` -- bulk IAM enumeration; when called by a non-human principal (Lambda execution role, EC2 instance profile) outside a deployment context, indicates reconnaissance
- `IAM: ListAttachedUserPolicies` -- policy enumeration on specific users; combined with ListUsers, indicates an attacker mapping privilege levels
- `Lambda: GetFunction20150331v2` -- function configuration retrieval; note when caller is not the owner account's deployment role and the function has a privileged execution role
- `Lambda: UpdateFunctionCode20150331v2` -- code replacement on a Lambda function; critical when followed within seconds by an invocation of the same function
- `Lambda: UpdateFunctionConfiguration20150331v2` -- configuration change; combined with UpdateFunctionCode, almost certainly indicates code injection
- `Lambda: InvokeFunction` -- function invocation; correlate with recent UpdateFunctionCode events to detect injection-then-invoke attack pattern
- `IAM: CreateAccessKey` -- new credentials created; critical when the caller is a Lambda execution role ARN (not a human user), indicating Lambda-mediated credential theft
- `IAM: CreateUser` -- new IAM user created; combined with AttachUserPolicy for AdministratorAccess within seconds, indicates backdoor account creation
- `IAM: AttachUserPolicy` -- managed policy attached to user; flag immediately when the policy ARN is `arn:aws:iam::aws:policy/AdministratorAccess`
- `STS: AssumeRole` -- role assumption; a burst of failures followed by successes (as seen in this attack) indicates automated role enumeration; post-escalation, a single principal assuming many roles with varied session names (explore, test, pwned, escalation) within a short window indicates identity spreading for persistence
- `IAM: CreateAccessKey` (bulk) -- multiple `CreateAccessKey` calls targeting different users from a single session within minutes; this pattern indicates an attacker establishing persistence across multiple pre-existing identities
- `Bedrock: InvokeModel` -- AI model invocation; flag when caller is not a known application role, or when called immediately after a period of IAM/Lambda enumeration
- `EC2: RunInstances` -- instance launch; flag `p`-series instance types (GPU), especially combined with a CreateKeyPair + CreateSecurityGroup burst in the same session
- `EC2: CreateSecurityGroup` + `EC2: AuthorizeSecurityGroupIngress` -- new security group with 0.0.0.0/0 inbound on port 22, created immediately before RunInstances, indicates attacker-controlled compute provisioning
- `SecretsManager: GetSecretValue` -- secret retrieval; flag when the caller is not the application that owns the secret
- `SSM: GetParameter` -- parameter retrieval; flag when the parameter path contains `key`, `secret`, `password`, or `token` and the caller is not an expected application role

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AI-Assisted Cloud Intrusion Achieves Admin Access in 8 Minutes](https://www.sysdig.com/blog/ai-assisted-cloud-intrusion-achieves-admin-access-in-8-minutes) -- Original Sysdig TRT blog post documenting the November 2025 attack; the primary source for this lab
- [MITRE ATT&CK: T1552.001 - Credentials In Files](https://attack.mitre.org/techniques/T1552/001/) -- Technique for discovering credentials stored in plaintext files
- [MITRE ATT&CK: T1648 - Serverless Execution](https://attack.mitre.org/techniques/T1648/) -- Abuse of serverless functions for code execution and privilege escalation
- [MITRE ATT&CK: T1098.001 - Additional Cloud Credentials](https://attack.mitre.org/techniques/T1098/001/) -- Creating additional access keys to maintain persistence
- [MITRE ATT&CK: T1496 - Resource Hijacking](https://attack.mitre.org/techniques/T1496/) -- Unauthorized use of compute resources for ML model training
- [Amazon Macie - Sensitive Data Discovery](https://docs.aws.amazon.com/macie/latest/user/what-is-macie.html) -- AWS service for detecting secrets and PII in S3 objects
