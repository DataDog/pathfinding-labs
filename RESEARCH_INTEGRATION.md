# Research Branch Integration Tracker

Status of scenarios cherry-picked from the archived `research` branch (and future research imports) onto the `research-integration` branch.

**How to read the gates:**

| Gate | Meaning |
|---|---|
| Picked | Scenario dir cherry-picked from research branch onto this branch |
| Migrator | `scenario-migrator` agent applied (Phase 1, 1.5, 2, 2.5, 3 if needed, 5) |
| README | `scenario-readme-migrator` applied -- README at schema v4.6.1 |
| Wired | `project-updator` applied -- root main.tf / variables.tf / outputs.tf / terraform.tfvars.example |
| Validator | `scenario-validator` PASS (auto-fix items resolved) |
| `tf validate` | `terraform validate` passes at repo root |
| AWS demo | User has run `plabs apply && plabs demo <id>` on real AWS, demo completes successfully |
| Cleanup | `plabs cleanup <id> && plabs destroy` cleanly tears down |
| Committed | Migration committed to the branch |

Gate values: `[x]` done, `[ ]` not done, `FAIL` blocked with note, `N/A` not applicable.

## Wave 1: First-pass cherry-pick from `research` (2026-05-12)

Eleven scenarios pulled from research's `modules/scenarios/single-account/privesc-one-hop/to-admin/`. kafkaconnect-001 and kafkaconnect-002 deferred (paused / in-progress on research, separate effort). synthetics-001 was migrated but subsequently removed from this branch (2026-05-13) — see its row below.

