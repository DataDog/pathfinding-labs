# Privilege Escalation via Bedrock AgentCore: Accessing Existing Code Interpreters

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Pathfinding.cloud ID:** bedrock-002
* **Technique:** Access existing code interpreter with privileged role to extract credentials from MicroVM Metadata Service (no iam:PassRole required)
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_bedrock_002_bedrockagentcore_startsession_invoke`
* **Schema Version:** 1.0.0
* **Attack Path:** starting_user → (StartCodeInterpreterSession) → existing code interpreter (with pre-attached admin role) → (InvokeCodeInterpreter) → extract credentials from MicroVM Metadata Service (169.254.169.254) → admin access
* **Attack Principals:** `arn:aws:iam::{account_id}:user/pl-prod-bedrock-002-to-admin-starting-user`; `arn:aws:iam::{account_id}:role/pl-prod-bedrock-002-to-admin-target-role`
* **Required Permissions:** `bedrock-agentcore:StartCodeInterpreterSession` on `arn:aws:bedrock-agentcore:*:*:code-interpreter/pl-prod-bedrock-002-to-admin-target-interpreter`; `bedrock-agentcore:InvokeCodeInterpreter` on `arn:aws:bedrock-agentcore:*:*:code-interpreter/pl-prod-bedrock-002-to-admin-target-interpreter`
* **Helpful Permissions:** `bedrock-agentcore:ListCodeInterpreters` (Discover existing code interpreters to target); `bedrock-agentcore:GetCodeInterpreter` (View interpreter details including execution role)
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1552.005 - Unsecured Credentials: Cloud Instance Metadata API

## Attack Overview

This scenario demonstrates a critical privilege escalation vulnerability discovered by Nigel Sood at Sonrai Security in 2025. Unlike the bedrock-001 attack which requires creating a NEW code interpreter with `iam:PassRole`, this scenario exploits EXISTING code interpreters that already have privileged IAM roles attached. An attacker with only `bedrock-agentcore:StartCodeInterpreterSession` and `bedrock-agentcore:InvokeCodeInterpreter` permissions can access pre-deployed code interpreters, start a session, and extract credentials from the MicroVM Metadata Service (MMDS) at 169.254.169.254.

This attack is analogous to `lambda:UpdateFunctionCode` versus `lambda:CreateFunction` - it targets existing resources rather than creating new ones, and therefore does NOT require `iam:PassRole` permission since the role is already attached to the interpreter.

The vulnerability is particularly dangerous because:
- **No iam:PassRole Required**: The role is already attached to the existing interpreter, eliminating the most common privilege escalation control
- **Lower Permission Bar**: Organizations may grant "read-only" Bedrock access (Start/Invoke) while carefully restricting Create permissions
- **Existing Infrastructure**: Exploits legitimate code interpreters already deployed for AI/ML workloads
- **Similar to Lambda UpdateFunctionCode**: Follows the same pattern as other "modify existing resource" escalation paths
- **Detection Gap**: CSPM tools may focus on CreateCodeInterpreter while missing Start/Invoke on existing privileged interpreters

The bedrock-002 attack path represents a **fundamentally different escalation vector** from bedrock-001. Organizations that carefully restrict `iam:PassRole` are still vulnerable if they grant Start/Invoke permissions on existing privileged interpreters. Teams may view `StartCodeInterpreterSession` and `InvokeCodeInterpreter` as "safe" operational permissions, similar to viewing Lambda logs or invoking functions. The attack exploits legitimate business resources (AI/ML interpreters) rather than requiring attacker-controlled infrastructure, and more principals are likely to have Start/Invoke than Create+PassRole permissions.

This scenario follows the same pattern as other "access existing privileged resource" escalation paths: `lambda:UpdateFunctionCode` on privileged Lambda functions, `codebuild:StartBuild` on privileged build projects, and `apprunner:UpdateService` on privileged App Runner services. All follow the pattern: **Access + Execute Existing Privileged Resource → Credential Extraction → Privilege Escalation**.

Bedrock code interpreters run on Firecracker MicroVMs, which expose a metadata service similar to EC2's IMDS at 169.254.169.254. The credential path `/latest/meta-data/iam/security-credentials/execution_role` returns a JSON response containing AccessKeyId, SecretAccessKey, Token, and Expiration — with no IMDSv2 token requirement (unlike EC2). This endpoint is accessible from any Python code executed in the interpreter.

**Compared to bedrock-001 (CREATE + PassRole)**:

| Aspect | bedrock-001 (CREATE) | bedrock-002 (ACCESS) |
|--------|---------------------|---------------------|
| **Primary Permission** | `bedrock-agentcore:CreateCodeInterpreter` | `bedrock-agentcore:StartCodeInterpreterSession` |
| **Requires iam:PassRole** | YES | NO |
| **Target Resource** | Creates new interpreter | Accesses existing interpreter |
| **Analogous To** | `lambda:CreateFunction` + `iam:PassRole` | `lambda:UpdateFunctionCode` or `lambda:InvokeFunction` |
| **Detection Focus** | Monitor Create + PassRole combination | Monitor Start/Invoke on privileged interpreters |
| **Common Scenario** | Developer with Create permissions | Operator with "read-only" access to existing interpreters |

**Notes**: This scenario requires a region where Amazon Bedrock AgentCore is available. Unlike bedrock-001, the code interpreter is deployed during `terraform apply` (not during the attack). The cleanup script terminates sessions but preserves the interpreter and IAM infrastructure.

### MITRE ATT&CK Mapping

- **Tactic**: TA0004 - Privilege Escalation, TA0006 - Credential Access
- **Technique**: T1078.004 - Valid Accounts: Cloud Accounts
- **Technique**: T1552.005 - Unsecured Credentials: Cloud Instance Metadata API
- **Sub-technique**: Accessing existing privileged resources to extract credentials from metadata service

### Principals in the attack path

- `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-bedrock-002-to-admin-starting-user` (Scenario-specific starting user)
- `arn:aws:bedrock-agentcore:REGION:PROD_ACCOUNT:code-interpreter/pl-prod-bedrock-002-to-admin-target-interpreter` (Pre-deployed code interpreter with admin role)
- `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-bedrock-002-to-admin-target-role` (Admin execution role already attached to the interpreter)

### Attack Path Diagram

```mermaid
graph LR
    A[pl-prod-bedrock-002-to-admin-starting-user] -->|bedrock-agentcore:StartCodeInterpreterSession| B[Existing Code Interpreter]
    B -->|Pre-attached Admin Role| C[pl-prod-bedrock-002-to-admin-target-role]
    B -->|bedrock-agentcore:InvokeCodeInterpreter| D[Execute Python Code]
    D -->|HTTP GET 169.254.169.254| E[MicroVM Metadata Service]
    E -->|/latest/meta-data/iam/security-credentials/| F[Extract Admin Credentials]
    F -->|Use Credentials| G[Administrator Access]

    style A fill:#ff9999,stroke:#333,stroke-width:2px
    style B fill:#ffcc99,stroke:#333,stroke-width:2px
    style E fill:#ffcc99,stroke:#333,stroke-width:2px
    style G fill:#99ff99,stroke:#333,stroke-width:2px
