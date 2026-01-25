#!/bin/bash

# Cleanup script for ecs:ExecuteCommand privilege escalation demo
# This scenario does not create any persistent artifacts - cleanup is minimal

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: ECS ExecuteCommand Scenario${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${YELLOW}Checking for artifacts...${NC}"
echo ""
echo "This scenario only involves:"
echo "  1. Discovering running ECS tasks"
echo "  2. Executing commands to read metadata"
echo "  3. Using existing temporary credentials"
echo ""
echo "No persistent artifacts are created during this attack."
echo ""
echo -e "${GREEN}Completed: No cleanup required${NC}"
echo ""

# Step 1: Get region from Terraform for reference
echo -e "${YELLOW}Step 1: Verifying scenario state from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")

# Get admin cleanup user credentials from root terraform output
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null || echo "")
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null || echo "")

if [ -z "$ADMIN_ACCESS_KEY" ] || [ "$ADMIN_ACCESS_KEY" == "null" ]; then
    echo -e "${YELLOW}Note: Could not find admin cleanup credentials${NC}"
    echo "This is fine - no cleanup actions needed for this scenario"
else
    # Set admin credentials for verification
    export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
    export AWS_REGION="$CURRENT_REGION"
    unset AWS_SESSION_TOKEN

    echo "Region: $CURRENT_REGION"
    echo -e "${GREEN}Completed: Retrieved configuration${NC}"
fi

# Navigate back to scenario directory
cd - > /dev/null

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}CLEANUP COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Summary:${NC}"
echo "- No artifacts were created during the demo"
echo "- The ECS task credentials retrieved were temporary session credentials"
echo "- Those credentials will expire automatically (typically within 1-12 hours)"
echo ""
echo -e "${GREEN}The environment is in its original state.${NC}"
echo -e "${YELLOW}The infrastructure (ECS cluster, service, task, roles) remains deployed${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply${NC}"
echo ""

echo -e "${YELLOW}Security Recommendations:${NC}"
echo "1. Limit ecs:ExecuteCommand to specific clusters/tasks using resource conditions"
echo "2. Use IAM conditions to restrict which principals can execute commands"
echo "3. Avoid assigning overly-privileged roles (like AdministratorAccess) to ECS tasks"
echo "4. Enable CloudTrail logging for ECS ExecuteCommand events"
echo "5. Consider using VPC endpoints to control metadata service access"
echo ""
