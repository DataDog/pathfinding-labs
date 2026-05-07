# Scenario Attack Map Schema Changelog

Version history for `.claude/scenario-attackmap-schema.md`. When bumping the schema version, add an entry here describing what changed and why. Include a `migration:` YAML block with machine-readable rules for the orchestrator.

---

## 1.7.0 — 2026-05-05

Minor: codified the principal→resource→principal authoring rule — all hints for a combined visual hop live on the IN edge; resource→principal (OUT) edges carry `hints: []`.

**Changes:**
- New "Principal→Resource→Principal Pairs" section: when the frontend collapses a resource node into a companion islet, the two edge hint sets are displayed together. Authors must treat the pair as a single unit: resynthesize 1-3 hints on the IN (principal→resource) edge covering the full execution story; set the OUT (resource→principal) edge to `hints: []`.
- Minimum hints updated: 0 is now valid on resource→principal (OUT) edges; 1 remains the minimum on principal→resource and principal→principal edges.
- pathfinding.cloud link must be last on the IN edge (so it remains last in the combined display).
- Added Lambda UpdateFunctionCode style note: frame as "fetch existing code and append payload" — less destructive to the environment than a full replace.
- Compliance checklist updated with four new assertions covering the pair rule and link-last requirement.

**Why:** The frontend collapses principal→resource→principal chains into a single visual hop, merging hint sets from both edges. Before this fix, the pathfinding.cloud link (last hint on the IN edge) was followed by OUT edge hints, making it no longer last. Combined hint counts also exceeded 3 in 25 of 69 pairs. The fix moves all hint authorship to the IN edge and leaves the OUT edge empty, giving authors a single place to craft the full story.

**Migration rules:**
- Applies to all scenarios with at least one principal→resource→principal chain.
- For each such pair: resynthesize IN edge hints + OUT edge hints into 1-3 cohesive hints on the IN edge, pathfinding.cloud link last. Set OUT edge to `hints: []`.

```yaml
migration:
  tier: agent
  scope:
    field: "structure"
    custom: "all scenarios with a principal→resource→principal edge chain"
  requires_scenario_yaml_fields: []
  requires_companion_files: false
  affected_sections:
    - "attack_map.yaml:edges[].hints (principal→resource IN edges)"
    - "attack_map.yaml:edges[].hints (resource→principal OUT edges)"
  operations:
    - description: "Resynthesize IN+OUT hints into 1-3 hints on the IN edge, pathfinding.cloud link last"
    - description: "Set OUT edge hints to []"
  agent_instructions: |
    For each principal→resource→principal triple in the attack map:
    1. Identify the IN edge (principal→resource) and OUT edge (resource→principal).
    2. Combine the hints from both edges.
    3. Resynthesize into 1-3 cohesive hints that preserve all useful information from both.
    4. If a pathfinding.cloud link appears anywhere in the combined set, it must be the last hint.
    5. Write the resynthesized hints onto the IN edge.
    6. Set the OUT edge hints to [].
    No other changes to the file.
```

---

## 1.6.0 — 2026-05-05

Minor: reduced hints per edge from 3-7 to 1-3 and refocused hint content from recon/identification to exploitation mechanics.

**Changes:**
- Quantity rule updated: minimum 3 → 1, maximum 7 → 3 hints per edge
- Content rules updated: hints now assume the attacker already knows the target (the attack map shows the destination node). Recon/enumeration steps ("use ListRoles to find...", "discover which...", "start by enumerating...") are no longer appropriate hint content.
- New explicit guidance: hints focus on exploitation mechanics, timing gotchas (IAM propagation delays, Lambda update latency), required flags, and pitfalls
- Every hop where a pathfinding.cloud path ID is relevant must include a link hint (was "typically the last or second-to-last hint" — now always the last)
- Ordering rules simplified: order of operations first, pathfinding.cloud link last
- Example hints rewritten to reflect new style (ssm-001 and iam-002 examples)

**Why:** The context assumption changed. Since a CSPM tool or open source tool (e.g., pmapper) has already identified the attack path, and the attack map visualizes the next hop's destination node, hints that guide target discovery add noise rather than value. The focus should be: you know where you're going, here's how to execute it well.

