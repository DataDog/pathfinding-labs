# Bedrock Agent Session + Invocation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Access existing code interpreter with privileged role to extract credentials from MicroVM Metadata Service (no iam:PassRole required)
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_bedrock_002_bedrockagentcore_startsession_invoke`
* **Schema Version:** 4.1.1
* **Pathfinding.cloud ID:** bedrock-002
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1552.005 - Unsecured Credentials: Cloud Instance Metadata API

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-bedrock-002-to-admin-starting-user` IAM user to the `pl-prod-bedrock-002-to-admin-target-role` administrative role by starting a session on a pre-deployed Bedrock AgentCore code interpreter and extracting credentials from the MicroVM Metadata Service.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-bedrock-002-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-bedrock-002-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-bedrock-002-to-admin-starting-user`):
- `bedrock-agentcore:StartCodeInterpreterSession` on `arn:aws:bedrock-agentcore:*:*:code-interpreter/pl-prod-bedrock-002-to-admin-target-interpreter` -- initiate a session on the existing code interpreter
- `bedrock-agentcore:InvokeCodeInterpreter` on `arn:aws:bedrock-agentcore:*:*:code-interpreter/pl-prod-bedrock-002-to-admin-target-interpreter` -- execute Python code within the interpreter session to reach the metadata service

**Helpful** (`pl-prod-bedrock-002-to-admin-starting-user`):
- `bedrock-agentcore:ListCodeInterpreters` -- discover existing code interpreters to target
- `bedrock-agentcore:GetCodeInterpreter` -- view interpreter details including the execution role

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable bedrock-002-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `bedrock-002-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-bedrock-002-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:bedrock-agentcore:{region}:{account_id}:code-interpreter/pl-prod-bedrock-002-to-admin-target-interpreter` | Pre-deployed code interpreter with admin execution role |
| `arn:aws:iam::{account_id}:role/pl-prod-bedrock-002-to-admin-target-role` | Target privileged role with AdministratorAccess (pre-attached to interpreter) |
| `arn:aws:iam::{account_id}:policy/pl-prod-bedrock-002-to-admin-starting-user-policy` | Policy granting Start/Invoke permissions (NO PassRole or CreateCodeInterpreter) |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Start a session on the existing code interpreter (no creation needed)
4. Extract credentials from the MicroVM Metadata Service
5. Verify successful privilege escalation with admin operations


#### Resources Created by Attack Script

- Active code interpreter session on `pl-prod-bedrock-002-to-admin-target-interpreter`
- Temporary Python script at `/tmp/bedrock_extract_credentials.py`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo bedrock-002-bedrockagentcore-startsession+invoke
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `bedrock-002-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup bedrock-002-bedrockagentcore-startsession+invoke
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `bedrock-002-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable bedrock-002-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `bedrock-002-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- Principals with `bedrock-agentcore:StartCodeInterpreterSession` and `bedrock-agentcore:InvokeCodeInterpreter` permissions on code interpreters that have privileged execution roles
- Privilege escalation path from a low-privilege principal to a high-privilege interpreter without requiring `iam:PassRole`
- Principals with `bedrock-agentcore:*` or unrestricted Start/Invoke permissions
- Code interpreters with administrative execution roles combined with broad Start/Invoke access granted to non-administrative principals
- Code interpreters with privileged roles accessible for session/invocation (analogous to the Lambda `UpdateFunctionCode` privilege escalation risk)

#### Prevention Recommendations

1. **Restrict Session Start Permissions**: Limit `bedrock-agentcore:StartCodeInterpreterSession` to specific non-privileged interpreters using resource-based conditions:
   ```json
   {
     "Effect": "Allow",
     "Action": "bedrock-agentcore:StartCodeInterpreterSession",
     "Resource": "arn:aws:bedrock-agentcore:*:*:code-interpreter/non-privileged-*"
   }
   ```

2. **Restrict Invoke Permissions**: Similarly limit `bedrock-agentcore:InvokeCodeInterpreter` to specific interpreters:
   ```json
   {
     "Effect": "Allow",
     "Action": "bedrock-agentcore:InvokeCodeInterpreter",
     "Resource": "arn:aws:bedrock-agentcore:*:*:code-interpreter/non-privileged-*"
   }
   ```

3. **Implement Service Control Policies (SCPs)**: Use SCPs to prevent access to code interpreters with privileged roles:
   ```json
   {
     "Effect": "Deny",
     "Action": [
       "bedrock-agentcore:StartCodeInterpreterSession",
       "bedrock-agentcore:InvokeCodeInterpreter"
     ],
     "Resource": "arn:aws:bedrock-agentcore:*:*:code-interpreter/*admin*",
     "Condition": {
       "StringNotEquals": {
         "aws:PrincipalArn": "arn:aws:iam::*:role/TrustedAutomationRole"
       }
     }
   }
   ```

4. **Separate Responsibilities**: Never grant both Start and Invoke permissions together unless absolutely necessary. Grant `StartCodeInterpreterSession` only to trusted users/services, and `InvokeCodeInterpreter` only to authorized operators.

5. **Principle of Least Privilege for Interpreter Roles**: Design code interpreter execution roles with minimal permissions. Never use AdministratorAccess or PowerUserAccess for interpreter execution roles; grant only specific permissions required for the AI/ML workload (e.g., S3 read access to training data).

6. **Implement Resource Tagging and Conditional Access**: Tag code interpreters with sensitivity levels and enforce conditional access:
   ```json
   {
     "Effect": "Deny",
     "Action": [
       "bedrock-agentcore:StartCodeInterpreterSession",
       "bedrock-agentcore:InvokeCodeInterpreter"
     ],
     "Resource": "*",
     "Condition": {
       "StringEquals": {
         "aws:ResourceTag/Sensitivity": "Privileged"
       }
     }
   }
   ```

7. **Use IAM Access Analyzer**: Enable IAM Access Analyzer to identify privilege escalation paths involving Bedrock AgentCore resources and their execution roles.

8. **Audit Existing Code Interpreters**: Regularly review all deployed code interpreters and their execution roles:
   ```bash
   aws bedrock-agentcore list-code-interpreters
   aws bedrock-agentcore get-code-interpreter --interpreter-id <ID>
   aws iam get-role --role-name <execution-role-name>
   ```

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `Bedrock: StartCodeInterpreterSession` -- session started on an existing code interpreter; critical when the target interpreter has a privileged execution role
- `Bedrock: InvokeCodeInterpreter` -- code invoked within an interpreter session; high severity when followed by credential usage from a different IP address

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

This privilege escalation technique (bedrock-002) was discovered by **Nigel Sood** at **Sonrai Security** in 2025:

- [AWS AgentCore: The Overlooked Privilege Escalation Path in Bedrock AI Tooling](https://sonraisecurity.com/blog/aws-agentcore-privilege-escalation-bedrock-scp-fix/) -- Sonrai Security Blog
- [Sandboxed to Compromised: New Research Exposes Credential Exfiltration Paths in AWS Code Interpreters](https://sonraisecurity.com/blog/sandboxed-to-compromised-new-research-exposes-credential-exfiltration-paths-in-aws-code-interpreters/) -- Sonrai Security Blog

**Credit**: Special thanks to Nigel Sood and the Sonrai Security research team for discovering and responsibly disclosing both bedrock-001 and bedrock-002 privilege escalation paths.
