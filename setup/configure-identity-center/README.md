# Configure IAM Identity Center for Pathfinding Labs

This guide walks you through enabling AWS IAM Identity Center in your Organizations management account, creating a local admin user, and granting that user administrator access to `pl-prod`, `pl-dev`, and `pl-ops`. By the end you'll have named AWS CLI profiles for each account backed by short-lived SSO credentials instead of long-lived IAM access keys.

## Prerequisites

- AWS Organizations is enabled and `pl-prod`, `pl-dev`, `pl-ops` exist as child accounts. If not, follow [create-org/README.md](../create-org/README.md) first.
- AWS CLI v2 configured with admin credentials for the management account.
- The `jq` utility installed (`brew install jq` / `apt install jq`).

## Step 1: Enable IAM Identity Center

IAM Identity Center must be enabled from the AWS Console — there is no CLI command to perform the initial activation.

1. Sign in to the management account.
2. Open **IAM Identity Center** (search for it in the top bar).
3. Click **Enable** and confirm. AWS will provision an instance in your home region; this takes about 30 seconds.
4. On the settings page that appears, note the **AWS access portal URL** — it looks like `https://d-xxxxxxxxxx.awsapps.com/start`. You'll need it later.

Confirm the instance is ready and grab the IDs you'll need for the remaining CLI steps:

```bash
# Get the instance ARN and identity store ID
aws sso-admin list-instances --query 'Instances[0]' --output json
```

Save both values — you'll use them throughout this guide:

```bash
# Set these in your shell for convenience
export SSO_INSTANCE_ARN="arn:aws:sso:::instance/ssoins-xxxxxxxxxxxxxxxxx"
export IDENTITY_STORE_ID="d-xxxxxxxxxx"
```

## Step 2: Create a local Identity Center user

Use whatever username, given name, and family name you like — these are just display values and don't affect access. A first name and last name works fine; so does a handle or anything else you'll recognize.

```bash
aws identitystore create-user \
  --identity-store-id "$IDENTITY_STORE_ID" \
  --user-name <your-chosen-username> \
  --name '{"GivenName":"<FirstName>","FamilyName":"<LastName>","Formatted":"<FirstName> <LastName>"}' \
  --emails '[{"Value":"your-email@example.com","Type":"work","Primary":true}]'
```

Note the `UserId` in the response — you'll need it in Step 5:

```bash
export SSO_USER_ID="<UserId from output>"
```

AWS will send an activation email to the address you provided. Open it and set a password before continuing — the account assignments in Step 5 will succeed without this, but you won't be able to log in until the password is set.

## Step 3: Create an admin permission set

A permission set is a template that defines what level of access a user gets when they log in to an account. You'll create one that grants full `AdministratorAccess`.

```bash
aws sso-admin create-permission-set \
  --instance-arn "$SSO_INSTANCE_ARN" \
  --name "AdministratorAccess" \
  --description "Full administrator access for Pathfinding Labs accounts" \
  --session-duration "PT8H"
```

Note the `PermissionSetArn` from the output:

```bash
export PERMISSION_SET_ARN="arn:aws:sso:::permissionSet/ssoins-xxxxxxxxxxxxxxxxx/ps-xxxxxxxxxxxxxxxxx"
```

## Step 4: Attach the AdministratorAccess managed policy

```bash
aws sso-admin attach-managed-policy-to-permission-set \
  --instance-arn "$SSO_INSTANCE_ARN" \
  --permission-set-arn "$PERMISSION_SET_ARN" \
  --managed-policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"
```

## Step 5: Assign the permission set to each account

Get the account IDs for your three child accounts:

```bash
aws organizations list-accounts \
  --query 'Accounts[?Name==`pl-prod` || Name==`pl-dev` || Name==`pl-ops`].[Name,Id]' \
  --output table
```

Then create an account assignment for each one (replace the account IDs with your actual values):

```bash
export PROD_ACCOUNT_ID="<pl-prod account ID>"
export DEV_ACCOUNT_ID="<pl-dev account ID>"
export OPS_ACCOUNT_ID="<pl-ops account ID>"

for ACCOUNT_ID in "$PROD_ACCOUNT_ID" "$DEV_ACCOUNT_ID" "$OPS_ACCOUNT_ID"; do
  aws sso-admin create-account-assignment \
    --instance-arn "$SSO_INSTANCE_ARN" \
    --target-id "$ACCOUNT_ID" \
    --target-type "AWS_ACCOUNT" \
    --permission-set-arn "$PERMISSION_SET_ARN" \
    --principal-type "USER" \
    --principal-id "$SSO_USER_ID"
done
```

Each command returns a `AccountAssignmentCreationStatus` with a `RequestId`. The assignments are asynchronous — check that they all reach `SUCCEEDED`:

```bash
# Run for each RequestId printed above
aws sso-admin describe-account-assignment-creation-status \
  --instance-arn "$SSO_INSTANCE_ARN" \
  --account-assignment-creation-request-id "<RequestId>"
```

## Step 6: Configure AWS CLI profiles

Add an `sso-session` block and a profile for each account to `~/.aws/config`. Replace `<SSO_START_URL>` with the access portal URL from Step 1 and the account IDs with your real values.

```ini
[sso-session pathfinding-labs]
sso_start_url = https://d-xxxxxxxxxx.awsapps.com/start
sso_region = us-east-1
sso_registration_scopes = sso:account:access

[profile pl-prod]
sso_session = pathfinding-labs
sso_account_id = <PROD_ACCOUNT_ID>
sso_role_name = AdministratorAccess
region = us-east-1

[profile pl-dev]
sso_session = pathfinding-labs
sso_account_id = <DEV_ACCOUNT_ID>
sso_role_name = AdministratorAccess
region = us-east-1

[profile pl-ops]
sso_session = pathfinding-labs
sso_account_id = <OPS_ACCOUNT_ID>
sso_role_name = AdministratorAccess
region = us-east-1
```

## Step 7: Log in and verify

Authenticate once — this opens a browser to the access portal:

```bash
aws sso login --sso-session pathfinding-labs
```

Then verify each profile resolves to the correct account:

```bash
aws sts get-caller-identity --profile pl-prod
aws sts get-caller-identity --profile pl-dev
aws sts get-caller-identity --profile pl-ops
```

Each call should return the expected account ID and a `UserId` that includes your IAM Identity Center username.

## What you have now

- IAM Identity Center enabled in the management account with a local user directory (no external IdP needed).
- An `AdministratorAccess` permission set applied to `pl-prod`, `pl-dev`, and `pl-ops`.
- Three AWS CLI profiles backed by short-lived SSO credentials instead of long-lived access keys.
- A single `aws sso login` command that refreshes credentials for all three profiles at once.

## Next steps

Head back to the [setup guide](../README.md) and continue from **Step 2: Deploy Pathfinding Labs**. Use `pl-prod`, `pl-dev`, and `pl-ops` as the profile names when configuring `terraform.tfvars`.

## Re-authenticating

SSO sessions expire (default 8 hours for the permission set; the portal session itself defaults to 8 hours and is configurable up to 90 days). When credentials expire, re-run:

```bash
aws sso login --sso-session pathfinding-labs
```

You do not need separate logins per profile — one login refreshes all profiles that share the same `sso-session`.
