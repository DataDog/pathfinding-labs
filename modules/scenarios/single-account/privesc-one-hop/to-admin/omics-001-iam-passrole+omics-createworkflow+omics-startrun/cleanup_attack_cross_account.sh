#!/bin/bash

# Cleanup script for cross-account variant of iam:PassRole + omics:CreateWorkflow + omics:StartRun
# This script detaches AdministratorAccess from the starting user, deletes HealthOmics runs
# and workflows, removes exfiltrated credentials from S3, and cleans up attacker-side resources
# (ECR repo and S3 bucket).

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-omics-001-to-admin-starting-user"
WORKFLOW_NAME="pl-prod-omics-001-to-admin-workflow"
ATTACKER_PROFILE="demo-attacker.AWSAdministratorAccess"
ATTACKER_ECR_REPO_NAME="pl-attacker-omics-001-aws-cli"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: PassRole + HealthOmics CreateWorkflow + StartRun${NC}"
echo -e "${GREEN}(Cross-Account Attacker ECR + S3 Variant)${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Get admin credentials and region from Terraform
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get admin cleanup user credentials from root terraform output
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

# Also get S3 bucket name from the scenario output
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_omics_001_iam_passrole_omics_createworkflow_omics_startrun.value // empty')
S3_BUCKET_NAME=""
if [ -n "$MODULE_OUTPUT" ]; then
    S3_BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.s3_bucket_name // empty')
fi

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
echo "S3 Bucket: ${S3_BUCKET_NAME:-not found}"
echo -e "${GREEN}Retrieved admin credentials${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Detach AdministratorAccess from starting user
echo -e "${YELLOW}Step 2: Detaching AdministratorAccess from starting user${NC}"
echo "User: $STARTING_USER"

ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

if aws iam list-attached-user-policies --user-name "$STARTING_USER" --query "AttachedPolicies[?PolicyArn=='$ADMIN_POLICY_ARN'].PolicyName" --output text 2>/dev/null | grep -q "AdministratorAccess"; then
    aws iam detach-user-policy \
        --user-name "$STARTING_USER" \
        --policy-arn "$ADMIN_POLICY_ARN"
    echo -e "${GREEN}Detached AdministratorAccess from $STARTING_USER${NC}"
else
    echo -e "${YELLOW}AdministratorAccess not attached to $STARTING_USER (may already be detached)${NC}"
fi
echo ""

# Step 3: Delete HealthOmics runs and workflows
echo -e "${YELLOW}Step 3: Finding and deleting HealthOmics workflows and runs${NC}"
echo "Looking for workflows matching: $WORKFLOW_NAME"

# Find all workflows matching our scenario name
WORKFLOW_IDS=$(aws omics list-workflows \
    --region $CURRENT_REGION \
    --type PRIVATE \
    --query "items[?name=='$WORKFLOW_NAME'].id" \
    --output text 2>/dev/null)

if [ -n "$WORKFLOW_IDS" ] && [ "$WORKFLOW_IDS" != "None" ]; then
    for WF_ID in $WORKFLOW_IDS; do
        echo ""
        echo "Processing workflow: $WF_ID"

        # Find and cancel/delete runs associated with this workflow
        RUN_IDS=$(aws omics list-runs \
            --region $CURRENT_REGION \
            --query "items[?workflowId=='$WF_ID'].id" \
            --output text 2>/dev/null)

        if [ -n "$RUN_IDS" ] && [ "$RUN_IDS" != "None" ]; then
            for RID in $RUN_IDS; do
                # Check run state
                RUN_STATE=$(aws omics get-run \
                    --region $CURRENT_REGION \
                    --id "$RID" \
                    --query 'status' \
                    --output text 2>/dev/null)

                echo "Run $RID state: $RUN_STATE"

                # Cancel if still running
                if [ "$RUN_STATE" == "PENDING" ] || [ "$RUN_STATE" == "STARTING" ] || [ "$RUN_STATE" == "RUNNING" ]; then
                    echo "Cancelling run: $RID"
                    aws omics cancel-run \
                        --region $CURRENT_REGION \
                        --id "$RID" 2>/dev/null || true
                    echo "Waiting 15 seconds for cancellation to process..."
                    sleep 15
                fi

                # Delete the run
                echo "Deleting run: $RID"
                aws omics delete-run \
                    --region $CURRENT_REGION \
                    --id "$RID" 2>/dev/null || true
                echo -e "${GREEN}Deleted run: $RID${NC}"
            done
        else
            echo "No runs found for workflow $WF_ID"
        fi

        # Delete the workflow
        echo "Deleting workflow: $WF_ID"
        aws omics delete-workflow \
            --region $CURRENT_REGION \
            --id "$WF_ID" 2>/dev/null

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Deleted HealthOmics workflow: $WF_ID${NC}"
        else
            echo -e "${YELLOW}Could not delete workflow $WF_ID (may need manual cleanup)${NC}"
        fi
    done
