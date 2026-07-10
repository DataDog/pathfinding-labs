# AgentCore Custom Browser Creation to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** new-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Principal with iam:PassRole and AgentCore Browser create/session permissions can create a Custom Browser with a privileged execution role and extract credentials from MMDS via CDP/Playwright by rewriting IMDSv2 token requests through a context.route hook
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_bedrock_006_iam_passrole_bedrockagentcore_createbrowser`
* **Schema Version:** 4.7.1
* **Pathfinding.cloud ID:** bedrock-006
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access
* **MITRE Techniques:** T1098.001 - Account Manipulation: Additional Cloud Credentials, T1552.005 - Unsecured Credentials: Cloud Instance Metadata API
* **CTF Flag Location:** ssm-parameter
* **Required Preconditions:**
  - IAM Role: with administrative privileges that trusts bedrock-agentcore.amazonaws.com as a service principal (so it can be passed to the new browser as its execution role)

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-bedrock-006-to-admin-starting-user` IAM user to the `pl-prod-bedrock-006-to-admin-target-role` administrative role by creating a new AgentCore Custom Browser with the privileged role as its execution role, then connecting over CDP via Playwright to issue JavaScript fetch() calls that read temporary credentials from the MicroVM Metadata Service (MMDS) at 169.254.169.254 using a context.route hook to rewrite the IMDSv2 token request as a PUT.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-bedrock-006-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-bedrock-006-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-bedrock-006-to-admin-starting-user`):
- `iam:PassRole` on `arn:aws:iam::*:role/pl-prod-bedrock-006-to-admin-target-role` -- pass the privileged role to a new AgentCore Custom Browser as its execution role
- `bedrock-agentcore:CreateBrowser` on `*` -- deploy a new Custom Browser provisioned with the attacker-chosen execution role
- `bedrock-agentcore:StartBrowserSession` on `*` -- open a browser session and obtain a WebSocket URL for CDP connection
- `bedrock-agentcore:ConnectBrowserAutomationStream` on `*` -- connect to the browser's Chrome DevTools Protocol endpoint to issue JavaScript commands

**Helpful** (`pl-prod-bedrock-006-to-admin-starting-user`):
- `iam:ListRoles` -- discover available privileged roles to pass to the new browser
- `iam:GetRole` -- view role trust policies and confirm bedrock-agentcore.amazonaws.com is a trusted service principal
- `bedrock-agentcore:GetBrowser` -- poll the browser status and confirm it reached READY state before starting a session

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable bedrock-006-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `bedrock-006-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-bedrock-006-to-admin-starting-user` | Scenario-specific starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-bedrock-006-to-admin-target-role` | Target privileged role with AdministratorAccess, trusts bedrock-agentcore.amazonaws.com |
| `arn:aws:iam::{account_id}:policy/pl-prod-bedrock-006-to-admin-starting-user-policy` | Policy granting PassRole and Bedrock AgentCore Browser permissions |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/bedrock-006-to-admin` | CTF flag stored in SSM Parameter Store |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Retrieve starting user credentials from Terraform outputs
3. Create an AgentCore Custom Browser passing the privileged target role as the execution role
4. Wait for the browser to reach READY state by polling GetBrowser
5. Start a browser session to obtain the CDP WebSocket URL
6. Connect to the browser via Playwright over CDP using the WebSocket URL
7. Register a context.route hook to intercept requests to 169.254.169.254 and rewrite the IMDSv2 token PUT request with the required header
8. Issue a JavaScript fetch() from inside the browser's MicroVM to retrieve a session token from MMDS
9. Issue a second fetch() with the token header to read temporary credentials for the target role
10. Extract AccessKeyId, SecretAccessKey, and Token from the MMDS response
11. Verify successful privilege escalation with `sts:GetCallerIdentity`
12. Read the CTF flag from SSM Parameter Store using the elevated credentials

#### Resources Created by Attack Script

- Bedrock AgentCore Custom Browser with the privileged target role attached as the execution role
- Local Python script at `/tmp/extract_bedrock_006_creds.py` containing the Playwright CDP extraction code

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo bedrock-006-iam-passrole+bedrockagentcore-createbrowser
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup bedrock-006-iam-passrole+bedrockagentcore-createbrowser
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable bedrock-006-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `bedrock-006-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- Principal with `iam:PassRole` on privileged roles combined with `bedrock-agentcore:CreateBrowser`, `bedrock-agentcore:StartBrowserSession`, and `bedrock-agentcore:ConnectBrowserAutomationStream` -- detectable privilege escalation path from static policy analysis
- IAM policy granting PassRole on roles with administrative permissions without restricting the `iam:PassedToService` condition to a non-escalation service
- Principal with unrestricted `bedrock-agentcore:*` permissions, especially when combined with PassRole
- Roles that trust `bedrock-agentcore.amazonaws.com` with `AdministratorAccess` or other broad permissions -- any principal holding PassRole on these roles can escalate regardless of the specific AgentCore resource type (Runtime, Harness, or Browser)
- User/role with both `CreateBrowser` and `ConnectBrowserAutomationStream` permissions -- these two together constitute the full Browser-to-credentials attack chain via CDP

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

