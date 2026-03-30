# How to List Privilege-Escalation to-Admin Scenarios: Deployed vs. Pending

## Goal

Identify which privilege-escalation to-admin scenarios are **deployed and ready to demo**, and which are **enabled but still need to be deployed**.

The `plabs` binary is at:
```
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs
```

---

## Step 1: List all to-admin scenarios with their status

Run this command:

```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs scenarios list --category=one-hop --target=admin
```

**Why these flags:**
- `--category=one-hop` — narrows to one-hop privilege-escalation scenarios (omit to include self-escalation and multi-hop as well)
- `--target=admin` — filters to scenarios whose goal is reaching admin

To also capture **self-escalation** and **multi-hop** paths to admin, run three commands:

```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs scenarios list --category=self-escalation --target=admin
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs scenarios list --category=one-hop --target=admin
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs scenarios list --category=multi-hop --target=admin
```

Or, to see **all categories at once** and scan the "Privilege Escalation to Admin" section:

```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs scenarios list
```

**How to interpret the output — the 4-state status indicators:**

Each scenario row begins with a colored dot:

| Symbol | Color | Meaning |
|--------|-------|---------|
| `●` | Green | **Enabled AND deployed** — ready to demo right now |
| `●` | Yellow | **Enabled but not yet deployed** — needs `plabs deploy` before you can run a demo |
| `●` | Red | **Disabled but still deployed** — resources exist in AWS; needs `plabs deploy` (with that scenario disabled) to destroy them |
| `○` | Dim/grey | **Disabled and not deployed** — inactive; optionally unavailable if cross-account mode is required |

**For your question:** you want every **green `●`** row in the "Privilege Escalation to Admin" sections.

---

## Step 2: See only enabled scenarios (quicker scan)

```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs scenarios list --enabled --target=admin
```

**Why `--enabled`:** filters the list to only scenarios that have been toggled on in your config (`~/.plabs/plabs.yaml`). This removes the noise of the many disabled scenarios so you can focus on the ones you care about.

The output will show only enabled scenarios, each with either a **green `●`** (deployed) or **yellow `●`** (pending deploy).

---

## Step 3: See only deployed scenarios (most direct answer)

```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs scenarios list --deployed --target=admin
```

**Why `--deployed`:** shows only scenarios that are confirmed present in Terraform state. Every scenario in this output is immediately demo-able. This is the fastest way to answer "what can I demo right now?"

---

## Step 4: Use `plabs status` for a summary view

```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs status
```

This command shows:
1. **Environment status** — whether `prod` (and optionally `dev`/`ops`) environments are deployed
2. **Enabled scenarios** — listed with `deployed` (green) or `pending` (yellow) labels
3. **Summary line** — counts like `Total: 5 enabled | 3 deployed | 2 pending`

**How to read the summary line:**
- `N deployed` — these are ready to demo
- `N pending` — these are enabled in config but not yet applied to AWS; see Step 5

**Note:** `plabs status` shows **all** enabled scenarios regardless of category. You will need to visually identify which ones are privilege-escalation to-admin scenarios by their IDs (e.g., `iam-002-to-admin`, `sts-001-to-admin`).

---

## Step 5: For scenarios that are "enabled but not yet deployed"

If any scenario shows a **yellow `●`** (pending) in `scenarios list` or `pending` in `status`, the AWS resources have not been created yet. To deploy them:

```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs deploy
```

What this does, step by step:
1. Syncs your `~/.plabs/plabs.yaml` config to `terraform.tfvars`
2. Runs `terraform init` if not already initialized
3. Runs `terraform plan` and shows what will be created
4. Prompts you to confirm with `[y/N]`
5. Runs `terraform apply` to create the AWS resources

After `plabs deploy` completes successfully, re-run `plabs status` or `plabs scenarios list --deployed --target=admin` to confirm the previously-pending scenarios now show as deployed (green `●`).

---

## Step 6: Confirm a specific scenario is ready for demo

Once you have a scenario ID (e.g., `iam-002-to-admin`), you can verify it is demo-ready:

```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs demo --list
```

This command categorizes **every scenario that has a `demo_attack.sh` script** into three groups:

| Group | Symbol | Meaning |
|-------|--------|---------|
| Ready to Run | Green `●` with `✓` | Enabled AND deployed — run `plabs demo <id>` now |
| Enabled but not deployed | Yellow `○` | Run `plabs deploy` first |
| Not enabled | Dim `○` | Run `plabs enable <id>` then `plabs deploy` first |

---

## Quick Reference: Complete Workflow

```
# 1. See all to-admin scenarios and their current state
plabs scenarios list --target=admin

# 2. See only the enabled ones
plabs scenarios list --enabled --target=admin

# 3. See only the ones ready to demo right now
plabs scenarios list --deployed --target=admin

# 4. Get an overall summary with counts
plabs status

# 5. If any are "enabled but pending" — deploy them
plabs deploy

# 6. Confirm what's demo-ready
plabs demo --list

# 7. Run a specific demo (once confirmed deployed)
plabs demo <scenario-id>
```

---

## Status Indicator Reference (full legend)

From the bottom of `plabs scenarios list` output:

```
● = deployed    ● = pending    ● = pending destroy    ○ = disabled
(green)         (yellow)       (red)                   (dim)
```

- **Green `●` deployed**: Terraform state confirms resources exist in AWS. Demo scripts will find credentials via `terraform output`. Safe to run `plabs demo <id>`.
- **Yellow `●` pending**: Scenario is enabled in config (`~/.plabs/plabs.yaml`) but `terraform apply` has not been run yet (or it failed). Run `plabs deploy`.
- **Red `●` pending destroy**: Scenario was previously enabled and deployed, then disabled in config. Resources still exist in AWS and are incurring cost. Run `plabs deploy` (with the scenario disabled) to destroy them.
- **Dim `○` disabled**: Not enabled in config and not deployed. No action needed unless you want to enable it.
