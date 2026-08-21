# AgentCore Runtime Command Injection to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** Can/mo
* **Cost Estimate When Demo Executed:** Can/mo
* **Technique:** Principal with bedrock-agentcore:InvokeAgentRuntimeCommand can run root shell commands inside an existing Runtime or Harness microVM and extract its execution role credentials from MMDS
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_bedrock_004_bedrockagentcore_invokeagentcommand`
* **Schema Version:** 4.7.1
* **Pathfinding.cloud ID:** bedrock-004
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1552.005 - Unsecured Credentials: Cloud Instance Metadata API
* **CTF Flag Location:** ssm-parameter
* **Required Preconditions:**
  - IAM Role: with administrative privileges that trusts bedrock-agentcore.amazonaws.com as a service principal
  - AgentCore Runtime: with the admin execution role attached, using IAM as its Inbound Auth type (not JWT), in READY state

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-bedrock-004-to-admin-starting-user` IAM user to the `pl-prod-bedrock-004-to-admin-target-role` administrative role by invoking a shell command directly inside a pre-existing AgentCore Runtime microVM and extracting the execution role's credentials from the MicroVM Metadata Service.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-bedrock-004-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-bedrock-004-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-bedrock-004-to-admin-starting-user`):
- `bedrock-agentcore:InvokeAgentRuntimeCommand` on `*` -- run a root shell command inside an existing AgentCore Runtime or Harness microVM, bypassing the agent, model, and guardrails entirely

**Helpful** (`pl-prod-bedrock-004-to-admin-starting-user`):
- `bedrock-agentcore:ListAgentRuntimes` -- discover existing runtimes to target
- `bedrock-agentcore:GetAgentRuntime` -- confirm execution role ARN and Inbound Auth type of the target runtime

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable bedrock-004-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `bedrock-004-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-bedrock-004-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:bedrock-agentcore:{region}:{account_id}:runtimes/pl-prod-bedrock-004-to-admin-target-runtime` | Pre-deployed AgentCore Runtime with admin execution role and IAM Inbound Auth |
| `arn:aws:iam::{account_id}:role/pl-prod-bedrock-004-to-admin-target-role` | Target privileged role with AdministratorAccess (pre-attached to runtime) |
| `arn:aws:iam::{account_id}:policy/pl-prod-bedrock-004-to-admin-starting-user-policy` | Policy granting InvokeAgentRuntimeCommand only (no PassRole, no CreateAgentRuntime) |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/bedrock-004-to-admin` | CTF flag stored in SSM Parameter Store, readable only with admin access |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Enumerate existing runtimes using helpful permissions to identify the target
3. Confirm the runtime's execution role and Inbound Auth type
4. Call `bedrock-agentcore:InvokeAgentRuntimeCommand` with a shell command to read MMDS credentials
5. Parse the streaming response to extract AccessKeyId, SecretAccessKey, and Token
6. Export the credentials and verify admin access with `sts:GetCallerIdentity` and `iam:ListUsers`

#### Resources Created by Attack Script

- No persistent AWS resources are created — the attack uses a single API call against the pre-existing runtime

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo bedrock-004-bedrockagentcore-invokeagentcommand
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup bedrock-004-bedrockagentcore-invokeagentcommand
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable bedrock-004-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `bedrock-004-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- Principals with `bedrock-agentcore:InvokeAgentRuntimeCommand` permission on AgentCore Runtimes or Harnesses that have privileged execution roles
- Privilege escalation path from a low-privilege principal to a high-privilege runtime without requiring `iam:PassRole` — one permission is sufficient
- Principals with `bedrock-agentcore:*` or unrestricted `InvokeAgentRuntimeCommand` permissions scoped to `*`
- AgentCore Runtimes configured with IAM Inbound Auth (as opposed to JWT) combined with broad InvokeAgentRuntimeCommand access granted to non-administrative principals — IAM auth is the prerequisite for this attack; JWT-auth resources reject the unauthenticated command channel
- AgentCore Runtimes and Harnesses with administrative execution roles, analogous to Lambda functions with AdministratorAccess or EC2 instances with over-permissive instance profiles

#### Prevention Recommendations

1. **Scope InvokeAgentRuntimeCommand to specific runtime ARNs**: Restrict the permission to specific, non-privileged runtimes rather than wildcarding all resources:
   ```json
   {
     "Effect": "Allow",
     "Action": "bedrock-agentcore:InvokeAgentRuntimeCommand",
     "Resource": "arn:aws:bedrock-agentcore:*:*:runtimes/non-privileged-*"
   }
   ```

2. **Apply an SCP to deny InvokeAgentRuntimeCommand org-wide except for an approved allowlist**: Prevent any principal not on the allowlist from calling this API at the organization level:
   ```json
   {
     "Effect": "Deny",
     "Action": "bedrock-agentcore:InvokeAgentRuntimeCommand",
     "Resource": "*",
     "Condition": {
       "StringNotEquals": {
         "aws:PrincipalArn": "arn:aws:iam::*:role/TrustedAgentCoreOperator"
       }
     }
   }
   ```

3. **Use JWT Inbound Auth instead of IAM Inbound Auth on runtimes with privileged roles**: JWT-authenticated runtimes reject the unauthenticated command channel used by this attack. Prefer JWT auth for any runtime that must carry an elevated execution role.

4. **Principle of least privilege for runtime execution roles**: Never attach AdministratorAccess or PowerUserAccess to an AgentCore Runtime or Harness execution role. Grant only the specific permissions required by the agent workload (for example, read access to a specific S3 bucket or a specific Bedrock model).

5. **Audit all existing runtimes and harnesses for over-permissive execution roles**: Review deployed resources regularly:
   ```bash
   aws bedrock-agentcore list-agent-runtimes
   aws bedrock-agentcore get-agent-runtime --agent-runtime-id <ID>
   aws iam get-role --role-name <execution-role-name>
   ```

6. **Alert on InvokeAgentRuntimeCommand from principals that do not routinely operate AgentCore**: Legitimate operational use of this API is rare; any call from a developer-tier user or automated pipeline that doesn't own the runtime should be investigated immediately.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `bedrock-agentcore:InvokeAgentRuntimeCommand` -- direct shell command executed inside a runtime microVM; critical when the calling principal is not the runtime owner and the target runtime has a privileged execution role
- `sts:AssumeRole` -- role assumption using credentials exfiltrated from MMDS; correlate the assumed-role ARN against known runtime execution roles to detect post-exfiltration activity
- `sts:GetCallerIdentity` -- commonly used immediately after credential exfiltration to verify the stolen identity; watch for this call from a principal or source IP not associated with normal runtime operations

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS AgentCore Privilege Escalation — BeyondTrust](https://www.beyondtrust.com/blog/entry/aws-agentcore-privilege-escalation) -- Original research covering InvokeAgentRuntimeCommand as a privilege escalation vector
- [Credentials Management in AgentCore — AWS Documentation](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/security-credentials-management.html) -- How execution role credentials are vended to runtimes via MMDS
- [AgentCore Runtime Security Best Practices — AWS Documentation](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-security-best-practices.html) -- AWS guidance on locking down runtime permissions
