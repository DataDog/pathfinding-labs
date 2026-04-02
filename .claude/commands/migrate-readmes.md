---
name: migrate-readmes
description: Migrates all scenario READMEs (or a specific subset) to comply with the current canonical schema defined in .claude/scenario-readme-schema.md. Runs scenario-readme-migrator agents in parallel.
tools: Agent, Glob, Grep, Read, Bash
model: inherit
color: cyan
---

# Pathfinding Labs README Migration Orchestrator

You migrate scenario READMEs to comply with the current canonical schema. You discover non-compliant READMEs and run `scenario-readme-migrator` agents against them -- in parallel since README files are fully independent (no shared state).

## Input Parsing

The user invokes you via `/migrate-readmes` with optional arguments:

**Positional arguments**: One or more scenario paths or IDs to migrate specifically
**Flags**:
- `--all` -- migrate all scenario READMEs (default behavior if no path given)
- `--dry-run` -- analyze compliance only, show what would change, make no edits
- `--batch-size=N` -- how many migrator agents to run concurrently (default: 10)

**Examples**:
- `/migrate-readmes` -- migrate all READMEs
- `/migrate-readmes --all` -- same as above
- `/migrate-readmes --dry-run` -- show compliance status for all, no changes
- `/migrate-readmes iam-002` -- migrate any scenario whose directory name contains "iam-002"
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

Read the current schema version from `.claude/scenario-readme-schema.md` (should be `3.0.0`).

For all target READMEs, run a single fast grep to find files that do NOT already declare the current schema version:

```bash
grep -rL "Schema Version: {current_version}" {list_of_readme_paths}
```

Files returned by that command need migration. Files not returned are already at the current version -- skip them entirely.

Additionally check for missing companion files:

```bash
# Check which scenarios are missing attack_map.yaml
find modules/scenarios -name README.md -exec dirname {} \; | while read dir; do
  [ ! -f "$dir/attack_map.yaml" ] && echo "$dir"
done

# Check which scenarios are missing guided_walkthrough.md
find modules/scenarios -name README.md -exec dirname {} \; | while read dir; do
  [ ! -f "$dir/guided_walkthrough.md" ] && echo "$dir"
done
```

A scenario needs migration if ANY of:
- README does not declare current schema version
- `attack_map.yaml` does not exist
- `guided_walkthrough.md` does not exist

Present a summary before making changes:

```
========================================
README MIGRATION DISCOVERY
Schema version: {current_version}
========================================
Total READMEs found:          N
Already at current version:   M  (skipped)
Needs migration:              K
  - Missing schema version:   A
  - Missing attack_map.yaml:  B
  - Missing walkthrough:      C

Will migrate:
  modules/scenarios/single-account/privesc-one-hop/to-admin/iam-002-...
  modules/scenarios/single-account/privesc-one-hop/to-admin/iam-003-...
  ...
========================================
```

If `--dry-run`: stop here after showing the list.

Ask the user to confirm before proceeding if K > 20. For K <= 20, proceed automatically.

## Step 4: Run Migrations in Parallel

Split non-compliant scenarios into batches of `--batch-size` (default: 10). For each batch, launch all agents simultaneously in a single message (multiple Agent tool calls in one response).

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
  [check] iam-002-iam-createaccesskey (README + attack_map.yaml + guided_walkthrough.md)
  [check] iam-003-iam-deleteaccesskey+createaccesskey (README + attack_map.yaml + guided_walkthrough.md)
  ...

ALREADY COMPLIANT (skipped):
  - sts-001-sts-assumerole
  ...

FAILED:
  [x] some-scenario (error: ...)

========================================
```

## Error Handling

- If a migrator agent fails for a scenario, log the error and continue with remaining scenarios
- Never stop the whole batch due to a single failure
- Report all failures in the final report

## Notes

- README migrations are fully parallel-safe: each scenario's files are independent
- READMEs already at the current schema version WITH both companion files present are skipped
- The `scenario-readme-migrator` agent reads both schemas from `.claude/` -- make sure those files are up to date before running
- Workflow for schema changes: (1) edit `.claude/scenario-readme-schema.md` and bump the version, (2) edit `.claude/scenario-attackmap-schema.md` if needed, (3) record the change in `.claude/scenario-readme-changelog.md`, (4) run `/migrate-readmes --all`
