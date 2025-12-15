#!/bin/bash

# Cross-Account Lambda Function Code Update Attack Cleanup
# This script restores the original Lambda function code and removes malicious changes

set -e

echo "🧹 Starting Cross-Account Lambda Attack Cleanup"
echo "=============================================="

# Check if AWS CLI is configured
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed or not in PATH"
    exit 1
fi

# Check if we have the required profile
if ! aws sts get-caller-identity --profile pl-pathfinding-starting-user-dev &> /dev/null; then
    echo "❌ AWS profile 'pl-pathfinding-starting-user-dev' not found"
    echo "Please run: ./create_pathfinding_profiles.sh"
    exit 1
fi

echo "✅ AWS CLI and profile configured"

# Step 1: Assume the dev Lambda invoke role
echo ""
echo "📋 Step 1: Assuming dev Lambda invoke role..."
DEV_ROLE_ARN=$(aws sts get-caller-identity --profile pl-pathfinding-starting-user-dev --query 'Account' --output text)
DEV_ROLE_ARN="arn:aws:iam::${DEV_ROLE_ARN}:role/pl-dev-lambda-invoke-role"

echo "Assuming role: $DEV_ROLE_ARN"

# Get temporary credentials for the dev role
TEMP_CREDS=$(aws sts assume-role \
    --profile pl-pathfinding-starting-user-dev \
    --role-arn "$DEV_ROLE_ARN" \
    --role-session-name "lambda-cleanup-demo" \
    --output json)

if [ $? -ne 0 ]; then
    echo "❌ Failed to assume dev role"
    exit 1
fi

# Extract credentials
export AWS_ACCESS_KEY_ID=$(echo $TEMP_CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $TEMP_CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $TEMP_CREDS | jq -r '.Credentials.SessionToken')
export AWS_DEFAULT_REGION="us-west-2"

echo "✅ Successfully assumed dev Lambda invoke role"

# Step 2: Get the prod Lambda function ARN using admin cleanup profile
echo ""
echo "📋 Step 2: Getting prod Lambda function ARN..."
PROD_ACCOUNT_ID=$(aws sts get-caller-identity --profile pl-admin-cleanup-prod --query 'Account' --output text)
FUNCTION_NAME=$(aws lambda list-functions --profile pl-admin-cleanup-prod --query "Functions[?starts_with(FunctionName, 'pl-prod-hello-world-')].FunctionName" --output text | head -1)

if [ -z "$FUNCTION_NAME" ]; then
    echo "❌ Could not find prod Lambda function"
    exit 1
fi

# Construct the full ARN for cross-account access
FUNCTION_ARN="arn:aws:lambda:us-west-2:${PROD_ACCOUNT_ID}:function:${FUNCTION_NAME}"
echo "Found function: $FUNCTION_NAME"
echo "Full ARN: $FUNCTION_ARN"

# Step 3: Restore original hello world code
echo ""
echo "📋 Step 3: Restoring original Lambda function code..."

# Create original hello world code
cat > /tmp/hello_world.py << 'EOF'
def lambda_handler(event, context):
    return {
        'statusCode': 200,
        'body': 'Hello from Pathfinding Labs!'
    }
EOF

# Create zip file
cd /tmp
zip -q restore_lambda.zip hello_world.py

# Update the function code back to original using full ARN
aws lambda update-function-code \
    --function-name "$FUNCTION_ARN" \
    --zip-file "fileb://restore_lambda.zip"

if [ $? -eq 0 ]; then
    echo "✅ Successfully restored original Lambda function code"
else
    echo "❌ Failed to restore Lambda function code"
    exit 1
fi

# Step 4: Verify the function is back to normal
echo ""
echo "📋 Step 4: Verifying function restoration..."

RESPONSE=$(aws lambda invoke \
    --function-name "$FUNCTION_ARN" \
    --payload '{}' \
    /tmp/restore_response.json)

if [ $? -eq 0 ]; then
    echo "✅ Function restored successfully"
    echo "Response: $(cat /tmp/restore_response.json | jq -r '.body')"
else
    echo "❌ Failed to verify function restoration"
    exit 1
fi

# Cleanup
echo ""
echo "🧹 Cleaning up temporary files..."
rm -f /tmp/restore_lambda.py /tmp/restore_lambda.zip /tmp/restore_response.json

echo ""
echo "✅ Cleanup completed successfully!"
echo "The prod Lambda function has been restored to its original state."
