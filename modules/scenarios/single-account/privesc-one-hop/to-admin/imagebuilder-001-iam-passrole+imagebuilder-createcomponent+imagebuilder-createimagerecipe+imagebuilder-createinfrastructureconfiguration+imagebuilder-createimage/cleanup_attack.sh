#!/bin/bash
set -e

# Cleanup script for iam:PassRole + EC2 Image Builder privilege escalation demo
# This script detaches AdministratorAccess from the starting user, cancels in-progress
# image builds, and deletes Image Builder resources (images, recipes, components,
# infrastructure configurations), along with any AMIs and EBS snapshots created.

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-imagebuilder-001-to-admin-starting-user"
COMPONENT_NAME="pl-prod-imagebuilder-001-to-admin-component"
RECIPE_NAME="pl-prod-imagebuilder-001-to-admin-recipe"
INFRA_CONFIG_NAME="pl-prod-imagebuilder-001-to-admin-infra-config"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: PassRole + EC2 Image Builder${NC}"
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

# Navigate back to scenario directory
cd - > /dev/null

# Source demo permissions library
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Safety: remove any orphaned restriction policies
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Detach AdministratorAccess from starting user
echo -e "${YELLOW}Step 2: Detaching AdministratorAccess policy from starting user${NC}"
echo "User: $STARTING_USER"

ADMIN_POLICY_ARN="arn:aws:iam::aws:policy/AdministratorAccess"

if aws iam list-attached-user-policies --user-name "$STARTING_USER" --query "AttachedPolicies[?PolicyArn=='$ADMIN_POLICY_ARN'].PolicyName" --output text 2>/dev/null | grep -q "AdministratorAccess"; then
    aws iam detach-user-policy \
        --user-name "$STARTING_USER" \
        --policy-arn "$ADMIN_POLICY_ARN"
    echo -e "${GREEN}✓ Detached AdministratorAccess from $STARTING_USER${NC}"
else
    echo -e "${YELLOW}AdministratorAccess not attached to $STARTING_USER (may already be detached)${NC}"
fi
echo ""

# Step 3: Cancel in-progress image builds and delete images
echo -e "${YELLOW}Step 3: Finding and deleting Image Builder images${NC}"
echo "Searching for images in region: $CURRENT_REGION"

# List image build versions owned by this account that match our recipe pattern
# Image Builder images are identified by ARN; we search by owner and filter by name
IMAGE_ARNS=$(aws imagebuilder list-images \
    --region $CURRENT_REGION \
    --owner Self \
    --query "imageVersionList[?starts_with(name, '$RECIPE_NAME')].arn" \
    --output text 2>/dev/null)

