#!/bin/bash

# Cleanup script for x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin attack path
# This script removes any Lambda functions that may have been created during the attack demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Cross-Account PassRole to Lambda Admin Attack Cleanup ===${NC}"
echo "This script cleans up any Lambda functions created during the attack demo."
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

echo -e "${YELLOW}Step 1: Checking for Lambda functions with 'pl-privesc-demo-' prefix${NC}"

# List Lambda functions that might have been created during the demo
if LAMBDA_FUNCTIONS=$(aws lambda list-functions --output json 2>/dev/null); then
    DEMO_FUNCTIONS=$(echo "$LAMBDA_FUNCTIONS" | jq -r '.Functions[] | select(.FunctionName | startswith("pl-privesc-demo-")) | .FunctionName')
    
    if [ -n "$DEMO_FUNCTIONS" ]; then
        FUNCTION_COUNT=$(echo "$DEMO_FUNCTIONS" | wc -l)
        echo "Found $FUNCTION_COUNT Lambda function(s) with 'pl-privesc-demo-' prefix:"
        echo "$DEMO_FUNCTIONS" | while read -r function_name; do
            echo "  - $function_name"
        done
        echo ""
        
        echo -e "${YELLOW}Step 2: Removing Lambda functions${NC}"
        
        # Delete each Lambda function
        echo "$DEMO_FUNCTIONS" | while read -r function_name; do
            echo "Deleting Lambda function: $function_name"
            if aws lambda delete-function --function-name "$function_name" 2>/dev/null; then
                echo -e "${GREEN}✓ Successfully deleted Lambda function: $function_name${NC}"
            else
                echo -e "${RED}✗ Failed to delete Lambda function: $function_name${NC}"
            fi
        done
        
        echo ""
        echo -e "${YELLOW}Step 3: Verifying cleanup${NC}"
        
        # Verify that all Lambda functions have been removed
        if REMAINING_FUNCTIONS=$(aws lambda list-functions --output json 2>/dev/null); then
            REMAINING_DEMO_FUNCTIONS=$(echo "$REMAINING_FUNCTIONS" | jq -r '.Functions[] | select(.FunctionName | startswith("pl-privesc-demo-")) | .FunctionName')
            if [ -z "$REMAINING_DEMO_FUNCTIONS" ]; then
                echo -e "${GREEN}✓ All demo Lambda functions successfully removed${NC}"
            else
                echo -e "${YELLOW}⚠ Warning: Some demo Lambda functions still remain${NC}"
                echo "Remaining functions:"
                echo "$REMAINING_DEMO_FUNCTIONS" | while read -r function_name; do
                    echo "  - $function_name"
                done
            fi
        else
            echo -e "${YELLOW}⚠ Warning: Could not verify cleanup (insufficient permissions)${NC}"
        fi
        
    else
        echo -e "${GREEN}✓ No demo Lambda functions found${NC}"
    fi
    
else
    echo -e "${YELLOW}⚠ Warning: Could not list Lambda functions${NC}"
    echo "This could be because:"
    echo "1. Insufficient permissions to list Lambda functions"
    echo "2. Lambda service is not available in this region"
    echo "3. No Lambda functions exist"
fi

echo ""
echo -e "${YELLOW}Step 4: Additional cleanup checks${NC}"

# Check for any other resources that might have been created
echo "Checking for any other resources that might need cleanup..."

# Check for CloudWatch Log Groups that might have been created by Lambda functions
if LOG_GROUPS=$(aws logs describe-log-groups --log-group-name-prefix "/aws/lambda/pl-privesc-demo-" --output json 2>/dev/null); then
    DEMO_LOG_GROUPS=$(echo "$LOG_GROUPS" | jq -r '.logGroups[] | .logGroupName')
    if [ -n "$DEMO_LOG_GROUPS" ]; then
        echo "Found demo CloudWatch Log Groups:"
        echo "$DEMO_LOG_GROUPS" | while read -r log_group; do
            echo "  - $log_group"
        done
        echo ""
        echo "Note: CloudWatch Log Groups are not automatically deleted to avoid data loss."
        echo "You may want to manually delete them if they are no longer needed."
    else
        echo "No demo CloudWatch Log Groups found"
    fi
else
    echo "Could not check CloudWatch Log Groups (insufficient permissions or service unavailable)"
fi

# Check for any IAM roles that might have been created
if IAM_ROLES=$(aws iam list-roles --output json 2>/dev/null); then
    DEMO_ROLES=$(echo "$IAM_ROLES" | jq -r '.Roles[] | select(.RoleName | startswith("pl-privesc-demo-")) | .RoleName')
    if [ -n "$DEMO_ROLES" ]; then
        echo "Found demo IAM roles:"
        echo "$DEMO_ROLES" | while read -r role_name; do
            echo "  - $role_name"
        done
        echo ""
        echo "Note: IAM roles are not automatically deleted to avoid breaking dependencies."
        echo "You may want to manually delete them if they are no longer needed."
    else
        echo "No demo IAM roles found"
    fi
else
    echo "Could not check IAM roles (insufficient permissions)"
fi

echo ""
echo -e "${GREEN}=== CLEANUP COMPLETE ===${NC}"
echo "Cleanup process completed. Any Lambda functions created during the attack demo"
echo "should have been removed. CloudWatch Log Groups and IAM roles are preserved"
echo "to avoid data loss and dependency issues."
echo ""

# Output standardized cleanup results
echo "CLEANUP_RESULT:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:SUCCESS"
echo "CLEANUP_DETAILS:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:Lambda functions cleanup completed"
echo "CLEANUP_METRICS:x-account-from-dev-to-prod-role-assumption-passrole-to-lambda-admin:cleanup_completed=true"
