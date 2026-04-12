#!/bin/bash

# Cleanup script for: AI-Assisted Cloud Intrusion: 8 Minutes to Admin
# This script removes all artifacts created during the demo_attack.sh run.
#
# Artifacts removed:
#   - EC2 GPU instance (pl-8min-gpu-monster) -- MOST CRITICAL, $3.06/hr
#   - EC2 security group (pl-8min-gpu-sg)
#   - EC2 keypair (pl-8min-gpu-key)
#   - IAM user backdoor-admin and all its access keys
#   - Access keys created for pl-prod-8min-frick (via Lambda injection)
#   - Access keys created for pl-prod-8min-rocker
#   - Access keys created for pl-prod-8min-admingh (first attempt)
#   - Access keys created for identity-spreading users (azureadmanager, deploy-svc, monitoring, ci-runner)
#   - Lambda function code restored to original innocent implementation
#   - Lambda timeout restored to 3 seconds
#   - Local temp files

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}Cleanup: AI-Assisted Cloud Intrusion — 8 Minutes to Admin${NC}"
echo -e "${GREEN}============================================================${NC}\n"
echo -e "${RED}PRIORITY: Terminating GPU instance first to stop billing charges.${NC}\n"

# Source demo permissions library for safety restore
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../scripts/lib/demo_permissions.sh"

# Safety restore: remove any orphaned permission restriction policies from the demo
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# =============================================================================
# Step 1: Get admin credentials and region from Terraform
# =============================================================================
echo -e "${YELLOW}Step 1: Getting admin cleanup credentials from Terraform${NC}"
cd ../../../..  # Navigate to root of terraform project

ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
CURRENT_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")

# Also retrieve the EC2 init function name from the grouped output so cleanup works
# even if the demo script didn't export it
MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.attack_simulation_sysdig_8_minutes_to_admin.value // empty')
EC2_INIT_FUNCTION=$(echo "$MODULE_OUTPUT" | jq -r '.ec2_init_function_name' 2>/dev/null || echo "pl-prod-8min-ec2-init")
FRICK_USERNAME=$(echo "$MODULE_OUTPUT" | jq -r '.frick_username' 2>/dev/null || echo "pl-prod-8min-frick")

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
echo "EC2-init function: $EC2_INIT_FUNCTION"
echo -e "${GREEN}✓ Retrieved admin credentials${NC}\n"

# Navigate back to scenario directory
cd - > /dev/null

# Get account ID for reference
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "Account ID: $ACCOUNT_ID"
echo ""

# =============================================================================
# Step 2: Terminate the GPU instance (CRITICAL — $3.06/hr)
# =============================================================================
echo -e "${YELLOW}Step 2: Terminating GPU instance (p3.2xlarge — \$3.06/hr)${NC}"
echo "Searching in region: $CURRENT_REGION"
echo ""

# Try to read instance ID from file written by demo script
INSTANCE_ID_FILE="/tmp/pl-8min-gpu-instance-id.txt"
SG_ID_FILE="/tmp/pl-8min-gpu-sg-id.txt"

if [ -f "$INSTANCE_ID_FILE" ]; then
    SAVED_INSTANCE_ID=$(cat "$INSTANCE_ID_FILE" 2>/dev/null || echo "")
    echo "Found saved instance ID: $SAVED_INSTANCE_ID"
fi

# Find all active instances by tag (covers both file-present and file-missing cases)
echo "Searching for instances tagged Scenario=sysdig-8-minutes-to-admin..."
ALL_INSTANCE_STATES=$(aws ec2 describe-instances \
    --region $CURRENT_REGION \
    --filters "Name=tag:Scenario,Values=sysdig-8-minutes-to-admin" \
    --query 'Reservations[*].Instances[*].[InstanceId,State.Name]' \
    --output text 2>/dev/null || echo "")

if [ -n "$ALL_INSTANCE_STATES" ]; then
    echo "Found instances (all states):"
    echo "$ALL_INSTANCE_STATES"
    echo ""
fi

