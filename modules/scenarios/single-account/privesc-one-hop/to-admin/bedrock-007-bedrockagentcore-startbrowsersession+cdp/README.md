# AgentCore Custom Browser CDP Credential Theft to Admin

* **Category:** Privilege Escalation
* **Sub-Category:** existing-passrole
* **Path Type:** one-hop
* **Target:** to-admin
* **Environments:** prod
* **Cost Estimate:** $0/mo
* **Cost Estimate When Demo Executed:** $0/mo
* **Technique:** Principal with bedrock-agentcore:StartBrowserSession and ConnectBrowserAutomationStream can drive an existing Custom Browser over CDP to read its execution role credentials from MMDS
* **Terraform Variable:** `enable_single_account_privesc_one_hop_to_admin_bedrock_007_bedrockagentcore_startbrowsersession_cdp`
* **Schema Version:** 4.7.1
* **Pathfinding.cloud ID:** bedrock-007
* **MITRE Tactics:** TA0004 - Privilege Escalation, TA0006 - Credential Access
* **MITRE Techniques:** T1078.004 - Valid Accounts: Cloud Accounts, T1552.005 - Unsecured Credentials: Cloud Instance Metadata API
* **CTF Flag Location:** ssm-parameter
* **Required Preconditions:**
  - IAM Role: with administrative privileges that trusts bedrock-agentcore.amazonaws.com as a service principal
  - AgentCore Custom Browser: with an execution role explicitly attached (role is optional at browser creation — only browsers provisioned with one are vulnerable to this path)

## Objective

Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-bedrock-007-to-admin-starting-user` IAM user to the `pl-prod-bedrock-007-to-admin-target-role` administrative role by connecting to a pre-existing AgentCore Custom Browser over the Chrome DevTools Protocol (CDP), registering a route hook to satisfy the IMDSv2 token requirement, and issuing `fetch()` calls from inside the browser's JavaScript context to read the execution role's credentials from the MicroVM Metadata Service.

- **Start:** `arn:aws:iam::{account_id}:user/pl-prod-bedrock-007-to-admin-starting-user`
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-bedrock-007-to-admin-target-role`

### Starting Permissions

**Required** (`pl-prod-bedrock-007-to-admin-starting-user`):
- `bedrock-agentcore:StartBrowserSession` on `*` -- start a new browser session against an existing AgentCore Custom Browser, receiving a session ID and WebSocket endpoint
- `bedrock-agentcore:ConnectBrowserAutomationStream` on `*` -- connect to the live CDP WebSocket stream for the session, giving full DevTools control over the browser process running inside the MicroVM

**Helpful** (`pl-prod-bedrock-007-to-admin-starting-user`):
- `bedrock-agentcore:ListBrowsers` -- discover existing Custom Browsers to target
- `bedrock-agentcore:GetBrowser` -- confirm the execution role attached to the target browser and verify it is in READY state

## Self-hosted Lab Setup

### Prerequisites

1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)

### Deploy with plabs non-interactive

```bash
plabs enable bedrock-007-to-admin
plabs apply
```

### Deploy with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `bedrock-007-to-admin` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply

## Attack

### Scenario Specific Resources Created

| ARN | Purpose |
| -- | -- |
| `arn:aws:iam::{account_id}:user/pl-prod-bedrock-007-to-admin-starting-user` | Starting user with access keys |
| `arn:aws:iam::{account_id}:role/pl-prod-bedrock-007-to-admin-target-role` | Target privileged role with AdministratorAccess, trusts bedrock-agentcore.amazonaws.com |
| `arn:aws:bedrock-agentcore:{region}:{account_id}:browser/pl-prod-bedrock-007-to-admin-victim-browser` | Pre-provisioned Custom Browser with the admin execution role attached |
| `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/bedrock-007-to-admin` | CTF flag stored in SSM Parameter Store, readable only with admin access |

### Solution

For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)

### Automated Demo

#### Executing the automated demo_attack script

The script will:
1. Display a step-by-step walkthrough with color-coded output
2. Enumerate existing Custom Browsers using helpful permissions to identify the target
3. Confirm the browser's execution role and READY state using `bedrock-agentcore:GetBrowser`
4. Call `bedrock-agentcore:StartBrowserSession` to obtain a session ID and WebSocket endpoint
5. Call `bedrock-agentcore:ConnectBrowserAutomationStream` to obtain the CDP WebSocket URL
6. Connect with Playwright over CDP and register a `context.route()` hook to rewrite the IMDSv2 PUT token request
7. Use `page.evaluate()` with `fetch()` to read the MMDS token and then the execution role credentials at `http://169.254.169.254`
8. Parse and export the `AccessKeyId`, `SecretAccessKey`, and `Token` fields
9. Verify admin access with `sts:GetCallerIdentity` and `iam:ListUsers`
10. Read the CTF flag from SSM Parameter Store using the elevated credentials

#### Resources Created by Attack Script

- `/tmp/extract_bedrock_007_creds.py` -- local Python script written by the demo that performs the CDP/Playwright credential extraction; removed by `cleanup_attack.sh`

#### With plabs non-interactive

