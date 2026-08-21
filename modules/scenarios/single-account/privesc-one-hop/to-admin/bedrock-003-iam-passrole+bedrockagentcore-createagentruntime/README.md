# AgentCore Runtime Creation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** Can/mo
* **Cost Estimate When Demo Executed:** Can/mo
* **Technique:** Deploy a new AgentCore Runtime with an attacker-chosen privileged execution role, then run a shell command via InvokeAgentRuntimeCommand to read temporary credentials from MMDS at 169.254.169.254
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_bedrock_003_iam_passrole_bedrockagentcore_createagentruntime`
* **Schema Version:** 4.7.1
* **Pathfinding.cloud ID:** bedrock-003
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1552.005 - Unsecured Credentials: Cloud Instance Metadata API
* **CTF Flag Location:** ssm-parameter
* **Required Preconditions:**
  - IAM Role: with administrative privileges that trusts bedrock-agentcore.amazonaws.com as a service principal (so it can be passed to the new runtime as its execution role)

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-bedrock-003-to-admin-starting-user` IAM user to the `pl-prod-bedrock-003-to-admin-target-role` administrative role by creating a new AgentCore Runtime with the privileged role as its execution role, then invoking a shell command inside the Runtime's Firecracker MicroVM to extract temporary credentials from the MicroVM Metadata Service (MMDS) at 169.254.169.254.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-bedrock-003-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-bedrock-003-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-bedrock-003-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-bedrock-003-to-admin-target-role` -- pass the privileged role to a new AgentCore Runtime as its execution role
- `bedrock-agentcore:CreateAgentRuntime` on `*` -- deploy a new Runtime provisioned with the attacker-chosen execution role
- `bedrock-agentcore:CreateAgentRuntimeEndpoint` on `*` -- create an endpoint for the new Runtime
- `bedrock-agentcore:CreateWorkloadIdentity` on `*` -- create the workload identity associated with the Runtime
- `bedrock-agentcore:InvokeAgentRuntimeCommand` on `*` -- execute a shell command inside the Runtime's Firecracker MicroVM as root

**Helpful** (`pl-prod-bedrock-003-to-admin-starting-user`):
- `iam:ListRoles` -- discover available privileged roles to pass to the new Runtime
- `iam:GetRole` -- view role trust policies and confirm bedrock-agentcore.amazonaws.com is a trusted service principal
- `bedrock-agentcore:GetAgentRuntime` -- poll the Runtime status and confirm it reached READY state before invoking a command

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable bedrock-003-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `bedrock-003-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-bedrock-003-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-bedrock-003-to-admin-target-role` | Target privileged role with AdministratorAccess, trusts bedrock-agentcore.amazonaws.com |
| `arn:aws:iam::{account_id}:policy/pl-prod-bedrock-003-to-admin-starting-user-policy` | Policy granting PassRole and Bedrock AgentCore Runtime permissions |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/bedrock-003-to-admin` | CTF flag stored in SSM Parameter Store |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Retrieve starting user credentials from Terraform outputs
3. Create an AgentCore Runtime passing the privileged target role as the execution role
4. Wait for the Runtime to reach READY state
5. Invoke a shell command inside the Runtime MicroVM that reads MMDS credentials at 169.254.169.254
6. Extract AccessKeyId, SecretAccessKey, and Token from the MMDS response
7. Verify successful privilege escalation with `sts:GetCallerIdentity`
8. Read the CTF flag from SSM Parameter Store using the elevated credentials

#### Resources Created by Attack Script

- Bedrock AgentCore Runtime with the privileged target role attached as the execution role
- AgentCore Runtime Endpoint associated with the new Runtime

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo bedrock-003-iam-passrole+bedrockagentcore-createagentruntime
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup bedrock-003-iam-passrole+bedrockagentcore-createagentruntime
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable bedrock-003-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `bedrock-003-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- Principal with `iam:PassRole` on privileged roles combined with `bedrock-agentcore:CreateAgentRuntime` and `bedrock-agentcore:InvokeAgentRuntimeCommand` -- detectable privilege escalation path from static policy analysis
- IAM policy granting PassRole on roles with administrative permissions without restricting the `iam:PassedToService` condition to a non-escalation service
- Principal with unrestricted `bedrock-agentcore:*` permissions, especially when combined with PassRole
- Roles that trust `bedrock-agentcore.amazonaws.com` with `AdministratorAccess` or other broad permissions -- any principal holding PassRole on these roles can escalate
- User/role with both `CreateAgentRuntime` and `InvokeAgentRuntimeCommand` permissions -- these two together constitute the full Runtime-to-credentials attack chain

