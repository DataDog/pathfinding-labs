# Scenario README Schema Changelog

Version history for `.claude/scenario-readme-schema.md`. When bumping the schema version, add an entry here describing what changed and why.

---

## 4.0.1 — 2026-04-05

Patch: clarified public/anonymous starting point pattern for CTF, CSPM, and Toxic Combination scenarios.

**Changes:**
- **`- **Start:**` line** -- updated placeholder description to explicitly allow public resource URLs and plain descriptions for anonymous-access scenarios (not just IAM principal ARNs)
- **`### Starting Permissions` section** -- added canonical pattern for `principal_type: "public"` entries: use a descriptive label (e.g., `anonymous (public URL)`) in the heading rather than a fabricated ARN; documented when to include a Helpful block for IAM recon principals
- **Compliance checklist** -- loosened Starting Permissions item to accommodate descriptive labels for anonymous principals and URL-format Start lines
- **Prohibited pattern** -- explicitly banned invented ARNs like `arn:aws:sts::{account_id}:assumed-role/unauthenticated/attacker` for anonymous starting points
- **Added public-start example** alongside the existing ssm-001 IAM example in the Objective section

**Motivation:**
- CTF and CSPM scenarios that start from anonymous public access were being forced into IAM-principal framing (fabricated ARNs, awkward principal labels) because the schema only showed IAM-start examples
- `scenario.yaml` already supported `principal_type: "public"` correctly; the README schema just lacked matching guidance
- Fixed `cspm-toxic-combo/public-lambda-with-admin` README which had a fabricated `arn:aws:sts::...:assumed-role/unauthenticated/attacker` ARN in its Start line

**Migration rules:**
- If `- **Start:**` contains a fabricated `assumed-role/unauthenticated/...` ARN, replace with the actual public resource URL (e.g., the Lambda function URL) plus a `(public, no auth required)` note
- If `**Required** (...)` heading uses a fabricated ARN as the principal label, replace with a descriptive label matching the `principal` field in `scenario.yaml`
- No structural changes -- stamp `Schema Version: 4.0.1`

---

## 4.0.0 — 2026-04-03

Major version bump: per-principal permissions structure in `### Starting Permissions` and `scenario.yaml`.

**Breaking changes:**
- **`### Starting Permissions` restructured** -- Required and Helpful headings now include the principal name in parentheses: `**Required** ({principal_name}):` and `**Helpful** ({principal_name}):`. Multi-principal scenarios have multiple headings.
- **`scenario.yaml` `permissions.required` restructured** -- changed from a flat list of permission entries to an array of principal entries, each containing `principal`, `principal_type`, and `permissions` fields.
- **`scenario.yaml` `permissions.helpful` restructured** -- same per-principal grouping as required permissions.

**Motivation:**
- Support temporary deny-policy validation in demo scripts: during `demo_attack.sh`, helpful permissions are denied per-principal to prove only required permissions are needed for exploitation.
- Accurate multi-hop permission attribution: each principal in a multi-hop chain now has its own required and helpful permissions clearly associated.
- Frontend display clarity: pathfinding.cloud can render per-principal permission breakdowns.

**Migration rules:**
- Flat `**Required:**` heading becomes `**Required** ({principal_name}):` with principal name from scenario.yaml
- Flat `**Helpful:**` heading becomes `**Helpful** ({principal_name}):` with principal name from scenario.yaml
- Multi-hop scenarios split permissions across multiple principal headings
- Stamp `Schema Version: 4.0.0`

---

## 3.0.0 — 2026-04-01

Major version bump: README restructuring + attack map extraction + guided walkthrough creation. Separates the README into a lab guide (no spoilers) while attack data moves to `attack_map.yaml` and narrative content moves to `guided_walkthrough.md`.

**Breaking changes:**
- **Removed `## Attack Overview` H2** — prose moves to `guided_walkthrough.md` opening
- **Removed `### MITRE ATT&CK Mapping` section** — data stays in metadata fields only
- **Removed `### Principals in the attack path` section** — data lives in `attack_map.yaml` nodes
- **Removed `### Attack Path Diagram` section** — frontend renders from `attack_map.yaml`
- **Removed `### Attack Steps` section** — content moves to `guided_walkthrough.md`
- **Removed `### Attack Map` embedded YAML** — extracted to standalone `attack_map.yaml` file
- **Removed `### Executing the attack manually` section** — content moves to `guided_walkthrough.md`
- **Removed metadata fields**: `Attack Path`, `Attack Principals`, `Required Permissions`, `Helpful Permissions` — data moved to `## Objective` / `### Starting Permissions` / `attack_map.yaml`
- **Renamed `## Attack Lab`** — split into `## Self-hosted Lab Setup` + `## Attack`
- **Renamed `## Detecting Misconfiguration (CSPM)`** — now H3 under `## Defend`
- **Renamed `## Detection Abuse (CloudSIEM)`** — now H3 under `## Defend`

