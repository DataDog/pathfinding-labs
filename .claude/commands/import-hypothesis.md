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

Delegates to the `scenario-research-importer` agent (via the Task tool), which:

1. Reads the research `REPORT.md`, `scenario.yaml` stub, `terraform/main.tf`, `demo_attack.sh`, and `validation.log`.
2. **Assigns a canonical pathfinding.cloud / pathfinding-labs ID** for the service. The research hypothesis ID (e.g., `amplify-002`) is its own counter and often collides with IDs already used upstream. The importer queries `pathfinding.cloud/paths.json` and scans `pathfinding-labs/modules/scenarios/` for existing IDs in that service, then picks the next free number (reusing the hypothesis ID only if it happens to be free in both places). The assignment is reported to the user.
3. Classifies the hypothesis into the labs taxonomy (category, sub_category, path_type, target). Asks if ambiguous.
4. Translates Terraform: drops the `pra-auditor` user, re-targets the `pra_flag` SSM parameter to the labs canonical flag, renames `pra-*` → `pl-prod-*`, swaps the provider for `aws.prod`, adds mandatory `force_destroy` / `force_detach_policies` flags. Hands the result to `scenario-terraform-builder` for splitting and polish.
5. Generates `scenario.yaml` at schema v1.8.0 with `required_preconditions` mapped from the research prerequisite categories. Strips any flag-revealing permissions (`ssm:GetParameter*`, `s3:GetObject` on flag bucket, `iam:ListUsers`) from the helpful permissions list.
6. Generates `demo_attack.sh` and `cleanup_attack.sh` via `scenario-demo-creator`, treating the research demo as the source of truth for how the attack actually works (sleeps, region re-exports, ordering nuances are carried over with explanatory comments) but rewriting the scaffolding to use labs conventions (terraform output -json, readonly creds, admin cleanup creds, no STEP markers). Final proof is the labs canonical `iam list-users` + flag fetch — not an `iam:AttachUserPolicy` re-attach.
7. Generates `README.md`, `solution.md`, and `attack_map.yaml` via `scenario-readme-creator`.
8. Appends the boolean flag, module block, and grouped output to root `variables.tf`, `main.tf`, and `outputs.tf`.
9. Runs `scenario-validator` against the new module and reports the result.

The command does NOT run `/test-scenarios` automatically — that requires AWS credentials and costs real time. After this command completes, the user should run `/test-scenarios <id>-<target>` to validate end-to-end.

## Output

A structured report listing the generated files, the root-file edits, translation notes (what was dropped, what was re-targeted), carried-over timing nuances with their justification, the final classification, and recommended next steps.

## Invocation

Use the Task tool with `subagent_type: "scenario-research-importer"`. Pass:
- Hypothesis ID (positional)
- Source directory (default `~/.pathfinding-research-agent/workspace/reports/<id>/` unless `--from` was supplied)
- Project root: the pathfinding-labs repo root (the current working directory if invoked from there)
