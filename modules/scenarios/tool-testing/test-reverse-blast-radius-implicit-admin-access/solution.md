# Solution: Implicit Admin Access to Bucket

This scenario tests a quiet but important gap in security tooling. The pathfinding graph backend intentionally does not create an edge from every administrator to every resource in the account. That keeps the graph small, but it means a reverse blast radius query such as "who can read this bucket?" or "who can write to this bucket?" can leave administrators out of the answer, while principals with explicit S3 statements show up as expected.

That is a problem in practice. An administrator with `AdministratorAccess` or an inline `Action: *` policy can read and overwrite your most sensitive bucket just as easily as the principal named in the bucket's access policy. A tool that only follows explicit grants understates the real blast radius, and teams that rely on those answers to scope incidents or review access will miss their most powerful principals.

This lab gives you a fixed truth table to test a tool against. Two principals have explicit S3 statements, two administrators have none, and one user has nothing at all.

## The Challenge

You have credentials for these principals:

- `pl-prod-rbr-ia-reader-user` -- explicit `s3:GetObject` and `s3:ListBucket` on the bucket
- `pl-prod-rbr-ia-writer-user` -- explicit `s3:PutObject` on the bucket
- `pl-prod-rbr-ia-admin-user` -- the `AdministratorAccess` managed policy, no S3 statements
- `pl-prod-rbr-ia-admin-role` -- an inline policy with `Action: *` on `Resource: *`, no S3 statements. Its trust policy trusts only `ec2.amazonaws.com`, so nobody can assume it
- `pl-prod-rbr-ia-no-access-user` -- a negative control with no policies

The target is the `pl-sensitive-data-rbr-ia-{account_id}-{suffix}` bucket, which has no bucket policy. Your goal is to confirm the real access matrix and then check that your security tool reports it correctly.

## Reconnaissance

Start by confirming who you are for each set of credentials:

```bash
aws sts get-caller-identity --query 'Arn' --output text
# Expected: arn:aws:iam::{account_id}:user/pl-prod-rbr-ia-reader-user
```

Then look at what each principal actually has. The administrators are the interesting ones:

```bash
aws iam list-attached-user-policies --user-name pl-prod-rbr-ia-admin-user
# Expected: AdministratorAccess

aws iam list-role-policies --role-name pl-prod-rbr-ia-admin-role
aws iam get-role-policy --role-name pl-prod-rbr-ia-admin-role --policy-name pl-prod-rbr-ia-admin-role-policy
# Expected: Action "*" on Resource "*", no S3 statement
```

Neither administrator mentions S3 anywhere. Also check the role's trust policy:

```bash
aws iam get-role --role-name pl-prod-rbr-ia-admin-role --query 'Role.AssumeRolePolicyDocument'
```

Only `ec2.amazonaws.com` is trusted. No user can assume this role, so any tool that finds it must do so from its own permissions, not from a path leading into it.

## Exploitation

### Explicit principals

As `reader-user`, list and read the bucket, then confirm a write is denied:

```bash
aws s3 ls "s3://pl-sensitive-data-rbr-ia-{account_id}-{suffix}/"
aws s3 cp "s3://pl-sensitive-data-rbr-ia-{account_id}-{suffix}/sensitive-data.txt" -
echo test | aws s3 cp - "s3://pl-sensitive-data-rbr-ia-{account_id}-{suffix}/rbr-ia-demo/reader-probe.txt"
# Expected: AccessDenied on the write
```

As `writer-user`, the opposite holds. A write succeeds and a read is denied:

```bash
echo 'rbr-ia write test' | aws s3 cp - "s3://pl-sensitive-data-rbr-ia-{account_id}-{suffix}/rbr-ia-demo/writer-probe.txt"
aws s3 cp "s3://pl-sensitive-data-rbr-ia-{account_id}-{suffix}/sensitive-data.txt" -
# Expected: AccessDenied on the read
```

### Implicit administrator: admin-user

As `admin-user`, read and write the bucket. Both succeed, even though no policy attached to this user mentions S3:

```bash
aws s3 cp "s3://pl-sensitive-data-rbr-ia-{account_id}-{suffix}/sensitive-data.txt" -
echo 'rbr-ia write test' | aws s3 cp - "s3://pl-sensitive-data-rbr-ia-{account_id}-{suffix}/rbr-ia-demo/admin-probe.txt"
```

This is the edge a tool must infer. It exists only because administrator permissions cover every action on every resource.

### Implicit administrator: admin-role

You cannot assume `admin-role`, so use policy simulation to see what it is allowed to do:

```bash
aws iam simulate-principal-policy \
  --policy-source-arn "arn:aws:iam::{account_id}:role/pl-prod-rbr-ia-admin-role" \
  --action-names s3:GetObject s3:PutObject \
  --resource-arns "arn:aws:s3:::pl-sensitive-data-rbr-ia-{account_id}-{suffix}/sensitive-data.txt" \
  --query 'EvaluationResults[*].[EvalActionName,EvalDecision]' --output text
# Expected: both allowed
```

### The negative control

As `no-access-user`, every bucket operation is denied:

```bash
aws s3 ls "s3://pl-sensitive-data-rbr-ia-{account_id}-{suffix}/"
# Expected: AccessDenied
```

## Verification

The real access matrix is now confirmed with live calls and policy simulation. This is what a correct tool should return.

Query: "Who can read `pl-sensitive-data-rbr-ia-{account_id}-{suffix}`?"

```
- arn:aws:iam::{account_id}:user/pl-prod-rbr-ia-reader-user
- arn:aws:iam::{account_id}:user/pl-prod-rbr-ia-admin-user
- arn:aws:iam::{account_id}:role/pl-prod-rbr-ia-admin-role
```

Query: "Who can write to `pl-sensitive-data-rbr-ia-{account_id}-{suffix}`?"

```
- arn:aws:iam::{account_id}:user/pl-prod-rbr-ia-writer-user
- arn:aws:iam::{account_id}:user/pl-prod-rbr-ia-admin-user
- arn:aws:iam::{account_id}:role/pl-prod-rbr-ia-admin-role
```

`pl-prod-rbr-ia-no-access-user` must appear in neither. If your tool returns only reader-user for reads and only writer-user for writes, it is dropping implicit administrators. If it returns admin-user but not admin-role, it handles the managed policy but not the inline wildcard, or it needs an inbound assume-role path to find the role.

## What Happened

You saw that administrator access is access to everything, but that is not always represented as an edge in a security graph. The explicit principals are easy to find because their policies name the bucket. The administrators are easy to miss because nothing names the bucket at all, and one of them has no inbound path either.

In real environments this matters most for incident scoping and access reviews. If "who can read this bucket?" leaves out every administrator, the answer understates the real exposure. This lab gives you a repeatable truth table to check whether your tooling either includes administrators in reverse blast radius answers or clearly tells you how to account for them.
