#!/bin/bash

# Cleanup script for iam:PassRole + elasticmapreduce:RunJobFlow privilege escalation demo
# This script detaches the AdministratorAccess policy and terminates any lingering EMR clusters

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-emr-001-to-admin-starting-user"
EMR_CLUSTER_NAME="pl-prod-emr-001-to-admin-privesc-cluster"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: IAM PassRole + EMR RunJobFlow Demo${NC}"
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

# Step 2: Detach AdministratorAccess policy from starting user
echo -e "${YELLOW}Step 2: Detaching AdministratorAccess policy from user${NC}"
echo "User: $STARTING_USER"

# Check if the policy is attached
if aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' \
    --output text | grep -q "AdministratorAccess"; then

    echo "Found AdministratorAccess policy attached to $STARTING_USER"

    # Detach the policy
    aws iam detach-user-policy \
        --user-name $STARTING_USER \
        --policy-arn arn:aws:iam::aws:policy/AdministratorAccess

    echo -e "${GREEN}✓ Detached AdministratorAccess policy from $STARTING_USER${NC}"
else
    echo -e "${YELLOW}AdministratorAccess policy not attached to $STARTING_USER (may already be detached)${NC}"
fi
echo ""

# Step 3: Terminate any lingering EMR clusters matching the name pattern
echo -e "${YELLOW}Step 3: Checking for lingering EMR clusters${NC}"
echo "Cluster name pattern: $EMR_CLUSTER_NAME"
echo "Region: $CURRENT_REGION"

# List active clusters and find any matching our name
ACTIVE_CLUSTERS=$(aws emr list-clusters \
    --region $CURRENT_REGION \
    --active \
    --query "Clusters[?Name=='$EMR_CLUSTER_NAME'].Id" \
    --output text 2>/dev/null)

if [ -n "$ACTIVE_CLUSTERS" ]; then
    echo "Found active EMR clusters to terminate: $ACTIVE_CLUSTERS"

    for CLUSTER_ID in $ACTIVE_CLUSTERS; do
        echo "Terminating cluster: $CLUSTER_ID"
        aws emr terminate-clusters \
            --region $CURRENT_REGION \
            --cluster-ids $CLUSTER_ID
        echo -e "${GREEN}✓ Terminated cluster: $CLUSTER_ID${NC}"
    done

    echo ""
    echo "Waiting for clusters to terminate (this may take a few minutes)..."
    for CLUSTER_ID in $ACTIVE_CLUSTERS; do
        aws emr wait cluster-terminated \
            --region $CURRENT_REGION \
            --cluster-id $CLUSTER_ID 2>/dev/null || true
    done
    echo -e "${GREEN}✓ All clusters terminated${NC}"
else
    echo -e "${YELLOW}No active EMR clusters found matching '$EMR_CLUSTER_NAME' (already terminated or auto-terminated)${NC}"
fi
echo ""

# Step 4: Verify cleanup
echo -e "${YELLOW}Step 4: Verifying cleanup${NC}"

# Check that the policy is detached
if aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[?PolicyArn==`arn:aws:iam::aws:policy/AdministratorAccess`]' \
    --output text | grep -q "AdministratorAccess"; then
    echo -e "${YELLOW}Warning: AdministratorAccess policy still attached to $STARTING_USER${NC}"
else
    echo -e "${GREEN}✓ AdministratorAccess policy successfully detached${NC}"
fi

# Check that no active clusters remain
REMAINING_CLUSTERS=$(aws emr list-clusters \
    --region $CURRENT_REGION \
    --active \
    --query "Clusters[?Name=='$EMR_CLUSTER_NAME'].Id" \
    --output text 2>/dev/null)

if [ -n "$REMAINING_CLUSTERS" ]; then
    echo -e "${YELLOW}Warning: Active EMR clusters still found: $REMAINING_CLUSTERS${NC}"
else
    echo -e "${GREEN}✓ No active EMR clusters remaining${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Detached AdministratorAccess policy from: $STARTING_USER"
echo "- Terminated any lingering EMR clusters matching: $EMR_CLUSTER_NAME"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users and roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
