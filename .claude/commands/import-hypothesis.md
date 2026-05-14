---
name: import-hypothesis
description: Imports a validated pathfinding-research-agent hypothesis into pathfinding-labs as a fully-formed scenario module
---

# /import-hypothesis

Convert a validated hypothesis from `pathfinding-research-agent` into a pathfinding-labs scenario.

## Usage

```
/import-hypothesis <hypothesis-id> [--from <path>]
```

**Arguments:**
- `<hypothesis-id>` — the research hypothesis ID (e.g., `amplify-002`, `imagebuilder-007`)
- `--from <path>` — optional override for the source report directory. Defaults to `~/.pathfinding-research-agent/workspace/reports/<hypothesis-id>/`.

**Examples:**
- `/import-hypothesis amplify-002`
- `/import-hypothesis lambda-014 --from /tmp/handoff/lambda-014/`

## What this does

Delegates to `/workflows:scenario-orchestrator` in **research hypothesis mode**, which:

1. Reads the research source files (`REPORT.md`, `scenario.yaml` stub, `terraform/main.tf`, `demo_attack.sh`, `validation.log`) directly from the source directory.
2. **Assigns a canonical pathfinding.cloud / pathfinding-labs ID** for the service. Queries `pathfinding.cloud/paths.json` and scans `pathfinding-labs/modules/scenarios/` for existing IDs in that service, then picks the next free number. Also checks the local naming convention used by existing same-service scenarios in the target category path. Reports the assignment to the user.
3. Classifies the hypothesis into the labs taxonomy (category, sub_category, path_type, target). Asks if ambiguous.
4. **Presents a validation summary to the user** (canonical ID, directory path, classification, required permissions, attack path summary) and waits for approval before proceeding.
5. Creates `scenario.yaml` at the current schema version with `required_preconditions` mapped from the research prerequisite categories. Strips any flag-revealing permissions from the helpful permissions list.
6. **Concurrently delegates** to the same 5 specialized agents used by the standard scenario orchestrator, each receiving a `RESEARCH CONTEXT` block with the source directory path so they can read the research files directly:
   - `scenario-terraform-builder` — reads research `terraform/main.tf` as a proof-of-concept reference for a full labs-convention rebuild
   - `scenario-demo-creator` — reads research `demo_attack.sh` as ground truth for attack ordering, sleeps, and region handling
   - `scenario-readme-creator` — reads research `REPORT.md` and `demo_attack.sh` for exploitation steps and proof methodology
   - `project-updator` — wires the new module into root `variables.tf`, `main.tf`, `outputs.tf`
   - `scenario-cost-estimator` — runs infracost on the generated Terraform
7. Runs `scenario-validator` against the new module and reports the result.

The command does NOT run `/test-scenarios` automatically — that requires AWS credentials and costs real time. After this command completes, run `/test-scenarios <id>-<target>` to validate end-to-end.

## Output

A structured report listing the generated files, the root-file edits, translation notes (what was dropped, what was re-targeted), carried-over timing nuances with their justification, the final classification, and recommended next steps.

## Invocation

Use the Agent tool with `subagent_type: "scenario-research-importer"`. Pass:
- Hypothesis ID (positional)
- Source directory (default `~/.pathfinding-research-agent/workspace/reports/<id>/` unless `--from` was supplied)
- Project root: the pathfinding-labs repo root (the current working directory if invoked from there)

> **Note:** The `scenario-research-importer` agent now orchestrates via the standard `scenario-orchestrator` flow. The research hypothesis is passed as source material to the orchestrator's "Research Hypothesis Input Mode" rather than handled by a separate parallel pipeline.
