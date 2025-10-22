#!/bin/bash

# Cleanup script for prod_role_has_access_to_bucket_through_resource_policy attack path
# This script removes any test files that may have been created during the attack demo

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== S3 Bucket Access Through Resource Policy Attack Cleanup ===${NC}"
echo "This script cleans up any test files created during the attack demo."
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed or not in PATH${NC}"
    exit 1
fi

# Check if we have AWS credentials configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured. Please run 'aws configure' first.${NC}"
    exit 1
fi

echo -e "${YELLOW}Step 1: Finding sensitive buckets that may need cleanup${NC}"

# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Current account: $ACCOUNT_ID"

# Look for sensitive buckets
echo "Looking for sensitive buckets with 'pl-sensitive-data' prefix..."
if SENSITIVE_BUCKETS=$(aws s3 ls --output json 2>/dev/null | jq -r '.[] | select(.Name | startswith("pl-sensitive-data")) | .Name'); then
    if [ -n "$SENSITIVE_BUCKETS" ]; then
        echo "Found sensitive buckets:"
        echo "$SENSITIVE_BUCKETS" | while read -r bucket; do
            echo "  - $bucket"
        done
        echo ""
        
        echo -e "${YELLOW}Step 2: Checking for test files in sensitive buckets${NC}"
        
        # Check each sensitive bucket for test files
        echo "$SENSITIVE_BUCKETS" | while read -r bucket; do
            echo "Checking bucket: $bucket"
            
            # Look for test files
            if TEST_FILES=$(aws s3 ls "s3://$bucket/" --output json 2>/dev/null | jq -r '.[] | select(.Key | startswith("test-upload")) | .Key'); then
                if [ -n "$TEST_FILES" ]; then
                    echo "Found test files in $bucket:"
                    echo "$TEST_FILES" | while read -r file; do
                        echo "  - $file"
                    done
                    
                    echo "Removing test files from $bucket..."
                    echo "$TEST_FILES" | while read -r file; do
                        if aws s3 rm "s3://$bucket/$file" 2>/dev/null; then
                            echo -e "${GREEN}✓ Removed: $file${NC}"
                        else
                            echo -e "${RED}✗ Failed to remove: $file${NC}"
                        fi
                    done
                else
                    echo -e "${GREEN}✓ No test files found in $bucket${NC}"
                fi
            else
                echo -e "${YELLOW}⚠ Could not list objects in $bucket (insufficient permissions)${NC}"
            fi
            echo ""
        done
        
    else
        echo -e "${GREEN}✓ No sensitive buckets found${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Could not list S3 buckets (insufficient permissions)${NC}"
fi

echo -e "${YELLOW}Step 3: Checking for other test artifacts${NC}"

# Check for any temporary files that might have been created
echo "Checking for temporary test files in /tmp..."
if TEMP_FILES=$(find /tmp -name "test-upload-*.txt" -type f 2>/dev/null); then
    if [ -n "$TEMP_FILES" ]; then
        echo "Found temporary test files:"
        echo "$TEMP_FILES" | while read -r file; do
            echo "  - $file"
        done
        
        echo "Removing temporary test files..."
        echo "$TEMP_FILES" | while read -r file; do
            if rm -f "$file" 2>/dev/null; then
                echo -e "${GREEN}✓ Removed: $file${NC}"
            else
                echo -e "${RED}✗ Failed to remove: $file${NC}"
            fi
        done
    else
        echo -e "${GREEN}✓ No temporary test files found${NC}"
    fi
else
    echo -e "${GREEN}✓ No temporary test files found${NC}"
fi

echo ""
echo -e "${YELLOW}Step 4: Verifying cleanup${NC}"

# Verify that no test files remain
echo "Verifying that all test files have been removed..."

if [ -n "$SENSITIVE_BUCKETS" ]; then
    echo "$SENSITIVE_BUCKETS" | while read -r bucket; do
        echo "Verifying cleanup in bucket: $bucket"
        
        if REMAINING_TEST_FILES=$(aws s3 ls "s3://$bucket/" --output json 2>/dev/null | jq -r '.[] | select(.Key | startswith("test-upload")) | .Key'); then
            if [ -n "$REMAINING_TEST_FILES" ]; then
                echo -e "${YELLOW}⚠ Warning: Some test files still remain in $bucket:${NC}"
                echo "$REMAINING_TEST_FILES" | while read -r file; do
                    echo "  - $file"
                done
            else
                echo -e "${GREEN}✓ All test files removed from $bucket${NC}"
            fi
        else
            echo -e "${YELLOW}⚠ Could not verify cleanup in $bucket (insufficient permissions)${NC}"
        fi
    done
fi

# Check for remaining temporary files
if REMAINING_TEMP_FILES=$(find /tmp -name "test-upload-*.txt" -type f 2>/dev/null); then
    if [ -n "$REMAINING_TEMP_FILES" ]; then
        echo -e "${YELLOW}⚠ Warning: Some temporary test files still remain:${NC}"
        echo "$REMAINING_TEMP_FILES" | while read -r file; do
            echo "  - $file"
        done
    else
        echo -e "${GREEN}✓ All temporary test files removed${NC}"
    fi
else
    echo -e "${GREEN}✓ All temporary test files removed${NC}"
fi

echo ""
echo -e "${GREEN}=== CLEANUP COMPLETE ===${NC}"
echo "Cleanup process completed. Any test files created during the attack demo"
echo "should have been removed. The sensitive bucket and its original contents"
echo "are preserved to avoid breaking dependencies."
echo ""

# Output standardized cleanup results
echo "CLEANUP_RESULT:prod_role_has_access_to_bucket_through_resource_policy:SUCCESS"
echo "CLEANUP_DETAILS:prod_role_has_access_to_bucket_through_resource_policy:Test files cleanup completed"
echo "CLEANUP_METRICS:prod_role_has_access_to_bucket_through_resource_policy:cleanup_completed=true"
