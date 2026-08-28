# AgentCore Harness Creation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** Can/mo
* **Cost Estimate When Demo Executed:** Can/mo
* **Technique:** Principal with iam:PassRole and AgentCore Harness create/invoke permissions can deploy a new Harness with a privileged execution role and extract credentials from MMDS at 169.254.169.254
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_bedrock_005_iam_passrole_bedrockagentcore_createharness`
* **Schema Version:** 4.7.1
* **Pathfinding.cloud ID:** bedrock-005
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1552.005 - Unsecured Credentials: Cloud Instance Metadata API
* **CTF Flag Location:** ssm-parameter
* **Required Preconditions:**
  - IAM Role: with administrative privileges that trusts bedrock-agentcore.amazonaws.com as a service principal (so it can be passed to the new harness as its execution role)
  - [configuration] at least one Bedrock foundation model enabled in the account (required at CreateHarness time; the model is never invoked by the attack since InvokeAgentRuntimeCommand bypasses the agent loop entirely)

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-bedrock-005-to-admin-starting-user` IAM user to the `pl-prod-bedrock-005-to-admin-target-role` administrative role by creating a new AgentCore Harness with the privileged role as its execution role, then invoking a shell command inside the Harness's Firecracker MicroVM to extract temporary credentials from the MicroVM Metadata Service (MMDS) at 169.254.169.254.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-bedrock-005-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-bedrock-005-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-bedrock-005-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-bedrock-005-to-admin-target-role` -- pass the privileged role to a new AgentCore Harness as its execution role
- `bedrock-agentcore:CreateHarness` on `*` -- deploy a new Harness (AWS-managed container, no custom image required) provisioned with the attacker-chosen execution role and a specified foundation model
- `bedrock-agentcore:CreateAgentRuntime` on `*` -- required internally by CreateHarness to provision the underlying Runtime
- `bedrock-agentcore:CreateAgentRuntimeEndpoint` on `*` -- required internally by CreateHarness to create an endpoint for the underlying Runtime
- `bedrock-agentcore:CreateWorkloadIdentity` on `*` -- required internally by CreateHarness to create the workload identity associated with the Runtime
- `bedrock-agentcore:GetAgentRuntime` on `*` -- required internally by CreateHarness to resolve the Runtime it provisions
- `bedrock-agentcore:GetHarness` on `*` -- poll the status of the Harness and confirm it reached READY state before invoking a command
- `bedrock-agentcore:InvokeAgentRuntimeCommand` on `*` -- execute a shell command inside the Harness's Firecracker MicroVM as root

**Helpful** (`pl-prod-bedrock-005-to-admin-starting-user`):
- `iam:ListRoles` -- discover available privileged roles to pass to the new Harness
- `iam:GetRole` -- view role trust policies and confirm bedrock-agentcore.amazonaws.com is a trusted service principal

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)
3. AWS CLI v2.35.7 or newer, which is the first release able to disable harness memory on `create-harness`

### Deploy with plabs non-interactive

```bash
plabs enable bedrock-005-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `bedrock-005-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-bedrock-005-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-bedrock-005-to-admin-target-role` | Target privileged role with AdministratorAccess, trusts bedrock-agentcore.amazonaws.com |
| `arn:aws:iam::{account_id}:policy/pl-prod-bedrock-005-to-admin-starting-user-policy` | Policy granting PassRole and Bedrock AgentCore Harness permissions |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/bedrock-005-to-admin` | CTF flag stored in SSM Parameter Store |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Retrieve starting user credentials from Terraform outputs
3. Create an AgentCore Harness passing the privileged target role as the execution role and specifying a foundation model ID
4. Extract the Harness ARN and Harness ID from the CreateHarness response
5. Wait for the Harness to reach READY state by polling GetHarness
6. Invoke a shell command inside the Harness MicroVM that reads MMDS credentials at 169.254.169.254
7. Extract AccessKeyId, SecretAccessKey, and Token from the MMDS response
8. Verify successful privilege escalation with `sts:GetCallerIdentity`
9. Read the CTF flag from SSM Parameter Store using the elevated credentials

#### Resources Created by Attack Script