if [ -n "$IMAGE_ARNS" ] && [ "$IMAGE_ARNS" != "None" ]; then
    for IMAGE_VERSION_ARN in $IMAGE_ARNS; do
        echo "Found image version: $IMAGE_VERSION_ARN"

        # List build versions for this image
        BUILD_VERSION_ARNS=$(aws imagebuilder list-image-build-versions \
            --region $CURRENT_REGION \
            --image-version-arn "$IMAGE_VERSION_ARN" \
            --query 'imageSummaryList[*].arn' \
            --output text 2>/dev/null)

        if [ -n "$BUILD_VERSION_ARNS" ] && [ "$BUILD_VERSION_ARNS" != "None" ]; then
            for BUILD_ARN in $BUILD_VERSION_ARNS; do
                echo "  Build version: $BUILD_ARN"

                # Check build status
                BUILD_STATUS=$(aws imagebuilder get-image \
                    --region $CURRENT_REGION \
                    --image-build-version-arn "$BUILD_ARN" \
                    --query 'image.state.status' \
                    --output text 2>/dev/null)

                echo "  Status: $BUILD_STATUS"

                # Cancel if in progress
                if [ "$BUILD_STATUS" == "PENDING" ] || [ "$BUILD_STATUS" == "BUILDING" ] || [ "$BUILD_STATUS" == "TESTING" ] || [ "$BUILD_STATUS" == "DISTRIBUTING" ]; then
                    echo "  Cancelling in-progress build..."
                    aws imagebuilder cancel-image-creation \
                        --region $CURRENT_REGION \
                        --image-build-version-arn "$BUILD_ARN" 2>/dev/null || true
                    echo "  Waiting 15 seconds for cancellation..."
                    sleep 15
                fi

                # Get AMI ID if the build produced one
                OUTPUT_AMI=$(aws imagebuilder get-image \
                    --region $CURRENT_REGION \
                    --image-build-version-arn "$BUILD_ARN" \
                    --query 'image.outputResources.amis[0].image' \
                    --output text 2>/dev/null)

                if [ -n "$OUTPUT_AMI" ] && [ "$OUTPUT_AMI" != "None" ]; then
                    echo "  Output AMI: $OUTPUT_AMI"

                    # Get snapshots associated with this AMI before deregistering
                    SNAPSHOT_IDS=$(aws ec2 describe-images \
                        --region $CURRENT_REGION \
                        --image-ids "$OUTPUT_AMI" \
                        --query 'Images[0].BlockDeviceMappings[*].Ebs.SnapshotId' \
                        --output text 2>/dev/null)

                    # Deregister the AMI
                    echo "  Deregistering AMI: $OUTPUT_AMI"
                    aws ec2 deregister-image \
                        --region $CURRENT_REGION \
                        --image-id "$OUTPUT_AMI" 2>/dev/null

                    if [ $? -eq 0 ]; then
                        echo -e "  ${GREEN}✓ Deregistered AMI: $OUTPUT_AMI${NC}"
                    else
                        echo -e "  ${YELLOW}⚠ Could not deregister AMI: $OUTPUT_AMI${NC}"
                    fi

                    # Delete associated snapshots
                    if [ -n "$SNAPSHOT_IDS" ] && [ "$SNAPSHOT_IDS" != "None" ]; then
                        for SNAP_ID in $SNAPSHOT_IDS; do
                            echo "  Deleting snapshot: $SNAP_ID"
                            aws ec2 delete-snapshot \
                                --region $CURRENT_REGION \
                                --snapshot-id "$SNAP_ID" 2>/dev/null

                            if [ $? -eq 0 ]; then
                                echo -e "  ${GREEN}✓ Deleted snapshot: $SNAP_ID${NC}"
                            else
                                echo -e "  ${YELLOW}⚠ Could not delete snapshot: $SNAP_ID${NC}"
                            fi
                        done
                    fi
                fi

                # Delete the image build version
                echo "  Deleting image build version..."
                aws imagebuilder delete-image \
                    --region $CURRENT_REGION \
                    --image-build-version-arn "$BUILD_ARN" 2>/dev/null

                if [ $? -eq 0 ]; then
                    echo -e "  ${GREEN}✓ Deleted image build: $BUILD_ARN${NC}"
                else
                    echo -e "  ${YELLOW}⚠ Could not delete image build (may need manual cleanup)${NC}"
                fi
            done
        fi
    done
else
    echo -e "${YELLOW}No Image Builder images found matching $RECIPE_NAME (may already be deleted)${NC}"
fi
echo ""

# Step 4: Delete image recipes
echo -e "${YELLOW}Step 4: Deleting Image Builder recipes${NC}"
echo "Looking for recipes matching: $RECIPE_NAME"

RECIPE_ARNS=$(aws imagebuilder list-image-recipes \
    --region $CURRENT_REGION \
    --owner Self \
    --query "imageRecipeSummaryList[?starts_with(name, '$RECIPE_NAME')].arn" \
    --output text 2>/dev/null)

if [ -n "$RECIPE_ARNS" ] && [ "$RECIPE_ARNS" != "None" ]; then
    for RECIPE_ARN in $RECIPE_ARNS; do
        echo "Deleting recipe: $RECIPE_ARN"
        aws imagebuilder delete-image-recipe \
            --region $CURRENT_REGION \
            --image-recipe-arn "$RECIPE_ARN" 2>/dev/null

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Deleted recipe: $RECIPE_ARN${NC}"
        else
            echo -e "${YELLOW}⚠ Could not delete recipe (may have dependent images)${NC}"
        fi
    done
else
    echo -e "${YELLOW}No Image Builder recipes found matching $RECIPE_NAME (may already be deleted)${NC}"
fi
echo ""

# Step 5: Delete infrastructure configurations
echo -e "${YELLOW}Step 5: Deleting Image Builder infrastructure configurations${NC}"
echo "Looking for configs matching: $INFRA_CONFIG_NAME"

INFRA_ARNS=$(aws imagebuilder list-infrastructure-configurations \
    --region $CURRENT_REGION \
    --query "infrastructureConfigurationSummaryList[?starts_with(name, '$INFRA_CONFIG_NAME')].arn" \
    --output text 2>/dev/null)

if [ -n "$INFRA_ARNS" ] && [ "$INFRA_ARNS" != "None" ]; then
    for INFRA_ARN in $INFRA_ARNS; do
        echo "Deleting infrastructure configuration: $INFRA_ARN"
        aws imagebuilder delete-infrastructure-configuration \
            --region $CURRENT_REGION \
            --infrastructure-configuration-arn "$INFRA_ARN" 2>/dev/null

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Deleted infrastructure configuration: $INFRA_ARN${NC}"
        else
            echo -e "${YELLOW}⚠ Could not delete infrastructure configuration${NC}"
        fi
    done
else
    echo -e "${YELLOW}No infrastructure configurations found matching $INFRA_CONFIG_NAME (may already be deleted)${NC}"
