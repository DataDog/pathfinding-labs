#!/bin/bash

# Cleanup script for Launch Template Modification privilege escalation demo
# This script terminates instances, restores the original launch template default version,
# and removes the AdministratorAccess policy from the starting user

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-lt-modify-to-admin-starting-user"
VICTIM_TEMPLATE_NAME="pl-prod-lt-modify-to-admin-victim-template"
VICTIM_ASG_NAME="pl-prod-lt-modify-to-admin-victim-asg"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Launch Template Modification${NC}"
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

# Step 2: Scale down Auto Scaling Group to zero
echo -e "${YELLOW}Step 2: Scaling down Auto Scaling Group to zero${NC}"
echo "Setting desired capacity to 0 for: $VICTIM_ASG_NAME"

aws autoscaling set-desired-capacity \
    --region $CURRENT_REGION \
    --auto-scaling-group-name $VICTIM_ASG_NAME \
    --desired-capacity 0 \
    --output text > /dev/null 2>&1 || echo -e "${YELLOW}Warning: Could not set desired capacity (ASG may not exist or already at 0)${NC}"

echo -e "${GREEN}✓ Auto Scaling Group scaled to 0${NC}\n"

# Step 3: Wait for instances to begin terminating
echo -e "${YELLOW}Step 3: Waiting for ASG instances to begin terminating${NC}"
echo "Waiting 30 seconds for ASG to process the capacity change..."
sleep 30
echo -e "${GREEN}✓ Wait complete${NC}\n"

# Step 4: Find and terminate any remaining instances from the ASG
echo -e "${YELLOW}Step 4: Finding and terminating any remaining instances${NC}"
echo "Searching in region: $CURRENT_REGION"
echo ""

# Find instances by ASG tag
ASG_INSTANCES=$(aws autoscaling describe-auto-scaling-groups \
    --region $CURRENT_REGION \
    --auto-scaling-group-names $VICTIM_ASG_NAME \
    --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
    --output text 2>/dev/null || echo "")

if [ -n "$ASG_INSTANCES" ] && [ "$ASG_INSTANCES" != "None" ]; then
    echo "Found instances in ASG: $ASG_INSTANCES"

    for INSTANCE_ID in $ASG_INSTANCES; do
        INSTANCE_STATE=$(aws ec2 describe-instances \
            --region $CURRENT_REGION \
            --instance-ids $INSTANCE_ID \
            --query 'Reservations[0].Instances[0].State.Name' \
            --output text 2>/dev/null || echo "unknown")

        if [ "$INSTANCE_STATE" != "terminated" ] && [ "$INSTANCE_STATE" != "terminating" ]; then
            echo "Terminating instance: $INSTANCE_ID (state: $INSTANCE_STATE)"
            aws ec2 terminate-instances \
                --region $CURRENT_REGION \
                --instance-ids $INSTANCE_ID \
                --output text > /dev/null
            echo -e "${GREEN}✓ Terminated instance: $INSTANCE_ID${NC}"
        else
            echo "Instance $INSTANCE_ID already terminating or terminated"
        fi
    done

    echo ""
    echo "Waiting for instances to terminate (this may take a minute)..."
    for INSTANCE_ID in $ASG_INSTANCES; do
        aws ec2 wait instance-terminated \
            --region $CURRENT_REGION \
            --instance-ids $INSTANCE_ID 2>/dev/null || true
    done
    echo -e "${GREEN}✓ All instances terminated${NC}"
else
    echo -e "${YELLOW}No instances found in ASG (may already be terminated)${NC}"
fi
echo ""

# Step 5: Get launch template information
echo -e "${YELLOW}Step 5: Retrieving launch template information${NC}"

TEMPLATE_INFO=$(aws ec2 describe-launch-templates \
    --region $CURRENT_REGION \
    --launch-template-names $VICTIM_TEMPLATE_NAME \
    --query 'LaunchTemplates[0]' \
    --output json 2>/dev/null || echo "{}")

if [ "$TEMPLATE_INFO" = "{}" ] || [ -z "$TEMPLATE_INFO" ]; then
    echo -e "${RED}Error: Could not find launch template: $VICTIM_TEMPLATE_NAME${NC}"
    echo "The template may have been deleted or renamed"
