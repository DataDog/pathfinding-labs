# Scenario Attack Map Schema Changelog

Version history for `.claude/scenario-attackmap-schema.md`. When bumping the schema version, add an entry here describing what changed and why. Include a `migration:` YAML block with machine-readable rules for the orchestrator.

---

## 1.3.0 — 2026-04-18

Minor: added optional `isAttackerControlled` boolean field to distinguish attacker-owned infrastructure nodes from victim resources.

**Changes:**
- New `isAttackerControlled` field on nodes (default `false`)
- Use on nodes representing infrastructure the attacker owns or controls — e.g., an exfil S3 bucket deployed in the attacker's own AWS account
- Mutually exclusive with `isTarget: true` — the attack destination is always on the victim side
- Compliance checklist updated: no node may have both `isTarget` and `isAttackerControlled`
- Added "Attacker-Controlled Infrastructure" section to schema explaining when and how to use the field

**Why:** Scenarios that involve data exfiltration to an attacker-owned account previously had no way to distinguish the exfil destination (attacker infrastructure) from the target data (victim resource). Without this distinction, the exfil bucket was incorrectly represented as the `isTarget` node, implying it was the victim's misconfiguration rather than the attacker's own staging area. The `isAttackerControlled` flag makes this distinction explicit in the attack map.

**Migration rules:**
- Only scenarios with exfil-to-attacker-account patterns are affected
- For any node that represents a bucket or resource deployed in an attacker account: add `isAttackerControlled: true`
- Ensure `isTarget: true` points to the victim-side resource (the sensitive data the attacker reads), not the exfil destination
- Remove `isTarget: true` from exfil/attacker-side nodes; move it to the sensitive data node

```yaml
migration:
  tier: agent
  scope:
    field: "category"
    custom: "scenarios with attacker-controlled exfil infrastructure"
  requires_scenario_yaml_fields: []
  requires_companion_files: true
  affected_sections:
    - "attack_map.yaml:nodes[].isAttackerControlled"
    - "attack_map.yaml:nodes[].isTarget"
  operations: []
  agent_instructions: |
    Review the attack map for nodes representing attacker-owned infrastructure (exfil buckets in attacker account).
    Add isAttackerControlled: true to those nodes.
    Move isTarget: true to the victim-side sensitive data node if it is currently on an attacker-controlled node.
```

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