else
    echo -e "${YELLOW}No HealthOmics workflows found matching: $WORKFLOW_NAME${NC}"

    # Also check for orphaned runs (in case workflow was already deleted)
    echo "Checking for orphaned runs..."
    ALL_RUNS=$(aws omics list-runs \
        --region $CURRENT_REGION \
        --query "items[?status!='DELETED'].{id:id,status:status}" \
        --output json 2>/dev/null)

    if [ -n "$ALL_RUNS" ] && [ "$ALL_RUNS" != "[]" ] && [ "$ALL_RUNS" != "null" ]; then
        echo "Found runs (review manually if needed):"
        echo "$ALL_RUNS" | jq -r '.[] | "  \(.id) (\(.status))"' 2>/dev/null
    fi
fi
echo ""

# Step 4: Remove exfiltrated credentials and output from victim S3
echo -e "${YELLOW}Step 4: Removing exfiltrated credentials and output from victim S3${NC}"

if [ -n "$S3_BUCKET_NAME" ]; then
    echo "Cleaning all objects from s3://$S3_BUCKET_NAME/"

    OBJECTS=$(aws s3 ls "s3://$S3_BUCKET_NAME/" --region $CURRENT_REGION --recursive 2>/dev/null)
    if [ -n "$OBJECTS" ]; then
        aws s3 rm "s3://$S3_BUCKET_NAME/" \
            --region $CURRENT_REGION \
            --recursive
        echo -e "${GREEN}Removed all objects from victim S3 bucket${NC}"
    else
        echo -e "${YELLOW}No objects found in victim S3 bucket (may already be cleaned)${NC}"
    fi
else
    echo -e "${YELLOW}S3 bucket name not available, skipping victim S3 cleanup${NC}"
fi
echo ""

# Step 5: Delete attacker ECR repo
echo -e "${YELLOW}Step 5: Deleting attacker ECR repository${NC}"

ATTACKER_ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text --profile "$ATTACKER_PROFILE" 2>/dev/null)

if [ -z "$ATTACKER_ACCOUNT_ID" ] || [ "$ATTACKER_ACCOUNT_ID" == "null" ]; then
    echo -e "${YELLOW}Warning: Could not get attacker account ID using profile '$ATTACKER_PROFILE'${NC}"
    echo "Skipping attacker ECR repo cleanup"
else
    echo "Attacker Account ID: $ATTACKER_ACCOUNT_ID"
    echo "ECR Repository: $ATTACKER_ECR_REPO_NAME"

    # Check if repo exists
    if aws ecr describe-repositories \
        --repository-names "$ATTACKER_ECR_REPO_NAME" \
        --region "$CURRENT_REGION" \
        --profile "$ATTACKER_PROFILE" &>/dev/null; then

        echo "Deleting attacker ECR repository (--force removes all images)..."
        aws ecr delete-repository \
            --repository-name "$ATTACKER_ECR_REPO_NAME" \
            --force \
            --region "$CURRENT_REGION" \
            --profile "$ATTACKER_PROFILE" 2>/dev/null

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Deleted attacker ECR repo: $ATTACKER_ECR_REPO_NAME${NC}"
        else
            echo -e "${YELLOW}Warning: Could not delete attacker ECR repo $ATTACKER_ECR_REPO_NAME${NC}"
            echo "  Manual cleanup: aws ecr delete-repository --repository-name $ATTACKER_ECR_REPO_NAME --force --region $CURRENT_REGION --profile $ATTACKER_PROFILE"
        fi
    else
        echo -e "${YELLOW}Attacker ECR repo $ATTACKER_ECR_REPO_NAME not found (may already be deleted)${NC}"
    fi
fi
echo ""

# Step 6: Delete attacker S3 bucket
echo -e "${YELLOW}Step 6: Deleting attacker S3 bucket${NC}"

if [ -n "$ATTACKER_ACCOUNT_ID" ]; then
    ATTACKER_BUCKET_NAME="pl-attacker-omics-001-exfil-${ATTACKER_ACCOUNT_ID}"
    echo "Attacker bucket: $ATTACKER_BUCKET_NAME"

    # Check if bucket exists
    if aws s3api head-bucket --bucket "$ATTACKER_BUCKET_NAME" --profile "$ATTACKER_PROFILE" 2>/dev/null; then
        echo "Removing objects from attacker bucket..."
        aws s3 rm "s3://$ATTACKER_BUCKET_NAME" --recursive --profile "$ATTACKER_PROFILE" 2>/dev/null

        echo "Deleting attacker bucket..."
        aws s3api delete-bucket --bucket "$ATTACKER_BUCKET_NAME" --profile "$ATTACKER_PROFILE" 2>/dev/null

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Deleted attacker bucket: $ATTACKER_BUCKET_NAME${NC}"
        else
            echo -e "${YELLOW}Warning: Could not delete attacker bucket $ATTACKER_BUCKET_NAME${NC}"
            echo "  Manual cleanup: aws s3 rb s3://$ATTACKER_BUCKET_NAME --force --profile $ATTACKER_PROFILE"
        fi
    else
        echo -e "${YELLOW}Attacker bucket $ATTACKER_BUCKET_NAME not found (may already be deleted)${NC}"
    fi
