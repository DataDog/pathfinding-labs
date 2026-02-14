#!/bin/bash

# Cleanup script for ec2:ModifyInstanceAttribute privilege escalation demo
# This script restores the EC2 instance to its original state


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
TARGET_INSTANCE_TAG="pl-prod-ec2-002-to-admin-target-instance"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}EC2 ModifyInstanceAttribute Demo Cleanup${NC}"
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

# Step 2: Find the target EC2 instance
echo -e "${YELLOW}Step 2: Finding target EC2 instance${NC}"
INSTANCE_ID=$(aws ec2 describe-instances \
    --region $CURRENT_REGION \
    --filters "Name=tag:Name,Values=$TARGET_INSTANCE_TAG" "Name=instance-state-name,Values=running,stopped,stopping,pending" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text)

if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
    echo -e "${YELLOW}Target instance not found (may not exist or already terminated)${NC}"
    echo -e "${GREEN}✓ Nothing to clean up${NC}\n"
else
    echo "Found target instance: $INSTANCE_ID"

    # Get current state
    CURRENT_STATE=$(aws ec2 describe-instances \
        --region $CURRENT_REGION \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text)

    echo "Current state: $CURRENT_STATE"
    echo -e "${GREEN}✓ Found instance${NC}\n"

    # Step 3: Restore original user data if backup exists
    echo -e "${YELLOW}Step 3: Checking for user data backup${NC}"

    if [ -f /tmp/original_userdata.b64 ]; then
        echo "Found backup file: /tmp/original_userdata.b64"

        # Stop instance if running
        if [ "$CURRENT_STATE" = "running" ]; then
            echo "Stopping instance to restore user data..."
            aws ec2 stop-instances \
                --region $CURRENT_REGION \
                --instance-ids $INSTANCE_ID \
                --output text > /dev/null

            echo "Waiting for instance to stop..."
            aws ec2 wait instance-stopped \
                --region $CURRENT_REGION \
                --instance-ids $INSTANCE_ID

            echo -e "${GREEN}✓ Instance stopped${NC}"
        fi

        # Restore original user data
        ORIGINAL_DATA=$(cat /tmp/original_userdata.b64)
        if [ -n "$ORIGINAL_DATA" ]; then
            # Save to temp file for AWS CLI
            echo "$ORIGINAL_DATA" > /tmp/restore_userdata.b64
            aws ec2 modify-instance-attribute \
                --region $CURRENT_REGION \
                --instance-id $INSTANCE_ID \
                --attribute userData \
                --value "file:///tmp/restore_userdata.b64"
            rm -f /tmp/restore_userdata.b64
            echo -e "${GREEN}✓ Restored original user data${NC}"
        else
            # Clear user data if it was originally empty
            aws ec2 modify-instance-attribute \
                --region $CURRENT_REGION \
                --instance-id $INSTANCE_ID \
                --attribute userData \
                --value ""
            echo -e "${GREEN}✓ Cleared user data (was originally empty)${NC}"
        fi

        # Remove backup files
        rm -f /tmp/original_userdata.b64
        rm -f /tmp/malicious_userdata.b64
        echo -e "${GREEN}✓ Removed backup files${NC}"
    else
        echo -e "${YELLOW}No backup file found at /tmp/original_userdata.b64${NC}"
        echo "If user data was modified, you may need to manually restore it"
        echo "or redeploy the scenario"
    fi
    echo ""

    # Step 4: Ensure instance is in running state
    echo -e "${YELLOW}Step 4: Ensuring instance is in running state${NC}"

    CURRENT_STATE=$(aws ec2 describe-instances \
        --region $CURRENT_REGION \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text)

    if [ "$CURRENT_STATE" != "running" ]; then
        echo "Starting instance..."
        aws ec2 start-instances \
            --region $CURRENT_REGION \
            --instance-ids $INSTANCE_ID \
            --output text > /dev/null

        echo "Waiting for instance to start..."
        aws ec2 wait instance-running \
            --region $CURRENT_REGION \
            --instance-ids $INSTANCE_ID

        echo -e "${GREEN}✓ Instance started${NC}"
    else
        echo "Instance already running"
        echo -e "${GREEN}✓ Instance is running${NC}"
    fi
    echo ""
fi

# Step 5: Clean up temporary files
echo -e "${YELLOW}Step 5: Cleaning up temporary files${NC}"
rm -f /tmp/original_userdata.b64
echo -e "${GREEN}✓ Cleaned up temporary files${NC}\n"

# Step 6: Verify cleanup
echo -e "${YELLOW}Step 6: Verifying cleanup${NC}"

if [ -n "$INSTANCE_ID" ] && [ "$INSTANCE_ID" != "None" ]; then
    FINAL_STATE=$(aws ec2 describe-instances \
        --region $CURRENT_REGION \
        --instance-ids $INSTANCE_ID \
        --query 'Reservations[0].Instances[0].State.Name' \
        --output text)

    if [ "$FINAL_STATE" = "running" ]; then
        echo -e "${GREEN}✓ Instance is running: $INSTANCE_ID${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: Instance is in state: $FINAL_STATE${NC}"
    fi
fi

if [ ! -f /tmp/original_userdata.b64 ]; then
    echo -e "${GREEN}✓ No temporary files remaining${NC}"
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- Restored original user data (if backup existed)"
echo "- Ensured instance is in running state"
echo "- Cleaned up temporary files"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The infrastructure (users, roles, and EC2 instance) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
