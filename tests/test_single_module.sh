#!/bin/bash

# Test a single module and parse its standardized output

set -e

# Ensure we're using bash
if [ -z "$BASH_VERSION" ]; then
    echo "This script requires bash. Please run with: bash $0"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

if [ $# -eq 0 ]; then
    echo "Usage: $0 <module_name>"
    echo ""
    echo "Available modules:"
    find ../modules -name "demo_attack.sh" -type f | sed 's|../modules/||' | sed 's|/demo_attack.sh||' | sort
    exit 1
fi

MODULE_NAME="$1"
MODULE_PATH="../modules/$MODULE_NAME"
DEMO_SCRIPT="$MODULE_PATH/demo_attack.sh"

echo -e "${BLUE}=== Testing Module: $MODULE_NAME ===${NC}"

if [ ! -f "$DEMO_SCRIPT" ]; then
    echo -e "${RED}✗ Demo script not found: $DEMO_SCRIPT${NC}"
    exit 1
fi

if [ ! -x "$DEMO_SCRIPT" ]; then
    echo -e "${RED}✗ Demo script not executable: $DEMO_SCRIPT${NC}"
    exit 1
fi

echo "Running: $DEMO_SCRIPT"
echo ""

# Record start time
START_TIME=$(date +%s)

# Run the test and capture output
if TEST_OUTPUT=$(cd "$MODULE_PATH" && timeout 300 ./demo_attack.sh 2>&1); then
    EXIT_CODE=0
else
    EXIT_CODE=$?
fi

# Record end time
END_TIME=$(date +%s)
EXECUTION_TIME=$((END_TIME - START_TIME))

echo ""
echo -e "${BLUE}=== Test Results ===${NC}"

# Parse standardized output
RESULT="UNKNOWN"
DETAILS="No details provided"
METRICS="execution_time=${EXECUTION_TIME}s"

# Extract TEST_RESULT
RESULT_LINE=$(echo "$TEST_OUTPUT" | grep "^TEST_RESULT:$MODULE_NAME:" | tail -1)
if [ -n "$RESULT_LINE" ]; then
    RESULT=$(echo "$RESULT_LINE" | cut -d: -f3)
fi

# Extract TEST_DETAILS
DETAILS_LINE=$(echo "$TEST_OUTPUT" | grep "^TEST_DETAILS:$MODULE_NAME:" | tail -1)
if [ -n "$DETAILS_LINE" ]; then
    DETAILS=$(echo "$DETAILS_LINE" | cut -d: -f3-)
fi

# Extract TEST_METRICS
METRICS_LINE=$(echo "$TEST_OUTPUT" | grep "^TEST_METRICS:$MODULE_NAME:" | tail -1)
if [ -n "$METRICS_LINE" ]; then
    EXTRACTED_METRICS=$(echo "$METRICS_LINE" | cut -d: -f3-)
    METRICS="$EXTRACTED_METRICS,execution_time=${EXECUTION_TIME}s"
fi

# Display results
echo "Module: $MODULE_NAME"
echo "Execution Time: ${EXECUTION_TIME}s"
echo "Exit Code: $EXIT_CODE"
echo ""

if [ $EXIT_CODE -eq 0 ] && [ "$RESULT" = "SUCCESS" ]; then
    echo -e "${GREEN}✓ Result: SUCCESS${NC}"
else
    echo -e "${RED}✗ Result: FAILURE${NC}"
    if [ $EXIT_CODE -ne 0 ]; then
        echo -e "${RED}  Script failed with exit code $EXIT_CODE${NC}"
    fi
fi

echo "Details: $DETAILS"
echo "Metrics: $METRICS"

# Show full output if there was an error
if [ $EXIT_CODE -ne 0 ] || [ "$RESULT" != "SUCCESS" ]; then
    echo ""
    echo -e "${YELLOW}Full Output:${NC}"
    echo "----------------------------------------"
    echo "$TEST_OUTPUT"
    echo "----------------------------------------"
fi

# Exit with appropriate code
if [ $EXIT_CODE -eq 0 ] && [ "$RESULT" = "SUCCESS" ]; then
    exit 0
else
    exit 1
fi
