# Pathfinding Labs Setup

Before deploying, you need one or more AWS accounts with named CLI profiles. Which path you take depends on what you already have.

---

## Option A: One account (single-account scenarios only)

If you only have one AWS account and want to keep it simple, that works. The majority of Pathfinding Labs scenarios are single-account and will run fine with just `pl-prod`.

You just need a named AWS CLI profile pointing at that account. Once you have that, you're ready to run `plabs init`.

---

## Option B: Two or three accounts, already set up

If you already have three AWS accounts you want to use as `prod`, `dev`, and `ops`, you just need named CLI profiles for each. Once those are in place, run `plabs init`.

---

## Option C: Two or three accounts, starting from a single account

For this option to work, your initial account can not already be managed by an organization. 

If you want the full multi-account setup but don't have the accounts yet, we have step-by-step guides:

1. [Create an AWS Organization and three child accounts](create-org/README.md) — converts an existing account into an org management account and creates `pl-prod`, `pl-dev`, `pl-ops` as children.
2. [Configure IAM Identity Center with SSO profiles](configure-identity-center/README.md) — sets up a local Identity Center user with admin access to all three accounts and configures named AWS CLI profiles.

---

## Once prerequisites are met

Run `plabs init` — it will walk you through connecting your profiles and deploying scenarios.
