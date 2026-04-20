#!/bin/bash

# Cleanup script for prod_role_with_multiple_privesc_paths module
# This script removes all changes made by the demo_attack.sh script


# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Source demo permissions library for safety restore
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"

# Safety: remove any orphaned restriction policies
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

echo -e "${YELLOW}=== Pathfinding-labs Multiple Privilege Escalation Cleanup ===${NC}"
echo "This script cleans up all changes made by the demo_attack.sh script"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

# Navigate to the Terraform root directory (6 levels up from scenario directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_ROOT="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"

echo "🔍 Retrieving admin credentials from Terraform outputs..."
cd "$TERRAFORM_ROOT"

# Get admin credentials from Terraform outputs
ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

if [ -z "$ADMIN_ACCESS_KEY" ] || [ -z "$ADMIN_SECRET_KEY" ]; then
    echo -e "${RED}❌ Error: Could not retrieve admin credentials from Terraform outputs.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Retrieved admin credentials from Terraform${NC}"

# Set environment variables for admin user
export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
export AWS_DEFAULT_REGION="us-west-2"

# Check if the role exists
ROLE_NAME="pl-prod-role-with-multiple-privesc-paths"
echo -e "${YELLOW}Step 1: Checking if role exists${NC}"
if aws iam get-role --role-name "$ROLE_NAME" &> /dev/null; then
    echo -e "${GREEN}✓ Role $ROLE_NAME exists${NC}"
else
    echo -e "${RED}✗ Role $ROLE_NAME not found. Nothing to clean up.${NC}"
    exit 0
fi

# Get the role ARN
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)
echo "Role ARN: $ROLE_ARN"

echo ""
echo -e "${YELLOW}Step 2: Using admin credentials from Terraform${NC}"
echo -e "${GREEN}✓ Admin credentials configured${NC}"

echo ""
echo -e "${BLUE}=== Cleaning up EC2 Resources ===${NC}"
echo -e "${YELLOW}Step 3: Terminating EC2 instances${NC}"

# Find and terminate EC2 instances (look for instances with demo tags)
INSTANCE_IDS=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=privesc-demo-ec2" "Name=instance-state-name,Values=running,pending" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text \
    --region us-west-2 \
    --profile "$PROFILE")

if [ -n "$INSTANCE_IDS" ] && [ "$INSTANCE_IDS" != "None" ]; then
    echo "Found EC2 instances to terminate: $INSTANCE_IDS"
    aws ec2 terminate-instances --instance-ids $INSTANCE_IDS --region us-west-2     echo "Waiting for instances to terminate..."
    #aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS --region us-west-2     echo -e "${GREEN}✓ EC2 instances terminated${NC}"
else
    echo -e "${GREEN}✓ No EC2 instances found to terminate${NC}"
fi

echo ""
echo -e "${BLUE}=== Cleaning up Lambda Resources ===${NC}"
echo -e "${YELLOW}Step 4: Deleting Lambda functions${NC}"

# Delete Lambda function
if aws lambda get-function --function-name privesc-demo-lambda --region us-west-2 --profile "$PROFILE" &> /dev/null; then
    aws lambda delete-function --function-name privesc-demo-lambda --region us-west-2     echo -e "${GREEN}✓ Lambda function deleted${NC}"
else
    echo -e "${GREEN}✓ Lambda function not found (already deleted)${NC}"
fi

echo ""
echo -e "${BLUE}=== Cleaning up CloudFormation Resources ===${NC}"
echo -e "${YELLOW}Step 5: Deleting CloudFormation stack${NC}"

# Delete CloudFormation stack
if aws cloudformation describe-stacks --stack-name privesc-demo-cf-stack --region us-west-2 --profile "$PROFILE" &> /dev/null; then
    aws cloudformation delete-stack --stack-name privesc-demo-cf-stack --region us-west-2     echo "Waiting for CloudFormation stack to be deleted..."
    aws cloudformation wait stack-delete-complete --stack-name privesc-demo-cf-stack --region us-west-2     echo -e "${GREEN}✓ CloudFormation stack deleted${NC}"
else
    echo -e "${GREEN}✓ CloudFormation stack not found (already deleted)${NC}"
fi

echo ""
echo -e "${BLUE}=== Cleaning up Created Admin Roles ===${NC}"
echo -e "${YELLOW}Step 6: Removing created admin roles${NC}"

# List of roles that might have been created
ROLES_TO_DELETE=(
    "privesc-demo-ec2-admin-role"
    "privesc-demo-lambda-admin-role"
    "privesc-demo-cf-admin-role"
)

for role in "${ROLES_TO_DELETE[@]}"; do
    if aws iam get-role --role-name "$role" --profile "$PROFILE" &> /dev/null; then
        echo "Deleting role: $role"
        
        # Detach all policies first
        ATTACHED_POLICIES=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text --profile "$PROFILE")
        for policy in $ATTACHED_POLICIES; do
            if [ -n "$policy" ] && [ "$policy" != "None" ]; then
                aws iam detach-role-policy --role-name "$role" --policy-arn "$policy"
            fi
        done

        # Delete inline policies
        INLINE_POLICIES=$(aws iam list-role-policies --role-name "$role" --query 'PolicyNames' --output text --profile "$PROFILE")
        for policy in $INLINE_POLICIES; do
            if [ -n "$policy" ] && [ "$policy" != "None" ]; then
                aws iam delete-role-policy --role-name "$role" --policy-name "$policy"
            fi
        done

        # Delete the role
        aws iam delete-role --role-name "$role"
        echo -e "${GREEN}✓ Deleted role: $role${NC}"
    else
        echo -e "${GREEN}✓ Role $role not found (already deleted)${NC}"
    fi
done

echo ""
echo -e "${YELLOW}Step 7: Final verification${NC}"
echo "Checking for any remaining resources..."

# Check for any remaining EC2 instances
REMAINING_INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=privesc-demo-ec2" "Name=instance-state-name,Values=running,pending" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text \
    --region us-west-2 \
    --profile "$PROFILE")

if [ -n "$REMAINING_INSTANCES" ] && [ "$REMAINING_INSTANCES" != "None" ]; then
    echo -e "${YELLOW}⚠ Warning: Some EC2 instances may still be running: $REMAINING_INSTANCES${NC}"
else
    echo -e "${GREEN}✓ No remaining EC2 instances${NC}"
fi

# Check for any remaining Lambda functions
if aws lambda get-function --function-name privesc-demo-lambda --region us-west-2 --profile "$PROFILE" &> /dev/null; then
    echo -e "${YELLOW}⚠ Warning: Lambda function may still exist${NC}"
else
    echo -e "${GREEN}✓ No remaining Lambda functions${NC}"
fi

# Check for any remaining CloudFormation stacks
if aws cloudformation describe-stacks --stack-name privesc-demo-cf-stack --region us-west-2 --profile "$PROFILE" &> /dev/null; then
    echo -e "${YELLOW}⚠ Warning: CloudFormation stack may still exist${NC}"
else
    echo -e "${GREEN}✓ No remaining CloudFormation stacks${NC}"
fi

echo ""
echo -e "${GREEN}=== Cleanup Complete ===${NC}"
echo "All resources created by the demo have been cleaned up."
echo "The original module resources remain intact."

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
