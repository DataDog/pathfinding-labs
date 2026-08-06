#!/bin/bash
# Sweeps AWS Batch, EMR Serverless, and App Runner in the account for leftover
# artifacts that block deletion of the account's service-linked roles
# (AWSServiceRoleForBatch, AWSServiceRoleForAmazonEMRServerless, AWSServiceRoleForAppRunner).
#
# These artifacts are created by lab demo_attack.sh scripts (or by running pathrunner
# modules directly) and are normally removed by each scenario's cleanup_attack.sh.
# This script is a blunt, account-wide fallback for when those weren't run and
# `terraform destroy` fails with "Service Linked Role is still in use".
#
# Usage: ./scripts/cleanup-slr-blockers.sh [aws-profile] [aws-region]

set -uo pipefail

export AWS_PAGER=""
PROFILE="${1:-ddplp}"
REGION="${2:-us-east-1}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

aws_cli() {
    aws --profile "$PROFILE" --region "$REGION" "$@"
}

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}SLR Blocker Cleanup${NC}"
echo -e "Profile: $PROFILE  Region: $REGION"
echo -e "${GREEN}========================================${NC}\n"

# ---------------------------------------------------------------------------
# AWS Batch: disable + delete every job queue, then every compute environment
# ---------------------------------------------------------------------------
echo -e "${YELLOW}== AWS Batch ==${NC}"

JOB_QUEUES=$(aws_cli batch describe-job-queues --query 'jobQueues[].jobQueueName' --output text 2>/dev/null)
if [ -n "$JOB_QUEUES" ]; then
    for JQ in $JOB_QUEUES; do
        echo "Job queue: $JQ"
        STATE=$(aws_cli batch describe-job-queues --job-queues "$JQ" --query 'jobQueues[0].state' --output text 2>/dev/null)
        if [ "$STATE" != "DISABLED" ]; then
            aws_cli batch update-job-queue --job-queue "$JQ" --state DISABLED >/dev/null
            echo "  disabling, waiting 10s..."
            sleep 10
        fi
        aws_cli batch delete-job-queue --job-queue "$JQ" 2>/dev/null || true
        echo -e "  ${GREEN}delete requested${NC}"
    done
else
    echo "No job queues found"
fi

COMPUTE_ENVS=$(aws_cli batch describe-compute-environments --query 'computeEnvironments[].computeEnvironmentName' --output text 2>/dev/null)
if [ -n "$COMPUTE_ENVS" ]; then
    for CE in $COMPUTE_ENVS; do
        echo "Compute environment: $CE"
        STATE=$(aws_cli batch describe-compute-environments --compute-environments "$CE" --query 'computeEnvironments[0].state' --output text 2>/dev/null)
        if [ "$STATE" != "DISABLED" ]; then
            aws_cli batch update-compute-environment --compute-environment "$CE" --state DISABLED >/dev/null
            echo "  disabling, waiting 15s..."
            sleep 15
        fi
        aws_cli batch delete-compute-environment --compute-environment "$CE" 2>/dev/null || true
        echo -e "  ${GREEN}delete requested${NC}"
    done
else
    echo "No compute environments found"
fi
echo ""

# ---------------------------------------------------------------------------
# EMR Serverless: cancel running job runs, stop, then delete every application
# ---------------------------------------------------------------------------
echo -e "${YELLOW}== EMR Serverless ==${NC}"

APP_IDS=$(aws_cli emr-serverless list-applications --query 'applications[].id' --output text 2>/dev/null)
if [ -n "$APP_IDS" ]; then
    for APP_ID in $APP_IDS; do
        echo "Application: $APP_ID"

        RUNNING_JOBS=$(aws_cli emr-serverless list-job-runs --application-id "$APP_ID" \
            --states RUNNING PENDING SCHEDULED SUBMITTED --query 'jobRuns[].id' --output text 2>/dev/null)
        for JOB_ID in $RUNNING_JOBS; do
            echo "  cancelling job run $JOB_ID"
            aws_cli emr-serverless cancel-job-run --application-id "$APP_ID" --job-run-id "$JOB_ID" >/dev/null 2>&1 || true
        done
        if [ -n "$RUNNING_JOBS" ]; then
            echo "  waiting 15s for job runs to cancel..."
            sleep 15
        fi

        STATE=$(aws_cli emr-serverless get-application --application-id "$APP_ID" --query 'application.state' --output text 2>/dev/null)
        if [ "$STATE" == "STARTED" ] || [ "$STATE" == "STARTING" ]; then
            echo "  stopping application..."
            aws_cli emr-serverless stop-application --application-id "$APP_ID" >/dev/null 2>&1 || true
            sleep 10
        fi

        aws_cli emr-serverless delete-application --application-id "$APP_ID" 2>/dev/null || true
        echo -e "  ${GREEN}delete requested${NC}"
    done
else
    echo "No EMR Serverless applications found"
fi
echo ""

# ---------------------------------------------------------------------------
# App Runner: delete every service
# ---------------------------------------------------------------------------
echo -e "${YELLOW}== App Runner ==${NC}"

SERVICE_ARNS=$(aws_cli apprunner list-services --query 'ServiceSummaryList[].ServiceArn' --output text 2>/dev/null)
if [ -n "$SERVICE_ARNS" ]; then
    for ARN in $SERVICE_ARNS; do
        echo "Service: $ARN"
        aws_cli apprunner delete-service --service-arn "$ARN" 2>/dev/null || true
        echo -e "  ${GREEN}delete requested${NC}"
    done
else
    echo "No App Runner services found"
fi
echo ""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Sweep complete.${NC}"
echo -e "Deletions above are async. Batch queues/compute envs typically finish in ~1-2 min,"
echo -e "EMR Serverless apps in ~1 min, App Runner services in ~1-3 min."
echo -e "Wait a bit, then re-run: terraform destroy"
echo -e "${GREEN}========================================${NC}"
