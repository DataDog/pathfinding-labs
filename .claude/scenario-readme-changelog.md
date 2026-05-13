# Scenario README Schema Changelog

Version history for `.claude/scenario-readme-schema.md`. When bumping the schema version, add an entry here describing what changed and why.

---

## 4.7.0 — 2026-05-13

Minor: added optional `* **Required Preconditions:**` metadata field.

**Changes:**
- **`* **Required Preconditions:**`** -- new optional metadata field rendered from `required_preconditions` in `scenario.yaml`. Each precondition entry renders as a bullet nested under the field label:
  - `aws-resource` entries: `- {resource}: {description}` (e.g., `- Lambda Function: with admin execution role attached`)
  - all other type entries: `- [{type}] {description}` (e.g., `- [network] function must be publicly invocable`)
- Field appears after `* **CTF Flag Location:**` and before any blank line ending the metadata block.
- Field is omitted entirely when `required_preconditions` is absent from `scenario.yaml` -- no change needed for existing scenarios.

**Motivation:**
- Preconditions are a first-class differentiator in attack path uniqueness. Two paths sharing the same permissions (e.g., `lambda:UpdateFunctionCode`) are fundamentally different attacks if one requires an existing Lambda with a privileged role and the other does not.
- Aligns pathfinding-labs with pathfinding.cloud, which already expresses `prerequisites` on path entries.
- Canonical use case: `existing-passrole` and `credential-access` sub_categories, and `Attack Simulation` scenarios.

**Migration rules:**
- This is a MINOR -- the field is optional and existing READMEs remain compliant. No migration required for existing scenarios.
- When creating or updating a README for a scenario whose `scenario.yaml` includes `required_preconditions`, add the field to the metadata block.
- Stamp `Schema Version: 4.7.0` only when making another change that touches the README; do not update the stamp for the preconditions field alone unless the preconditions field is also being added.

```yaml
migration:
  tier: none
  scope: new-scenarios-only
  affected_sections:
    - "metadata:Required Preconditions"
  operations: []
```

---

## 4.6.1 — 2026-05-07

Patch: standardized CloudTrail event format in `#### CloudTrail Events to Monitor` sections.

**Changes:**
- **`#### CloudTrail Events to Monitor` format** -- event names now use lowercase service prefix with no space after the colon: `` `service:EventName` `` (e.g., `iam:CreateAccessKey`, `lambda:CreateFunction20150331`). Previous format was `` `Service: EventName` `` (capitalized, space after colon).
- **Separator** -- standardized to `--` (double dash) throughout. Em dash `—` is no longer permitted.
- **`iam:PassRole` prohibition** -- `iam:PassRole` must not appear as a monitored CloudTrail event because it does not produce a standalone event. PassRole abuse is detected via the role ARN field in the service creation event (e.g., `requestParameters.role` in `lambda:CreateFunction20150331`, `requestParameters.taskRoleArn` in `ecs:RegisterTaskDefinition`, `requestParameters.serviceRole` in `codebuild:CreateProject`, `requestParameters.roleARN` in `cloudformation:CreateStack`, `requestParameters.roleArn` in `sagemaker:CreateTrainingJob`, etc.).
- **Compliance checklist** -- updated assertion to: `` `service:EventName` `` format (lowercase service prefix, no space after colon, `--` separator — never an em dash).

**Motivation:**
- AWS CloudTrail uses lowercase service prefixes with no space (e.g., `iam:CreateAccessKey`), matching the IAM action syntax. The previous capitalized format (`IAM: CreateAccessKey`) was inconsistent with how events appear in CloudTrail logs, CloudWatch filters, and EventBridge rules.
- `iam:PassRole` does not emit a CloudTrail event — it is an authorization check embedded within service creation calls. Listing it as a detectable event was misleading to practitioners.

**Migration rules:**
- This is a PATCH — no structural changes. Existing READMEs remain compliant at their current schema version. Apply opportunistically when a README is otherwise being updated.
- In `#### CloudTrail Events to Monitor`: replace `` `Service: Action` `` with `` `service:Action` `` (lowercase prefix, remove space after colon).
- Replace any `` ` — `` (em dash separator) with `` ` -- `` (double dash).
- Remove any `` - `iam:PassRole` `` bullet entirely. Move the PassRole detection context into the description of the service creation event that carries the role ARN field.
- Stamp `Schema Version: 4.6.1`.