else
    TEMPLATE_ID=$(echo "$TEMPLATE_INFO" | jq -r '.LaunchTemplateId')
    CURRENT_DEFAULT_VERSION=$(echo "$TEMPLATE_INFO" | jq -r '.DefaultVersionNumber')
    LATEST_VERSION=$(echo "$TEMPLATE_INFO" | jq -r '.LatestVersionNumber')

    echo "Launch Template ID: $TEMPLATE_ID"
    echo "Current Default Version: $CURRENT_DEFAULT_VERSION"
    echo "Latest Version: $LATEST_VERSION"
    echo -e "${GREEN}✓ Retrieved launch template information${NC}\n"

    # Step 6: Restore original launch template default version
    echo -e "${YELLOW}Step 6: Restoring original launch template default version${NC}"

    # The original version should be version 1 (created by Terraform)
    ORIGINAL_VERSION=1

    if [ "$CURRENT_DEFAULT_VERSION" != "$ORIGINAL_VERSION" ]; then
        echo "Restoring default version from $CURRENT_DEFAULT_VERSION to $ORIGINAL_VERSION..."

        aws ec2 modify-launch-template \
            --region $CURRENT_REGION \
            --launch-template-id $TEMPLATE_ID \
            --default-version $ORIGINAL_VERSION \
            --output text > /dev/null

        echo -e "${GREEN}✓ Restored launch template default version to $ORIGINAL_VERSION${NC}"
    else
        echo -e "${YELLOW}Launch template default version is already $ORIGINAL_VERSION${NC}"
    fi
    echo ""

    # Step 7: Delete malicious launch template versions
    echo -e "${YELLOW}Step 7: Cleaning up malicious launch template versions${NC}"

    if [ "$LATEST_VERSION" -gt "$ORIGINAL_VERSION" ]; then
        echo "Deleting versions $((ORIGINAL_VERSION + 1)) through $LATEST_VERSION..."

        for VERSION in $(seq $((ORIGINAL_VERSION + 1)) $LATEST_VERSION); do
            echo "Deleting version: $VERSION"
            aws ec2 delete-launch-template-versions \
                --region $CURRENT_REGION \
                --launch-template-id $TEMPLATE_ID \
                --versions $VERSION \
                --output text > /dev/null 2>&1 || echo -e "${YELLOW}  Warning: Could not delete version $VERSION (may already be deleted)${NC}"
        done

        echo -e "${GREEN}✓ Deleted malicious launch template versions${NC}"
    else
        echo -e "${YELLOW}No additional versions to delete${NC}"
    fi
    echo ""
fi

# Step 8: Detach AdministratorAccess policy from starting user
echo -e "${YELLOW}Step 8: Detaching AdministratorAccess policy from starting user${NC}"
echo "Removing AdministratorAccess policy from: $STARTING_USER"

# Check if the policy is attached
ATTACHED_POLICIES=$(aws iam list-attached-user-policies --user-name $STARTING_USER --query 'AttachedPolicies[?PolicyName==`AdministratorAccess`].PolicyName' --output text 2>/dev/null || echo "")

if [ "$ATTACHED_POLICIES" == "AdministratorAccess" ]; then
    aws iam detach-user-policy \
        --user-name $STARTING_USER \
        --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
    echo -e "${GREEN}✓ Detached AdministratorAccess policy${NC}"
else
    echo -e "${YELLOW}AdministratorAccess policy not attached (may already be detached)${NC}"
fi
echo ""

# Step 9: Verify cleanup
echo -e "${YELLOW}Step 9: Verifying cleanup${NC}"

# Check if AdministratorAccess is still attached
ATTACHED_POLICIES=$(aws iam list-attached-user-policies --user-name $STARTING_USER --query 'AttachedPolicies[?PolicyName==`AdministratorAccess`].PolicyName' --output text 2>/dev/null || echo "")

if [ -z "$ATTACHED_POLICIES" ]; then
    echo -e "${GREEN}✓ AdministratorAccess policy successfully removed${NC}"
else
    echo -e "${RED}⚠ Warning: AdministratorAccess policy may still be attached${NC}"
fi

# Check ASG capacity
ASG_DESIRED=$(aws autoscaling describe-auto-scaling-groups \
    --region $CURRENT_REGION \
    --auto-scaling-group-names $VICTIM_ASG_NAME \
    --query 'AutoScalingGroups[0].DesiredCapacity' \
    --output text 2>/dev/null || echo "unknown")

if [ "$ASG_DESIRED" = "0" ]; then
    echo -e "${GREEN}✓ Auto Scaling Group desired capacity is 0${NC}"
else
    echo -e "${YELLOW}⚠ Warning: ASG desired capacity is $ASG_DESIRED (expected 0)${NC}"
fi

# Check no instances are running
REMAINING_INSTANCES=$(aws autoscaling describe-auto-scaling-groups \
    --region $CURRENT_REGION \
    --auto-scaling-group-names $VICTIM_ASG_NAME \
    --query 'AutoScalingGroups[0].Instances[*].InstanceId' \
    --output text 2>/dev/null || echo "")

if [ -z "$REMAINING_INSTANCES" ] || [ "$REMAINING_INSTANCES" = "None" ]; then
    echo -e "${GREEN}✓ No instances remaining in ASG${NC}"
else
    echo -e "${YELLOW}⚠ Warning: Some instances may still exist: $REMAINING_INSTANCES${NC}"
fi

# Verify launch template default version restored
if [ -n "$TEMPLATE_ID" ]; then
    CURRENT_DEFAULT=$(aws ec2 describe-launch-templates \
        --region $CURRENT_REGION \
        --launch-template-ids $TEMPLATE_ID \
        --query 'LaunchTemplates[0].DefaultVersionNumber' \
        --output text 2>/dev/null || echo "unknown")

    if [ "$CURRENT_DEFAULT" = "1" ]; then
        echo -e "${GREEN}✓ Launch template default version restored to 1${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: Launch template default version is $CURRENT_DEFAULT (expected 1)${NC}"
    fi
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Scaled Auto Scaling Group to 0"
echo "- Terminated all demo instances"
echo "- Restored launch template default version to original (version 1)"
echo "- Deleted malicious launch template versions"
echo "- Detached AdministratorAccess policy from starting user"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, launch template v1, ASG) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"