```bash
plabs demo --list
plabs demo bedrock-007-bedrockagentcore-startbrowsersession+cdp
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script

### Cleanup

#### With plabs non-interactive

```bash
plabs cleanup --list
plabs cleanup bedrock-007-bedrockagentcore-startbrowsersession+cdp
```

#### With plabs tui

1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script

## Teardown

### Teardown with plabs non-interactive

```bash
plabs disable bedrock-007-to-admin
plabs apply
```

### Teardown with plabs tui

1. Launch the TUI: `plabs`
2. Navigate to `bedrock-007-to-admin` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy

## Defend

### Detecting Misconfiguration (CSPM)

#### What CSPM tools should detect

- Principals with `bedrock-agentcore:StartBrowserSession` and `bedrock-agentcore:ConnectBrowserAutomationStream` permissions combined, where accessible Custom Browsers carry privileged execution roles — the two permissions together are sufficient for credential theft without any `iam:PassRole` or browser creation
- Privilege escalation path from a low-privilege principal to a high-privilege Custom Browser without requiring `iam:PassRole` — the attacker never needs to provision infrastructure, only to interact with what already exists
- AgentCore Custom Browsers with administrative execution roles, analogous to Lambda functions with AdministratorAccess or EC2 instances with over-permissive instance profiles
- Principals with `bedrock-agentcore:*` or broadly scoped `StartBrowserSession` / `ConnectBrowserAutomationStream` permissions that encompass production Custom Browsers carrying elevated roles
- Custom Browsers where the attached execution role trusts `bedrock-agentcore.amazonaws.com` and holds sensitive data-plane permissions beyond what the browsing workload requires

#### Prevention Recommendations

1. **Scope StartBrowserSession and ConnectBrowserAutomationStream to specific browser ARNs**: Restrict both permissions to non-privileged or user-owned browser resources rather than wildcarding all browsers:
   ```json
   {
     "Effect": "Allow",
     "Action": [
       "bedrock-agentcore:StartBrowserSession",
       "bedrock-agentcore:ConnectBrowserAutomationStream"
     ],
     "Resource": "arn:aws:bedrock-agentcore:*:*:browser/sandbox-*"
   }
   ```

2. **Apply an SCP to deny ConnectBrowserAutomationStream org-wide except for an approved allowlist**: Prevent any principal not on the allowlist from obtaining raw CDP access at the organization level:
   ```json
   {
     "Effect": "Deny",
     "Action": "bedrock-agentcore:ConnectBrowserAutomationStream",
     "Resource": "*",
     "Condition": {
       "StringNotEquals": {
         "aws:PrincipalArn": "arn:aws:iam::*:role/TrustedBrowserOperator"
       }
     }
   }
   ```

3. **Principle of least privilege for Custom Browser execution roles**: Never attach AdministratorAccess, PowerUserAccess, or any broad data-plane policy to a Custom Browser execution role. Grant only the specific permissions the browsing workload requires (for example, read access to a specific S3 bucket).

4. **Provision Custom Browsers without an execution role when elevated permissions are not needed**: The execution role is optional at browser creation. Browsers without an attached role have no credentials accessible from MMDS, eliminating this attack path entirely.

5. **Audit all existing Custom Browsers for over-permissive execution roles**: Review deployed browsers regularly:
   ```bash
   aws bedrock-agentcore list-browsers
   aws bedrock-agentcore get-browser --browser-id <ID>
   aws iam get-role --role-name <execution-role-name>
   ```

6. **Alert on ConnectBrowserAutomationStream from principals that do not own the target browser**: Legitimate use of the raw CDP stream is rare outside of automation workloads that created the browser. Any call from a developer-tier user or unrelated pipeline should be investigated immediately.

### Detecting Abuse (CloudSIEM)

#### CloudTrail Events to Monitor

- `bedrock-agentcore:StartBrowserSession` -- new browser session started; critical when the calling principal is not the browser owner and the target browser carries a privileged execution role
- `bedrock-agentcore:ConnectBrowserAutomationStream` -- raw CDP WebSocket connection established to a browser session; any call from a principal that does not routinely operate Custom Browsers should be investigated
- `sts:AssumeRole` -- role assumption using credentials exfiltrated from MMDS; correlate the assumed-role ARN against known Custom Browser execution roles to detect post-exfiltration activity
- `sts:GetCallerIdentity` -- commonly used immediately after credential exfiltration to verify the stolen identity; watch for this call from a principal or source IP not associated with normal browser operations
- `ssm:GetParameter` -- flag retrieval step; if the accessed parameter is under `/pathfinding-labs/flags/` and the caller assumed a role consistent with a browser execution role, treat as a confirmed escalation

#### Detonation logs

_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._

## References

- [AWS AgentCore Privilege Escalation — BeyondTrust](https://www.beyondtrust.com/blog/entry/aws-agentcore-privilege-escalation) -- Original research covering AgentCore as a privilege escalation vector; the Custom Browser CDP path shares the same MMDS credential exfiltration pattern
- [Credentials Management in AgentCore — AWS Documentation](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/security-credentials-management.html) -- How execution role credentials are vended to Custom Browsers via MMDS
- [Chrome DevTools Protocol — CDP Specification](https://chromedevtools.github.io/devtools-protocol/) -- The protocol used to control the browser and execute JavaScript inside the MicroVM
- [Playwright Python API — context.route](https://playwright.dev/python/docs/api/class-browsercontext#browser-context-route) -- How to intercept and rewrite requests, used here to satisfy the IMDSv2 PUT requirement
