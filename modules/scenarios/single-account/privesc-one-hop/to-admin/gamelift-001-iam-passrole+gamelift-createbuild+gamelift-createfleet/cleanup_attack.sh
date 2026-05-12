#!/bin/bash

# Cleanup script for iam:PassRole + gamelift:CreateBuild + gamelift:CreateFleet privilege escalation demo
# This script detaches the AdministratorAccess policy from the starting user,
# deletes the GameLift fleet, and deletes the GameLift build.

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-gamelift-001-to-admin-starting-user"
BUILD_NAME="pl-prod-gamelift-001-to-admin-build"
FLEET_NAME="pl-prod-gamelift-001-to-admin-fleet"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: PassRole + GameLift CreateBuild + CreateFleet${NC}"
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

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# Step 2: Detach AdministratorAccess from starting user
echo -e "${YELLOW}Step 2: Detaching AdministratorAccess policy from starting user${NC}"
echo "User: $STARTING_USER"

if aws iam list-attached-user-policies --user-name $STARTING_USER --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' --output text 2>/dev/null | grep -q "AdministratorAccess"; then
    aws iam detach-user-policy \
        --user-name $STARTING_USER \
        --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
    echo -e "${GREEN}✓ Detached AdministratorAccess from $STARTING_USER${NC}"
else
    echo -e "${YELLOW}AdministratorAccess not attached to $STARTING_USER (may already be detached)${NC}"
fi
echo ""

# Step 3: Find and delete GameLift fleets
echo -e "${YELLOW}Step 3: Finding and deleting GameLift fleets${NC}"
echo "Searching for fleets in region: $CURRENT_REGION"

# List all fleets and find ours by name
FLEET_IDS=$(aws gamelift list-fleets \
    --region $CURRENT_REGION \
    --query 'FleetIds' \
    --output json 2>/dev/null)

if [ -n "$FLEET_IDS" ] && [ "$FLEET_IDS" != "[]" ] && [ "$FLEET_IDS" != "null" ]; then
    # Check each fleet to find ours by name
    for FLEET_ID in $(echo "$FLEET_IDS" | jq -r '.[]'); do
        FLEET_ATTRS=$(aws gamelift describe-fleet-attributes \
            --fleet-ids "$FLEET_ID" \
            --region $CURRENT_REGION \
            --query 'FleetAttributes[0]' \
            --output json 2>/dev/null)

        FLEET_FOUND_NAME=$(echo "$FLEET_ATTRS" | jq -r '.Name // empty')
        FLEET_STATUS=$(echo "$FLEET_ATTRS" | jq -r '.Status // empty')

        if [ "$FLEET_FOUND_NAME" == "$FLEET_NAME" ]; then
            echo "Found fleet: $FLEET_ID (Name: $FLEET_FOUND_NAME, Status: $FLEET_STATUS)"

            if [ "$FLEET_STATUS" == "TERMINATED" ]; then
                echo -e "${YELLOW}Fleet $FLEET_ID is already terminated${NC}"
            elif [ "$FLEET_STATUS" == "DELETING" ]; then
                echo -e "${YELLOW}Fleet $FLEET_ID is already deleting${NC}"
            else
                # Wait for fleet to leave transitional states before deleting
                if [ "$FLEET_STATUS" == "ACTIVATING" ] || [ "$FLEET_STATUS" == "BUILDING" ] || [ "$FLEET_STATUS" == "DOWNLOADING" ] || [ "$FLEET_STATUS" == "VALIDATING" ]; then
                    echo "Fleet is in transitional state ($FLEET_STATUS), waiting for it to settle..."
                    WAIT_ELAPSED=0
                    MAX_WAIT=300
                    while [ $WAIT_ELAPSED -lt $MAX_WAIT ]; do
                        sleep 15
                        WAIT_ELAPSED=$((WAIT_ELAPSED + 15))
                        FLEET_STATUS=$(aws gamelift describe-fleet-attributes \
                            --fleet-ids "$FLEET_ID" \
                            --region $CURRENT_REGION \
                            --query 'FleetAttributes[0].Status' \
                            --output text 2>/dev/null)
                        echo "Fleet status: $FLEET_STATUS (${WAIT_ELAPSED}s waited)"
                        if [ "$FLEET_STATUS" == "ACTIVE" ] || [ "$FLEET_STATUS" == "ERROR" ] || [ "$FLEET_STATUS" == "TERMINATED" ] || [ "$FLEET_STATUS" == "DELETING" ]; then
                            break
                        fi
                    done
                fi

                if [ "$FLEET_STATUS" == "TERMINATED" ] || [ "$FLEET_STATUS" == "DELETING" ]; then
                    echo -e "${YELLOW}Fleet $FLEET_ID is already $FLEET_STATUS${NC}"
                else
                    echo "Deleting fleet: $FLEET_ID"
                    aws gamelift delete-fleet \
                        --fleet-id "$FLEET_ID" \
                        --region $CURRENT_REGION 2>/dev/null

                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}✓ Fleet deletion initiated: $FLEET_ID${NC}"
                    else
                        echo -e "${YELLOW}⚠ Could not delete fleet $FLEET_ID${NC}"
                        echo "  aws gamelift delete-fleet --fleet-id $FLEET_ID --region $CURRENT_REGION"
                    fi
                fi
            fi
        fi
    done
