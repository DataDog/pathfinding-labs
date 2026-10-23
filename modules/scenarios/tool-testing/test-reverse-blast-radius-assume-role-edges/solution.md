# Solution: Reverse Blast Radius Assume-Role Edge Correctness

This scenario validates the single most load-bearing edge in any reverse blast radius answer: the `sts:AssumeRole` edge. A same-account assume-role is allowed only when BOTH halves line up -- the caller's identity policy must allow `sts:AssumeRole` on the role, and the role's trust policy must allow the caller. Get either side wrong and your graph is wrong. A tool that reads only identity policies draws edges that do not exist; a tool that reads only trust policies does the same in the other direction.

There is a third subtlety that trips up both tools and humans. A trust policy that grants to the account `root` does not grant assumption to the entire account. It delegates the decision to identity policies. A caller covered by a `root` trust still needs its own `sts:AssumeRole` permission, and a caller that has that identity permission can assume even though it is not named explicitly. This lab builds five users around exactly these cases so you can prove, with real AWS calls, which can reach a bucket and which cannot -- then compare that ground truth to what your security tool reports.

## The Challenge

You hold credentials for five IAM users, each satisfying a different combination of the two halves of a same-account assume-role:

- `pl-prod-rbr-are-both` -- identity `sts:AssumeRole` on `pl-prod-rbr-are-target-role`, and named in that role's trust (both halves)
- `pl-prod-rbr-are-identity-only` -- identity `sts:AssumeRole` on `target-role`, but NOT named in its trust (identity only)
- `pl-prod-rbr-are-trust-only` -- named in `target-role`'s trust, but no identity `sts:AssumeRole` (trust only)
- `pl-prod-rbr-are-root-with-identity` -- identity `sts:AssumeRole` on `pl-prod-rbr-are-target-role-root`, whose trust grants to `root` (identity + root trust)
- `pl-prod-rbr-are-root-no-identity` -- covered by `target-role-root`'s `root` trust, but no identity `sts:AssumeRole` (root trust only)

Two roles complete the graph. `pl-prod-rbr-are-target-role` reads the bucket directly and trusts exactly `are-both` and `are-trust-only`. `pl-prod-rbr-are-target-role-root` reads the bucket directly and trusts the account `root`. The target is `pl-sensitive-data-rbr-are-{account_id}-{suffix}`. Your goal is to prove who can read it and compare that against your tool's reverse blast radius answer.

## Reconnaissance

Start by confirming who you are for each set of credentials:

```bash
export AWS_ACCESS_KEY_ID="<are_both_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<are_both_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity --query 'Arn' --output text
# Expected: arn:aws:iam::{account_id}:user/pl-prod-rbr-are-both
```

The graph is documented, so the work is proving it. Before exploiting anything, note the prediction so you can check it against reality: only `are-both` and `are-root-with-identity` should be able to assume a bucket-reading role. The other three each satisfy only one half of the requirement and should be denied.

| User | Identity allows assume? | Trust allows caller? | Can assume? |
| -- | -- | -- | -- |
| are-both | yes (target-role) | yes (named) | YES |
| are-identity-only | yes (target-role) | no | NO |
| are-trust-only | no | yes (named) | NO |
| are-root-with-identity | yes (target-role-root) | yes (root defers to identity) | YES |
| are-root-no-identity | no | yes (root) | NO |

## Exploitation

### Both halves satisfied (are-both)

As `are-both`, assume `target-role` and read the bucket:

```bash
CREDENTIALS=$(aws sts assume-role \
    --role-arn "arn:aws:iam::{account_id}:role/pl-prod-rbr-are-target-role" \
    --role-session-name rbr-are-both \
    --query 'Credentials' --output json)

export AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS" | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS" | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$CREDENTIALS" | jq -r '.SessionToken')

aws s3 ls "s3://pl-sensitive-data-rbr-are-{account_id}-{suffix}/"
aws s3 cp "s3://pl-sensitive-data-rbr-are-{account_id}-{suffix}/sensitive-data.txt" /tmp/rbr-are-sensitive.txt
```

This works because both halves line up: `are-both` has the identity permission and is named in `target-role`'s trust. The assumed session inherits the role's `s3:GetObject` and `s3:ListBucket`.

### Identity + root trust (are-root-with-identity)

Switch to `are-root-with-identity` and assume `target-role-root`:

```bash
unset AWS_SESSION_TOKEN
export AWS_ACCESS_KEY_ID="<are_root_with_identity_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<are_root_with_identity_secret_access_key>"

CREDENTIALS=$(aws sts assume-role \
    --role-arn "arn:aws:iam::{account_id}:role/pl-prod-rbr-are-target-role-root" \
    --role-session-name rbr-are-root-with-identity \
    --query 'Credentials' --output json)

export AWS_ACCESS_KEY_ID=$(echo "$CREDENTIALS" | jq -r '.AccessKeyId')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDENTIALS" | jq -r '.SecretAccessKey')
export AWS_SESSION_TOKEN=$(echo "$CREDENTIALS" | jq -r '.SessionToken')

aws s3 ls "s3://pl-sensitive-data-rbr-are-{account_id}-{suffix}/"
```

