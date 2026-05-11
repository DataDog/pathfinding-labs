# Bedrock Code Interpreter Creation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Pass privileged IAM role to Bedrock code interpreter and extract credentials from MicroVM Metadata Service
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_bedrock_001_iam_passrole_bedrockagentcore_codeinterpreter`
* **Schema Version:** 4.6.0
* **CTF Flag Location:** ssm-parameter `/pathfinding-labs/flags/bedrock-001-to-admin`
* **Pathfinding.cloud ID:** bedrock-001
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1552.005 - Unsecured Credentials: Cloud Instance Metadata API

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-bedrock-001-to-admin-starting-user` IAM user to the `pl-prod-bedrock-001-to-admin-target-role` administrative role by passing the privileged role to a Bedrock AgentCore code interpreter and extracting temporary credentials from the MicroVM Metadata Service at 169.254.169.254.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-bedrock-001-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-bedrock-001-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-bedrock-001-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-bedrock-001-to-admin-target-role` -- pass the privileged role to Bedrock AgentCore as an execution role
- `bedrock-agentcore:CreateCodeInterpreter` on `*` -- create the code interpreter provisioned with the privileged execution role
- `bedrock-agentcore:StartCodeInterpreterSession` on `*` -- start an interactive session inside the code interpreter
- `bedrock-agentcore:InvokeCodeInterpreter` on `*` -- execute code within the session to query the metadata service

**Helpful** (`pl-prod-bedrock-001-to-admin-starting-user`):
- `iam:ListRoles` -- discover available privileged roles to pass
- `iam:GetRole` -- view role trust policies and attached permissions
- `bedrock-agentcore:GetCodeInterpreter` -- verify code interpreter creation and configuration

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew tap DataDog/pathfinding-labs https://github.com/DataDog/pathfinding-labs
   brew install DataDog/pathfinding-labs/plabs
   ```
   Or with Go 1.25+ installed:
   ```bash
   go install github.com/DataDog/pathfinding-labs/cmd/plabs@latest
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable bedrock-001-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `bedrock-001-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-bedrock-001-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-bedrock-001-to-admin-target-role` | Target privileged role with AdministratorAccess policy |
| `arn:aws:iam::{account_id}:policy/pl-prod-bedrock-001-to-admin-starting-user-policy` | Policy granting PassRole and Bedrock AgentCore permissions |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Create a code interpreter with the privileged role
4. Extract credentials from the MicroVM Metadata Service
5. Verify successful privilege escalation with admin operations


#### Resources Created by Attack Script

- Bedrock AgentCore code interpreter with the privileged target role attached
- Active code interpreter session

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo bedrock-001-iam-passrole+bedrockagentcore-codeinterpreter
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `bedrock-001-to-admin` in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup bedrock-001-iam-passrole+bedrockagentcore-codeinterpreter
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `bedrock-001-to-admin` in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable bedrock-001-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `bedrock-001-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- Principal with `iam:PassRole` permission on privileged roles combined with `bedrock-agentcore:CreateCodeInterpreter` -- detectable privilege escalation path from static policy analysis
- IAM policy allowing PassRole on roles with administrative or sensitive permissions without restricting the `iam:PassedToService` condition
- Principal with unrestricted `bedrock-agentcore:*` permissions
- Roles that trust `bedrock-agentcore.amazonaws.com` without restrictive `aws:SourceAccount` or `aws:SourceArn` conditions
- User/role with both PassRole and Bedrock AgentCore create permissions that can reach privileged roles -- toxic combination detectable from policy graph analysis

#### Prevention Recommendations

1. **Restrict PassRole Permissions**: Limit `iam:PassRole` to specific non-privileged roles using resource-based conditions:
   ```json
   {
     "Effect": "Allow",
     "Action": "iam:PassRole",
     "Resource": "arn:aws:iam::*:role/bedrock-limited-*",
     "Condition": {
       "StringEquals": {
         "iam:PassedToService": "bedrock-agentcore.amazonaws.com"
       }
     }
   }
   ```

2. **Implement Service Control Policies (SCPs)**: Use SCPs to prevent PassRole on administrative roles:
   ```json
   {
     "Effect": "Deny",
     "Action": "iam:PassRole",
     "Resource": [
       "arn:aws:iam::*:role/*Admin*",
       "arn:aws:iam::*:role/*admin*"
     ],
     "Condition": {
       "StringEquals": {
         "iam:PassedToService": "bedrock-agentcore.amazonaws.com"
       }
     }
   }
   ```

3. **Restrict Bedrock AgentCore Permissions**: Avoid granting broad `bedrock-agentcore:*` permissions. Separate responsibilities:
   - Grant `CreateCodeInterpreter` only to trusted automation
   - Grant `InvokeCodeInterpreter` only to users who need interactive access
   - Never combine with `iam:PassRole` on privileged roles

4. **Role Trust Policy Restrictions**: Add conditions to roles trusted by `bedrock-agentcore.amazonaws.com`:
   ```json
   {
     "Effect": "Allow",
     "Principal": {
       "Service": "bedrock-agentcore.amazonaws.com"
     },
     "Action": "sts:AssumeRole",
     "Condition": {
       "StringEquals": {
         "aws:SourceAccount": "123456789012"
       },
       "ArnLike": {
         "aws:SourceArn": "arn:aws:bedrock:us-east-1:123456789012:code-interpreter/*"
       }
     }
   }
   ```

5. **Use IAM Access Analyzer**: Enable IAM Access Analyzer to identify privilege escalation paths involving PassRole and AWS service integrations

6. **Principle of Least Privilege**: Design Bedrock execution roles with minimal permissions required for the specific use case, never administrative access

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `bedrock:CreateCodeInterpreter` -- Bedrock AgentCore code interpreter created with an execution role; critical when the passed role ARN has elevated or administrative permissions
- `bedrock:StartCodeInterpreterSession` -- A new interactive session started on a code interpreter; monitor for sessions initiated outside of expected automation workflows
- `bedrock:InvokeCodeInterpreter` -- Code executed within a code interpreter session; high severity when combined with credential usage from a different IP address immediately after
- `sts:AssumeRole` -- Temporary credentials assumed by the Bedrock AgentCore service on behalf of a code interpreter execution role; look for `bedrock-agentcore.amazonaws.com` as the assumed-role principal

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

This privilege escalation technique was discovered by **Nigel Sood** at **Sonrai Security** in 2025:

- [AWS AgentCore: The Overlooked Privilege Escalation Path in Bedrock AI Tooling](https://sonraisecurity.com/blog/aws-agentcore-privilege-escalation-bedrock-scp-fix/) -- Sonrai Security Blog
- [Sandboxed to Compromised: New Research Exposes Credential Exfiltration Paths in AWS Code Interpreters](https://sonraisecurity.com/blog/sandboxed-to-compromised-new-research-exposes-credential-exfiltration-paths-in-aws-code-interpreters/) -- Sonrai Security Blog

**Credit**: Special thanks to Nigel Sood and the Sonrai Security research team for discovering and responsibly disclosing this privilege escalation path.
