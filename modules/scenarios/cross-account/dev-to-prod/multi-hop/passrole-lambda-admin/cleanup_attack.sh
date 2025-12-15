#!/bin/bash

# Cross-Account PassRole to Lambda Admin Attack Cleanup
# This script removes any Lambda functions created during the multi-hop attack demo
# Path: pl-pathfinding-starting-user-dev -> pl-lambda-prod-updater -> pl-lambda-updater -> pl-Lambda-admin

set -e

echo "🧹 Starting Cross-Account PassRole to Lambda Admin Attack Cleanup"
echo "================================================================="

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed or not in PATH"
    exit 1
fi

# Check if we have the required admin cleanup profile
if ! aws sts get-caller-identity --profile pl-admin-cleanup-prod &> /dev/null; then
    echo "❌ AWS profile 'pl-admin-cleanup-prod' not found"
    echo "Please run: ./create_pathfinder_profiles.sh"
    exit 1
fi

echo "✅ AWS CLI and admin cleanup profile configured"

# Step 1: Check for and remove demo Lambda functions using admin cleanup profile
echo ""
echo "📋 Step 1: Checking for Lambda functions with 'pl-privesc-demo-' prefix..."
echo "Using admin cleanup profile to list and delete Lambda functions in prod account..."

# List Lambda functions that might have been created during the demo using admin profile
if LAMBDA_FUNCTIONS=$(aws lambda list-functions --profile pl-admin-cleanup-prod --output json 2>/dev/null); then
    DEMO_FUNCTIONS=$(echo "$LAMBDA_FUNCTIONS" | jq -r '.Functions[] | select(.FunctionName | startswith("pl-privesc-demo-")) | .FunctionName')
    
    if [ -n "$DEMO_FUNCTIONS" ]; then
        FUNCTION_COUNT=$(echo "$DEMO_FUNCTIONS" | wc -l)
        echo "Found $FUNCTION_COUNT Lambda function(s) with 'pl-privesc-demo-' prefix:"
        echo "$DEMO_FUNCTIONS" | while read -r function_name; do
            echo "  - $function_name"
        done
        echo ""
        
        echo "📋 Step 2: Removing Lambda functions..."
        
        # Delete each Lambda function using admin profile
        echo "$DEMO_FUNCTIONS" | while read -r function_name; do
            echo "Deleting Lambda function: $function_name"
            if aws lambda delete-function --profile pl-admin-cleanup-prod --function-name "$function_name" 2>/dev/null; then
                echo "✅ Successfully deleted Lambda function: $function_name"
            else
                echo "❌ Failed to delete Lambda function: $function_name"
            fi
        done
        
        echo ""
        echo "📋 Step 3: Verifying cleanup..."
        
        # Verify that all Lambda functions have been removed using admin profile
        if REMAINING_FUNCTIONS=$(aws lambda list-functions --profile pl-admin-cleanup-prod --output json 2>/dev/null); then
            REMAINING_DEMO_FUNCTIONS=$(echo "$REMAINING_FUNCTIONS" | jq -r '.Functions[] | select(.FunctionName | startswith("pl-privesc-demo-")) | .FunctionName')
            if [ -z "$REMAINING_DEMO_FUNCTIONS" ]; then
                echo "✅ All demo Lambda functions successfully removed"
            else
                echo "⚠️ Warning: Some demo Lambda functions still remain"
                echo "Remaining functions:"
                echo "$REMAINING_DEMO_FUNCTIONS" | while read -r function_name; do
                    echo "  - $function_name"
                done
            fi
        else
            echo "⚠️ Warning: Could not verify cleanup (insufficient permissions)"
        fi
        
    else
        echo "✅ No demo Lambda functions found"
    fi
    
else
    echo "⚠️ Warning: Could not list Lambda functions"
    echo "This could be because:"
    echo "1. The pl-admin-cleanup-prod profile is not configured"
    echo "2. Lambda service is not available in this region"
    echo "3. No Lambda functions exist"
fi

echo ""
echo "✅ Cleanup completed successfully!"
echo "Any Lambda functions created during the attack demo have been removed."