**Migration rules:**
- Applies to all `attack_map.yaml` files (all scenarios)
- For each edge: rewrite hints to 1-3 exploitation-focused hints
- Drop all hints that guide target discovery or enumeration
- Keep: exploitation mechanics, timing notes, required flags, pitfall warnings, pathfinding.cloud links
- Add a pathfinding.cloud link hint on any edge that references a path ID but is missing one

```yaml
migration:
  tier: agent
  scope: all
  requires_scenario_yaml_fields: []
  requires_companion_files: false
  affected_sections:
    - "attack_map.yaml:edges[].hints"
  operations:
    - description: "Rewrite each edge's hints array to 1-3 exploitation-focused hints, dropping recon/identification content"
    - description: "Add pathfinding.cloud link hint to any edge missing one where a path ID is known"
  agent_instructions: |
    For each edge in the attack map:
    1. Read the current hints array.
    2. Drop all hints that guide the attacker to discover, enumerate, or identify the target (e.g., "use ListRoles to find...", "look for users with elevated permissions", "start by understanding what roles exist").
    3. Keep and condense: exploitation mechanics (how to execute the hop), timing gotchas (IAM propagation, Lambda update delay), required flags, pitfall warnings.
    4. If a pathfinding.cloud path ID appears in the edge label, description, or existing hints, ensure the last hint is "Browse to https://pathfinding.cloud/paths/{path-id} for technique details."
    5. Result must be 1-3 hints total. If the condensed content naturally fits in 1-2, do not pad to 3.
    No other changes to the file (nodes, commands, descriptions, ARNs are untouched).
```

---

## 1.5.0 — 2026-04-27

Minor: added `grantsAdmin` boolean field on edges to fix the dual-crown bug in self-escalation to-admin scenarios.

**Changes:**
- New optional `grantsAdmin` boolean field on edges (default `false`). Only meaningful on self-loop edges (`from === to`). When `true`, the frontend suppresses the crown on the pre-escalation visual instance of the principal and applies the crown to the post-escalation instance.
- `isAdmin: true` on a node now means "this principal already holds admin at this point in the path." Self-escalating principals that *gain* admin through the self-loop should NOT carry `isAdmin: true` on the node; they should carry `grantsAdmin: true` on the self-loop edge.
- Updated `isAdmin` node field description with explicit "Do NOT set on self-escalating principals" guidance.
- New "Self-Escalation Self-Loop" pattern section describing the before/after visual split and the `grantsAdmin` field.
- Compliance checklist: added rule requiring `grantsAdmin: true` on the self-loop edge (not `isAdmin: true` on the node) for self-escalation to-admin scenarios.

**Why:** The frontend (`parseAttackMapToGameNodes`) expands a self-loop edge into two visual node instances — one before escalation, one after. Both instances were created from the same `nodeData` object, so `isAdmin: true` on the node caused both copies to get the admin crown. The fix separates the semantics: node-level `isAdmin` means "currently admin", edge-level `grantsAdmin` means "transitions to admin here."

**Migration rules:**
- Affects all self-escalation to-admin scenarios where the self-escalating principal currently has `isAdmin: true` and a self-loop edge.
- For each affected scenario: remove `isAdmin: true` from the self-escalating principal node; add `grantsAdmin: true` to the self-loop edge.
- Migrated in this release: iam-001, iam-005 (to-admin), iam-007, iam-008, iam-009 (to-admin).
- To-bucket self-escalation scenarios (iam-005-to-bucket, iam-009-to-bucket) are not affected — the self-loop grants scoped access, not full admin, so `isAdmin: true` was never set on those nodes.

```yaml
migration:
  tier: simple
  scope:
    field: "category"
    custom: "self-escalation to-admin scenarios with a self-loop edge where the escalating principal has isAdmin: true"
  requires_scenario_yaml_fields: []
  requires_companion_files: false
  affected_sections:
    - "attack_map.yaml:nodes[].isAdmin"
    - "attack_map.yaml:edges[].grantsAdmin"
  operations:
    - description: "Remove isAdmin: true from the self-escalating principal node"
    - description: "Add grantsAdmin: true to the self-loop edge on the same node"
  agent_instructions: |
    For each self-escalation to-admin scenario:
    1. Find the node that has both isAdmin: true and a self-loop edge (from === to === node.id).
    2. Remove isAdmin: true from that node.
    3. Add grantsAdmin: true to the self-loop edge.
    No other changes required.
```

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
