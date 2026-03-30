# Plan: Cleanup All Active Demos and Destroy Scenario Infrastructure

## Overview

This plan covers two sequential phases:

1. **Cleanup** — run `plabs cleanup` for every scenario that currently has an active demo, removing demo artifacts (extra access keys, modified policies, `.demo_active` markers) without touching the deployed AWS infrastructure.
2. **Destroy scenarios** — run `plabs destroy --scenarios-only --auto-approve` to tear down all scenario modules while leaving the base environment (starting users, environments module) intact.

The commands are non-interactive throughout. No AWS-affecting commands were executed to produce this plan.

---

## Phase 0 — Orient (always run first)

```bash
PLABS=/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs

$PLABS status
```

**Purpose:** Confirm which scenarios are currently enabled and deployed before touching anything. The four-state output (green = enabled+deployed, yellow = enabled+not deployed, red = deployed+disabled, dim = neither) tells you the exact set of scenarios whose infrastructure exists and needs to be destroyed.

```bash
$PLABS scenarios list --demo-active
```

**Purpose:** List only the scenarios that have an active `.demo_active` marker — these are the ones that need cleanup before destroy. If this returns nothing, Phase 1 can be skipped.

---

## Phase 1 — Cleanup All Active Demos

For each scenario ID shown by `scenarios list --demo-active`, run:

```bash
$PLABS cleanup <scenario-id>
```

For example, if `iam-002` and `sts-001` are active:

```bash
$PLABS cleanup iam-002
$PLABS cleanup sts-001
```

**What this does:**
- Executes the scenario's `cleanup_attack.sh` script using the admin credentials from Terraform outputs.
- Removes any AWS resources created during the demo (e.g. extra IAM access keys, modified inline policies).
- Deletes the `.demo_active` marker file.
- Does **not** remove Terraform-managed infrastructure — that is left for Phase 2.

**Why cleanup before destroy:**
Cleanup scripts use admin credentials sourced from `terraform output`. Once `terraform destroy` runs, those outputs are gone. Running cleanup first ensures the scripts can authenticate and properly undo any demo-created AWS resources, preventing orphaned IAM keys or dangling policy modifications that Terraform does not own and therefore cannot remove.

If you have many active demos and want a single command when the CLI supports it:

```bash
# Bulk cleanup (if supported — check `plabs cleanup --help`)
$PLABS cleanup --all-active
```

Otherwise, iterate over the list manually as shown above.

---

## Phase 2 — Destroy Scenario Infrastructure Only

```bash
$PLABS destroy --scenarios-only --auto-approve
```

### Flag explanations

| Flag | Why it is used |
|------|---------------|
| `--scenarios-only` | Destroys only the Terraform modules under `modules/scenarios/` — the attack-path IAM roles, users, Lambda functions, EC2 instances, S3 buckets, etc. It does **not** destroy the base environment modules (the pathfinding starting users in prod/dev/ops, VPCs, or other shared infrastructure). This is the right choice when you want to clean up scenario resources between test runs but keep the foundational environment intact so you can re-enable and re-deploy scenarios without re-running `plabs init`. |
| `--auto-approve` | Passes `-auto-approve` through to `terraform destroy`, suppressing the interactive "Do you really want to destroy?" prompt. This is required for non-interactive/agent execution. `-y` is the equivalent short form. |

### Why NOT `--all`

`--all` would also destroy the base environment modules — the starting users, environment-level IAM policies, and any shared VPC/networking resources. Rebuilding the base environment requires re-running `terraform apply` against the environments modules, which takes additional time and may require re-running `plabs init` steps. Use `--all` only when you intend a full teardown (e.g. decommissioning the lab entirely).

---

## Phase 3 — Verify

```bash
$PLABS status
```

**Expected output after `--scenarios-only` destroy:**
- All previously green (deployed) scenarios should now show as yellow (enabled, not deployed) or dim (disabled, not deployed).
- No scenarios should remain green.
- The base environment (starting users) should still be present — you can confirm by checking that `plabs info` still shows valid AWS profile configuration and that no environment-level resources were removed.

---

## Complete Command Sequence (copy-paste ready)

```bash
PLABS=/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs

# 0. Orient
$PLABS status
$PLABS scenarios list --demo-active

# 1. Cleanup active demos (repeat for each ID returned above)
# $PLABS cleanup <id-1>
# $PLABS cleanup <id-2>

# 2. Destroy scenario infrastructure, leave base env intact
$PLABS destroy --scenarios-only --auto-approve

# 3. Verify
$PLABS status
```

---

## Notes and Caveats

- **Binary location:** The `plabs` binary is at `/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs`. If Go code has changed since the binary was last built, rebuild first: `go build -o plabs ./cmd/plabs` from the repo root.
- **Dev mode:** If `~/.plabs/plabs.yaml` has `dev_mode: true`, `plabs` reads Terraform from the local repo path. Run `plabs info` to confirm the active Terraform directory before destroying.
- **Cross-account scenarios:** If any active scenarios span multiple AWS accounts (dev-to-prod, ops-to-prod), ensure all required AWS profiles are still valid before running destroy. Invalid credentials for a non-prod account will cause Terraform to fail mid-destroy.
- **Order matters:** Always cleanup demos before destroying infrastructure. Reversing the order can leave orphaned AWS resources that Terraform does not manage and that will not be cleaned up automatically.
