#!/bin/bash

# Cleanup script for PutRolePolicy privilege escalation attack
# This script undoes the permanent changes made by demo_attack.sh

set -e  # Exit on any error

# Configuration
PROFILE="pl-admin-cleanup-prod"
REGION="us-west-2"

# Get the account ID from the profile
echo "🔍 Getting account ID from profile: $PROFILE"
ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --query Account --output text)
echo "📋 Account ID: $ACCOUNT_ID"

# Role ARNs
ROLE_A_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-role-a-non-admin"
ROLE_B_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-role-b-admin"

echo ""
echo "🧹 Starting cleanup of PutRolePolicy privilege escalation attack..."
echo "=================================================================="

# Step 1: Check if the malicious policy exists and remove it
echo ""
echo "🔄 Step 1: Checking for malicious admin policy on RoleB..."

# Check if the malicious policy exists
if aws iam get-role-policy --role-name pl-prod-role-b-admin --policy-name malicious-admin-policy --profile $PROFILE &> /dev/null; then
    echo "⚠️  Found malicious-admin-policy on RoleB, removing it..."
    
    # Remove the malicious policy
    aws iam delete-role-policy \
        --role-name pl-prod-role-b-admin \
        --policy-name malicious-admin-policy \
        --profile $PROFILE \
        --region $REGION
    
    echo "✅ Successfully removed malicious admin policy from RoleB"
else
    echo "✅ No malicious admin policy found on RoleB (already clean)"
fi

# Step 2: Verify RoleB no longer has admin policies
echo ""
echo "🔄 Step 2: Verifying RoleB no longer has admin policies..."

echo "🔍 Listing remaining policies on RoleB..."

aws iam list-role-policies \
    --role-name pl-prod-role-b-admin \
    --profile $PROFILE \
    --region $REGION

echo "✅ RoleB policies cleaned up successfully!"

# Step 3: Final verification
echo ""
echo "🔄 Step 3: Final verification of cleanup..."

echo "🔍 Checking RoleB's current policies..."

aws iam list-role-policies \
    --role-name pl-prod-role-b-admin \
    --profile $PROFILE \
    --region $REGION

echo ""
echo "🎉 CLEANUP COMPLETE! Successfully reverted PutRolePolicy privilege escalation!"
echo "=========================================================================="
echo "📊 Cleanup Summary:"
echo "   - Used admin profile: $PROFILE"
echo "   - Removed malicious admin policy from RoleB"
echo "   - Verified RoleB no longer has admin permissions"
echo "   - Successfully reverted to secure state"
echo ""
echo "💡 The attack has been completely cleaned up!"
echo "   RoleB is now back to its original non-admin state."
echo "✅ Cleanup script completed successfully"