2. **Implement Service Control Policies (SCPs)**: Deny `bedrock-agentcore:ConnectBrowserAutomationStream` and `bedrock-agentcore:StartBrowserSession` org-wide except for an approved allowlist of principals. CDP access to a browser's MicroVM is the critical capability that enables MMDS credential extraction:
   ```json
   {
     "Effect": "Deny",
     "Action": [
       "bedrock-agentcore:ConnectBrowserAutomationStream",
       "bedrock-agentcore:StartBrowserSession"
     ],
     "Resource": "*",
     "Condition": {
       "StringNotEquals": {
         "aws:PrincipalArn": ["arn:aws:iam::*:role/approved-browser-operator"]
       }
     }
   }
   ```

3. **Separate Create and Session Privileges**: Never grant both `bedrock-agentcore:CreateBrowser` and `bedrock-agentcore:ConnectBrowserAutomationStream` to the same principal. Browser provisioning and browser automation access should be held by distinct service accounts with separate approval workflows.

4. **Role Trust Policy Restrictions**: Add `aws:SourceAccount` and `aws:SourceArn` conditions to roles trusted by `bedrock-agentcore.amazonaws.com` to prevent them from being passed to attacker-created Custom Browsers:
   ```json
   {
     "Effect": "Allow",
     "Principal": {"Service": "bedrock-agentcore.amazonaws.com"},
     "Action": "sts:AssumeRole",
     "Condition": {
       "StringEquals": {"aws:SourceAccount": "123456789012"},
       "ArnLike": {
         "aws:SourceArn": "arn:aws:bedrock-agentcore:us-east-1:123456789012:browser/approved-browser-*"
       }
     }
   }
   ```

5. **Audit Roles Trusting bedrock-agentcore.amazonaws.com**: Periodically enumerate all IAM roles with `bedrock-agentcore.amazonaws.com` in their trust policy. Any such role with `AdministratorAccess` or equivalent is a passive privilege escalation target for any principal that holds PassRole on it -- this includes browsers, runtimes, and harnesses.

6. **Principle of Least Privilege for Execution Roles**: Design AgentCore execution roles with only the permissions needed for the specific workload. Execution roles should never carry `AdministratorAccess`, `iam:*`, or `sts:AssumeRole` on arbitrary roles.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `bedrock-agentcore:CreateBrowser` -- new Custom Browser deployed with an execution role ARN in `requestParameters.executionRoleArn`; high severity when the passed role has administrative permissions; alert when followed within minutes by `bedrock-agentcore:StartBrowserSession` from the same principal
- `bedrock-agentcore:StartBrowserSession` -- browser session opened and CDP WebSocket URL vended; alert on any occurrence outside of expected automation pipelines
- `bedrock-agentcore:ConnectBrowserAutomationStream` -- CDP connection established to a browser's MicroVM; alert on any occurrence outside of expected automation; this event provides direct JavaScript execution inside the MicroVM where MMDS credentials are accessible
- `sts:AssumeRole` -- temporary credentials assumed by `bedrock-agentcore.amazonaws.com` on behalf of a Browser execution role; look for `bedrock-agentcore.amazonaws.com` as the assumed-role principal with an unusual or admin-equivalent role ARN

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS AgentCore Privilege Escalation (BeyondTrust)](https://www.beyondtrust.com/blog/entry/aws-agentcore-privilege-escalation) -- Original research blog post documenting the AgentCore credential extraction technique including Runtime, Harness, and Browser variants
- [AWS Bedrock AgentCore Security Credentials Management](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/security-credentials-management.html) -- AWS documentation on how AgentCore manages execution role credentials inside browser MicroVMs
- [AWS Bedrock AgentCore Browser Documentation](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/browser.html) -- AWS documentation on the Custom Browser resource type, CDP access, and session management
- [Chrome DevTools Protocol (CDP) Documentation](https://chromedevtools.github.io/devtools-protocol/) -- Protocol reference for browser automation commands used to issue JavaScript fetch() calls from inside the MicroVM
