# Solution: Custom Role Update Self-Escalation to Admin

Custom roles are supposed to be GCP's answer to least privilege: instead of handing a workload a broad primitive role like `roles/editor`, you craft a role containing only the handful of permissions it actually needs. The trouble starts when one of those permissions is `iam.roles.update` and the same identity is also a *member* of the role it can edit. At that point the role is no longer a least-privilege boundary at all -- it is a self-service permission vending machine. The service account can add any permission it likes to the role, and because it holds the role, it instantly gains that permission.

This technique was documented by Rhino Security Labs in "Privilege Escalation in GCP (Part 1)" and is tracked by NetSPI's GCPwn as the `UPDATE_CUSTOM_ROLE_ADD_PERMISSIONS` edge, which carries the prerequisite that the source identity must already hold the custom role it updates. In this lab you'll start as a service account whose only interesting permission is `iam.roles.update` on a role it belongs to, and you'll walk that single capability all the way up to `roles/owner` on the project -- and then read a secret that owner access unlocks.

## The Challenge

You start as `pl-prod-gcp-iam-003-start`, a service account whose credentials (via impersonation) were provided to you. It has no `roles/owner`, no `roles/editor`, and no direct access to Secret Manager. What it *does* have is membership in a project custom role named `gcp_iam_003_editable`, and that role grants `iam.roles.update`.

That one permission is the whole game. `iam.roles.update` lets you modify a custom role's definition -- including the list of permissions the role grants. And since you are a member of `gcp_iam_003_editable`, every permission in that role is already yours. If you can add a permission to the role, you add it to yourself. Your target is `roles/owner` on the project, and the trophy behind it is a flag stored in Secret Manager that nobody has granted you access to -- yet.

## Reconnaissance

Start by confirming what you can and can't do. Check the active identity and try the thing you ultimately want:

```bash
gcloud auth list --filter=status:ACTIVE --format='value(account)'
# pl-prod-gcp-iam-003-start@<project_id>.iam.gserviceaccount.com

gcloud secrets versions access latest --secret=pl-gcp-iam-003-flag
# ERROR: (gcloud.secrets.versions.access) PERMISSION_DENIED: Permission
# 'secretmanager.versions.access' denied on resource ...
```

Denied, as expected. Now enumerate the project's custom roles to find the one you can edit:

```bash
gcloud iam roles list --project=<project_id>
```

One of them is `gcp_iam_003_editable`. Describe it to see exactly what it grants:

```bash
gcloud iam roles describe gcp_iam_003_editable --project=<project_id>
```

The `includedPermissions` list contains `iam.roles.update`. Combined with the fact that your service account is bound to this very role, that is the vulnerability: you hold the role, and the role lets you rewrite the role. Any permission you append becomes a permission you hold.

## Exploitation

The attack is two moves. First, manufacture a more dangerous permission by editing the role. Second, spend that permission to make yourself owner.

**Move 1 -- add `resourcemanager.projects.setIamPolicy` to the role you hold.** `resourcemanager.projects.setIamPolicy` is the permission that lets you rewrite the project's IAM policy, and it is exactly the capability you need to grant yourself a new role. Append it to the editable role:

```bash
gcloud iam roles update gcp_iam_003_editable \
  --project=<project_id> \
  --add-permissions=resourcemanager.projects.setIamPolicy \
  --impersonate-service-account=pl-prod-gcp-iam-003-start@<project_id>.iam.gserviceaccount.com
```

Under the hood, `gcloud` reads the role first (that's the `iam.roles.get` gcloud-mechanic) and then writes the full permission list back with your addition appended. The raw `roles.patch` API doesn't need the read at all -- `./demo_attack.sh --api-only` proves the attack works with only `iam.roles.update`. Either way, `resourcemanager.projects.setIamPolicy` was never granted to you by an administrator; you minted it for yourself. Give IAM a few seconds to propagate the change.

**Move 2 -- self-bind `roles/owner`.** Now that your role (and therefore you) holds `resourcemanager.projects.setIamPolicy`, add your own service account to the project IAM policy as an owner:

```bash
gcloud projects add-iam-policy-binding <project_id> \
  --member=serviceAccount:pl-prod-gcp-iam-003-start@<project_id>.iam.gserviceaccount.com \
  --role=roles/owner \
  --impersonate-service-account=pl-prod-gcp-iam-003-start@<project_id>.iam.gserviceaccount.com
```

`add-iam-policy-binding` is an additive read-modify-write; `gcloud` reads the current policy (the `resourcemanager.projects.getIamPolicy` gcloud-mechanic) and writes it back with your new `roles/owner` binding added. The raw `setIamPolicy` API doesn't require the preceding read. After another short propagation wait, you are a project owner.

## Verification

Confirm the owner binding landed and that you now have access you didn't before. The cleanest check is to try an operation that previously failed:

```bash
gcloud projects get-iam-policy <project_id> \
  --flatten="bindings[].members" \
  --filter="bindings.members:pl-prod-gcp-iam-003-start@<project_id>.iam.gserviceaccount.com" \
  --format="table(bindings.role)"
# roles/owner  (alongside the original custom role)
```

Your service account is now bound to `roles/owner` -- the same account that, minutes ago, held nothing but a custom role with `iam.roles.update`.

## Capture the Flag

The flag lives as the latest version of a Secret Manager secret, and `roles/owner` includes `secretmanager.versions.access`. Read it as the escalated service account:

```bash
gcloud secrets versions access latest \
  --secret=pl-gcp-iam-003-flag \
  --impersonate-service-account=pl-prod-gcp-iam-003-start@<project_id>.iam.gserviceaccount.com
```

This is the same command that returned `PERMISSION_DENIED` during reconnaissance. Nothing about the secret changed -- what changed is you. No `secretAccessor` role was ever pre-granted to your service account; the only reason you can read the flag now is that `roles/owner`, which you granted yourself, is a superset that happens to include secret payload access. The final read is performed as the escalated starting service account, not as any administrator who deployed the lab.

## What Happened

You escalated from a service account with zero administrative roles to full project ownership using a single starting permission: `iam.roles.update` on a custom role you were also a member of. The chain was two API calls -- edit the role to add `resourcemanager.projects.setIamPolicy`, then use that permission to self-bind `roles/owner` -- followed by reading a secret that owner access unlocked.

The lesson is subtle and easy to miss in a real environment. `iam.roles.update` does not look like a dangerous permission the way `roles/owner` does, so it survives access reviews. But the moment an identity is both a *member* of a custom role and able to *update* that role, the role stops being a least-privilege boundary: it becomes an open-ended grant of every permission the identity can later append. Detection should key on exactly that combination -- an identity holding effective `iam.roles.update` over a custom role it is also bound to -- rather than on any single permission in isolation.
