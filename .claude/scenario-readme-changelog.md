# Scenario README Schema Changelog

Version history for `.claude/scenario-readme-schema.md`. When bumping the schema version, add an entry here describing what changed and why.

---

## 4.1.1 — 2026-04-07

Patch: fixed `plabs enable`/`plabs disable` commands and TUI navigation instructions in deploy and teardown boilerplate.

**Changes:**
- **`### Deploy with plabs non-interactive`** -- changed `plabs enable {terraform_variable_name}` to `plabs enable {scenario_plabs_id}` (e.g., `plabs enable apprunner-001-to-admin`)
- **`### Teardown with plabs non-interactive`** -- same fix for `plabs disable`
- **`### Deploy with plabs tui`** -- changed generic "Navigate to this scenario" to `Navigate to \`{scenario_plabs_id}\`` so the instruction names the specific scenario
- **`### Teardown with plabs tui`** -- same fix

**Motivation:**
- The old boilerplate used Terraform variable names (e.g., `enable_single_account_privesc_one_hop_to_admin_apprunner_001_...`) which are internal identifiers -- the `plabs` CLI accepts scenario plabs IDs (e.g., `apprunner-001-to-admin`)
- TUI instructions were generic ("this scenario") when they should reference the specific scenario name for clarity

**Migration rules:**
- Replace `plabs enable {terraform_variable_name}` with `plabs enable {scenario_plabs_id}` in deploy section
- Replace `plabs disable {terraform_variable_name}` with `plabs disable {scenario_plabs_id}` in teardown section
- Replace "Navigate to this scenario in the scenarios list" with "Navigate to \`{scenario_plabs_id}\` in the scenarios list" in both TUI sections
- `{scenario_plabs_id}` = `{pathfinding-cloud-id}-{target}` if `pathfinding-cloud-id` exists, else `{name}-{target}`
- Stamp `Schema Version: 4.1.1`

```yaml
migration:
  tier: script
  requires_scenario_yaml_fields: [pathfinding-cloud-id, name, target, terraform.variable_name]
  affected_sections:
    - "### Deploy with plabs non-interactive"
    - "### Deploy with plabs tui"
    - "### Teardown with plabs non-interactive"
    - "### Teardown with plabs tui"
    - "metadata:Schema Version"
  operations:
    - find: "plabs enable {terraform.variable_name}"
      replace: "plabs enable {scenario_plabs_id}"
    - find: "plabs disable {terraform.variable_name}"
      replace: "plabs disable {scenario_plabs_id}"
    - find: "Navigate to this scenario in the scenarios list"
      replace: "Navigate to `{scenario_plabs_id}` in the scenarios list"
  derived_variables:
    scenario_plabs_id: "{pathfinding-cloud-id}-{target}"
    scenario_plabs_id_fallback: "{name}-{target}"
```

---

## 4.1.0 — 2026-04-06

Minor version bump: renamed `guided_walkthrough.md` companion file to `solution.md` and renamed the `### Guided Walkthrough` README section to `### Solution`.

**Changes:**
- **`solution.md`** -- companion file renamed from `guided_walkthrough.md`; content and format unchanged
- **`### Solution`** -- README section heading renamed from `### Guided Walkthrough`; link text and target updated accordingly
- **Schema file** -- all references to `guided_walkthrough.md` and "Guided Walkthrough" updated to `solution.md` and "Solution"

**Motivation:**
- "Guided Walkthrough" was ambiguous and confused with the hint-based "Guided Challenge" section on the frontend
- "Solution" is clearer and universally understood — it's the full answer, not a hint or guided discovery process
- Works equally well for CTF and non-CTF labs

**Migration rules:**
- Rename `guided_walkthrough.md` → `solution.md` in each scenario directory
- Update `### Guided Walkthrough` → `### Solution` in each README
- Update `[Guided Walkthrough](guided_walkthrough.md)` → `[Solution](solution.md)` in each README
- Stamp `Schema Version: 4.1.0`

```yaml
migration:
  tier: script
  requires_scenario_yaml_fields: []
  affected_sections:
    - "### Solution"
    - "metadata:Schema Version"
  operations:
    - type: file_rename
      from: "guided_walkthrough.md"
      to: "solution.md"
    - find: "### Guided Walkthrough"
      replace: "### Solution"
    - find: "[Guided Walkthrough](guided_walkthrough.md)"
      replace: "[Solution](solution.md)"
  derived_variables: {}
```

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

```yaml
migration:
  tier: agent
  scope:
    field: "permissions.required[].principal_type"
    contains: "public"
  requires_scenario_yaml_fields: [permissions, pathfinding-cloud-id, name, target]
  requires_companion_files: false
  affected_sections:
    - "metadata:Start"
    - "### Starting Permissions"
  operations: []
  agent_instructions: |
    If `- **Start:**` contains a fabricated ARN like `assumed-role/unauthenticated/...`,
    replace with the actual public resource URL from scenario.yaml or main.tf.
    If `**Required** (...)` heading uses a fabricated ARN as the principal label,
    replace with a descriptive label matching the `principal` field in scenario.yaml.
```

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

```yaml
migration:
  tier: agent
  scope: all
  requires_scenario_yaml_fields: [permissions]
  requires_companion_files: false
  affected_sections:
    - "### Starting Permissions"
    - "metadata:Required Permissions"
    - "metadata:Helpful Permissions"
  operations: []
  agent_instructions: |
    Rebuild ### Starting Permissions using per-principal format from scenario.yaml.
    Each principal gets its own **Required** ({principal_name}): and **Helpful** ({principal_name}): headings.
    Remove old metadata fields: Required Permissions, Helpful Permissions.
```

---

## 3.0.0 — 2026-04-01

