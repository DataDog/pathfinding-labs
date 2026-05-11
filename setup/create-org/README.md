# Set up an AWS Organization with `pl-prod`, `pl-dev`, and `pl-ops`

This guide walks you through converting an existing standalone AWS account into an **Organizations management account** and then creating three child accounts (`pl-prod`, `pl-dev`, `pl-ops`) using the AWS CLI. The whole thing takes about 10 minutes once you have the prerequisites in place.

## Before you start

You'll need:

- An existing AWS account that is **not already part of an Organization**.
- AWS CLI v2 installed and configured with admin credentials for that account. Test it: `aws sts get-caller-identity` should return your account ID.
- A single email address you control. We'll use [plus addressing](#about-plus-addressing) so one inbox handles all four accounts.

### About plus addressing

AWS requires every account — including the management account and each child — to have a unique root email. Gmail, Google Workspace, Fastmail, iCloud, Outlook 365, and most modern providers all support **plus addressing**: `you+anything@yourdomain.com` is delivered to `you@yourdomain.com`, but AWS treats it as a distinct email.

So if your real address is `cloud@example.com`, you can use:

| Account     | Email                       |
|-------------|-----------------------------|
| management  | `cloud@example.com` (already exists, no change) |
| pl-prod     | `cloud+pl-prod@example.com` |
| pl-dev      | `cloud+pl-dev@example.com`  |
| pl-ops      | `cloud+pl-ops@example.com`  |

All four route to the same inbox. **Send yourself a test email to `cloud+test@example.com` before continuing** to confirm your provider delivers it. (Some self-hosted or corporate setups strip the `+` part.)

## Step 1: Enable AWS Organizations

From your existing account, run:

```bash
aws organizations create-organization --feature-set ALL
```

That's it — this account is now the **management account** of a brand-new organization. Costs and billing from all child accounts will roll up to the payment method on the initial AWS account that can now be referred to as the **management account**. 

Verify:

```bash
aws organizations describe-organization
```

You should see your account listed as the `MasterAccountId`.

## Step 2: Create the three child accounts

`create-account` is asynchronous: it returns immediately with a request ID, and the account gets provisioned in the background (usually under a minute, sometimes a few).

Run these three commands, replacing the email domain with your own:

```bash
aws organizations create-account \
  --email cloud+pl-prod@example.com \
  --account-name pl-prod \
  --role-name OrganizationAccountAccessRole

aws organizations create-account \
  --email cloud+pl-dev@example.com \
  --account-name pl-dev \
  --role-name OrganizationAccountAccessRole

aws organizations create-account \
  --email cloud+pl-ops@example.com \
  --account-name pl-ops \
  --role-name OrganizationAccountAccessRole
```

Each command prints a `CreateAccountStatus` object — note the `Id` field (looks like `car-abc123…`); you'll use it to check progress.

The `--role-name OrganizationAccountAccessRole` flag tells AWS to automatically create a cross-account IAM role in each new account that your management account can assume. This means **you never need to log in to the child accounts as root** — you just `sts:AssumeRole` into them from the management account.

## Step 3: Wait for accounts to finish provisioning

Check status for each request:

```bash
aws organizations describe-create-account-status \
  --create-account-request-id car-abc123...
```

Look for `"State": "SUCCEEDED"` and an `AccountId` field. If you see `FAILED`, the `FailureReason` will tell you why — the most common ones are:

- `EMAIL_ALREADY_EXISTS` — the address is already on another AWS account. Pick a different plus-suffix.
- `ACCOUNT_LIMIT_EXCEEDED` — newer org master accounts cap out around 10 accounts by default. Open a support ticket via *Service Quotas → AWS Organizations → Number of accounts* to raise it.
- `INVALID_EMAIL` — your provider may not allow `+` in addresses; try a different one.

To list everything in your org at once:

```bash
aws organizations list-accounts --output table
```

## Step 4: Configure AWS profiles for each account

Once all accounts show `SUCCEEDED`, add profiles to `~/.aws/config` so you can address each account by name without session juggling:

```ini
[profile pl-prod]
role_arn = arn:aws:iam::<PL_PROD_ACCOUNT_ID>:role/OrganizationAccountAccessRole
source_profile = default

[profile pl-dev]
role_arn = arn:aws:iam::<PL_DEV_ACCOUNT_ID>:role/OrganizationAccountAccessRole
source_profile = default

[profile pl-ops]
role_arn = arn:aws:iam::<PL_OPS_ACCOUNT_ID>:role/OrganizationAccountAccessRole
source_profile = default
```

Replace `<PL_PROD_ACCOUNT_ID>` etc. with the account IDs from `aws organizations list-accounts`.

Verify each profile works:

```bash
aws sts get-caller-identity --profile pl-prod
aws sts get-caller-identity --profile pl-dev
aws sts get-caller-identity --profile pl-ops
```

## What you have now

- A management account with AWS Organizations enabled (`ALL` features).
- Three child accounts (`pl-prod`, `pl-dev`, `pl-ops`), each with a unique root email routing to your shared inbox.
- A cross-account admin role in each child that you can assume from the management account.
- Three named AWS profiles ready to use with `plabs` and Terraform.

## Next steps

Head back to the [setup guide](../README.md) and continue from **Step 2: Deploy Pathfinding Labs**.

### Hardening (optional but recommended)

- **Lock down root** on each child: use "forgot password" on the child's root email, set a strong password, enable MFA, then never use it again.
- **Enable IAM Identity Center** (formerly SSO) so humans get federated access instead of long-lived IAM users.


## Undoing this

Child accounts can be closed via `aws organizations close-account --account-id <id>` (there's a 90-day grace period before permanent deletion). The organization itself can be deleted with `aws organizations delete-organization` only after all child accounts have been removed or closed.