else
    echo -e "${YELLOW}Skipping attacker bucket cleanup (attacker account ID unavailable)${NC}"
fi
echo ""

# Step 7: Clean up local temporary files
echo -e "${YELLOW}Step 7: Cleaning up local temporary files${NC}"
LOCAL_FILES=("/tmp/omics-workflow/main.wdl" "/tmp/omics-workflow.zip" "/tmp/stolen_creds.json")

FILES_DELETED=false
for FILE in "${LOCAL_FILES[@]}"; do
    if [ -f "$FILE" ]; then
        rm -f "$FILE"
        echo "Removed: $FILE"
        FILES_DELETED=true
    fi
done

# Remove the workflow directory if it exists
if [ -d "/tmp/omics-workflow" ]; then
    rm -rf /tmp/omics-workflow
    echo "Removed: /tmp/omics-workflow/"
    FILES_DELETED=true
fi

if [ "$FILES_DELETED" = false ]; then
    echo "No local temporary files found"
fi

echo -e "${GREEN}Cleaned up local files${NC}"
echo ""

# Step 8: Verify cleanup
echo -e "${YELLOW}Step 8: Verifying cleanup${NC}"

# Check that AdministratorAccess is detached
if aws iam list-attached-user-policies --user-name "$STARTING_USER" --query "AttachedPolicies[?PolicyArn=='$ADMIN_POLICY_ARN'].PolicyName" --output text 2>/dev/null | grep -q "AdministratorAccess"; then
    echo -e "${YELLOW}Warning: AdministratorAccess still attached to $STARTING_USER${NC}"
else
    echo -e "${GREEN}AdministratorAccess successfully detached from $STARTING_USER${NC}"
fi

# Check that workflows are deleted
REMAINING_WORKFLOWS=$(aws omics list-workflows \
    --region $CURRENT_REGION \
    --type PRIVATE \
    --query "items[?name=='$WORKFLOW_NAME'].{id:id,status:status}" \
    --output text 2>/dev/null)

if [ -z "$REMAINING_WORKFLOWS" ] || [ "$REMAINING_WORKFLOWS" == "None" ]; then
    echo -e "${GREEN}All HealthOmics workflows deleted${NC}"
else
    echo -e "${YELLOW}Some workflows still present:${NC}"
    echo "$REMAINING_WORKFLOWS"
fi

# Check victim S3 cleanup
if [ -n "$S3_BUCKET_NAME" ]; then
    REMAINING_OBJECTS=$(aws s3 ls "s3://$S3_BUCKET_NAME/" --region $CURRENT_REGION --recursive 2>/dev/null)
    if [ -n "$REMAINING_OBJECTS" ]; then
        echo -e "${YELLOW}Warning: Objects still in victim S3 bucket${NC}"
    else
        echo -e "${GREEN}Victim S3 bucket cleaned${NC}"
    fi
fi

# Check attacker ECR repo
if [ -n "$ATTACKER_ACCOUNT_ID" ]; then
    if aws ecr describe-repositories \
        --repository-names "$ATTACKER_ECR_REPO_NAME" \
        --region "$CURRENT_REGION" \
        --profile "$ATTACKER_PROFILE" &>/dev/null; then
        echo -e "${YELLOW}Warning: Attacker ECR repo still exists: $ATTACKER_ECR_REPO_NAME${NC}"
    else
        echo -e "${GREEN}Attacker ECR repo deleted${NC}"
    fi

    # Check attacker bucket
    if [ -n "$ATTACKER_BUCKET_NAME" ]; then
        if aws s3api head-bucket --bucket "$ATTACKER_BUCKET_NAME" --profile "$ATTACKER_PROFILE" 2>/dev/null; then
            echo -e "${YELLOW}Warning: Attacker bucket still exists: $ATTACKER_BUCKET_NAME${NC}"
        else
            echo -e "${GREEN}Attacker bucket deleted${NC}"
        fi
    fi
fi

echo -e "${GREEN}Local temporary files cleaned up${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess from $STARTING_USER"
echo "- Deleted HealthOmics workflow runs"
echo "- Deleted HealthOmics workflows"
echo "- Removed exfiltrated credentials from victim S3"
echo "- Deleted attacker ECR repository (cross-account)"
echo "- Deleted attacker S3 bucket (cross-account)"
echo "- Cleaned up local temporary files"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