INSTANCE_IDS=$(aws ec2 describe-instances \
    --region $CURRENT_REGION \
    --filters "Name=tag:Scenario,Values=sysdig-8-minutes-to-admin" \
              "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text 2>/dev/null || echo "")

# Also check by Name tag in case the Scenario tag wasn't applied
if [ -z "$INSTANCE_IDS" ]; then
    INSTANCE_IDS=$(aws ec2 describe-instances \
        --region $CURRENT_REGION \
        --filters "Name=tag:Name,Values=pl-8min-gpu-monster" \
                  "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text 2>/dev/null || echo "")
fi

if [ -z "$INSTANCE_IDS" ]; then
    echo -e "${YELLOW}No active GPU instances found (may already be terminated)${NC}"
else
    echo "Terminating instances: $INSTANCE_IDS"
    for INSTANCE_ID in $INSTANCE_IDS; do
        echo "  Terminating: $INSTANCE_ID"
        aws ec2 terminate-instances \
            --region $CURRENT_REGION \
            --instance-ids $INSTANCE_ID \
            --output text > /dev/null 2>/dev/null || true
        echo -e "  ${GREEN}✓ Termination initiated: $INSTANCE_ID${NC}"
    done

    echo ""
    echo "Waiting for instances to terminate..."
    for INSTANCE_ID in $INSTANCE_IDS; do
        aws ec2 wait instance-terminated \
            --region $CURRENT_REGION \
            --instance-ids $INSTANCE_ID 2>/dev/null || true
    done
    echo -e "${GREEN}✓ All GPU instances terminated${NC}"
fi

rm -f "$INSTANCE_ID_FILE"
echo ""

# =============================================================================
# Step 3: Delete the security group
# =============================================================================
echo -e "${YELLOW}Step 3: Deleting GPU security group${NC}"

# Try saved SG ID first
SG_ID=""
if [ -f "$SG_ID_FILE" ]; then
    SG_ID=$(cat "$SG_ID_FILE" 2>/dev/null || echo "")
fi

# Fall back to lookup by group name
if [ -z "$SG_ID" ]; then
    SG_ID=$(aws ec2 describe-security-groups \
        --region $CURRENT_REGION \
        --filters "Name=group-name,Values=pl-8min-gpu-sg" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "")
fi

if [ -z "$SG_ID" ] || [ "$SG_ID" == "None" ] || [ "$SG_ID" == "null" ]; then
    echo -e "${YELLOW}Security group pl-8min-gpu-sg not found (may already be deleted)${NC}"
else
    echo "Deleting security group: $SG_ID"
    # Retry up to 3 times — instances may still be detaching from the SG
    for ATTEMPT in 1 2 3; do
        if aws ec2 delete-security-group \
            --region $CURRENT_REGION \
            --group-id $SG_ID 2>/dev/null; then
            echo -e "${GREEN}✓ Deleted security group: $SG_ID${NC}"
            break
        else
            if [ $ATTEMPT -lt 3 ]; then
                echo "  Security group still in use — waiting 15 seconds before retry $((ATTEMPT+1))/3..."
                sleep 15
            else
                echo -e "${YELLOW}Could not delete security group $SG_ID — may still be attached to a terminating instance${NC}"
                echo -e "${YELLOW}Run 'aws ec2 delete-security-group --group-id $SG_ID --region $CURRENT_REGION' manually in a few minutes${NC}"
            fi
        fi
    done
fi

rm -f "$SG_ID_FILE"
echo ""

# =============================================================================
# Step 4: Delete the EC2 keypair
# =============================================================================
echo -e "${YELLOW}Step 4: Deleting EC2 keypair pl-8min-gpu-key${NC}"

if aws ec2 describe-key-pairs \
    --region $CURRENT_REGION \
    --key-names pl-8min-gpu-key > /dev/null 2>/dev/null; then
    aws ec2 delete-key-pair \
        --region $CURRENT_REGION \
        --key-name pl-8min-gpu-key
    echo -e "${GREEN}✓ Deleted keypair pl-8min-gpu-key${NC}"
else
    echo -e "${YELLOW}Keypair pl-8min-gpu-key not found (may already be deleted)${NC}"
fi

rm -f /tmp/pl-8min-gpu-key.pem
echo ""

# =============================================================================
# Step 5: Delete backdoor-admin user and all its access keys
# =============================================================================
echo -e "${YELLOW}Step 5: Deleting backdoor-admin user${NC}"

if aws iam get-user --user-name backdoor-admin > /dev/null 2>/dev/null; then
    # Delete all access keys first
    BACKDOOR_KEYS=$(aws iam list-access-keys \
        --user-name backdoor-admin \
        --query 'AccessKeyMetadata[*].AccessKeyId' \
        --output text 2>/dev/null || echo "")
    if [ -n "$BACKDOOR_KEYS" ]; then
        for KEY_ID in $BACKDOOR_KEYS; do
            echo "  Deleting access key: $KEY_ID"
            aws iam delete-access-key --user-name backdoor-admin --access-key-id $KEY_ID
        done
    fi

    # Detach all managed policies
    ATTACHED_POLICIES=$(aws iam list-attached-user-policies \
        --user-name backdoor-admin \
        --query 'AttachedPolicies[*].PolicyArn' \
        --output text 2>/dev/null || echo "")
    if [ -n "$ATTACHED_POLICIES" ]; then
        for POLICY_ARN in $ATTACHED_POLICIES; do
            echo "  Detaching policy: $POLICY_ARN"
            aws iam detach-user-policy --user-name backdoor-admin --policy-arn $POLICY_ARN
        done
    fi

    # Delete inline policies
    INLINE_POLICIES=$(aws iam list-user-policies \
        --user-name backdoor-admin \
        --query 'PolicyNames[*]' \
        --output text 2>/dev/null || echo "")
    if [ -n "$INLINE_POLICIES" ]; then
        for POLICY_NAME in $INLINE_POLICIES; do
            echo "  Deleting inline policy: $POLICY_NAME"
            aws iam delete-user-policy --user-name backdoor-admin --policy-name $POLICY_NAME
        done
    fi

    # Delete the user
    aws iam delete-user --user-name backdoor-admin
    echo -e "${GREEN}✓ Deleted backdoor-admin user${NC}"
else
    echo -e "${YELLOW}backdoor-admin user not found (may already be deleted)${NC}"
fi
echo ""

# =============================================================================
# Step 6: Delete access keys created for frick via Lambda injection
# =============================================================================
echo -e "${YELLOW}Step 6: Deleting access keys created for $FRICK_USERNAME${NC}"
echo "Note: Terraform manages frick's original Terraform-created credentials."
echo "Only access keys NOT in Terraform state will be present here."
echo ""

FRICK_KEYS=$(aws iam list-access-keys \
    --user-name $FRICK_USERNAME \
    --query 'AccessKeyMetadata[*].AccessKeyId' \
    --output text 2>/dev/null || echo "")

if [ -z "$FRICK_KEYS" ]; then
    echo -e "${YELLOW}No access keys found for $FRICK_USERNAME${NC}"
else
    echo "Found access keys for $FRICK_USERNAME:"
    for KEY_ID in $FRICK_KEYS; do
        echo "  Deleting: $KEY_ID"
        aws iam delete-access-key \
            --user-name $FRICK_USERNAME \
            --access-key-id $KEY_ID
        echo -e "  ${GREEN}✓ Deleted: $KEY_ID${NC}"
    done
fi
echo ""

# =============================================================================
# Step 7: Delete access keys created for pl-prod-8min-rocker
# =============================================================================
echo -e "${YELLOW}Step 7: Deleting access keys created for pl-prod-8min-rocker${NC}"

ROCKER_KEYS=$(aws iam list-access-keys \
    --user-name pl-prod-8min-rocker \
    --query 'AccessKeyMetadata[*].AccessKeyId' \
    --output text 2>/dev/null || echo "")

if [ -z "$ROCKER_KEYS" ]; then
    echo -e "${YELLOW}No access keys found for pl-prod-8min-rocker${NC}"
else
    for KEY_ID in $ROCKER_KEYS; do
        echo "  Deleting: $KEY_ID"
        aws iam delete-access-key \
            --user-name pl-prod-8min-rocker \
            --access-key-id $KEY_ID
        echo -e "  ${GREEN}✓ Deleted: $KEY_ID${NC}"
    done
fi
echo ""

# =============================================================================
# Step 8: Delete access keys created for pl-prod-8min-admingh (first attempt)
# =============================================================================
echo -e "${YELLOW}Step 8: Deleting any access keys created for pl-prod-8min-admingh${NC}"

ADMINGH_KEYS=$(aws iam list-access-keys \
    --user-name pl-prod-8min-admingh \
    --query 'AccessKeyMetadata[*].AccessKeyId' \
    --output text 2>/dev/null || echo "")

if [ -z "$ADMINGH_KEYS" ]; then
    echo -e "${YELLOW}No access keys found for pl-prod-8min-admingh (likely already cleaned up during demo)${NC}"
else
    for KEY_ID in $ADMINGH_KEYS; do
        echo "  Deleting: $KEY_ID"
        aws iam delete-access-key \
            --user-name pl-prod-8min-admingh \
            --access-key-id $KEY_ID
        echo -e "  ${GREEN}✓ Deleted: $KEY_ID${NC}"
    done
fi
echo ""

# =============================================================================
# Step 9: Delete access keys created for identity-spreading users
# =============================================================================
echo -e "${YELLOW}Step 9: Deleting access keys created for identity-spreading users${NC}"

for SPREAD_USER in pl-prod-8min-azureadmanager pl-prod-8min-deploy-svc pl-prod-8min-monitoring pl-prod-8min-ci-runner; do
    SPREAD_KEYS=$(aws iam list-access-keys \
        --user-name $SPREAD_USER \
        --query 'AccessKeyMetadata[*].AccessKeyId' \
        --output text 2>/dev/null || echo "")

    if [ -z "$SPREAD_KEYS" ]; then
        echo -e "${YELLOW}No access keys found for $SPREAD_USER${NC}"
    else
        for KEY_ID in $SPREAD_KEYS; do
            echo "  Deleting: $SPREAD_USER / $KEY_ID"
            aws iam delete-access-key \
                --user-name $SPREAD_USER \
                --access-key-id $KEY_ID
            echo -e "  ${GREEN}✓ Deleted: $KEY_ID${NC}"
        done
    fi
done
echo ""

# =============================================================================
# Step 10: Restore Lambda function to original innocent code
# =============================================================================
echo -e "${YELLOW}Step 10: Restoring Lambda function $EC2_INIT_FUNCTION to original code${NC}"

if aws lambda get-function \
    --function-name $EC2_INIT_FUNCTION \
    --region $CURRENT_REGION > /dev/null 2>/dev/null; then

    cat > /tmp/original_handler.py << 'PYTHON'
import boto3
import json

def handler(event, context):
    """Initializes new EC2 instances by verifying connectivity and checking instance state."""
    ec2 = boto3.client('ec2')
    try:
        response = ec2.describe_instances(
            Filters=[{'Name': 'instance-state-name', 'Values': ['pending', 'running']}]
        )
        instance_count = sum(len(r['Instances']) for r in response['Reservations'])
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'EC2 init check complete. {instance_count} active instances.',
                'status': 'ok'
            })
        }
    except Exception as e:
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}
PYTHON

    cd /tmp && zip -q original_lambda.zip original_handler.py && cd - > /dev/null
    echo "Restoring function code..."

    aws lambda update-function-code \
        --region $CURRENT_REGION \
        --function-name "$EC2_INIT_FUNCTION" \
        --zip-file fileb:///tmp/original_lambda.zip \
        --handler original_handler.handler > /dev/null
    echo -e "${GREEN}✓ Lambda code restored${NC}"

    echo "Restoring function timeout to 3 seconds..."
    aws lambda update-function-configuration \
        --region $CURRENT_REGION \
        --function-name "$EC2_INIT_FUNCTION" \
        --timeout 3 > /dev/null
    echo -e "${GREEN}✓ Lambda timeout restored to 3 seconds${NC}"