**New sections:**
- `## Objective` with `### Starting Permissions` — replaces metadata fields and first paragraph of Attack Overview
- `## Self-hosted Lab Setup` — contains Prerequisites and Deploy sections
- `## Attack` — contains resources, guided walkthrough, automated demo, cleanup
- `### Guided Walkthrough` — link to `guided_walkthrough.md`
- `### Automated Demo` — wrapper for demo script sub-sections
- `## Teardown` — promoted from sub-sections of Attack Lab
- `## Defend` — contains CSPM and CloudSIEM as H3 sub-sections

**New companion files per scenario:**
- `attack_map.yaml` — standalone structured attack graph data (extracted from README)
- `guided_walkthrough.md` — narrative CTF writeup (synthesized from Attack Overview + Attack Steps + manual execution + demo_attack.sh)

**New companion schema:**
- `.claude/scenario-attackmap-schema.md` — standalone schema for `attack_map.yaml` with improved hints system

**Hints improvements (in attack_map.yaml):**
- `hints` field on edges is now required (was optional)
- Minimum 3, maximum 7 hints per edge
- Ordered by order of operations first, then vague to specific
- Must include pathfinding.cloud link where a path ID is relevant
- Must not reveal exact commands

---

## 2.0.1 — 2026-03-31

Patch: added duplicate-ARN / phantom-node detection rule and migration guidance.

**Changes:**
- **Added "No duplicate ARNs" rule** to Attack Map section. Each node must have a unique ARN. Nodes that share an ARN with another node are "phantom" nodes representing a state change (e.g., "starting user after gaining admin") and must be removed.
- **Added migration procedure** for phantom node removal: use `scenario.yaml` → `attack_path.principals` as the source of truth for the real target ARN, remove the phantom node and its edge, move `isTarget: true` to the correct target node.
- **Added compliance checklist item**: "Attack Map has no duplicate ARNs across nodes (no phantom nodes)"
- 19 scenarios affected by this rule, primarily PassRole + compute patterns and iam-014/iam-019 attach-then-assume patterns.

---

## 2.0.0 — 2026-03-30

Major version bump: restructured Attack Map schema to fix target node identity, hint placement, and type semantics.

**Breaking changes:**
- **Removed `type: target`** from node types. Nodes now use `type: principal` or `type: resource` only, reflecting what the node IS rather than its graph position.
- **Added `isTarget: true`** boolean flag on nodes. Exactly one node per map must have this flag. Replaces the removed `target` type value.
- **Moved `hints` from nodes to edges.** Hints guide the attacker toward completing the next transition (edge), not from a static position (node). Hints are now an optional field on edges.
- **Removed `hints` from node schema.** Nodes no longer have a `hints` field.

**Semantic fixes:**
- **Target node identity**: The target node must represent the real infrastructure resource that grants escalated access (e.g., the admin role passed to a service), NOT the starting principal relabeled after exploitation.
- **Self-escalation self-loop pattern**: Self-escalation scenarios (iam-001, iam-005, iam-007, etc.) now use 2 nodes with a self-loop edge instead of 3 nodes with a phantom target. The starting role gets `isTarget: true` and an edge from itself to itself.

**Migration rules:**
- `type: target` with IAM subType -> `type: principal, isTarget: true`
- `type: target` with resource subType -> `type: resource, isTarget: true`
- Node `hints` arrays move to the outgoing edge from that node
- PassRole + compute targets change from "Starting User (Admin)" to the actual admin role
- Self-escalation targets collapse from 3 nodes to 2 nodes with self-loop

---

## 1.1.0 — 2026-03-30

New required section: `### Attack Map` under `## Attack Overview`.

**Changes:**
- Added `### Attack Map` section (after `### Attack Steps`, before `### Scenario specific resources created`)
- Contains a YAML code block with structured `attackMap` data (nodes, edges, hints, commands)
- Nodes define principals, resources, and targets with ARNs, descriptions, and progressive hints
- Edges define transitions with AWS permissions and CLI commands from demo_attack.sh
- Starting node description must begin with the standard initial-access prologue paragraph
- Required for all scenario types (privesc, CSPM, toxic-combo, tool-testing)
- CSPM scenarios may have simpler maps with fewer/empty commands
- Frontend uses this data to render gamified attack maps (hints on nodes, commands on edges)
- Added 4 compliance checklist items for Attack Map validation

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