```yaml
migration:
  tier: script
  scope: all
  affected_sections:
    - "#### CloudTrail Events to Monitor"
    - "metadata:Schema Version"
  operations:
    - pattern: "- `([A-Z][a-zA-Z]*): ([^`]+)`"
      replace: "- `{lowercase($1)}:{$2}`"
    - find: "` — "
      replace: "` -- "
    - remove_line_matching: "^- `iam:PassRole`"
    - find: "Schema Version: 4.6.0"
      replace: "Schema Version: 4.6.1"
```

---

## 4.6.0 — 2026-04-22

Minor version bump: added `CTF Flag Location` metadata field and the `## Capture the Flag` section in `solution.md`. Pairs with attack map schema v1.4.0.

**Changes:**
- **Metadata block** — new required field for all non-tool-testing scenarios: `* **CTF Flag Location:** {ssm-parameter|s3-object}`. Placed after `Supports Online Mode` (the previous last conditional field). Indicates the storage mechanism for the scenario's CTF flag; the exact path/key is in the `attack_map.yaml` terminal node ARN.
- **solution.md structure** — new required section `## Capture the Flag`, positioned between `## Verification` and `## What Happened`. Describes the final flag-retrieval step using the credentials/access gained in the previous sections. Shows the exact CLI command but never the flag value (values are deployment-specific and come from `flags.default.yaml` or a vendor override file).
- **Compliance checklist** — two new assertions:
  - Non-tool-testing scenarios must have `CTF Flag Location` in metadata.
  - Non-tool-testing scenarios' `solution.md` must have a `## Capture the Flag` section.
- **Schema version pinning** — bumped the hardcoded version reference in the compliance checklist from `4.5.0` to `4.6.0`.

**Motivation:**
- Pathfinding Labs is shifting from "the attack ends at admin" to a true CTF model where every scenario has a concrete flag to capture. The flag resource (SSM parameter or S3 object) is declared in the scenario's Terraform, exposed by the attack map as the new `isTarget: true` terminal, and retrieved as the last step of the demo script. The README and solution.md need to reflect this final step consistently across all scenarios.
- A structured `CTF Flag Location` field (rather than prose) lets the pathfinding.cloud frontend and the `plabs` CLI reason about flag storage without natural-language parsing. The exact flag path is already recoverable from `attack_map.yaml` and terraform outputs, so this field only needs to identify the storage pattern.
- Tool-testing scenarios are exempt: they exist for detection-engine testing rather than CTF gameplay, so they don't get a flag terminal.

**Migration rules:**
- Applies to every scenario NOT under `tool-testing/` (privesc-self-escalation, privesc-one-hop, privesc-multi-hop, cspm-misconfig, cspm-toxic-combo, attack-simulation, cross-account, ctf).
- Add `* **CTF Flag Location:** ssm-parameter` to metadata for every `target: to-admin` scenario.
- Add `* **CTF Flag Location:** s3-object` to metadata for every `target: to-bucket` scenario.
- Add a `## Capture the Flag` section to `solution.md` between `## Verification` and `## What Happened`. The section shows the appropriate retrieval command (`aws ssm get-parameter ...` for to-admin, `aws s3 cp s3://<bucket>/flag.txt -` for to-bucket) plus a short paragraph explaining why the credentials from the previous step grant flag access.
- Stamp `Schema Version: 4.6.0`.
- This migration is executed as part of `scenario-migrator` Phase 5 (CTF Flag Migration), which simultaneously updates Terraform (flag resource + `flag_value` variable), attack_map.yaml (isAdmin/isTarget rewiring per attackmap v1.4.0), demo_attack.sh (final flag-retrieval step), and the root Terraform (`flag_value = lookup(var.scenario_flags, ...)` plumbing). Running the README migration standalone will produce incomplete scenarios; always run Phase 5 end-to-end.

```yaml
migration:
  tier: agent
  scope:
    field: "category"
    custom: "all scenarios except those under tool-testing/"
  requires_scenario_yaml_fields: [target, name]
  requires_companion_files: true
  affected_sections:
    - "metadata_block"
    - "solution.md"
  operations:
    - find: "Schema Version: 4.5.0"
      replace: "Schema Version: 4.6.0"
  agent_instructions: |
    Run only as part of scenario-migrator Phase 5 (CTF Flag Migration). Do NOT run standalone.

    For the README:
    1. Read scenario.yaml to determine `target` (to-admin or to-bucket).
    2. Add the appropriate `* **CTF Flag Location:** ssm-parameter` (to-admin) or `* **CTF Flag Location:** s3-object` (to-bucket) line after the existing last conditional metadata field. If the scenario already has a legacy CTF `* **Flag Location:** ...` prose line (ctf/ directory only), keep it — it describes specifics; the new structured enum is orthogonal.
    3. Stamp `Schema Version: 4.6.0`.

    For solution.md:
    1. Add a `## Capture the Flag` section between `## Verification` and `## What Happened`.
    2. Show the exact retrieval command:
       - to-admin: `aws ssm get-parameter --name /pathfinding-labs/flags/<scenario-id> --query 'Parameter.Value' --output text`
       - to-bucket: `aws s3 cp s3://<bucket-name>/flag.txt -`
    3. Do NOT include the actual flag value — it is deployment-specific.
    4. Write 1-2 paragraphs explaining why the credentials obtained in the Exploitation/Verification step grant access to the flag (administrator permissions include ssm:GetParameter; bucket access already includes s3:GetObject).

    Tool-testing scenarios: skip entirely.
```

---

## 4.5.0 — 2026-04-18

Minor version bump: added `Supports Online Mode` conditional metadata field.

**Changes:**
- **Conditional metadata fields** -- added `* **Supports Online Mode:** Yes` as the last conditional field in the metadata block. Emitted only when `supports_online_mode: true` in `scenario.yaml`. Omitted entirely when false or absent (false is the default for all existing scenarios).

**Motivation:**
- The pathfinding.cloud frontend reads `state.lab?.supportsOnlineMode` to determine whether to render the "Play Online" button for a lab. The field must flow from `scenario.yaml` → README metadata → `generate-labs-json.py` → `labs.json` → frontend. Adding it to the README metadata section is the necessary step to wire it into the existing generator pipeline.
- Labs will have this set to `false` by default. The Pathfinding team manually sets `supports_online_mode: true` in `scenario.yaml` (and the corresponding README line is updated) as individual labs are validated and provisioned for online play.

**Migration rules:**
- No migration needed for existing scenarios — the field is conditional and defaults to absent (false)
- No existing README needs a new line added (only add when `supports_online_mode: true`)
- New scenarios: omit the field entirely unless the lab is online-ready
- Stamp `Schema Version: 4.5.0` only on READMEs that are otherwise being updated

```yaml
migration:
  tier: none
  scope: none
  affected_sections: [metadata_block]
  operations: []
```

---

## 4.4.0 — 2026-04-10

Minor version bump: added `Cost Estimate (Demo)` required metadata field.

**Changes:**
- **Metadata block** -- added `* **Cost Estimate When Demo Executed:** {value}` immediately after `* **Cost Estimate:** {value}`. Value comes from `cost_estimate_when_demo_executed` in `scenario.yaml`.

**Motivation:**
- Labs have two distinct cost states: idle (lab deployed, no attack running) and active (demo script executing, which may provision temporary resources like EC2 instances or Lambda functions). Surfacing both values in the TUI and website gives users accurate cost visibility before running a demo.

**Migration rules:**
- Add `* **Cost Estimate (Demo):** {cost_estimate_when_demo_executed}` after the existing `* **Cost Estimate:**` line
- Value comes from `cost_estimate_when_demo_executed` in `scenario.yaml` (always present in schema v1.5.0+)
- Stamp `Schema Version: 4.4.0`

```yaml
migration:
  tier: script
  scope: all
  requires_scenario_yaml_fields: [cost_estimate_when_demo_executed]
  affected_sections: [metadata_block]
  operations:
    - find: "* **Cost Estimate:** {value}"
      replace: "* **Cost Estimate:** {value}\n* **Cost Estimate When Demo Executed:** {cost_estimate_when_demo_executed}"
    - find: "Schema Version: 4.3.2"
      replace: "Schema Version: 4.4.0"
```

---

## 4.3.2 — 2026-04-09

Patch: restored `Lab Modifications` as a single-line reference in Attack Simulation metadata, pointing to the canonical `### Modifications from Original Attack` section instead of duplicating content.

**Changes:**
- **Metadata block** -- `**Lab Modifications:**` is back as a single fixed-text line: "This lab was modified from the original attack. See [Modifications from Original Attack](#modifications-from-original-attack) for details." Omitted if `modifications` is absent or empty in `scenario.yaml`.
- **Section Content Rules** -- clarified that `### Modifications from Original Attack` is the canonical location for the full list; the metadata line is a surface-level notice only.

**Motivation:**
- The 4.3.1 removal went too far — readers scanning the metadata have no indication that lab differences exist. A short reference line surfaces this without duplicating the full bullet list.

**Migration rules:**
- If `**Lab Modifications:**` was removed by the 4.3.1 migration and `modifications` is non-empty in `scenario.yaml`, add back the single-line form: `* **Lab Modifications:** This lab was modified from the original attack. See [Modifications from Original Attack](#modifications-from-original-attack) for details.`
- If `modifications` is absent or empty, leave the field omitted.
- Stamp `Schema Version: 4.3.2`

```yaml
migration:
  tier: script
  scope:
    field: "category"
    equals: "Attack Simulation"
  affected_sections: [metadata_block]
  operations:
    - if: "scenario.yaml has modifications list (non-empty) AND Lab Modifications field is absent"
      action: "add Lab Modifications single-line reference after Source Date"
      value: "* **Lab Modifications:** This lab was modified from the original attack. See [Modifications from Original Attack](#modifications-from-original-attack) for details."
    - find: "Schema Version: 4.3.1"
      replace: "Schema Version: 4.3.2"
```

---

## 4.3.1 — 2026-04-09

Patch: removed `Lab Modifications` metadata field for Attack Simulation scenarios; `### Modifications from Original Attack` section is the canonical location.

**Changes:**
- **Metadata block** -- removed `**Lab Modifications:**` nested bullet list. Source Date is now immediately followed by Technique with no Lab Modifications field between them.
- **Section Content Rules** -- clarified that the `modifications` list in `scenario.yaml` is the source data for `### Modifications from Original Attack`, not a metadata field.

**Motivation:**
- The `### Modifications from Original Attack` section under `## Attack` already documents this content in full prose. The metadata bullet list was redundant and lower quality.
- The frontend will read modifications from the `### Modifications from Original Attack` section going forward.

**Migration rules:**
- Remove `**Lab Modifications:**` and all its sub-bullets from the README metadata block if present
- Stamp `Schema Version: 4.3.1`

```yaml
migration:
  tier: script
  scope:
    field: "category"
    equals: "Attack Simulation"
  affected_sections: [metadata_block]
  operations:
    - find: "**Lab Modifications:**\n  * ..."
      action: "remove entire Lab Modifications field and sub-bullets"
    - find: "Schema Version: 4.3.0"
      replace: "Schema Version: 4.3.1"
```

---

## 4.3.0 — 2026-04-09

Minor version bump: added `Lab Modifications` conditional metadata field for Attack Simulation scenarios.

**Changes:**
- **Conditional metadata fields** -- added `**Lab Modifications:**` nested bullet list for Attack Simulation scenarios, displayed after `Source Date` and before `Technique`. Each sub-bullet maps to one entry in the `modifications` list in `scenario.yaml`. Omitted if `modifications` is absent or empty.

**Motivation:**
- Learners need to understand what was changed from the real-world attack before reading the objective. The website displays this between the source attribution block and the "Your objective is..." sentence, so it must be present in the README metadata.

**Migration rules:**
- No migration needed for existing scenarios -- `Lab Modifications` is conditional and only applies to Attack Simulation scenarios
- New Attack Simulation scenarios should include `Lab Modifications` if `modifications` is set in `scenario.yaml`
- Stamp `Schema Version: 4.3.0` for new or updated Attack Simulation READMEs

```yaml
migration:
  tier: none
  scope:
    field: "category"
    equals: "Attack Simulation"
  affected_sections: [metadata_block]
  operations:
    - if: "scenario.yaml has modifications list (non-empty)"
      action: "add Lab Modifications nested bullets after Source Date, before Technique"
```

---

## 4.2.0 — 2026-04-08

Minor version bump: added Attack Simulation category support.

**Changes:**
- **Metadata block** -- added `Attack Simulation` to Category enum, `attack-simulation` to Path Type enum
- **Conditional metadata fields** -- added Source URL, Source Title, Source Author, Source Date for Attack Simulation scenarios
- **Canonical section structure** -- added `### Modifications from Original Attack` (Attack Simulation only, between `### Scenario Specific Resources Created` and `### Solution`)
- **Section Content Rules** -- added Attack Simulation subsection documenting `## Objective` phrasing, `### Modifications from Original Attack` content, `## References` requirement, and demo script behavior

**Motivation:**
- New scenario category converts real-world breach blog posts into lab environments
- Requires source attribution metadata and documentation of modifications made for lab safety/cost
- Demo scripts follow chronological order of the original attack, including recon and failed attempts

**Migration rules:**
- No migration needed -- new category only, no structural changes to existing READMEs
- Stamp `Schema Version: 4.2.0` for new Attack Simulation scenarios only

```yaml
migration:
  tier: none
  scope:
    field: "category"
    equals: "Attack Simulation"
  requires_scenario_yaml_fields: [source]
  affected_sections: []
  operations: []
```

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