| Scenario | Picked | Migrator | README | Wired | Validator | tf validate | AWS demo | Cleanup | Committed | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| batch-001 | [x] | [x] | [x] | [x] | [x] | [x] | [x] | [x] | [x] | Canary scenario. Validated 2026-05-12. |
| stepfunctions-001 | [x] | [x] | [x] | [x] | [x] | [x] | [x] | [ ] | [x] | Demo confirmed working 2026-05-12. |
| braket-001 | [x] | [x] | [x] | [x] | [x] | [x] | [x] | [ ] | [x] | Uses `prod.tf` + attacker-account pattern. Demo confirmed working 2026-05-12. |
| emr-001 | [x] | [x] | [x] | [x] | [x] | [x] | [x] | [ ] | [x] | Cluster originally failed with `VALIDATION_ERROR: Service-linked role 'AWSServiceRoleForEMRCleanup' for EMR is required`. Fixed by adding EMR SLR (`elasticmapreduce.amazonaws.com`) to `modules/environments/prod/` + matching plabs SLR detection (`create_emr_slr`). Demo also now self-diagnoses by printing `StateChangeReason` on `TERMINATED_WITH_ERRORS`. Demo confirmed working 2026-05-12. |
| emr-serverless-001 | [x] | [x] | [x] | [x] | [x] | [x] | [x] | [ ] | [ ] | **Demo PASS 2026-05-13** after three fixes: (1) added `AWSServiceRoleForAmazonEMRServerless` SLR to prod env + plabs detection (`create_emr_serverless_slr`) — was originally failing with `ValidationException: Access denied when calling CreateServiceLinkedRole operation`; (2) Step 13/14 cred-switch fix — verify-policy-attached step was running under `use_starting_creds` and hitting the restriction-policy explicit-deny on `iam:ListAttachedUserPolicies`; canonical pattern is `[ReadOnly]` for the observation step then `[Attacker (now admin)]` for `list-users`; (3) added `s3:DeleteObject` to the attacker-bucket's `AllowProdAccountObjectAccess` Sid so the cleanup user can remove runtime-exfil artifacts cross-account. Cleanup re-test pending. |
| kinesisanalytics-001 | [x] | [x] | [x] | [x] | [x] | [x] | [x] | [ ] | [ ] | Demo PASS 209s 2026-05-12 (Flink app, AdministratorAccess attached, flag captured by elevated principal under restriction). Cleanup had `set -e + $(...)` swallow on post-deletion `kinesisanalyticsv2 describe-application` — fix applied at `cleanup_attack.sh:197` (`\|\| true` + simplified `if [ -z ]` guard). **Cleanup fix uncommitted, awaiting re-test.** Pre-test: deleted leftover empty bucket from a prior research-branch run (`pl-kinesisanalytics-001-code-864899841852-66pzel`). |
| ~~synthetics-001~~ | — | — | — | — | — | — | — | — | — | **REMOVED from research-integration branch 2026-05-13.** Remains on the original `research` branch for future re-attempt. Reason: helpful→required reclassification work (Synthetics service calls a long, partially-undocumented set of `lambda:*` and `s3:*` actions against the caller's identity during canary provisioning) was diverging from per-perm runtime discovery — two perms (`s3:GetBucketLocation`, `lambda:GetFunctionConfiguration`) successfully reclassified, but next failure surfaced `lambda:GetFunctionConfiguration` follow-on, and the full chain was likely 5+ more iterations. Deferred rather than continuing iteration; AWS resources destroyed and TF + scenario dir + root wiring removed cleanly. |
| imagebuilder-001 | [x] | [x] | [x] | [x] | [x] | [x] | [x] | [ ] | [ ] | **Demo PASS 2026-05-13** after three fixes: (1) added `AWSServiceRoleForImageBuilder` SLR to prod env + plabs detection (`create_imagebuilder_slr`) — was originally failing with `AccessDenied ... iam:CreateServiceLinkedRole`; (2) removed `ssm:GetParameter` from helpful (both `scenario.yaml` and `main.tf`'s `HelpfulForReconAndMonitoring` Sid) — the flag-read step was being explicit-denied by the restriction policy even though AdministratorAccess was attached, because the deny policy is built from scenario.yaml's helpful list and explicit-deny beats AdministratorAccess; (3) flag-capture step now has a 4-attempt retry loop with stderr surfaced (was the diagnostic that revealed bug #2). Cleanup re-test pending. |
| amplify-001 | [x] | [x] | [x] | [x] | [x] | [x] | FAIL | [ ] | [ ] | **Demo crashes 38s in** at `aws amplify create-app --repository <CodeCommit HTTPS URL>` with `Error parsing parameter '--repository': Unable to retrieve <url>: received non 200 status code of 401`. Root cause: AWS CLI v2 does an HTTP preflight on the `--repository` URL before sending the CreateApp request, and the preflight does not use the `aws codecommit credential-helper` configured for git. Needs investigation — try CodeCommit ARN form, SSH URL, or call `amplify CreateApp` via the SDK/JSON-input path that skips the preflight. Tested 2026-05-12. |
| gamelift-001 | [x] | [x] | [x] | [x] | [x] | [x] | [x] | [x] | [ ] | **Demo + Cleanup PASS 2026-05-13** after four fixes: (1) `cleanup_attack.sh` `MAX_WAIT` bumped 300s→600s, fall-through note added when still transitional, `delete-fleet` rewritten as `if cmd; then ... else ... fi` so `set -e` doesn't kill on a transitional-state rejection; (2) AP-4 fix: Step 10 split into `[OBSERVATION]` under readonly (`list-attached-user-policies`) + `[EXPLOIT]` under starting creds (`list-users`) — was previously verifying admin under `[ReadOnly]`; (3) `show_attack_cmd()` aligned to canonical 2-arg form (`identity`, `command`); two call sites at upload-build / create-fleet updated to add `"Attacker"` identity arg — also fixes the cosmetic `$ Attacker (now admin) aws ...` malformed-label bug as a side-effect; (4) flag-capture step backported the imagebuilder 4-attempt retry-with-surfaced-stderr pattern. Initial demo run 2026-05-12 took 333s (no fixes); post-fix run 2026-05-13 clean end-to-end. |
| omics-001 | [x] | [x] | [x] | [x] | [x] | [x] | [ ] | [ ] | [ ] | Attacker-account pattern (S3 + ECR). Preserved + updated cross-account script variants per user direction. Validator auto-fixed 3: admin-verify cred anti-pattern in both canonical and cross-account demos, stale CodeBuild rows in README. Non-blocking note: scenario takes 15+ min; consider `demo_timeout_seconds: 1200` if harness has default timeout. **Demo run started 2026-05-12 but interrupted (user stopped batch); no usable result. Re-test next session.** |

## Commit state (2026-05-12)

| Scenario | Commits |
|---|---|
| batch-001 | Committed in `ef494b5`. |
| stepfunctions-001, braket-001 | Committed in `c1f0abe`. |
| emr-001 (scenario) | Committed in `28ac970`. EMR SLR addition committed separately in `2828df9`. |
| emr-serverless-001, kinesisanalytics-001, synthetics-001, imagebuilder-001, amplify-001, gamelift-001, omics-001 | **Not yet committed** — staged and ready, awaiting per-scenario AWS validation before commit. |

## Deferred from Wave 1

| Scenario | Reason |
|---|---|
| kafkaconnect-001 | Paused on research branch -- most expensive scenario (MSK Serverless from scratch). Revisit separately. |
| kafkaconnect-002 | Was actively being debugged on research (S3 credential exfiltration approach). Revisit when ready. |
| synthetics-001 | Originally part of Wave 1; removed from this branch 2026-05-13. Remains on `research`. Re-import after a CloudTrail-driven helpful→required reclassification pass — see Resolved investigations for the partial work done. |

## Test runs

| Run dir | Date | Scenarios | Result |
|---|---|---|---|
| `test_results/run-2026-05-12T22-26-58/` | 2026-05-12 | kinesisanalytics-001 | Demo PASS, cleanup FAIL (fix applied, awaiting re-test) |
| `test_results/run-2026-05-12T22-45-16/` | 2026-05-12 | emr-serverless-001, synthetics-001, imagebuilder-001, amplify-001, gamelift-001, omics-001 | 1 PASS (gamelift demo), 4 FAIL (emr-serverless, synthetics, imagebuilder, amplify — see scenario rows above), omics not tested (interrupted) |
| Manual runs 2026-05-13 | 2026-05-13 | emr-serverless-001, imagebuilder-001 | Both demos now PASS after the fixes captured in their scenario rows above. Cleanup runs pending. |
| Code-only fixes 2026-05-13 | 2026-05-13 | gamelift-001, synthetics-001 | gamelift: 4 fixes (cleanup wait+guard, AP-4 Step 10 split, canonical `show_attack_cmd`, flag retry) — **demo + cleanup PASS 2026-05-13**. synthetics: 5 fixes (add `lambda:PublishLayerVersion`, surface CREATE_RESULT error, cleanup `get-canary` guards, Step 10 split, flag retry); subsequent AWS re-test surfaced ArtifactS3Location access error → `s3:GetBucketLocation` reclassified helpful→required 2026-05-13 (scoped to `arn:aws:s3:::cw-syn-results-*`). Synthetics awaiting next AWS run. |

## Outstanding fixes needed before re-test

1. ✅ **emr-serverless-001 + imagebuilder-001 SLRs** — DONE 2026-05-13 (commit pending). Both SLRs wired via the canonical pattern (`AWSServiceRoleForAmazonEMRServerless` → `ops.emr-serverless.amazonaws.com`; `AWSServiceRoleForImageBuilder` → `imagebuilder.amazonaws.com`); 9-file diff mirrors `2828df9`. Both demos confirmed PASS end-to-end (admin attached + flag captured).
2. ❌ **synthetics-001 — REMOVED 2026-05-13.** Pulled out of the research-integration branch entirely (AWS resources destroyed; scenario dir + root TF wiring + flags.default.yaml entry removed). Remains on the `research` branch as-is for future re-attempt with a dedicated CloudTrail-driven helpful→required reclassification pass. Two perms successfully reclassified (`s3:GetBucketLocation`, `lambda:GetFunctionConfiguration`) before pull-out — see Resolved investigations section for what was learned.
3. **amplify-001** — investigate alternatives to passing the CodeCommit HTTPS URL via `--repository` (CLI preflight returns 401). Try ARN form, SSH URL, or skip CLI preflight via `--cli-input-json`. Likely requires demo_attack.sh rewrite of the create-app call.
4. ✅ **gamelift-001 — DONE 2026-05-13.** Four fixes (cleanup wait+guard, AP-4 Step 10 split, canonical `show_attack_cmd`, flag retry) applied. Demo + cleanup both confirmed PASS end-to-end. Commit pending.
5. **kinesisanalytics-001** — cleanup fix already applied (`cleanup_attack.sh:197`); needs one re-test cycle to confirm PASS, then commit.
6. **omics-001** — never finished a full demo run; re-test next session. Note: today's `s3:DeleteObject` bucket-policy fix (added to `AllowProdAccountReadWrite` Sid) means cleanup should now succeed cross-account when omics re-tests.

## Agent-doc updates from today's findings (2026-05-13)

- `scenario-migrator.md` — new Phase 1.6 (Service-Linked Role Pre-Creation) added between 1.5 and 2; Phase 0 detection block updated; "Cross-account cleanup wrinkle (`s3:DeleteObject`)" paragraph added under Phase 3 Step 3a; Important Notes #11 added.
- `scenario-terraform-builder.md` — item 10 expanded with separate guidance for read-only vs exfiltration attacker buckets (the latter needs `s3:DeleteObject` in the prod-account Sid).
- `scenario-demo-creator.md` — new "Removing Runtime Artifacts From an Attacker Bucket (Cross-Account)" pattern in Common Cleanup Patterns.

## Wave 2: (TBD)

Reserved for the next batch of research scenarios the user mentioned wanting to import.

---

## Resolved investigations

### emr-001 missing SLR (2026-05-12)

**Symptom:** Cluster transitioned `STARTING -> TERMINATING -> TERMINATED_WITH_ERRORS` in ~30 seconds. Step "Escalate" was `CANCELLED`, never executed. `AdministratorAccess` was not attached.

**Root cause:** `aws emr describe-cluster --query 'Cluster.Status.StateChangeReason'` returned `VALIDATION_ERROR: Service-linked role 'AWSServiceRoleForEMRCleanup' for EMR is required.` The EMR SLR (created on first use of the service, but absent in fresh playground accounts) is validated by `RunJobFlow` before the cluster API call returns.

**Fix:** Added the EMR SLR to the prod environment module and wired it through plabs SLR detection, mirroring the existing autoscaling/spot/apprunner pattern (one entry in each of: `ServiceLinkedRoleStatus`, `slrStateAddresses`, `serviceLinkedRoleChecks`, `ServiceLinkedRoleFlags`, the four `SLRFlags` literal sites in `plan.go` / `deploy.go` / `tui/model.go`, root `variables.tf`, root `main.tf` pass-through, env-module `main.tf`/`variables.tf`). EMR is unusual in that the *only* SLR is named `AWSServiceRoleForEMRCleanup` -- it's not paired with a separate "creation" SLR; the customer-managed EMR service role (with `AmazonElasticMapReduceRole`) handles cluster operations, and the SLR handles post-termination VPC-endpoint cleanup. EMR validates the SLR exists before accepting any `RunJobFlow` call.

**Defensive change:** demo_attack.sh now prints `Cluster.Status.StateChangeReason` automatically on `TERMINATED_WITH_ERRORS` so future cluster-launch failures self-diagnose.

### emr-serverless-001 + imagebuilder-001 missing SLRs (2026-05-13)

**Symptom:** Both demos fail in their first API call to the service:
- emr-serverless: `ValidationException: Access denied when calling CreateServiceLinkedRole operation` on `aws emr-serverless create-application`.
- imagebuilder: `AccessDenied ... iam:CreateServiceLinkedRole on AWSServiceRoleForImageBuilder` on `aws imagebuilder create-image`.

**Root cause:** Both services validate (or attempt to create) their service-linked role at first use. Fresh playground accounts don't have these SLRs, and the starting user (by design) doesn't have `iam:CreateServiceLinkedRole` — granting it would be a precondition change.

**Fix:** Mirrored the emr-001 SLR pattern exactly. Added `AWSServiceRoleForAmazonEMRServerless` (service principal `ops.emr-serverless.amazonaws.com`, flag `create_emr_serverless_slr`) and `AWSServiceRoleForImageBuilder` (service principal `imagebuilder.amazonaws.com`, flag `create_imagebuilder_slr`) to `modules/environments/prod/` + the six plabs detection sites + root TF wiring. 9-file diff per SLR; total 12 net new lines + 6 alignment-only reformats.

**Documentation:** Phase 1.6 added to `scenario-migrator.md` so future scenarios that depend on a service whose SLR isn't auto-created get this pre-flight handled at migration time, never by granting `iam:CreateServiceLinkedRole` to the starting user.

### Cross-account cleanup needs `s3:DeleteObject` on attacker bucket (2026-05-13)

**Symptom:** emr-serverless-001 cleanup fails with `AccessDenied: DeleteObject` on `aws s3 rm` against the attacker-account bucket, even though the cleanup user has `AdministratorAccess` from the IAM side.

**Root cause:** Bucket lives in the attacker account; cleanup runs under the prod admin-cleanup user; cross-account access requires BOTH identity-policy allow AND resource-policy allow. The bucket policy granted prod-account principals `s3:GetObject` + `s3:PutObject` (to fetch the exploit script and let the compute role exfil to the bucket), but not `s3:DeleteObject` — so the cleanup user's IAM admin allow was overridden by the bucket policy gap.

**Fix:** Added `s3:DeleteObject` to the existing `AllowProdAccountObjectAccess` Sid (emr-serverless) / `AllowProdAccountReadWrite` Sid (omics) on each affected attacker bucket. The starting user's identity policy never includes `s3:DeleteObject`, so widening the bucket policy doesn't change the attack precondition — only the cleanup user gains the bucket-policy half of the permission pair.

**Distinction (captured in docs):** Read-only attacker buckets (e.g. synthetics-001's `exploit_code`) don't need this fix — cleanup leaves bucket contents alone and `terraform destroy` with `force_destroy = true` reclaims them. Only buckets that receive runtime-created exfiltration data need cross-account `DeleteObject`.

**Documentation:** Captured in `scenario-migrator.md` Phase 3 Step 3a, `scenario-terraform-builder.md` item 10, and `scenario-demo-creator.md` Common Cleanup Patterns.

### `ssm:GetParameter` must never be in helpful (2026-05-13)

**Symptom:** imagebuilder-001 flag-capture step fails with `AccessDeniedException ... ssm:GetParameter ... with an explicit deny in an identity-based policy`, despite `AdministratorAccess` being attached and `iam:list-users` succeeding seconds earlier.

**Root cause:** `ssm:GetParameter` was listed under `permissions.helpful` in scenario.yaml. The demo's `restrict_helpful_permissions` library builds an inline explicit-deny policy from scenario.yaml's helpful list. Explicit-deny beats `AdministratorAccess`. The flag-read step (which reuses the elevated principal's now-attached admin) was being denied by the restriction policy that was supposed to be lifted only after the attack succeeded.

**Fix:** Removed `ssm:GetParameter` from imagebuilder-001's scenario.yaml helpful list and from its main.tf `HelpfulForReconAndMonitoring` Sid. Audited all migrated scenarios — `ssm:GetParameter` is no longer listed as helpful in any `scenario.yaml`. The terraform-builder agent doc (item 12) already states this rule for the to-admin scenario flag-read step — reinforce in migrator if/when it surfaces again.

**Defensive change:** imagebuilder-001 flag-capture step now retries 4 times with stderr surfaced, so future IAM-propagation OR explicit-deny issues surface the real AWS error rather than being silently swallowed by `set -e + $(... 2>/dev/null)`. Consider backporting the retry-with-surfaced-stderr pattern to the canonical to-admin flag-capture template.

### synthetics-001 helpful→required reclassification (partial, 2026-05-13)

**Context:** synthetics-001 was migrated from research and tested 2026-05-12 + 2026-05-13. Demo failed inside the restriction window because the Synthetics service calls a long set of `lambda:*` and `s3:*` actions against the **caller's identity** (not the canary execution role) during `CreateCanary` provisioning. The migrated scenario classified these as helpful pending CloudTrail confirmation; the runtime denies effectively were that confirmation.

**Two perms reclassified before pull-out:**

| Permission | Scope | Symptom that surfaced it |
|---|---|---|
| `s3:GetBucketLocation` | `arn:aws:s3:::cw-syn-results-*` | `CreateCanary` returns `ValidationException: ArtifactS3Location: You do not have access to the bucket.` |
| `lambda:GetFunctionConfiguration` | `arn:aws:lambda:*:*:function:cwsyn-*` | Canary transitions to ERROR with `User is not authorized to perform: lambda:GetFunctionConfiguration on resource arn:aws:lambda:*:*:function:cwsyn-*-...` |

**Likely-still-needed caller-side perms (next iteration would have hit these):**
- `lambda:CreateFunction` (cwsyn-*)
- `lambda:GetFunction` (cwsyn-*)
- `lambda:PublishVersion` (cwsyn-*)
- `lambda:AddPermission` (cwsyn-*)
- `lambda:GetLayerVersion` (`arn:aws:lambda:*:*:layer:Synthetics-*`)
- `lambda:PublishLayerVersion` (`arn:aws:lambda:*:*:layer:Synthetics-*`)
- `s3:GetObject` on the attacker code bucket (`arn:aws:s3:::pl-synthetics-exploit-*`)

**Genuinely helpful (would have stayed in helpful):** `s3:PutObject`, `synthetics:GetCanary`, `synthetics:GetCanaryRuns`, `iam:ListAttachedUserPolicies`, `lambda:UpdateFunction*`.

**Decision:** Rather than continue per-perm iteration with multiple AWS rounds each, removed synthetics from `research-integration`. When re-attempting from `research`, the cleanest path is one of: (1) deploy the scenario WITHOUT the restriction window (set `PL_SKIP_RESTRICTION=1` for one run), capture CloudTrail for `pl-prod-synthetics-001-to-admin-starting-user`, classify every `lambda:*` / `s3:*` event as caller-side or service-side from the EventName/EventTime evidence, and apply the full reclassification in one shot; OR (2) batch-promote the 7 "likely-caller-side" perms above on faith and iterate from there. Approach (1) is the more thorough fix and was the original deferred (b) in the outstanding-fixes list.
