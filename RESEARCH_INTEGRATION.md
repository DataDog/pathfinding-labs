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

Eleven scenarios pulled from research's `modules/scenarios/single-account/privesc-one-hop/to-admin/`. kafkaconnect-001 and kafkaconnect-002 deferred (paused / in-progress on research, separate effort).

| Scenario | Picked | Migrator | README | Wired | Validator | tf validate | AWS demo | Cleanup | Committed | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| batch-001 | [x] | [x] | [x] | [x] | [x] | [x] | [x] | [x] | [x] | Canary scenario. Validated 2026-05-12. |
| stepfunctions-001 | [x] | [x] | [x] | [x] | [x] | [x] | [x] | [ ] | [ ] | Demo confirmed working 2026-05-12. |
| braket-001 | [x] | [x] | [x] | [x] | [x] | [x] | [x] | [ ] | [ ] | Uses `prod.tf` + attacker-account pattern. Demo confirmed working 2026-05-12. |
| emr-001 | [x] | [x] | [x] | [x] | [x] | [x] | FAIL | [ ] | [ ] | 2026-05-12: cluster TERMINATED_WITH_ERRORS in 30s, step CANCELLED before running. Likely cluster launch failure (subnet/VPC, service role permissions, or instance profile). Investigating. |
| emr-serverless-001 | [x] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | Research status: Created, untested. |
| kinesisanalytics-001 | [x] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | Research status: Created, untested. Likely quick win (inline code, no S3). |
| synthetics-001 | [x] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | Research status: Created, untested. May need helpful→required reclassification (cwsyn-* / cw-syn-results-*). |
| imagebuilder-001 | [x] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | Research status: Created, untested. Slow iteration (10-30min builds). |
| amplify-001 | [x] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | Research status: Created, untested. CodeCommit dependency. |
| gamelift-001 | [x] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | No research status row. iam:PassRole + gamelift:CreateBuild + gamelift:CreateFleet. |
| omics-001 | [x] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | [ ] | No research status row. ID kept as omics-001 (not 007). iam:PassRole + omics:CreateWorkflow + omics:StartRun. |

## Deferred from Wave 1

| Scenario | Reason |
|---|---|
| kafkaconnect-001 | Paused on research branch -- most expensive scenario (MSK Serverless from scratch). Revisit separately. |
| kafkaconnect-002 | Was actively being debugged on research (S3 credential exfiltration approach). Revisit when ready. |

## Wave 2: (TBD)

Reserved for the next batch of research scenarios the user mentioned wanting to import.

---

## Active investigations

### emr-001 (2026-05-12)

**Symptom:** Cluster transitioned `STARTING -> TERMINATING -> TERMINATED_WITH_ERRORS` in ~30 seconds. Step "Escalate" was `CANCELLED`, never executed. `AdministratorAccess` was not attached.

**Hypotheses to investigate:**
1. EMR couldn't launch EC2 instances -- missing/invalid subnet, security group, or instance profile.
2. Service role policy is `AmazonElasticMapReduceRole` (in main.tf) but should be the newer `AmazonEMRServicePolicy_v2` (deprecated managed policy on certain release labels).
3. Release label `emr-7.0.0` may have a minimum subnet/network requirement that isn't met when no subnet is passed.
4. Default VPC doesn't have a subnet with auto-assign-public-IPv4 enabled (EMR EC2 instances need outbound access).

**Next steps:** read emr-001/main.tf and demo_attack.sh to confirm what's being passed, then either pass an explicit subnet or update the service role policy.
