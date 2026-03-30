# Scenario README Schema Changelog

Version history for `.claude/scenario-readme-schema.md`. When bumping the schema version, add an entry here describing what changed and why.

---

## 1.0.0 — 2026-03-27

Initial formalized schema version. Established the tabbed-page structure mapping to pathfinding.cloud/labs frontend tabs.

**Structure introduced:**
- `## Attack Overview` — replaces `## Overview` + `## Understanding the attack scenario`
- `### MITRE ATT&CK Mapping` — moved under `## Attack Overview` (was under Detection section)
- `## Attack Lab` — replaces `## Executing the attack`
- `### Prerequisites`, `### Deploy with plabs non-interactive`, `### Deploy with plabs tui` — new boilerplate sections
- `### Executing the automated demo_attack script` — replaces `### Using the automated demo_attack.sh`
  - `#### Resources created by attack script` — new subsection
  - `#### With plabs non-interactive` (`plabs demo --list` / `plabs demo {name}`) — new subsection
  - `#### With plabs tui` (press `r`) — new subsection
- `### Cleanup` — replaces `### Cleaning up the attack artifacts`
  - `#### With plabs non-interactive` (`plabs cleanup --list` / `plabs cleanup {name}`) — new subsection
  - `#### With plabs tui` (press `c`) — new subsection
- `### Teardown with plabs non-interactive`, `### Teardown with plabs tui` — infrastructure teardown
- `## Detecting Misconfiguration (CSPM)` — split from `## Detection and prevention`
- `## Detection Abuse (CloudSIEM)` — new tab; CloudTrail events moved here
- CloudTrail event format: `` `Service: EventName` `` (was plain `` `EventName` `` or a table)
- `* **Schema Version:**` metadata field added to all READMEs
