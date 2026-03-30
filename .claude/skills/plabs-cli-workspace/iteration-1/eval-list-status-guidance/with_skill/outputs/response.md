# Listing Privilege-Escalation to-Admin Scenarios: Deployed vs. Pending

This guide walks you through the exact commands to run, what each flag means, and how to interpret
the output — without touching any AWS infrastructure.

---

## Step 1: Confirm Which Paths plabs Is Using

```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs info
```

**Why**: Before doing anything else, verify that `plabs` is pointing at the right Terraform
working directory and config file. If `dev_mode` is active in `~/.plabs/plabs.yaml`, the binary
reads Terraform state from your local repo path instead of the default `~/.plabs/pathfinding-labs/`.
Getting this wrong means every subsequent status check could be looking at the wrong state.

**What to look for in the output**:
- `Config path`: should be `~/.plabs/plabs.yaml`
- `Terraform dir`: the directory where `terraform.tfstate` lives
- `Dev mode`: `true` or `false`
- AWS profile names for `prod` (and optionally `dev`/`ops`)

---

## Step 2: Check the Overall Deployment Status

```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs status
```

**Why**: `plabs status` gives you the current four-state picture for every scenario that `plabs`
knows about. It reads both `~/.plabs/plabs.yaml` (which scenarios are *enabled* in config) and the
live Terraform state (which are *deployed* in AWS) to produce a combined status.

**Four-state status indicators** — each scenario is one of:

| Symbol | Color | Meaning | Demo-ready? |
|--------|-------|---------|-------------|
| `●` | green | Enabled **and** deployed | **Yes — ready to demo** |
| `●` | yellow | Enabled in config, **not yet deployed** | No — needs `plabs deploy -y` |
| `●` | red | Deployed in AWS but **disabled** in config | No — out-of-sync; either re-enable or destroy |
| `○` | dim/grey | Disabled and not deployed | No — nothing to do unless you want it |

You want to see only green `●` circles for scenarios you intend to demo.

---

## Step 3: Filter to Privilege-Escalation to-Admin Scenarios

```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs scenarios list \
  --category privilege-escalation \
  --target to-admin
```

**Flag breakdown**:
- `--category privilege-escalation`: narrows the list to the `privilege-escalation` category only,
  excluding CSPM misconfigs, toxic combos, and tool-testing scenarios
- `--target to-admin`: further narrows to scenarios whose final target is admin access (excludes
  `to-bucket` variants)

**What to look for**: Each row shows a scenario ID (e.g. `iam-002`), its subcategory
(`self-escalation`, `one-hop`, `multi-hop`), a short description, and its status indicator using
the four-state system described above.

---

## Step 4: Show Only the Enabled Subset

```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs scenarios list \
  --category privilege-escalation \
  --target to-admin \
  --enabled
```

**Why `--enabled`**: Adding this flag hides all the dim `○` scenarios (disabled and not deployed)
so you only see scenarios that are either green, yellow, or red. This is the most actionable view:
it tells you exactly which scenarios are in your config and what state each one is in.

**Reading the output**:
- **Green `●` rows** = these are deployed and ready to demo right now.
- **Yellow `●` rows** = these are in your config but not yet deployed; they need a `plabs deploy`.
- **Red `●` rows** = these are in AWS but you have disabled them in config; they need attention
  (see Step 6 below).

---

## Step 5: Identify What Is "Ready to Demo"

After running the command in Step 4, note all scenario IDs with a **green `●`**. These are fully
deployed. You can run demos immediately:

```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs demo <scenario-id>
# Example:
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs demo iam-002
```

To see which scenarios have demo scripts available:

```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs demo --list
```

---

## Step 6: Handling "Enabled but Not Yet Deployed" (Yellow `●`)

If you see yellow circles in the output from Step 4, those scenarios are listed in your config
but Terraform has not applied them to AWS yet. To deploy them:

```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs deploy -y
```

**Flag**: `-y` (equivalent to `--auto-approve`) suppresses the confirmation prompt so the command
runs non-interactively.

**What this does**: Generates a fresh `terraform.tfvars` from your `~/.plabs/plabs.yaml` (turning
on the boolean flags for all enabled scenarios), then runs `terraform apply -auto-approve` in the
configured Terraform directory. When it finishes, re-run Step 4 — those yellow circles should now
be green.

**Note**: This command *will* make AWS API calls and create real infrastructure. Do not run it
unless you intend to deploy. For a dry run first, use:

```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs plan
```

`plabs plan` runs `terraform plan` and shows you exactly what would be created without touching AWS.

---

## Step 7: Handling "Deployed but Disabled" (Red `●`)

A red circle means the scenario exists in AWS but is no longer listed as enabled in your config.
This is an out-of-sync state. You have two choices:

**Option A — Re-enable it** (makes it green again, no AWS changes needed):
```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs enable <scenario-id> -y
```

**Option B — Destroy it** (tears down the AWS resources for this scenario):
```bash
/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs destroy --scenarios-only -y
```

`--scenarios-only` destroys only scenario modules, leaving base infrastructure (the
`pl-pathfinding-starting-user-prod` user and environment base resources) intact. Omit this flag
and use `--all` only if you want to tear down everything.

---

## Complete Command Sequence (Summary)

```bash
PLABS=/Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs/plabs

# 1. Confirm working paths
$PLABS info

# 2. See overall status across all scenarios
$PLABS status

# 3. Narrow to privilege-escalation to-admin, enabled scenarios only
$PLABS scenarios list --category privilege-escalation --target to-admin --enabled

# 4a. For each GREEN scenario — already deployed, demo now:
$PLABS demo <scenario-id>

# 4b. For each YELLOW scenario — deploy first, then demo:
$PLABS plan                  # dry run; verify what will be created
$PLABS deploy -y             # actually deploy
$PLABS demo <scenario-id>

# 4c. For each RED scenario — decide: re-enable or destroy:
$PLABS enable <scenario-id> -y          # re-enable (green)
# OR
$PLABS destroy --scenarios-only -y      # remove from AWS
```

---

## Quick Reference: Four States

| State | Symbol | Color | Demo-ready | What to do |
|-------|--------|-------|-----------|------------|
| Enabled + Deployed | `●` | green | Yes | Run `plabs demo <id>` |
| Enabled, Not Deployed | `●` | yellow | No | Run `plabs deploy -y` |
| Deployed, Disabled | `●` | red | No | Re-enable or destroy |
| Disabled, Not Deployed | `○` | dim | No | Nothing required |
