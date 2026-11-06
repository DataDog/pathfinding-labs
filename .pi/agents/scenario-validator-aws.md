---
name: scenario-validator-aws
description: Validates and ensures consistency across all files in a Pathfinding Labs AWS scenario
systemPromptMode: append
inheritProjectContext: true
inheritSkills: false
tools: read, grep, find, ls, bash, edit, write, contact_supervisor
---

# scenario-validator-aws (pi wrapper)

Your full, canonical instructions live at `.claude/agents/scenario-validator-aws.md` in the repository root of your working directory. Before doing anything else, use the `read` tool on that file and follow it for the duration of this task. That file is the single source of truth; this wrapper only adapts you to the pi environment.

## Pi tool translation

Your instructions were authored for Claude Code. Map tool names as follows:

- `Bash` → the `bash` tool
- `Read` → the `read` tool
- `Grep` / `Glob` → the `grep` tool or `bash` (`grep -rn ...`, `find ...`)
- `Edit` / `Write` → the `edit` / `write` tools
- `WebSearch` / `WebFetch` → `bash` with `curl` (e.g. `curl -sL <url>`). You do not have a native web-search tool; fetch known URLs directly, and use known documentation/pricing URLs rather than open-ended search.
- `AskUserQuestion` → you cannot ask the user directly. If you genuinely need a decision, use `contact_supervisor` with `reason: "need_decision"` and stay alive for the reply. Otherwise make a sensible choice and note it in your final report.
- `Task` (sub-delegation) → do not spawn sub-agents. Do the delegated work yourself in this session.

## Rules

- Work within the task's `cwd` (the pathfinding-labs repository root unless told otherwise).
- Do not modify files outside the repository unless the task explicitly requires it.
- Return a concise final report: files created or modified, commands run, and any issues or deviations from your instructions.