- Bedrock AgentCore Harness with the privileged target role attached as the execution role
- AgentCore Runtime and Runtime Endpoint provisioned automatically by the CreateHarness API call

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo bedrock-005-iam-passrole+bedrockagentcore-createharness
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup bedrock-005-iam-passrole+bedrockagentcore-createharness
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable bedrock-005-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `bedrock-005-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- Principal with `iam:PassRole` on privileged roles combined with `bedrock-agentcore:CreateHarness` and `bedrock-agentcore:InvokeAgentRuntimeCommand` -- detectable privilege escalation path from static policy analysis
- IAM policy granting PassRole on roles with administrative permissions without restricting the `iam:PassedToService` condition to a non-escalation service
- Principal with unrestricted `bedrock-agentcore:*` permissions, especially when combined with PassRole
- Roles that trust `bedrock-agentcore.amazonaws.com` with `AdministratorAccess` or other broad permissions -- any principal holding PassRole on these roles can escalate
- User/role with both `CreateHarness` (or `CreateAgentRuntime`) and `InvokeAgentRuntimeCommand` permissions -- these two together constitute the full Harness-to-credentials attack chain

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

3. **Separate Create and Invoke Privileges**: Never grant both `bedrock-agentcore:CreateHarness` (or `CreateAgentRuntime`) and `bedrock-agentcore:InvokeAgentRuntimeCommand` to the same principal. Harness creation and runtime invocation should be held by distinct service accounts with separate approval workflows.

4. **Role Trust Policy Restrictions**: Add `aws:SourceAccount` and `aws:SourceArn` conditions to roles trusted by `bedrock-agentcore.amazonaws.com` to prevent them from being passed to attacker-created Harnesses:
   ```json
   {
     "Effect": "Allow",
     "Principal": {"Service": "bedrock-agentcore.amazonaws.com"},
     "Action": "sts:AssumeRole",
     "Condition": {
       "StringEquals": {"aws:SourceAccount": "123456789012"},
       "ArnLike": {
         "aws:SourceArn": "arn:aws:bedrock-agentcore:us-east-1:123456789012:harness/approved-harness-*"
       }
     }
   }
   ```

5. **Audit Roles Trusting bedrock-agentcore.amazonaws.com**: Periodically enumerate all IAM roles with `bedrock-agentcore.amazonaws.com` in their trust policy. Any such role with `AdministratorAccess` or equivalent is a passive privilege escalation target for any principal that holds PassRole on it.

6. **Principle of Least Privilege for Execution Roles**: Design AgentCore execution roles with only the permissions needed for the specific Harness workload. Execution roles should never carry `AdministratorAccess`, `iam:*`, or `sts:AssumeRole` on arbitrary roles.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `bedrock-agentcore:CreateHarness` -- new Harness deployed; check `requestParameters.executionRoleArn` for privileged roles; alert when followed within minutes by `bedrock-agentcore:InvokeAgentRuntimeCommand` from the same principal
- `bedrock-agentcore:CreateAgentRuntime` -- underlying Runtime provisioned as part of Harness creation; check `requestParameters.executionRoleArn`; alert when the passed role has administrative permissions
- `bedrock-agentcore:InvokeAgentRuntimeCommand` -- shell command executed inside a Harness MicroVM; alert on any occurrence outside of expected automation; check `/aws/bedrock-agentcore/runtimes/<runtimeId>-DEFAULT` CloudWatch log group for command body -- flag entries containing `169.254.169.254` or `security-credentials`
- `bedrock-agentcore:CreateAgentRuntimeEndpoint` -- endpoint created for the underlying Runtime; baseline the expected set of Runtimes and alert on new ones
- `sts:AssumeRole` -- temporary credentials assumed by `bedrock-agentcore.amazonaws.com` on behalf of a Harness execution role; look for `bedrock-agentcore.amazonaws.com` as the assumed-role principal with an unusual or admin-equivalent role ARN

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS AgentCore Privilege Escalation (BeyondTrust)](https://www.beyondtrust.com/blog/entry/aws-agentcore-privilege-escalation) -- Original research blog post documenting the AgentCore credential extraction technique including both Runtime and Harness variants
- [AWS Bedrock AgentCore Security Credentials Management](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/security-credentials-management.html) -- AWS documentation on how AgentCore manages execution role credentials inside Runtimes and Harnesses
- [AWS Bedrock AgentCore Harness Environment](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/harness-environment.html) -- AWS documentation on the Harness environment, its relationship to the underlying Runtime, and managed agent layer
