# AcmeBot

* **Category:** CTF
* **Path Type:** ctf
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $1/mo
* **Cost Estimate When Demo Executed:** $1/mo
* **Technique:** Acme Corp has deployed an AI-powered customer assistant at a public Lambda endpoint. Escalate to administrative access and retrieve the flag.
* **Difficulty:** beginner
* **Flag Location:** ssm-parameter at /pathfinding-labs/flags/ctf-001-to-admin
* **Terraform Variable:** `enable_ctf_ai_chatbot_to_admin`
* **Schema Version:** 4.6.0
* **MITRE Tactics:** TA0001 - Initial Access, TA0006 - Credential Access, TA0004 - Privilege Escalation
* **MITRE Techniques:** T1190 - Exploit Public-Facing Application, T1552.005 - Unsecured Credentials: Cloud Instance Metadata API, T1059 - Command and Scripting Interpreter

## Objective

Acme Corp has deployed an AI-powered customer assistant at a public Lambda Function URL. Your goal is to escalate to administrative access and retrieve the flag.

- **Start:** `https://{function_url_id}.lambda-url.{region}.on.aws/` (public, no auth)
- **Goal:** Retrieve the flag from SSM Parameter Store at `/pathfinding-labs/flags/ctf-001-to-admin`

### Starting Permissions

**Required** (`anonymous (public URL)`):
- `lambda:InvokeFunctionUrl` on `arn:aws:lambda:*:*:function/pl-prod-ctf-001-acmebot` -- invoke the chatbot via its public Function URL without any AWS credentials

**Helpful** (`pl-prod-ctf-001-starting-user`):
- `lambda:ListFunctions` -- enumerate Lambda functions to discover the chatbot
- `lambda:GetFunctionUrlConfig` -- retrieve the public Function URL for the chatbot

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable ctf-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ctf-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
|-----|---------|
| `arn:aws:lambda:{region}:{account_id}:function/pl-prod-ctf-001-acmebot` | Vulnerable AcmeBot chatbot Lambda with public Function URL |
| `arn:aws:iam::{account_id}:role/pl-prod-ctf-001-chatbot-role` | Lambda execution role with AdministratorAccess |
| `arn:aws:iam::{account_id}:user/pl-prod-ctf-001-starting-user` | Optional starting user for CLI-based enumeration |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/ctf-001-to-admin` | CTF flag (String, requires admin credentials to read) |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable ctf-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ctf-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- Lambda function (`pl-prod-ctf-001-acmebot`) has a public Function URL with `AuthType: NONE` and an execution role with `AdministratorAccess` -- toxic combination of public access and administrative permissions
- IAM role (`pl-prod-ctf-001-chatbot-role`) has `AdministratorAccess` attached and is used as a Lambda execution role for a publicly accessible function
- Lambda execution role permissions are not scoped to the minimum required for the function's declared purpose

#### Prevention Recommendations

- Never attach `AdministratorAccess` or broad managed policies to Lambda execution roles; apply least-privilege scoped to the specific AWS actions the function legitimately needs
- Restrict Lambda `run_command`-style tools to a strict allowlist of safe, pre-approved commands rather than allowing arbitrary shell execution
- Treat all LLM user input as untrusted; validate and sandbox tool invocations at the application layer regardless of system prompt instructions
- Use Lambda Function URL auth type `AWS_IAM` for internal tools rather than `NONE`; anonymous public access should be reserved for genuinely public endpoints
- Apply SCPs to prevent Lambda execution roles from being assigned AWS managed policies like `AdministratorAccess` or `PowerUserAccess` in non-production accounts

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `Lambda: GetFunctionUrlConfig` -- retrieval of a Lambda Function URL config; when performed by an external or unfamiliar principal, may indicate reconnaissance for a publicly exposed endpoint
- `SSM: GetParameter` -- access to a SecureString parameter; critical when performed using credentials associated with a Lambda execution role operating outside of Lambda's normal invocation context (i.e., from a non-Lambda source IP)
- `STS: AssumeRole` -- if the chatbot role credentials are used to assume further roles, this indicates credential extraction and lateral movement
- `IAM: ListUsers` or `IAM: ListRoles` -- broad IAM enumeration immediately after a Lambda invocation may indicate successful credential extraction

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [https://pathfinding.cloud/paths/ctf-001](https://pathfinding.cloud/paths/ctf-001) -- Interactive attack map for this scenario on pathfinding.cloud
- [MITRE ATT&CK T1190 - Exploit Public-Facing Application](https://attack.mitre.org/techniques/T1190/) -- Technique for exploiting vulnerabilities in public-facing applications
- [MITRE ATT&CK T1552.005 - Cloud Instance Metadata API](https://attack.mitre.org/techniques/T1552/005/) -- Credential access via cloud metadata endpoints and environment variables
- [MITRE ATT&CK T1059 - Command and Scripting Interpreter](https://attack.mitre.org/techniques/T1059/) -- Abusing command execution capabilities within a running environment
- [AWS Lambda Function URLs](https://docs.aws.amazon.com/lambda/latest/dg/lambda-urls.html) -- AWS documentation on Lambda Function URL authentication types