else
    echo -e "${YELLOW}Lambda function $EC2_INIT_FUNCTION not found${NC}"
fi
echo ""

# =============================================================================
# Step 11: Clean up local temporary files
# =============================================================================
echo -e "${YELLOW}Step 11: Removing local temporary files${NC}"

rm -f /tmp/rag-config.json \
      /tmp/malicious_handler_v1.py \
      /tmp/malicious_lambda_v1.zip \
      /tmp/malicious_handler_v2.py \
      /tmp/malicious_lambda_v2.zip \
      /tmp/lambda_response_v1.json \
      /tmp/lambda_response_v2.json \
      /tmp/original_handler.py \
      /tmp/original_lambda.zip \
      /tmp/bedrock-claude.json \
      /tmp/bedrock-nova.json \
      /tmp/bedrock-deepseek.json \
      /tmp/pl-8min-gpu-key.pem

echo -e "${GREEN}✓ Removed local temp files${NC}\n"

# =============================================================================
# Summary
# =============================================================================
echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}CLEANUP COMPLETE${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "${YELLOW}Summary of removed artifacts:${NC}"
echo "- EC2 GPU instance(s) terminated"
echo "- EC2 security group pl-8min-gpu-sg deleted"
echo "- EC2 keypair pl-8min-gpu-key deleted"
echo "- backdoor-admin IAM user and all its access keys deleted"
echo "- All access keys for $FRICK_USERNAME deleted"
echo "- All access keys for pl-prod-8min-rocker deleted"
echo "- All access keys for pl-prod-8min-admingh deleted"
echo "- All access keys for identity-spreading users (azureadmanager, deploy-svc, monitoring, ci-runner) deleted"
echo "- Lambda $EC2_INIT_FUNCTION restored to original code (3s timeout)"
echo "- Local temporary files removed"
echo ""
echo -e "${GREEN}The environment has been restored to its original state.${NC}"
echo -e "${YELLOW}The Terraform infrastructure (users, roles, Lambda, S3 bucket) remains deployed.${NC}"
echo -e "${YELLOW}To remove all infrastructure, set the scenario flag to false and run terraform apply.${NC}\n"

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