Major version bump: README restructuring + attack map extraction + guided walkthrough creation. Separates the README into a lab guide (no spoilers) while attack data moves to `attack_map.yaml` and narrative content moves to `solution.md`.

**Breaking changes:**
- **Removed `## Attack Overview` H2** — prose moves to `solution.md` opening
- **Removed `### MITRE ATT&CK Mapping` section** — data stays in metadata fields only
- **Removed `### Principals in the attack path` section** — data lives in `attack_map.yaml` nodes
- **Removed `### Attack Path Diagram` section** — frontend renders from `attack_map.yaml`
- **Removed `### Attack Steps` section** — content moves to `solution.md`
- **Removed `### Attack Map` embedded YAML** — extracted to standalone `attack_map.yaml` file
- **Removed `### Executing the attack manually` section** — content moves to `solution.md`
- **Removed metadata fields**: `Attack Path`, `Attack Principals`, `Required Permissions`, `Helpful Permissions` — data moved to `## Objective` / `### Starting Permissions` / `attack_map.yaml`
- **Renamed `## Attack Lab`** — split into `## Self-hosted Lab Setup` + `## Attack`
- **Renamed `## Detecting Misconfiguration (CSPM)`** — now H3 under `## Defend`
- **Renamed `## Detection Abuse (CloudSIEM)`** — now H3 under `## Defend`

**New sections:**
- `## Objective` with `### Starting Permissions` — replaces metadata fields and first paragraph of Attack Overview
- `## Self-hosted Lab Setup` — contains Prerequisites and Deploy sections
- `## Attack` — contains resources, guided walkthrough, automated demo, cleanup
- `### Guided Walkthrough` — link to `solution.md`
- `### Automated Demo` — wrapper for demo script sub-sections
- `## Teardown` — promoted from sub-sections of Attack Lab
- `## Defend` — contains CSPM and CloudSIEM as H3 sub-sections

**New companion files per scenario:**
- `attack_map.yaml` — standalone structured attack graph data (extracted from README)
- `solution.md` — narrative CTF writeup (synthesized from Attack Overview + Attack Steps + manual execution + demo_attack.sh)

**New companion schema:**
- `.claude/scenario-attackmap-schema.md` — standalone schema for `attack_map.yaml` with improved hints system

**Hints improvements (in attack_map.yaml):**
- `hints` field on edges is now required (was optional)
- Minimum 3, maximum 7 hints per edge
- Ordered by order of operations first, then vague to specific
- Must include pathfinding.cloud link where a path ID is relevant
- Must not reveal exact commands

```yaml
migration:
  tier: agent
  scope: all
  requires_scenario_yaml_fields: [permissions, pathfinding-cloud-id, name, target, attack_path]
  requires_companion_files: true
  affected_sections: ["*"]
  operations: []
  agent_instructions: |
    Full structural migration. Read full schema files.
    Extract attack_map.yaml from embedded YAML block.
    Create solution.md from attack content.
    Restructure README: remove Attack Overview, split Attack Lab, create Defend wrapper.
    See v2.0.1->v3.0.0 migration map in schema file for complete rules.
```

---

## 2.0.1 — 2026-03-31

Patch: added duplicate-ARN / phantom-node detection rule and migration guidance.

**Changes:**
- **Added "No duplicate ARNs" rule** to Attack Map section. Each node must have a unique ARN. Nodes that share an ARN with another node are "phantom" nodes representing a state change (e.g., "starting user after gaining admin") and must be removed.
- **Added migration procedure** for phantom node removal: use `scenario.yaml` → `attack_path.principals` as the source of truth for the real target ARN, remove the phantom node and its edge, move `isTarget: true` to the correct target node.
- **Added compliance checklist item**: "Attack Map has no duplicate ARNs across nodes (no phantom nodes)"
- 19 scenarios affected by this rule, primarily PassRole + compute patterns and iam-014/iam-019 attach-then-assume patterns.

```yaml
migration:
  tier: agent
  scope: all
  requires_scenario_yaml_fields: [attack_path]
  requires_companion_files: false
  affected_sections:
    - "### Attack Map"
  operations: []
  agent_instructions: |
    Check attack map for duplicate ARNs across nodes (phantom nodes).
    If found, remove phantom node and its edge, move isTarget: true to the real target node.
    Use scenario.yaml attack_path.principals as source of truth.
```

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

```yaml
migration:
  tier: agent
  scope: all
  requires_scenario_yaml_fields: [attack_path]
  requires_companion_files: false
  affected_sections:
    - "### Attack Map"
  operations: []
  agent_instructions: |
    Restructure attack map: remove type:target, add isTarget:true flag, move hints from nodes to edges.
    Fix target node identity for PassRole+compute patterns.
    Collapse self-escalation from 3 nodes to 2 nodes with self-loop.
```

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

```yaml
migration:
  tier: agent
  scope: all
  requires_scenario_yaml_fields: [attack_path, pathfinding-cloud-id]
  requires_companion_files: false
  affected_sections:
    - "## Attack Overview"
  operations: []
  agent_instructions: |
    Add ### Attack Map section under ## Attack Overview with structured YAML block.
    Create nodes and edges from attack_path data in scenario.yaml.
    Add hints to nodes and commands to edges from demo_attack.sh.
```

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

```yaml
migration:
  tier: agent
  scope: all
  requires_scenario_yaml_fields: [pathfinding-cloud-id, name, target, terraform.variable_name]
  requires_companion_files: false
  affected_sections: ["*"]
  operations: []
  agent_instructions: |
    Initial schema formalization. Restructure all sections to match v1.0.0 schema.
    Add boilerplate sections (Prerequisites, Deploy, Teardown, Cleanup).
    Add metadata block with Schema Version field.
    Read full schema for complete structure reference.
```