```

### Attack Steps

1. **Initial Access**: Start as `pl-prod-bedrock-002-to-admin-starting-user` (credentials provided via Terraform outputs)
2. **Discover Existing Interpreter**: Identify the pre-deployed code interpreter `pl-prod-bedrock-002-to-admin-target-interpreter` (optionally using `bedrock-agentcore:ListCodeInterpreters`)
3. **Start Session**: Initiate a session on the existing interpreter using `bedrock-agentcore:StartCodeInterpreterSession` (NO iam:PassRole required)
4. **Execute Credential Extraction**: Use `bedrock-agentcore:InvokeCodeInterpreter` to run Python code that accesses the MicroVM Metadata Service at 169.254.169.254
5. **Extract Credentials**: Read temporary credentials from `/latest/meta-data/iam/security-credentials/execution_role`
6. **Verification**: Use the extracted credentials to verify administrator access

### Scenario specific resources created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::PROD_ACCOUNT:user/pl-prod-bedrock-002-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:bedrock-agentcore:REGION:PROD_ACCOUNT:code-interpreter/pl-prod-bedrock-002-to-admin-target-interpreter` | Pre-deployed code interpreter with admin execution role |
| `arn:aws:iam::PROD_ACCOUNT:role/pl-prod-bedrock-002-to-admin-target-role` | Target privileged role with AdministratorAccess (pre-attached to interpreter) |
| `arn:aws:iam::PROD_ACCOUNT:policy/pl-prod-bedrock-002-to-admin-starting-user-policy` | Policy granting Start/Invoke permissions (NO PassRole or CreateCodeInterpreter) |

## Attack Lab

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable enable_single_account_privesc_one_hop_to_admin_bedrock_002_bedrockagentcore_startsession_invoke
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `space` to enable it
4. Press `d` to deploy

### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Show the commands being executed and their results
3. Start a session on the existing code interpreter (no creation needed)
4. Extract credentials from the MicroVM Metadata Service
5. Verify successful privilege escalation with admin operations
6. Output standardized test results for automation

#### Resources created by attack script

- Active code interpreter session on `pl-prod-bedrock-002-to-admin-target-interpreter`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo bedrock-002-bedrockagentcore-startsession+invoke
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup bedrock-002-bedrockagentcore-startsession+invoke
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

### Teardown with plabs non-interactive

```bash
plabs disable enable_single_account_privesc_one_hop_to_admin_bedrock_002_bedrockagentcore_startsession_invoke
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Detecting Misconfiguration (CSPM)

### What CSPM tools should detect

A properly configured Cloud Security Posture Management (CSPM) tool should identify this vulnerability by detecting:

1. **Access to Privileged Interpreters**: Principals with `StartCodeInterpreterSession` and `InvokeCodeInterpreter` permissions on code interpreters that have privileged execution roles
2. **Privilege Escalation Path**: Path from low-privilege principal to high-privilege interpreter without requiring PassRole
3. **Overly Broad Bedrock Permissions**: Principals with `bedrock-agentcore:*` or unrestricted Start/Invoke permissions
4. **Dangerous Resource Combinations**: Code interpreters with administrative roles + broad Start/Invoke access
5. **Similar to Lambda Update Paths**: Code interpreters with privileged roles accessible for session/invocation (analogous to Lambda functions with UpdateFunctionCode risk)

### Prevention recommendations

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

4. **Separate Responsibilities**: Never grant both Start and Invoke permissions together unless absolutely necessary:
   - Grant `StartCodeInterpreterSession` only to trusted users/services
   - Grant `InvokeCodeInterpreter` only to authorized operators
   - Require both permissions to be present for exploitation

5. **Monitor CloudTrail Events**: Set up alerts for suspicious Bedrock AgentCore activity:
   - `StartCodeInterpreterSession` on interpreters with privileged execution roles
   - `InvokeCodeInterpreter` API calls with HTTP requests to 169.254.169.254
   - Session starts followed immediately by credential usage from different IP addresses
   - Multiple failed session attempts followed by successful credential extraction

6. **Principle of Least Privilege for Interpreter Roles**: Design code interpreter execution roles with minimal permissions:
   - Never use AdministratorAccess or PowerUserAccess for interpreter execution roles
   - Grant only specific permissions required for AI/ML workload (e.g., S3 read access to training data)
   - Use resource-based conditions to limit scope

7. **Use IAM Access Analyzer**: Enable IAM Access Analyzer to identify privilege escalation paths involving Bedrock AgentCore resources and their execution roles

8. **Implement Resource Tagging and Conditional Access**: Tag code interpreters with sensitivity levels and enforce conditional access:
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

9. **Audit Existing Code Interpreters**: Regularly review all deployed code interpreters and their execution roles:
   ```bash
   # List all interpreters and check their execution roles
   aws bedrock-agentcore list-code-interpreters
   aws bedrock-agentcore get-code-interpreter --interpreter-id <ID>
   aws iam get-role --role-name <execution-role-name>
   ```

10. **Network Monitoring**: Monitor for unusual network patterns from Bedrock resources, including requests to 169.254.169.254

## Detection Abuse (CloudSIEM)

### CloudTrail events to monitor

- `Bedrock: StartCodeInterpreterSession` — Session started on an existing code interpreter; critical when the target interpreter has a privileged execution role
- `Bedrock: InvokeCodeInterpreter` — Code invoked within an interpreter session; high severity when followed by credential usage from a different IP address

### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

This privilege escalation technique (bedrock-002) was discovered by **Nigel Sood** at **Sonrai Security** in 2025:

- [AWS AgentCore: The Overlooked Privilege Escalation Path in Bedrock AI Tooling](https://sonraisecurity.com/blog/aws-agentcore-privilege-escalation-bedrock-scp-fix/) - Sonrai Security Blog
- [Sandboxed to Compromised: New Research Exposes Credential Exfiltration Paths in AWS Code Interpreters](https://sonraisecurity.com/blog/sandboxed-to-compromised-new-research-exposes-credential-exfiltration-paths-in-aws-code-interpreters/) - Sonrai Security Blog

**Credit**: Special thanks to Nigel Sood and the Sonrai Security research team for discovering and responsibly disclosing both bedrock-001 and bedrock-002 privilege escalation paths.