else
    echo -e "${YELLOW}No GameLift fleets found in region $CURRENT_REGION${NC}"
fi
echo ""

# Step 4: Find and delete GameLift builds
echo -e "${YELLOW}Step 4: Finding and deleting GameLift builds${NC}"
echo "Searching for builds with name: $BUILD_NAME"

BUILD_LIST=$(aws gamelift list-builds \
    --region $CURRENT_REGION \
    --query "Builds[?Name=='$BUILD_NAME']" \
    --output json 2>/dev/null)

if [ -n "$BUILD_LIST" ] && [ "$BUILD_LIST" != "[]" ] && [ "$BUILD_LIST" != "null" ]; then
    for BUILD_ID in $(echo "$BUILD_LIST" | jq -r '.[].BuildId'); do
        echo "Found build: $BUILD_ID"
        echo "Deleting build: $BUILD_ID"

        aws gamelift delete-build \
            --build-id "$BUILD_ID" \
            --region $CURRENT_REGION 2>/dev/null

        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ Deleted build: $BUILD_ID${NC}"
        else
            echo -e "${YELLOW}⚠ Could not delete build $BUILD_ID${NC}"
            echo "The build may be in use by a fleet. Delete the fleet first, then retry."
        fi
    done
else
    echo -e "${YELLOW}No GameLift builds found with name $BUILD_NAME (may already be deleted)${NC}"
fi
echo ""

# Step 5: Clean up local temporary files
echo -e "${YELLOW}Step 5: Cleaning up local temporary files${NC}"
BUILD_ROOT="/tmp/gamelift-build"

if [ -d "$BUILD_ROOT" ]; then
    rm -rf "$BUILD_ROOT"
    echo "Removed: $BUILD_ROOT"
else
    echo "No local build directory found"
fi
echo -e "${GREEN}✓ Cleaned up local files${NC}"
echo ""

# Step 6: Verify cleanup
echo -e "${YELLOW}Step 6: Verifying cleanup${NC}"

# Check that AdministratorAccess is detached
if aws iam list-attached-user-policies --user-name $STARTING_USER --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' --output text 2>/dev/null | grep -q "AdministratorAccess"; then
    echo -e "${YELLOW}⚠ Warning: AdministratorAccess still attached to $STARTING_USER${NC}"
else
    echo -e "${GREEN}✓ AdministratorAccess policy successfully detached from $STARTING_USER${NC}"
fi

# Check that builds are deleted
REMAINING_BUILDS=$(aws gamelift list-builds \
    --region $CURRENT_REGION \
    --query "Builds[?Name=='$BUILD_NAME'].BuildId" \
    --output text 2>/dev/null)

if [ -n "$REMAINING_BUILDS" ]; then
    echo -e "${YELLOW}⚠ Warning: Some builds still exist: $REMAINING_BUILDS${NC}"
else
    echo -e "${GREEN}✓ All GameLift builds cleaned up${NC}"
fi

# Check local files
if [ -d "$BUILD_ROOT" ]; then
    echo -e "${YELLOW}⚠ Warning: Local build directory still exists: $BUILD_ROOT${NC}"
else
    echo -e "${GREEN}✓ Local temporary files cleaned up${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess from $STARTING_USER"
echo "- Deleted GameLift fleet(s)"
echo "- Deleted GameLift build(s)"
echo "- Cleaned up local temporary files"
echo ""
echo -e "${YELLOW}Note: Fleet termination happens asynchronously and may take several minutes.${NC}"
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
