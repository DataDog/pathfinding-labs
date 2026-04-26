#!/bin/bash

# Cleanup script for public Lambda with admin role toxic combination
# This scenario creates no persistent attack artifacts — the attack only reads
# temporary credentials from the Lambda function's HTTP response. There is nothing
# to clean up after running demo_attack.sh.

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Cleanup: Public Lambda with Admin Role${NC}"
echo -e "${GREEN}========================================${NC}\n"

echo -e "${YELLOW}No cleanup required.${NC}"
echo ""
echo "The demo_attack.sh for this scenario does not create any persistent AWS resources."
echo "The attack reads temporary credentials from the Lambda function's HTTP response and"
echo "uses those credentials to read an SSM parameter — no new IAM users, access keys,"
echo "or policies are created."
echo ""
echo "To tear down the scenario infrastructure entirely, use:"
echo "  plabs disable public-lambda-with-admin-to-admin && plabs apply"
echo "or:"
echo "  terraform destroy"
echo ""
echo -e "${GREEN}✓ Nothing to clean up${NC}"
