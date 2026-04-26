# Scenario Attack Map Schema Changelog

Version history for `.claude/scenario-attackmap-schema.md`. When bumping the schema version, add an entry here describing what changed and why. Include a `migration:` YAML block with machine-readable rules for the orchestrator.

---

## 1.4.0 — 2026-04-22

Minor: added CTF flag terminal pattern and `isAdmin` node flag. Every scenario (except `tool-testing/`) now ends at a CTF flag resource rather than at the admin principal.

**Changes:**
- New optional `isAdmin` boolean field on `type: principal` nodes. Marks principals with administrator-equivalent permissions (e.g., `AdministratorAccess` managed policy) so the pathfinding.cloud frontend can render them distinctly from scoped intermediates.
- `isAdmin` and `isTarget` are mutually exclusive on the same node. `isAdmin` is compatible with `isAttackerControlled`.
- New `ssm-parameter` recognized in the `subType` enum.
- New "CTF Flag Terminal Pattern" section: every non-tool-testing scenario has the CTF flag as the `isTarget: true` node.
  - to-admin: a new `ssm-parameter` node holds the flag at `arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/{scenario-id}`. The admin principal takes `isAdmin: true` instead of `isTarget: true`. A new edge from the admin principal to the flag node carries the `ssm:GetParameter` command.
  - to-bucket: the existing target bucket keeps `isTarget: true`. The flag is an `s3://{bucket}/flag.txt` object; retrieval is appended to the final edge's `commands`.
- "Target Node Identity" section rewritten: the target is the flag resource, not the admin pivot.
- Compliance checklist extended with flag-terminal and `isAdmin` assertions.
- The complete example was rewritten to show the 3-node pattern (starting → admin pivot with `isAdmin: true` → flag terminal with `isTarget: true`).

**Why:** Scenarios previously "ended at admin" with no explicit capture step, so there was no concrete success criterion beyond "I got admin". A CTF flag terminal gives each scenario a verifiable endpoint, makes every scenario renderable as a real CTF in the pathfinding.cloud frontend, and creates a single knob (the flag value) that Seth can swap between a public-repo default set and a vendor-specific set for hosted labs. Separating `isAdmin` from `isTarget` lets the frontend mark admin-equivalent pivots visually without overloading the "terminal" flag.

**Migration rules:**
- Applies to all scenarios outside `tool-testing/` (including privesc-self-escalation, privesc-one-hop, privesc-multi-hop, cspm-misconfig, cspm-toxic-combo, attack-simulation, cross-account, ctf).
- For to-admin scenarios: identify the current `isTarget: true` node (the admin principal). Remove `isTarget: true`, add `isAdmin: true`. Add a new `ssm-parameter` node with `isTarget: true` using the canonical ARN. Add a new edge from the admin principal to the flag node.
- For to-bucket scenarios: keep `isTarget: true` on the bucket. Append the flag-retrieval command (`aws s3 cp s3://{bucket}/flag.txt -`) to the final edge's `commands` array. For multi-hop-to-bucket, add `isAdmin: true` to any mid-chain principal that reaches admin-equivalent permissions.
- Tool-testing scenarios: no changes required; admin role may still take `isTarget: true`.
- This migration pairs with the README schema v4.6.0 bump and the root Terraform changes (`scenario_flags` variable, `flag_value` module plumbing). The `scenario-migrator` Phase 5 performs the end-to-end migration of Terraform + attack_map.yaml + demo scripts + solution.md + README together.

```yaml
migration:
  tier: agent
  scope:
    field: "category"
    custom: "all scenarios except those under tool-testing/"
  requires_scenario_yaml_fields: [attack_path, target]
  requires_companion_files: true
  affected_sections:
    - "attack_map.yaml:nodes[].isTarget"
    - "attack_map.yaml:nodes[].isAdmin"
    - "attack_map.yaml:nodes[] (new ssm-parameter flag node for to-admin)"
    - "attack_map.yaml:edges[] (new admin->flag edge for to-admin; flag retrieval command on final edge for to-bucket)"
  operations: []
  agent_instructions: |
    Run as part of scenario-migrator Phase 5 (CTF Flag Migration) — do NOT run standalone; this migration couples attack_map.yaml changes with Terraform, demo script, solution.md, and README changes.

    For to-admin scenarios:
    1. Identify the node currently holding isTarget: true (the admin principal).
    2. Remove isTarget: true from that node; add isAdmin: true.
    3. Add a new ssm-parameter node with id "ctf-flag", label "CTF Flag", type resource, subType ssm-parameter, isTarget: true, arn "arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/<scenario-id>", and a description consistent with the CTF Flag Terminal Pattern in the schema.
    4. Add a new edge from the admin principal node to the ctf-flag node with label "Read CTF flag", an appropriate description, 3-5 hints, and a commands array containing the ssm:GetParameter invocation.

    For to-bucket scenarios:
    1. Keep isTarget: true on the existing target bucket.
    2. On the final edge (the one leading into the target bucket), append a commands entry that retrieves flag.txt via aws s3 cp (or s3api get-object).
    3. For multi-hop-to-bucket: add isAdmin: true to any mid-chain principal node that reaches admin-equivalent permissions.

    For all scenarios:
    - Ensure every principal node holding AdministratorAccess or a wildcard inline policy has isAdmin: true.
    - Verify isAdmin: true and isTarget: true never co-occur on the same node.
    - Tool-testing scenarios are exempt; skip them entirely.
```

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
