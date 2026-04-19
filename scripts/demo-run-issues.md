# Demo Run Issues

Recorded after capture run on 2026-04-17. 65 demos ran; 35 reported failures.
19 of those were a false failure caused by a bug in `scripts/lib/demo_permissions.sh`
(the `EXIT` trap always exited 130 even on success — now fixed). The remaining
failures below are real and need attention.

---

## 1. Demo restriction deny policy blocking a required permission

The `restrict_helpful_permissions` function in `demo_permissions.sh` attaches a deny
policy for permissions listed under `permissions.helpful` in `scenario.yaml`. These
scenarios have a required permission incorrectly classified as helpful, so the deny
policy breaks the attack mid-run.

### lambda-002

**Path:** `modules/scenarios/single-account/privesc-one-hop/to-admin/lambda-002-iam-passrole+lambda-createfunction+createeventsourcemapping-dynamodb/`

**Error:**
```
Error: Could not retrieve DynamoDB stream ARN
AccessDeniedException: not authorized to perform: dynamodb:DescribeTable
... with an explicit deny in an identity-based policy
```

**Fix:** Remove `dynamodb:DescribeTable` from `permissions.helpful` in `scenario.yaml`.
It is a required step in the attack path, not a shortcut.

---

### iam-003 (to-admin)

**Path:** `modules/scenarios/single-account/privesc-one-hop/to-admin/iam-003-iam-deleteaccesskey+createaccesskey/`

**Errors (two separate bugs):**

1. Deny policy blocks `iam:ListAccessKeys` on the target user, which the attack
   requires to enumerate existing keys before deleting one.
   ```
   AccessDenied: not authorized to perform: iam:ListAccessKeys
   ... with an explicit deny in an identity-based policy
   ```
2. Bash integer comparison error downstream: `line 164: [: : integer expected`
   — the key count variable is empty because `ListAccessKeys` was denied, so the
   comparison `[ $count -gt 0 ]` (or similar) blows up.

**Fix:**
- Remove `iam:ListAccessKeys` from `permissions.helpful` in `scenario.yaml`.
- Guard the key count comparison against an empty/non-integer value, e.g.
  `[ "${count:-0}" -gt 0 ]`.

---

### iam-003 (to-bucket)

**Path:** `modules/scenarios/single-account/privesc-one-hop/to-bucket/iam-003-iam-deleteaccesskey+createaccesskey/`

**Errors (two separate bugs):**

1. Same deny policy issue as to-admin: `iam:ListAccessKeys` blocked.
2. Scenario setup: the demo expects the target user to be at the AWS 2-key limit
   (requires deleting one key first), but Terraform only provisions 1 key for the
   target user.
   ```
   Error: Expected 2 access keys but found 1
   This scenario requires the target user to be at the AWS 2-key limit
   ```

**Fix:**
- Remove `iam:ListAccessKeys` from `permissions.helpful` in `scenario.yaml`.
- In `main.tf`, create a second dummy access key for the target user so the scenario
  starts at the 2-key limit as designed.

---

## 2. Empty Terraform output — role ARN not wired up

### sts-001-to-ecs-002-to-admin

**Path:** `modules/scenarios/single-account/privesc-multi-hop/to-admin/sts-001-to-ecs-002-to-admin/`

**Error:**
```
$ aws sts assume-role --role-arn arn:aws:iam::697683661464:role/ ...
Error: Failed to assume intermediate role
```

The intermediate role ARN is blank — the `demo_attack.sh` reads it from a Terraform
output that resolves to an empty string.

**Fix:** Find which `terraform output` call populates the intermediate role ARN in
`demo_attack.sh` and trace it back to `outputs.tf`. Either the output name is wrong,
the module reference is missing, or the resource was renamed. Verify with:
```bash
terraform output -json | jq '.[output_name]'
```

---

## 3. Timeouts — Glue and SageMaker jobs exceed 5-minute limit

These demos start a long-running AWS job (Glue dev endpoint or SageMaker notebook/
processing job) and poll until it completes. The 5-minute timeout in `run_demos.py`
is too short; the job is still running when the process is killed and no transcript
is written.

**Affected demos:**
- `glue-001` — `modules/scenarios/single-account/privesc-one-hop/to-admin/glue-001-iam-passrole+glue-createdevendpoint/`
- `glue-001-to-bucket` — `modules/scenarios/single-account/privesc-one-hop/to-bucket/glue-001-iam-passrole+glue-createdevendpoint/`
- `sagemaker-001` — `modules/scenarios/single-account/privesc-one-hop/to-admin/sagemaker-001-iam-passrole+sagemaker-createnotebookinstance/`
- `sagemaker-003` — `modules/scenarios/single-account/privesc-one-hop/to-admin/sagemaker-003-iam-passrole+sagemaker-createprocessingjob/`
- `sagemaker-004` — `modules/scenarios/single-account/privesc-one-hop/to-admin/sagemaker-004-sagemaker-createpresignednotebookinstanceurl/`
- `sagemaker-005` — `modules/scenarios/single-account/privesc-one-hop/to-admin/sagemaker-005-sagemaker-updatenotebook-lifecycle-config/`

**Fix options (pick one or combine):**

- **Increase the per-demo timeout** in `run_demos.py`. Glue dev endpoints can take
  10–15 minutes; SageMaker notebook instances 5–10 minutes. A 20-minute timeout
  (`timeout=1200`) is more appropriate for these.
- **Add a per-scenario timeout override** in `scenario.yaml` (e.g. `demo_timeout: 1200`)
  and read it in `run_demos.py` so only the slow demos get the longer limit.
- **Rewrite the slow demos** to not block on job completion — record the job ID and
  check status asynchronously, or reduce polling wait times if the jobs are finishing
  close to the limit.

---

## 4. Functional failure — CodeBuild batch job fails at runtime

### codebuild-003

**Path:** `modules/scenarios/single-account/privesc-one-hop/to-admin/codebuild-003-codebuild-startbuildbatch/`

The demo script ran to completion (exit 130 was the trap bug, now fixed), but the
CodeBuild batch build itself failed:
```
Build batch status: FAILED
```

**Fix:** Check the CodeBuild project and batch build configuration in `main.tf`.
Common causes: the buildspec references a resource that doesn't exist, the service
role lacks a needed permission, or the batch build configuration (compute type,
build timeout) is misconfigured. Pull the batch build ID from the transcript and
inspect the logs in the AWS console or via:
```bash
aws codebuild batch-get-build-batches --ids <batch-id>
aws logs get-log-events --log-group-name /aws/codebuild/<project> ...
```

---

## 5. Not fixable here — SCP blocks iam:CreateAccessKey

### iam-015, iam-018

Both demos succeed through most steps but fail at `iam:CreateAccessKey` due to an
explicit deny in an org-level SCP (`p-chymj835`):
```
AccessDenied: not authorized to perform: iam:CreateAccessKey
... with an explicit deny in a service control policy
```

This is an org-level constraint on the AWS account used for testing — not a bug in
the demos. The scenarios work correctly in accounts without this SCP.

---

## 6. Expected — cross-account demos require dev account profile

### lambda-invoke-update, multi-hop-both-sides, passrole-lambda-admin

These are cross-account scenarios that require `pl-pathfinding-starting-user-dev`
AWS profile to be configured. They fail immediately with:
```
Error: AWS profile 'pl-pathfinding-starting-user-dev' not found
```

Not bugs — expected to fail unless a dev account is configured in `~/.aws/config`.
