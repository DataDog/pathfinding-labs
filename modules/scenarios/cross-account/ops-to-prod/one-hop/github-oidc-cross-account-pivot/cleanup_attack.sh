#!/bin/bash

# Cleanup script for github-oidc-cross-account-pivot demo
#
# This demo does not modify any AWS infrastructure state. The attack path relies on
# GitHub Actions OIDC — all credentials obtained during a real exploit would be
# temporary STS session tokens that expire automatically. The demo script itself
# only performs read operations using existing admin credentials.
#
# This script confirms no artifacts were left and restores any permission restriction
# policies applied during the demo run.

# Disable AWS CLI paging
export AWS_PAGER=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}Cleanup: GitHub Actions OIDC Cross-Account Pivot${NC}"
echo -e "${GREEN}============================================================${NC}\n"

# Safety restore: ensure helpful permissions deny policy is removed regardless of
# whether the demo script completed normally or was interrupted
source "$SCRIPT_DIR/../../../../../../scripts/lib/demo_permissions.sh"
restore_helpful_permissions "$SCRIPT_DIR/scenario.yaml" 2>/dev/null || true

# =============================================================================
# Read GitHub repo from plabs config
# =============================================================================
PLABS_CONFIG="$HOME/.plabs/plabs.yaml"
GITHUB_REPO=""
if [ -f "$PLABS_CONFIG" ]; then
    GITHUB_REPO=$(grep -A5 'github-oidc-cross-account-pivot:' "$PLABS_CONFIG" 2>/dev/null \
        | grep 'github_repo:' | head -1 | sed 's/.*github_repo:[[:space:]]*//')
fi

# =============================================================================
# GitHub artifact cleanup
# =============================================================================
# Branch pattern: pl-oidc-exploit-<epoch>
# Workflow file:  .github/workflows/pl-oidc-pivot-exploit.yml
EXPLOIT_BRANCH_PREFIX="pl-oidc-exploit-"
EXPLOIT_BRANCH_PATTERN="^pl-oidc-exploit-[0-9]+$"
WORKFLOW_FILE="pl-oidc-pivot-exploit.yml"

echo -e "${YELLOW}Cleaning up GitHub artifacts in ${GITHUB_REPO:-<repo not configured>}...${NC}"
echo ""

if [ -z "$GITHUB_REPO" ]; then
    echo -e "${YELLOW}  github_repo not configured — skipping GitHub cleanup${NC}"
    echo "  Set it with: plabs config github-oidc-cross-account-pivot set github_repo org/repo"
elif ! gh auth status &>/dev/null; then
    echo -e "${YELLOW}  gh CLI not authenticated — skipping GitHub cleanup${NC}"
    echo "  Run: gh auth login"
else
    # --- Delete exploit branches ---
    echo -e "${BLUE}Fetching exploit branches (${EXPLOIT_BRANCH_PREFIX}*)...${NC}"
    BRANCHES=$(gh api "repos/$GITHUB_REPO/git/matching-refs/heads/${EXPLOIT_BRANCH_PREFIX}" \
        --paginate -q '.[].ref' 2>/dev/null || true)

    if [ -z "$BRANCHES" ]; then
        echo -e "${GREEN}  ✓ No exploit branches found${NC}"
    else
        while IFS= read -r ref; do
            branch="${ref#refs/heads/}"
            if echo "$branch" | grep -qE "$EXPLOIT_BRANCH_PATTERN"; then
                gh api -X DELETE "repos/$GITHUB_REPO/git/$ref" 2>/dev/null \
                    && echo -e "${GREEN}  ✓ Deleted branch: $branch${NC}" \
                    || echo -e "${RED}  ✗ Failed to delete branch: $branch${NC}"
            fi
        done <<< "$BRANCHES"
    fi
    echo ""

    # --- Delete workflow runs ---
    echo -e "${BLUE}Fetching workflow runs for ${WORKFLOW_FILE}...${NC}"
    # Collect run IDs for runs on exploit branches OR using the exploit workflow file
    RUN_IDS=$(gh api "repos/$GITHUB_REPO/actions/runs" \
        --paginate \
        -q ".workflow_runs[] | select(.head_branch | test(\"$EXPLOIT_BRANCH_PATTERN\")) | .id" \
        2>/dev/null || true)

    if [ -z "$RUN_IDS" ]; then
        echo -e "${GREEN}  ✓ No workflow runs found${NC}"
    else
        while IFS= read -r run_id; do
            gh api -X DELETE "repos/$GITHUB_REPO/actions/runs/$run_id" 2>/dev/null \
                && echo -e "${GREEN}  ✓ Deleted workflow run: $run_id${NC}" \
                || echo -e "${RED}  ✗ Failed to delete run: $run_id${NC}"
        done <<< "$RUN_IDS"
    fi
    echo ""
fi

# =============================================================================
# Local temp file cleanup
# =============================================================================
echo -e "${BLUE}Checking for local temp files...${NC}"
LOCAL_CLEANED=0
for tmp_dir in /tmp/pl-oidc-exploit-*; do
    if [ -d "$tmp_dir" ]; then
        rm -rf "$tmp_dir"
        echo -e "${GREEN}  ✓ Removed temp clone: $tmp_dir${NC}"
        LOCAL_CLEANED=1
    fi
done
if [ "$LOCAL_CLEANED" -eq 0 ]; then
    echo -e "${GREEN}  ✓ No local temp files to remove${NC}"
fi
echo ""

echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}✅ CLEANUP COMPLETE${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "${YELLOW}Infrastructure Status (deployed by Terraform — not removed):${NC}"
echo "  ops:pl-ops-goidc-pivot-deployer-role"
echo "  prod:pl-prod-goidc-pivot-deployer-role"
echo "  ops GitHub OIDC provider"
echo "  prod flag bucket (sensitive-data.txt intact)"
echo ""
echo -e "${YELLOW}To remove all infrastructure:${NC}"
echo "  enable_cross_account_ops_to_prod_github_oidc_pivot = false"
echo "  terraform apply"
echo ""

# Clear demo active marker for plabs tracking
rm -f "$(dirname "$0")/.demo_active"