The role's trust names only the account `root`, which on its own trusts no one in particular -- it defers to identity policies. Because this user holds the identity `sts:AssumeRole` permission on the role, that is enough. The assume succeeds and the session reads the bucket.

### Identity only (are-identity-only)

Switch to `are-identity-only` and attempt the same assume as `are-both`:

```bash
unset AWS_SESSION_TOKEN
export AWS_ACCESS_KEY_ID="<are_identity_only_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<are_identity_only_secret_access_key>"

aws sts assume-role \
    --role-arn "arn:aws:iam::{account_id}:role/pl-prod-rbr-are-target-role" \
    --role-session-name rbr-are-identity-only \
    --query 'Credentials' --output json
# Expected: An error occurred (AccessDenied) when calling the AssumeRole operation
```

The identity policy allows the call, but `target-role`'s trust policy names only `are-both` and `are-trust-only` -- not this user. One half is missing, so the assume is denied. A tool that reads only identity policies would wrongly report this user as a bucket reader.

### Trust only (are-trust-only)

Switch to `are-trust-only`, which IS named in `target-role`'s trust but has no identity `sts:AssumeRole`:

```bash
export AWS_ACCESS_KEY_ID="<are_trust_only_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<are_trust_only_secret_access_key>"

aws sts assume-role \
    --role-arn "arn:aws:iam::{account_id}:role/pl-prod-rbr-are-target-role" \
    --role-session-name rbr-are-trust-only \
    --query 'Credentials' --output json
# Expected: An error occurred (AccessDenied) when calling the AssumeRole operation
```

The role trusts this user, but the user's own policy grants only `sts:GetCallerIdentity`. Without an identity permission to call `sts:AssumeRole`, the assume is denied. A tool that reads only trust policies would wrongly report this user as a bucket reader.

### Root trust, no identity (are-root-no-identity)

Finally, switch to `are-root-no-identity` and attempt to assume `target-role-root`:

```bash
export AWS_ACCESS_KEY_ID="<are_root_no_identity_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<are_root_no_identity_secret_access_key>"

aws sts assume-role \
    --role-arn "arn:aws:iam::{account_id}:role/pl-prod-rbr-are-target-role-root" \
    --role-session-name rbr-are-root-no-identity \
    --query 'Credentials' --output json
# Expected: An error occurred (AccessDenied) when calling the AssumeRole operation
```

The role's `root` trust defers to identity policies, and this user has no identity `sts:AssumeRole` permission. The assume is denied. A tool that treats a `root` trust as granting the entire account would wrongly report this user as a bucket reader.

## Verification

Every claim is now backed by a real call:

- `are-both` assumed `target-role` and read the bucket (both halves satisfied)
- `are-root-with-identity` assumed `target-role-root` and read the bucket (identity + root trust)
- `are-identity-only`, `are-trust-only`, and `are-root-no-identity` were each denied, each missing exactly one half

Now run a reverse blast radius query in your security tool against the bucket and compare:

- Direct readers should be exactly `target-role` and `target-role-root`
- Users that can reach the bucket by assuming exactly one role should be exactly `are-both` and `are-root-with-identity`
- `are-identity-only`, `are-trust-only`, and `are-root-no-identity` must NOT appear in any "who can read the bucket" answer

If your tool includes `are-identity-only`, it is reading only identity policies. If it includes `are-trust-only` or `are-root-no-identity`, it is reading only trust policies -- or treating a `root` trust as an account-wide grant. Either way, the can_assume edge is wrong, and every reverse blast radius answer that depends on it is wrong too.

## What Happened

You exercised the five distinct ways a same-account assume-role can line up or fail to line up, and proved with real STS calls which users can reach a sensitive bucket. Only the two users satisfying both halves of the requirement -- an identity `sts:AssumeRole` grant and a matching role trust -- could assume a bucket-reading role. The three users satisfying only one half were denied, and the `root`-trust role correctly deferred to identity policies.

This is the foundation of every reverse blast radius answer. In real environments, trust policies and identity policies are maintained by different teams, drift apart over time, and frequently include `root` trusts that look permissive but aren't. A graph tool that gets the can_assume edge wrong will either overstate exposure (false positives that bury real findings in noise) or understate it (false negatives that hide the principals nobody remembers granting access). Use this lab as a repeatable test that your tool models both halves of the assume-role decision correctly before trusting it with anything deeper.