#### Prevention Recommendations

1. **Restrict PassRole Permissions**: Limit `iam:PassRole` to specific non-privileged roles using resource-based conditions and a `PassedToService` condition:
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

2. **Implement Service Control Policies (SCPs)**: Deny `bedrock-agentcore:InvokeAgentRuntimeCommand` org-wide except for an approved allowlist of principals. This single action is the most direct lever -- without it the credential extraction step cannot complete:
   ```json
   {
     "Effect": "Deny",
     "Action": "bedrock-agentcore:InvokeAgentRuntimeCommand",
     "Resource": "*",
     "Condition": {
       "StringNotEquals": {
         "aws:PrincipalArn": ["arn:aws:iam::*:role/approved-agentcore-invoker"]
       }
     }
   }
   ```

3. **Separate Create and Invoke Privileges**: Never grant both `bedrock-agentcore:CreateAgentRuntime` and `bedrock-agentcore:InvokeAgentRuntimeCommand` to the same principal. Runtime creation and runtime invocation should be held by distinct service accounts with separate approval workflows.

4. **Role Trust Policy Restrictions**: Add `aws:SourceAccount` and `aws:SourceArn` conditions to roles trusted by `bedrock-agentcore.amazonaws.com` to prevent them from being passed to attacker-created Runtimes:
   ```json
   {
     "Effect": "Allow",
     "Principal": {"Service": "bedrock-agentcore.amazonaws.com"},
     "Action": "sts:AssumeRole",
     "Condition": {
       "StringEquals": {"aws:SourceAccount": "123456789012"},
       "ArnLike": {
         "aws:SourceArn": "arn:aws:bedrock-agentcore:us-east-1:123456789012:runtime/approved-runtime-*"
       }
     }
   }
   ```

5. **Audit Roles Trusting bedrock-agentcore.amazonaws.com**: Periodically enumerate all IAM roles with `bedrock-agentcore.amazonaws.com` in their trust policy. Any such role with `AdministratorAccess` or equivalent is a passive privilege escalation target for any principal that holds PassRole on it.

6. **Principle of Least Privilege for Execution Roles**: Design AgentCore execution roles with only the permissions needed for the specific Runtime workload. Execution roles should never carry `AdministratorAccess`, `iam:*`, or `sts:AssumeRole` on arbitrary roles.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `bedrock-agentcore:CreateAgentRuntime` -- new Runtime deployed with an execution role ARN in `requestParameters.executionRoleArn`; high severity when the passed role has administrative permissions; alert when `CreateAgentRuntime` is followed within minutes by `InvokeAgentRuntimeCommand` from the same principal
- `bedrock-agentcore:InvokeAgentRuntimeCommand` -- shell command executed inside a Runtime's MicroVM; alert on any occurrence outside of expected automation; check `/aws/bedrock-agentcore/runtimes/<runtimeId>-DEFAULT` CloudWatch log group for command body -- flag entries containing `169.254.169.254` or `security-credentials`
- `bedrock-agentcore:CreateAgentRuntimeEndpoint` -- endpoint created for a Runtime; baseline the expected set of Runtimes in your account and alert on new ones
- `sts:AssumeRole` -- temporary credentials assumed by `bedrock-agentcore.amazonaws.com` on behalf of a Runtime execution role; look for `bedrock-agentcore.amazonaws.com` as the assumed-role principal with an unusual or admin-equivalent role ARN

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS AgentCore Privilege Escalation (BeyondTrust)](https://www.beyondtrust.com/blog/entry/aws-agentcore-privilege-escalation) -- Original research blog post documenting the AgentCore Runtime credential extraction technique
- [AWS Bedrock AgentCore Security Credentials Management](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/security-credentials-management.html) -- AWS documentation on how AgentCore manages execution role credentials inside Runtimes
- [AWS Bedrock AgentCore Runtime Permissions](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-permissions.html) -- AWS documentation on required IAM permissions for AgentCore Runtime operations
