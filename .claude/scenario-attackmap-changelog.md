# Scenario Attack Map Schema Changelog

Version history for `.claude/scenario-attackmap-schema.md`. When bumping the schema version, add an entry here describing what changed and why. Include a `migration:` YAML block with machine-readable rules for the orchestrator.

---

## 1.2.0 — 2026-04-06

Minor: added CTF Scenario Pattern section with content rules for challenge-appropriate node descriptions, edge labels, hints, and commands that preserve discovery without giving away the attack path.

**Changes:**
- New "CTF Scenario Pattern" section defining how to write attack maps for CTF-style scenarios
- Node descriptions must not reveal the attack technique
- Edge labels use generic phrasing ("Exploit vulnerability" vs "Use iam:PassRole")
- Hints are more oblique, guiding toward discovery rather than spelling out steps

**Migration rules:**
- CTF scenarios only: review node descriptions and edge hints against new CTF content rules
- Non-CTF scenarios: no changes needed

```yaml
migration:
  tier: agent
  scope:
    field: "category"
    equals: "CTF"
  requires_scenario_yaml_fields: [category]
  requires_companion_files: true
  affected_sections:
    - "attack_map.yaml:nodes[].description"
    - "attack_map.yaml:edges[].hints"
  operations: []
  agent_instructions: |
    Review node descriptions and edge hints for CTF scenarios.
    Apply content rules from CTF Scenario Pattern section of attackmap schema.
    Node descriptions must not reveal the attack technique.
    Edge hints should guide toward discovery, not spell out steps.
```

---

## 1.1.0 — 2026-04-06

Minor: added optional `access` object to nodes for structured entry-point URLs, IPs, and domains. Required on nodes that use the public access prologue.

**Changes:**
- New `access` field on nodes: `{ url: string, ip: string, domain: string }` (all optional)
- Required when the node's description uses the public/anonymous access prologue
- Used by the frontend to render clickable entry-point links

**Migration rules:**
- Public-start scenarios only: add `access` object to the starting node with the public URL
- All other scenarios: no changes needed

```yaml
migration:
  tier: agent
  scope:
    field: "permissions.required[].principal_type"
    contains: "public"
  requires_scenario_yaml_fields: [permissions]
  requires_companion_files: true
  affected_sections:
    - "attack_map.yaml:nodes[].access"
  operations: []
  agent_instructions: |
    Add access object to the starting node of public-access scenarios.
    Extract the public URL from main.tf or scenario.yaml.
    Format: access: { url: "https://..." }
```

---

## 1.0.0 — 2026-04-01

Initial schema, extracted from README schema v3.0.0.

**Changes:**
- Defined standalone `attack_map.yaml` file format
- Node schema: type, subType, arn, description, isTarget, hints
- Edge schema: from, to, label, hints, commands
- Standard starting node prologue patterns (IAM principal and public/anonymous)
- Pattern rules for self-escalation, multi-hop, CSPM, public/anonymous

```yaml
migration:
  tier: agent
  scope: all
  requires_scenario_yaml_fields: [attack_path, pathfinding-cloud-id]
  requires_companion_files: true
  affected_sections: ["*"]
  operations: []
  agent_instructions: |
    Initial extraction. Create attack_map.yaml from embedded ### Attack Map YAML block in README.
    This was handled as part of the README v3.0.0 migration.
```
