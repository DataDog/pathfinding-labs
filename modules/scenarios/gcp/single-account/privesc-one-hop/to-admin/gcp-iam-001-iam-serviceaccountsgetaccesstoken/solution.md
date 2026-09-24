# Solution: Service Account Access Token Generation to Admin

Service account impersonation is one of the most common ways GCP environments quietly accumulate privilege escalation paths. It is a legitimate and widely recommended pattern -- automation identities are supposed to impersonate more privileged service accounts rather than holding long-lived keys for them -- but the moment the impersonation grant crosses a privilege boundary that nobody is tracking, it becomes a ready-made escalation path. The permission behind this, `iam.serviceAccounts.getAccessToken`, does not show up in most people's mental model of "dangerous permissions" the way `roles/owner` does, which is exactly why it tends to survive access reviews unnoticed -- whether it arrives via the predefined `roles/iam.serviceAccountTokenCreator` role or, as in this lab, a custom role scoped to just that one permission.

In this lab, you'll start as a service account with no meaningful project permissions of its own and end up reading a secret that requires `roles/editor` to access. The entire escalation happens through a single IAM binding that most engineers would glance past without a second thought.

## The Challenge

You start as `pl-prod-gcp-iam-001-start`, a service account whose credentials (via impersonation) were provided to you. On its own, this service account has no project-level IAM roles -- it can't read Compute Engine instances, it can't list Cloud Storage buckets, and it certainly can't read Secret Manager secrets.

Somewhere in the project, though, there's a second service account: `pl-prod-gcp-iam-001-target`. That account holds `roles/editor` on the project -- one of GCP's broadest primitive roles, covering read/write access to nearly every resource type, including Secret Manager. Your job is to find a way to operate as that account.

## Reconnaissance

Start by confirming what you're actually working with. Check the active identity and see what it can and can't do:

```bash
gcloud auth list --filter=status:ACTIVE --format='value(account)'
# pl-prod-gcp-iam-001-start@<project_id>.iam.gserviceaccount.com

gcloud secrets versions access latest --secret=pl-gcp-iam-001-flag
# ERROR: (gcloud.secrets.versions.access) PERMISSION_DENIED: Permission
# 'secretmanager.versions.access' denied on resource ...
```

No direct access, as expected. Now look at what IAM bindings exist on other service accounts in the project. If you have `iam.serviceAccounts.list` and `iam.serviceAccounts.getIamPolicy` available, you can enumerate every service account and inspect its policy:

```bash
gcloud iam service-accounts list --format='value(email)'

gcloud iam service-accounts get-iam-policy \
  pl-prod-gcp-iam-001-target@<project_id>.iam.gserviceaccount.com
```

The policy on `pl-prod-gcp-iam-001-target` includes a binding granting a custom role -- one scoped to exactly `iam.serviceAccounts.getAccessToken` -- to `pl-prod-gcp-iam-001-start`. That single binding is the entire vulnerability: it means your starting service account is allowed to mint OAuth access tokens that authenticate as the target account, without ever needing a key file or password for it. In the wild you'll see this same permission delivered via the predefined `roles/iam.serviceAccountTokenCreator` role just as often as through a custom role like this one -- both grant the identical capability.

A quick check of the target account's own project-level role confirms why this matters:

```bash
gcloud projects get-iam-policy <project_id> \
  --flatten="bindings[].members" \
  --filter="bindings.members:pl-prod-gcp-iam-001-target@<project_id>.iam.gserviceaccount.com" \
  --format="table(bindings.role)"
# roles/editor
```

`roles/editor` on the project. That's the prize.

## Exploitation

Holding `iam.serviceAccounts.getAccessToken` on a service account authorizes you to call the `generateAccessToken` API method against it, which mints a short-lived OAuth 2.0 access token scoped to the impersonated service account. `gcloud` wraps this for you with the `--impersonate-service-account` flag, so you rarely need to call the underlying API directly.

Mint a token for the target and confirm the identity switch:

```bash
gcloud auth print-access-token \
  --impersonate-service-account=pl-prod-gcp-iam-001-target@<project_id>.iam.gserviceaccount.com
```

This returns a bearer token that is valid for a short window (typically one hour) and authenticates every subsequent API call as `pl-prod-gcp-iam-001-target`. Under the hood, `gcloud` is calling `generateAccessToken` on your behalf, authorized by the `iam.serviceAccounts.getAccessToken` grant you found during reconnaissance.

From this point forward, any `gcloud` command run with `--impersonate-service-account` set to the target account executes as that account -- with all of its `roles/editor` project permissions attached.

## Verification

Confirm that you are now operating with the target account's privileges rather than your own. A simple check is trying an operation your starting account couldn't do, this time with impersonation active:

```bash
gcloud secrets list --impersonate-service-account=pl-prod-gcp-iam-001-target@<project_id>.iam.gserviceaccount.com
```

Where the starting account got a `PERMISSION_DENIED`, the impersonated call succeeds and lists Secret Manager secrets in the project -- direct evidence that the target account's project-level access is now working in your favor.

## Capture the Flag

The CTF flag lives as the latest version of a Secret Manager secret. With the impersonation token active, read it directly:

```bash
gcloud secrets versions access latest \
  --secret=pl-gcp-iam-001-flag \
  --impersonate-service-account=pl-prod-gcp-iam-001-target@<project_id>.iam.gserviceaccount.com
```

This works because `roles/editor` alone does *not* grant `secretmanager.versions.access` -- Google deliberately excludes secret payload access from `roles/editor`/`roles/viewer` -- so the lab grants `roles/secretmanager.secretAccessor` directly on this secret to the target service account. Impersonating the target account gets you both: its `roles/editor` project permissions and its explicit `secretAccessor` grant on the flag. You never needed a role of your own; you only needed the ability to borrow the identity of an account that already had both.

## What Happened

You escalated from a service account with zero project-level permissions to one holding `roles/editor` -- and from there to a project secret -- entirely through a single misconfigured IAM binding: `iam.serviceAccounts.getAccessToken` granted across a privilege boundary. No keys were stolen, no passwords were guessed, and no vulnerability in application code was exploited. The entire attack was two `gcloud` commands using a permission that is easy to grant and easy to forget about.

This pattern shows up constantly in real GCP environments because service account impersonation is the *recommended* alternative to long-lived service account keys. Teams correctly move away from JSON key files, but in doing so they often grant impersonation rights broadly -- to a CI/CD pipeline's identity, to a shared "automation" service account, or to entire groups, via either `roles/iam.serviceAccountTokenCreator` or a custom role bundling `getAccessToken` -- without tracking which of those impersonation targets hold elevated project roles. The result is a privilege escalation graph hiding inside what looks, on the surface, like a security improvement.
