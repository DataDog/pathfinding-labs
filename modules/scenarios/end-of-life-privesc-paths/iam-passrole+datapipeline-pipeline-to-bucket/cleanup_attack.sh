#!/bin/bash

# Cleanup script for Data Pipeline resource policy bypass privilege escalation demo
# This script removes the Data Pipeline, EC2 instances, and exfiltrated data

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PIPELINE_NAME="pl-datapipeline-001-exfil-pipeline"
DEMO_INSTANCE_TAG="DataPipeline: pl-datapipeline-001-exfil-pipeline"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Data Pipeline Resource Policy Bypass${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get admin cleanup user credentials from root terraform output
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${RED}Error: Could not find admin cleanup credentials in terraform output${NC}"
    echo "Make sure the admin cleanup user is deployed"
    exit 1
fi

if [ -z "$CURRENT_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    CURRENT_REGION="us-east-1"
fi

# Set admin credentials
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_REGION="$CURRENT_REGION"
unset AWS_SESSION_TOKEN

echo "Region from Terraform: $CURRENT_REGION"
echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

# Get module output to retrieve bucket names
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_bucket_iam_passrole_datapipeline_pipeline.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve module outputs${NC}"
    EXFIL_BUCKET=""
else
    EXFIL_BUCKET=$(echo "$MODULE_OUTPUT" | jq -r '.exfil_bucket_name')
fi

# Navigate back to scenario directory
cd - > /dev/null

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Find and delete Data Pipeline
echo -e "${YELLOW}Step 2: Finding and deleting Data Pipeline${NC}"
echo "Searching for pipeline: $PIPELINE_NAME"
echo ""

# List all pipelines and find ours
PIPELINE_IDS=$(aws datapipeline list-pipelines \
    --region $CURRENT_REGION \
    --query "pipelineIdList[?name=='$PIPELINE_NAME'].id" \
    --output text)

if [ -n "$PIPELINE_IDS" ]; then
    for PIPELINE_ID in $PIPELINE_IDS; do
        echo "Found pipeline: $PIPELINE_ID"

        # Delete the pipeline
        aws datapipeline delete-pipeline \
            --region $CURRENT_REGION \
            --pipeline-id "$PIPELINE_ID"

        echo -e "${GREEN}✓ Deleted pipeline: $PIPELINE_ID${NC}"
    done
else
    echo -e "${YELLOW}No pipelines found with name $PIPELINE_NAME (may already be deleted)${NC}"
fi
echo ""

# Step 3: Find and terminate EC2 instances created by Data Pipeline
echo -e "${YELLOW}Step 3: Finding and terminating Data Pipeline EC2 instances${NC}"
echo "Searching for instances with tag: Name=$DEMO_INSTANCE_TAG"
echo "Searching in region: $CURRENT_REGION"
echo ""

# Find instances by tag (all states)
ALL_INSTANCES=$(aws ec2 describe-instances \
    --region $CURRENT_REGION \
    --filters "Name=tag:Name,Values=$DEMO_INSTANCE_TAG" \
    --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
    --output text)

if [ -n "$ALL_INSTANCES" ]; then
    echo "Found instances (all states):"
    echo "$ALL_INSTANCES"
    echo ""
fi

# Find instances that can be terminated
INSTANCE_IDS=$(aws ec2 describe-instances \
    --region $CURRENT_REGION \
    --filters "Name=tag:Name,Values=$DEMO_INSTANCE_TAG" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text)

if [ -z "$INSTANCE_IDS" ]; then
    echo -e "${YELLOW}No active Data Pipeline instances found (may already be terminated)${NC}"
else
    echo "Found active instances to terminate: $INSTANCE_IDS"

    # Terminate each instance
    for INSTANCE_ID in $INSTANCE_IDS; do
        echo "Terminating instance: $INSTANCE_ID"
        aws ec2 terminate-instances \
            --region $CURRENT_REGION \
            --instance-ids $INSTANCE_ID \
            --output text > /dev/null
        echo -e "${GREEN}✓ Terminated instance: $INSTANCE_ID${NC}"
    done

    echo ""
    echo "Waiting for instances to terminate (this may take a minute)..."
    for INSTANCE_ID in $INSTANCE_IDS; do
        aws ec2 wait instance-terminated \
            --region $CURRENT_REGION \
            --instance-ids $INSTANCE_ID 2>/dev/null || true
    done
    echo -e "${GREEN}✓ All instances terminated${NC}"
fi
echo ""

# Step 4: Delete exfiltrated file from exfil bucket
echo -e "${YELLOW}Step 4: Deleting exfiltrated file from exfil bucket${NC}"

if [ -n "$EXFIL_BUCKET" ] && [ "$EXFIL_BUCKET" != "null" ]; then
    echo "Exfil bucket: $EXFIL_BUCKET"

    # Check if the exfiltrated file exists
    if aws s3 ls s3://$EXFIL_BUCKET/exfiltrated.txt --region $CURRENT_REGION &> /dev/null; then
        # Delete the exfiltrated file
        aws s3 rm s3://$EXFIL_BUCKET/exfiltrated.txt --region $CURRENT_REGION
        echo -e "${GREEN}✓ Deleted exfiltrated file: s3://$EXFIL_BUCKET/exfiltrated.txt${NC}"
    else
        echo -e "${YELLOW}Exfiltrated file not found in bucket (may already be deleted or never created)${NC}"
    fi
else
    echo -e "${YELLOW}Could not determine exfil bucket name from Terraform outputs${NC}"
    echo "If the exfiltrated file exists, you may need to delete it manually"
fi
echo ""

# Step 5: Clean up local temporary files
echo -e "${YELLOW}Step 5: Cleaning up local temporary files${NC}"
LOCAL_FILES=("/tmp/pipeline_definition.json" "/tmp/pipeline_put_result.json")

FILES_REMOVED=false
for FILE in "${LOCAL_FILES[@]}"; do
    if [ -f "$FILE" ]; then
        rm -f "$FILE"
        echo "Removed: $FILE"
        FILES_REMOVED=true
    fi
done

if [ "$FILES_REMOVED" = false ]; then
    echo -e "${YELLOW}No local temporary files found (may already be cleaned up)${NC}"
else
    echo -e "${GREEN}✓ Cleaned up local files${NC}"
fi
echo ""

# Step 6: Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Deleted Data Pipeline: $PIPELINE_NAME"
echo "- Terminated EC2 instances created by the pipeline"
echo "- Deleted exfiltrated file from exfil bucket"
echo "- Cleaned up local temporary files"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, and buckets) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
