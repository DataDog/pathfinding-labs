# Plan: Clean Up Active Demos and Destroy Scenario Infrastructure

## Overview

This plan covers two sequential phases:

1. Run `plabs cleanup <id>` for every scenario that has an active demo
2. Run `plabs destroy --scenarios-only --auto-approve` to tear down scenario infrastructure while leaving the base environment in place

No commands are actually executed here - this is a step-by-step plan with explanations.

---

## Phase 1: Identify and Clean Up Active Demos

### Step 1 — Check current status to see which demos are active

```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs status
```

**Purpose:** This shows every enabled scenario and flags any that have a `.demo_active` marker file with a warning symbol. Look for lines labelled `demo active` in the output. Note each scenario ID listed there.

### Step 2 — Run cleanup for each scenario with an active demo

The `plabs cleanup` command takes exactly one scenario ID at a time. There is no `--all` flag on the CLI (bulk cleanup exists only in the interactive TUI via the `C` keybinding). You must run one command per active demo.

For each scenario ID you noted in Step 1, run:

```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs cleanup <scenario-id>
```

**Example — if `iam-002-to-admin` and `sts-001-to-admin` are active:**

```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs cleanup iam-002-to-admin
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs cleanup sts-001-to-admin
```

**What this does:** Each invocation finds the scenario's `cleanup_attack.sh` script and executes it. The script removes artifacts created during the demo — things like additional IAM access keys, modified inline policies, or temporary role trust policy changes — without touching the underlying Terraform-managed infrastructure.

**Verification:** After each cleanup, the `.demo_active` marker file in the scenario directory is removed. Re-running `plabs status` should show no more `demo active` warnings.

---

## Phase 2: Destroy Scenario Infrastructure Only

### Step 3 — Destroy scenarios while preserving the base environment

```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs destroy --scenarios-only --auto-approve
```

**Why `--scenarios-only` and not `--all`:**

| Flag | Behaviour |
|------|-----------|
| `--scenarios-only` | Disables all enabled scenarios in config, regenerates `terraform.tfvars`, then runs `terraform apply` to converge — only scenario resources are removed. Base environment modules (`prod_environment`, `dev_environment`, `ops_environment`) stay deployed. |
| `--all` | Runs a full `terraform destroy`, which removes **everything** including base environment IAM users, VPCs, and other foundational resources. Recovering from this requires re-running `plabs deploy` for the environment too. |

Because the task says "leave the base environment in place", `--scenarios-only` is the correct choice. It is the safe, targeted operation.

**Why `--auto-approve`:**

Without this flag, `plabs destroy --all` requires you to type the word `destroy` to confirm. The `--scenarios-only` path does not prompt for this confirmation text, but the `--auto-approve` flag (`-y`) is the canonical way to signal non-interactive mode across both paths. Passing it ensures the command runs unattended regardless of which code path is taken.

**What `--scenarios-only` actually does internally:**

1. Discovers all scenario YAML files in the repo.
2. Checks which ones are currently enabled in `~/.plabs/plabs.yaml`.
3. Calls `cfg.DisableScenario()` on each enabled one and saves the config.
4. Regenerates `terraform.tfvars` via `cfg.SyncTFVars()`.
5. Runs `terraform apply -auto-approve`, which Terraform resolves as "remove all resources belonging to now-disabled scenario modules while leaving environment module resources untouched."

---

## Full Command Sequence (with placeholder IDs)

```bash
# 1. Check what is active
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs status

# 2. Clean up each demo-active scenario (replace with real IDs from step 1)
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs cleanup <scenario-id-1>
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs cleanup <scenario-id-2>
# ... repeat for each active demo

# 3. Destroy only scenario infrastructure, keep base environment
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs destroy --scenarios-only --auto-approve
```

---

## Notes and Caveats

- **Cleanup before destroy is important.** If you skip cleanup and go straight to `destroy --scenarios-only`, the `.demo_active` marker files will linger on disk (they are not managed by Terraform). The next time you enable and deploy the same scenario, `plabs status` will still show `demo active` even though no actual attack artifacts exist. Running cleanup first ensures the marker files are cleared by the cleanup scripts.

- **`--scenarios-only` uses `terraform apply`, not `terraform destroy`.** This is intentional. Terraform computes the diff between the desired state (all scenarios disabled) and the current state (some scenarios deployed) and removes only the delta. This is safer than a targeted `destroy` because Terraform manages dependencies automatically.

- **Base environment resources are unaffected.** Resources in the `prod_environment`, `dev_environment`, and `ops_environment` modules — including pathfinding starting users, admin cleanup users, and any base VPC or IAM constructs — remain deployed and usable after this operation.

- **Re-enabling scenarios later.** After this operation all scenario variable names are set to `false` in both `~/.plabs/plabs.yaml` and `terraform.tfvars`. To redeploy a scenario, use `plabs enable <id>` followed by `plabs deploy`.
