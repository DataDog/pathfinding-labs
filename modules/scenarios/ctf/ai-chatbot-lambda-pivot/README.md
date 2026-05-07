# AcmeBot: The Backend

* **Category:** CTF
* **Path Type:** ctf
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $1/mo
* **Cost Estimate When Demo Executed:** $1/mo
* **Difficulty:** intermediate
* **Flag Location:** SSM Parameter Store at /pathfinding-labs/flags/ctf-002-to-admin (requires admin credentials)
* **Technique:** Acme Corp's AI assistant fronts a suite of internal Lambda services. Chain your way from the public chatbot to administrative access and retrieve the flag.
* **Terraform Variable:** `enable_ctf_ai_chatbot_lambda_pivot`
* **Schema Version:** 4.1.1
* **MITRE Tactics:** TA0001 - Initial Access, TA0006 - Credential Access, TA0004 - Privilege Escalation
* **MITRE Techniques:** T1190 - Exploit Public-Facing Application, T1552.005 - Unsecured Credentials: Cloud Instance Metadata API, T1525 - Implant Internal Image, T1059 - Command and Scripting Interpreter

## Objective

Acme Corp runs an AI-powered chatbot alongside internal backend services, all on Lambda. Starting from the public chatbot endpoint, your goal is to escalate to administrative access and retrieve the flag.

- **Start:** `https://{function_url_id}.lambda-url.{region}.on.aws/` (public, no auth)
- **Goal:** Retrieve the flag from SSM Parameter Store at `/pathfinding-labs/flags/ctf-002-to-admin`

### Starting Permissions

**Required** (anonymous public URL):
- `lambda:InvokeFunctionUrl` on `arn:aws:lambda:*:*:function/pl-prod-ctf-002-acmebot` -- invoke the chatbot via its public Function URL without any AWS credentials

**Required** (`pl-prod-ctf-002-chatbot-role`):
- `lambda:ListFunctions` on `*` -- enumerate Lambda functions to discover the data processor
- `lambda:UpdateFunctionCode` on `arn:aws:lambda:*:*:function/pl-prod-ctf-002-acme-data-processor` -- replace the target Lambda's code with a malicious handler
- `lambda:InvokeFunction` on `arn:aws:lambda:*:*:function/pl-prod-ctf-002-acme-data-processor` -- invoke the modified function to retrieve admin credentials

**Helpful** (`pl-prod-ctf-002-chatbot-role`):
- `lambda:GetFunction` -- view target Lambda details including the execution role ARN
- `iam:GetRole` -- inspect target role permissions before pivoting

**Helpful** (`pl-prod-ctf-002-starting-user`):
- `lambda:ListFunctions` -- enumerate Lambda functions in the account
- `lambda:GetFunction` -- inspect function configuration and execution roles
- `lambda:GetFunctionUrlConfig` -- retrieve the chatbot's public Function URL
- `sts:GetCallerIdentity` -- confirm current identity at each stage
- `iam:GetUser` -- retrieve starting user details

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable ctf-002-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ctf-002-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
|-----|---------|
| `arn:aws:lambda:{region}:{account_id}:function/pl-prod-ctf-002-acmebot` | Vulnerable AcmeBot chatbot Lambda with public Function URL |
| `arn:aws:iam::{account_id}:role/pl-prod-ctf-002-chatbot-role` | Chatbot execution role (limited Lambda permissions) |
| `arn:aws:lambda:{region}:{account_id}:function/pl-prod-ctf-002-acme-data-processor` | Privileged target Lambda (AdministratorAccess execution role) |
| `arn:aws:iam::{account_id}:role/pl-prod-ctf-002-target-role` | Target Lambda execution role (AdministratorAccess) |
| `arn:aws:iam::{account_id}:user/pl-prod-ctf-002-starting-user` | Starting IAM user for CLI-based participants |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/ctf-002-to-admin` | CTF flag (String, requires admin credentials to read) |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Cleanup

After completing the challenge, restore the target Lambda to its original code so the scenario is ready for the next participant.

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup ai-chatbot-lambda-pivot
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ctf-002-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable ctf-002-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `ctf-002-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- Lambda function execution role with `AdministratorAccess` attached (`pl-prod-ctf-002-target-role`)
- IAM role with `lambda:UpdateFunctionCode` permission over a Lambda function whose execution role has elevated privileges -- this combination is a privilege escalation path
- Lambda function with a public Function URL and no authentication (`pl-prod-ctf-002-acmebot` with `AuthType: NONE`)
- Privilege escalation path: `pl-prod-ctf-002-chatbot-role` → `lambda:UpdateFunctionCode` → `pl-prod-ctf-002-acme-data-processor` → `pl-prod-ctf-002-target-role` (AdministratorAccess)

#### Prevention Recommendations

- Never attach `AdministratorAccess` to a Lambda execution role; scope permissions to the minimum resources and actions the function actually needs
- Treat `lambda:UpdateFunctionCode` + `lambda:InvokeFunction` over a privileged function as equivalent to holding that function's execution role permissions -- audit grants of this combination carefully
- Restrict `lambda:UpdateFunctionCode` to CI/CD service principals rather than operational or application roles; use IAM conditions (`lambda:FunctionArn`) to scope it to specific non-privileged functions only
- For AI/LLM applications with tool use, apply strict input validation and output filtering; treat LLM tool-calling as a trust boundary and audit every tool for what it can expose
- Require authentication on Lambda Function URLs (use `AuthType: AWS_IAM`) unless anonymous public access is an explicit and reviewed requirement
- Implement AWS Config rules or CSPM policies that alert when a Lambda execution role has `AdministratorAccess` or any IAM write permissions

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `Lambda: GetFunctionUrlConfig` -- retrieval of a function's public URL; unusual when performed by principals outside CI/CD or deployment workflows
- `Lambda: ListFunctions` -- Lambda enumeration by a role not associated with deployment tooling, especially from credentials sourced from a Lambda execution environment
- `Lambda: GetFunction` -- inspection of a specific function's configuration including role ARN; precedes code injection attacks
- `IAM: ListAttachedRolePolicies` -- enumerating policies on a role during reconnaissance; high signal when performed by a Lambda execution role
- `Lambda: UpdateFunctionCode20150331v2` -- Lambda function code modified; critical when the target function has a privileged execution role, especially when followed immediately by an invocation
- `Lambda: InvokeFunction` -- function invocation; high severity when it follows a recent `UpdateFunctionCode` event on the same function
- `SSM: GetParameter` -- SSM parameter retrieval, especially with `--with-decryption`; alert when the caller is a newly seen role or one not normally associated with parameter access

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [https://pathfinding.cloud/paths/ctf-002](https://pathfinding.cloud/paths/ctf-002) -- Interactive attack map for this scenario
- [T1190 - Exploit Public-Facing Application](https://attack.mitre.org/techniques/T1190/) -- MITRE ATT&CK technique page
- [T1525 - Implant Internal Image](https://attack.mitre.org/techniques/T1525/) -- Lambda code injection as a variant of this technique
- [T1552.005 - Unsecured Credentials: Cloud Instance Metadata](https://attack.mitre.org/techniques/T1552/005/) -- extracting credentials from Lambda environment variables
