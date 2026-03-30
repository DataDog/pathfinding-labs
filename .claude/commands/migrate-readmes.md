---
name: migrate-readmes
description: Migrates all scenario READMEs (or a specific subset) to comply with the current canonical schema defined in .claude/scenario-readme-schema.md. Runs scenario-readme-migrator agents in parallel.
tools: Agent, Glob, Grep, Read, Bash
model: inherit
color: cyan
---

# Pathfinding Labs README Migration Orchestrator

You migrate scenario READMEs to comply with the current canonical schema. You discover non-compliant READMEs and run `scenario-readme-migrator` agents against them — in parallel since README files are fully independent (no shared state).

## Input Parsing

The user invokes you via `/migrate-readmes` with optional arguments:

**Positional arguments**: One or more scenario paths or IDs to migrate specifically
**Flags**:
- `--all` — migrate all scenario READMEs (default behavior if no path given)
- `--dry-run` — analyze compliance only, show what would change, make no edits
- `--batch-size=N` — how many migrator agents to run concurrently (default: 10)

**Examples**:
- `/migrate-readmes` — migrate all READMEs
- `/migrate-readmes --all` — same as above
- `/migrate-readmes --dry-run` — show compliance status for all, no changes
- `/migrate-readmes iam-002` — migrate any scenario whose directory name contains "iam-002"
- `/migrate-readmes modules/scenarios/single-account/privesc-one-hop/to-admin/iam-002-iam-createaccesskey`
- `/migrate-readmes --all --batch-size=5`

## Step 1: Discover READMEs

Find all scenario README files:

```
modules/scenarios/**/README.md
```

Use Glob to find all matches. Exclude the top-level `README.md` at the project root if present.

The project root is `/Users/seth.art/Documents/projects/pathfinding-labs`.

## Step 2: Filter Targets

If the user provided specific paths or IDs:
- Match against directory names (substring match is fine, e.g., "iam-002" matches "iam-002-iam-createaccesskey")
- Match against full paths

If `--all` or no argument given: use all discovered READMEs.

## Step 3: Version-Based Pre-Check

Read the current schema version from the first line of `.claude/scenario-readme-schema.md` (e.g., `1.0.0`).

For all target READMEs, run a single fast grep to find files that do NOT already declare the current schema version:

```bash
grep -rL "Schema Version: {current_version}" {list_of_readme_paths}
```

Files returned by that command need migration. Files not returned are already at the current version — skip them entirely, no agent needed.

Present a summary before making changes:

```
========================================
README MIGRATION DISCOVERY
Schema version: {current_version}
========================================
Total READMEs found:          N
Already at current version:   M  (skipped)
Needs migration:              K

Will migrate:
  modules/scenarios/single-account/privesc-one-hop/to-admin/iam-002-...
  modules/scenarios/single-account/privesc-one-hop/to-admin/iam-003-...
  ...
========================================
```

If `--dry-run`: stop here after showing the list.

Ask the user to confirm before proceeding if K > 20. For K ≤ 20, proceed automatically.

## Step 4: Run Migrations in Parallel

Split non-compliant READMEs into batches of `--batch-size` (default: 10). For each batch, launch all agents simultaneously in a single message (multiple Agent tool calls in one response).

For each scenario in the batch:

```
Agent(
  subagent_type="scenario-readme-migrator",
  description="Migrate README for {scenario-directory-name}",
  prompt="""
Migrate the README for the following scenario:

**Scenario directory**: {absolute_path_to_scenario_directory}
**Project root**: /Users/seth.art/Documents/projects/pathfinding-labs
"""
)
```

Wait for all agents in the batch to complete before launching the next batch.

## Step 5: Report Results

After all batches complete, produce a final report:

```
========================================
README MIGRATION REPORT
========================================
Total processed:    N
  Migrated:         M  (changes made)
  Already clean:    K  (no changes needed)
  Failed:           F  (errors)

MIGRATED:
  ✓ iam-002-iam-createaccesskey
  ✓ iam-003-iam-deleteaccesskey+createaccesskey
  ...

ALREADY COMPLIANT (skipped):
  - sts-001-sts-assumerole
  ...

FAILED:
  ✗ some-scenario (error: ...)

========================================
```

## Error Handling

- If a migrator agent fails for a scenario, log the error and continue with remaining scenarios
- Never stop the whole batch due to a single failure
- Report all failures in the final report

## Notes

- README migrations are fully parallel-safe: each README is an independent file with no shared state
- Unlike scenario code migrations, there is no terraform validation step needed
- READMEs already stamped with the current schema version are skipped with zero agent cost — only truly out-of-date files get processed
- The `scenario-readme-migrator` agent reads the schema from `.claude/scenario-readme-schema.md` — make sure that file is up to date before running
- Workflow for schema changes: (1) edit `.claude/scenario-readme-schema.md` and bump the version, (2) record the change in `.claude/scenario-readme-changelog.md`, (3) run `/migrate-readmes --all`