fi
echo ""

# Step 6: Delete components
echo -e "${YELLOW}Step 6: Deleting Image Builder components${NC}"
echo "Looking for components matching: $COMPONENT_NAME"

COMPONENT_VERSION_ARNS=$(aws imagebuilder list-components \
    --region $CURRENT_REGION \
    --owner Self \
    --query "componentVersionList[?starts_with(name, '$COMPONENT_NAME')].arn" \
    --output text 2>/dev/null)

if [ -n "$COMPONENT_VERSION_ARNS" ] && [ "$COMPONENT_VERSION_ARNS" != "None" ]; then
    for COMP_VERSION_ARN in $COMPONENT_VERSION_ARNS; do
        echo "Found component version: $COMP_VERSION_ARN"

        # List build versions for this component
        COMP_BUILD_ARNS=$(aws imagebuilder list-component-build-versions \
            --region $CURRENT_REGION \
            --component-version-arn "$COMP_VERSION_ARN" \
            --query 'componentSummaryList[*].arn' \
            --output text 2>/dev/null)

        if [ -n "$COMP_BUILD_ARNS" ] && [ "$COMP_BUILD_ARNS" != "None" ]; then
            for COMP_BUILD_ARN in $COMP_BUILD_ARNS; do
                echo "  Deleting component build version: $COMP_BUILD_ARN"
                aws imagebuilder delete-component \
                    --region $CURRENT_REGION \
                    --component-build-version-arn "$COMP_BUILD_ARN" 2>/dev/null

                if [ $? -eq 0 ]; then
                    echo -e "  ${GREEN}✓ Deleted component: $COMP_BUILD_ARN${NC}"
                else
                    echo -e "  ${YELLOW}⚠ Could not delete component (may be referenced by a recipe)${NC}"
                fi
            done
        fi
    done
else
    echo -e "${YELLOW}No Image Builder components found matching $COMPONENT_NAME (may already be deleted)${NC}"
fi
echo ""

# Step 7: Clean up local temporary files
echo -e "${YELLOW}Step 7: Cleaning up local temporary files${NC}"
LOCAL_FILES=("/tmp/imagebuilder-component.yaml")

FILES_DELETED=false
for FILE in "${LOCAL_FILES[@]}"; do
    if [ -f "$FILE" ]; then
        rm -f "$FILE"
        echo "Removed: $FILE"
        FILES_DELETED=true
    fi
done

if [ "$FILES_DELETED" = false ]; then
    echo "No local temporary files found"
fi

echo -e "${GREEN}✓ Cleaned up local files${NC}"
echo ""

# Step 8: Verify cleanup
echo -e "${YELLOW}Step 8: Verifying cleanup${NC}"

# Check that AdministratorAccess is detached
if aws iam list-attached-user-policies --user-name "$STARTING_USER" --query "AttachedPolicies[?PolicyArn=='$ADMIN_POLICY_ARN'].PolicyName" --output text 2>/dev/null | grep -q "AdministratorAccess"; then
    echo -e "${YELLOW}⚠ Warning: AdministratorAccess still attached to $STARTING_USER${NC}"
else
    echo -e "${GREEN}✓ AdministratorAccess successfully detached from $STARTING_USER${NC}"
fi

# Check that images are deleted
REMAINING_IMAGES=$(aws imagebuilder list-images \
    --region $CURRENT_REGION \
    --owner Self \
    --query "imageVersionList[?starts_with(name, '$RECIPE_NAME')].arn" \
    --output text 2>/dev/null)

if [ -z "$REMAINING_IMAGES" ] || [ "$REMAINING_IMAGES" == "None" ]; then
    echo -e "${GREEN}✓ All Image Builder images cleaned up${NC}"
else
    echo -e "${YELLOW}⚠ Some images may still exist (may take time to fully delete)${NC}"
fi

# Check that components are deleted
REMAINING_COMPONENTS=$(aws imagebuilder list-components \
    --region $CURRENT_REGION \
    --owner Self \
    --query "componentVersionList[?starts_with(name, '$COMPONENT_NAME')].arn" \
    --output text 2>/dev/null)

if [ -z "$REMAINING_COMPONENTS" ] || [ "$REMAINING_COMPONENTS" == "None" ]; then
    echo -e "${GREEN}✓ All Image Builder components cleaned up${NC}"
else
    echo -e "${YELLOW}⚠ Some components may still exist${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess from $STARTING_USER"
echo "- Cancelled in-progress image builds"
echo "- Deleted Image Builder images, recipes, infrastructure configs, and components"
echo "- Deregistered AMIs and deleted EBS snapshots created during the build"
echo "- Cleaned up local temporary files"
echo ""
echo -e "${YELLOW}Note: Image Builder resource deletion may take a few moments to fully propagate.${NC}"
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
