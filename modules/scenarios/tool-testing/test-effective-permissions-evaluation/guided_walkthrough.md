# Guided Walkthrough: Comprehensive Effective Permissions Evaluation Testing

This scenario is unlike any other in Pathfinding Labs. Rather than demonstrating a single exploitation path, it deploys 40 carefully crafted IAM principals — 15 with genuine effective admin access and 24 that look privileged but are not — and asks a deceptively simple question: does your security tooling get it right?

The challenge is real. Evaluating effective AWS permissions is harder than it looks. IAM policy evaluation is a layered system of allows, denies, boundaries, group memberships, and multi-policy aggregation. Any tool that shortcuts this process will produce false positives or false negatives, and both are dangerous in production. This scenario gives you a controlled benchmark with known-correct answers.

Organizations deploying CSPM tools, IAM analyzers, or building custom security tooling can use this scenario to measure accuracy with precision. False positives (flagging restricted principals as admin) and false negatives (missing actual admin access) both represent critical gaps in security posture visibility. The admin definition used throughout is deliberate: **`*` on `*` without any IAM denies (ignoring resource-based denies)**.

## The Challenge

You start as `pl-prod-epe-starting-user`, an IAM user with `sts:AssumeRole` access to all 39 test principals. The target is `pl-sensitive-data-epe-{account_id}-{suffix}`, an S3 bucket that isAdmin principals can list and notAdmin principals cannot.

Your goal is not to escalate privileges yourself — it is to validate that your CSPM or IAM analyzer correctly classifies every principal. Run the demo script and score your tool.

**Perfect score:**
- True Positives (TP) = 15 (all isAdmin correctly flagged)
- False Negatives (FN) = 0 (no isAdmin missed)
- True Negatives (TN) = 24 (all notAdmin correctly cleared)
- False Positives (FP) = 0 (no notAdmin wrongly flagged)
- Accuracy = 100%, Precision = 100%, Recall = 100%

## Reconnaissance

First, confirm your starting identity and verify you can reach the test bucket:

```bash
export AWS_ACCESS_KEY_ID="<starting_user_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<starting_user_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts get-caller-identity
```

You should see `pl-prod-epe-starting-user` as the ARN. Now confirm basic S3 connectivity using the starting user (which does not have S3 access itself):

```bash
aws s3 ls s3://pl-sensitive-data-epe-<account_id>-<suffix>/
# Expected: AccessDenied — starting user has no S3 permissions
```

This confirms the bucket exists and that access control is working. Next, verify you can assume one of the isAdmin test roles:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::<account_id>:role/pl-prod-epe-role-isAdmin-awsmanaged \
  --role-session-name recon-test
```

You should receive temporary credentials. Export them and confirm S3 access:

```bash
export AWS_ACCESS_KEY_ID="<temp_access_key>"
export AWS_SECRET_ACCESS_KEY="<temp_secret_key>"
export AWS_SESSION_TOKEN="<temp_session_token>"

aws s3 ls s3://pl-sensitive-data-epe-<account_id>-<suffix>/
# Expected: success — this role has AdministratorAccess
```

Now try a notAdmin role to confirm blocking works:

```bash
# Back to starting user first
export AWS_ACCESS_KEY_ID="<starting_user_access_key_id>"
export AWS_SECRET_ACCESS_KEY="<starting_user_secret_access_key>"
unset AWS_SESSION_TOKEN

aws sts assume-role \
  --role-arn arn:aws:iam::<account_id>:role/pl-prod-epe-role-notAdmin-adminpolicy-plus-denyall \
  --role-session-name recon-test-deny

export AWS_ACCESS_KEY_ID="<temp_access_key>"
export AWS_SECRET_ACCESS_KEY="<temp_secret_key>"
export AWS_SESSION_TOKEN="<temp_session_token>"

aws s3 ls s3://pl-sensitive-data-epe-<account_id>-<suffix>/
# Expected: AccessDenied — explicit Deny * on * blocks everything
```

This is the core dynamic of the scenario: policies that look identical at first glance (`AdministratorAccess` attached in both cases) but produce opposite outcomes at runtime.

## Exploitation

This scenario is not exploited in the traditional sense — you are the tester, not the attacker. The "exploitation" is running the validation suite against all 39 principals and measuring your CSPM tool's accuracy.

### Step 1: Run the automated demo script

```bash
plabs demo test-effective-permissions-evaluation
```

Or manually:

```bash
cd modules/scenarios/tool-testing/test-effective-permissions-evaluation
./demo_attack.sh
```

The script iterates through all 39 principals in order. For users, it tests directly with their credentials. For roles, it assumes each role using the starting user, then tests with the resulting session. Each test makes two API calls:

1. `aws s3 ls s3://<bucket>/` — tests S3 access
2. `aws iam list-users --max-items 1` — tests IAM read access

If both succeed, the principal is classified as `admin`. If both fail, it is classified as `not-admin`. The result is compared against the expected classification and scored pass/fail.

### Step 2: Point your CSPM tool at the account

While the demo script tests runtime access, the more valuable test is static analysis:

1. Deploy the scenario and let your CSPM or IAM analyzer scan the account
2. Wait for discovery and analysis to complete
3. Export findings related to admin access and privilege escalation

### Step 3: Compare against expected outcomes

The 39 test principals fall into two categories with these expected classifications:

**isAdmin — should be flagged as having admin access (15 principals):**

| Category | Pattern | Count |
|----------|---------|-------|
| Single Policy | AWS managed, customer managed, or inline AdministratorAccess | 6 |
| Group Membership | Users in groups with admin policies | 3 |
| Multi-Policy | Split policies that together equal `*` on `*` | 6 |

**notAdmin — should NOT be flagged as admin (24 principals):**

| Category | Pattern | Count |
|----------|---------|-------|
| Single Deny | Admin + Deny `*` on `*` (or Deny NotAction with exceptions) | 6 |
| Multi-Deny | Admin + multiple denies that together block everything | 6 |
| Single Boundary | Admin + boundary that allows nothing or only one action | 6 |
| Multi-Policy + Boundary | Split allows + boundary that restricts or mismatches | 6 |

### Step 4: Calculate accuracy metrics

```
True Positives (TP):  isAdmin principals correctly identified as admin
False Negatives (FN): isAdmin principals incorrectly identified as not-admin
True Negatives (TN):  notAdmin principals correctly identified as not-admin
False Positives (FP): notAdmin principals incorrectly identified as admin

Accuracy  = (TP + TN) / 39
Precision = TP / (TP + FP)
Recall    = TP / (TP + FN)
```

## Verification

After the demo script completes, you will see a summary like:

```
isAdmin Results:
  Correct: 15 / 15
  Incorrect: 0 / 15

notAdmin Results:
  Correct: 24 / 24
  Incorrect: 0 / 24

ALL TESTS PASSED (39/39)
```

If your CSPM tool produces the same classification for all 39 principals, it correctly evaluates effective permissions across all tested patterns. Any divergence reveals a gap in your tool's evaluation engine.

## What Happened

This scenario exposes the seven most common failure modes in IAM effective permissions evaluation:

1. **Group membership blind spots** — tools that only look at directly attached policies miss permissions inherited via group memberships.
2. **Multi-policy aggregation failures** — tools that evaluate each policy in isolation miss cases where two policies together equal `*` on `*` (e.g., `iam:*` + `NotAction iam:*`).
3. **Explicit deny blindness** — tools that only count allows and ignore denies will flag notAdmin principals as admin.
4. **Split deny confusion** — `Deny iam:*` + `Deny NotAction iam:*` is equivalent to `Deny *`, but many tools process each deny independently and miss the total coverage.
5. **Boundary intersection errors** — effective permissions are the intersection of identity policies and the boundary, not their union. Tools that treat boundaries as additive rather than restrictive will over-report permissions.
6. **Deny-only boundary misreading** — a boundary that contains only deny statements (or has no explicit allows) grants nothing, regardless of identity policies. Some tools treat this as "boundary allows everything" if they fail to parse the boundary correctly.
7. **Boundary mismatch blindness** — when identity policies allow only S3/EC2 and the boundary allows only IAM/Lambda, there is zero overlap and the principal has no effective permissions. Tools that evaluate each side independently without computing the intersection will miss this.

In real environments these patterns appear regularly — especially boundaries on delegated admin accounts, complex multi-policy configurations used for least-privilege role design, and inherited group permissions in large organizations. A tool that scores less than 100% on this benchmark will produce inaccurate blast radius analysis and privilege escalation detection.
