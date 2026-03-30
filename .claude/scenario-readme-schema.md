# Pathfinding Labs Scenario README Schema

**Current schema version: `1.0.0`**

This file is the canonical reference for the structure and content of all scenario README.md files. Both the `scenario-readme-creator` and `scenario-readme-migrator` agents read this file as their source of truth. Update this file when the standard changes — bump the version following semver, record the change in `.claude/scenario-readme-changelog.md`, then run `/migrate-readmes` to propagate changes to all existing READMEs.

**Version bump guide:**
- **PATCH** (e.g., `1.0.0` → `1.0.1`): boilerplate wording tweaks, content rule clarifications, no structural change
- **MINOR** (e.g., `1.0.0` → `1.1.0`): new required H3/H4 section added, new required metadata field added
- **MAJOR** (e.g., `1.0.0` → `2.0.0`): H2 section renamed, added, or removed; metadata field renamed or removed

---

## Canonical Section Structure

The sections below must appear in this exact order with these exact H2/H3/H4 headings.

```
# {Title}

{metadata bullet list}

## Attack Overview
### MITRE ATT&CK Mapping
### Principals in the attack path
### Attack Path Diagram
### Attack Steps
### Scenario specific resources created

## Attack Lab
### Prerequisites
### Deploy with plabs non-interactive
### Deploy with plabs tui
### Executing the automated demo_attack script
#### Resources created by attack script
#### With plabs non-interactive
#### With plabs tui
### Executing the attack manually         ← omit for simple one-hop; required for multi-hop
### Cleanup
#### With plabs non-interactive
#### With plabs tui
### Teardown with plabs non-interactive
### Teardown with plabs tui

## Detecting Misconfiguration (CSPM)
### What CSPM tools should detect
### Prevention recommendations

## Detection Abuse (CloudSIEM)
### CloudTrail events to monitor
### Detonation logs

## References                             ← optional; include when meaningful links exist
```

---

## Metadata Block

The metadata bullet list appears immediately after the H1 title, before any H2 sections. Each bullet is a `* **Field:** value` line.

**Required fields (all scenarios):**
```
* **Category:** {Privilege Escalation|CSPM: Misconfig|CSPM: Toxic Combination|Tool Testing}
* **Path Type:** {self-escalation|one-hop|multi-hop|cross-account|single-condition|toxic-combination}
* **Target:** {to-admin|to-bucket}
* **Environments:** {prod|dev|operations|prod, dev}
* **Cost Estimate:** {value, e.g., "$0/mo"}
* **Technique:** {one-line description of the exploit}
* **Terraform Variable:** `{variable_name}`
* **Schema Version:** {current version from this file, e.g., 1.0.0}
```

`Schema Version` must always reflect the schema version in effect when the README was last created or migrated. It is the last required field in the metadata block, appearing after `Terraform Variable` and before any conditional fields.

**Conditional fields:**
```
* **Sub-Category:** {self-escalation|principal-access|new-passrole|existing-passrole|credential-access}
  ← only for privesc self-escalation and one-hop scenarios

* **Pathfinding.cloud ID:** {e.g., iam-002}
  ← only if pathfinding-cloud-id is present in scenario.yaml

* **Interactive Demo:** Yes
  ← only if interactive_demo: true in scenario.yaml

* **Attack Path:** {arrow-notation, e.g., starting_user → (iam:CreateAccessKey) → admin access}
  ← include for privesc scenarios

* **Attack Principals:** `{arn1}`; `{arn2}`; `{arn3}`
  ← include for privesc scenarios; semicolon-separated, each ARN in backticks, use {account_id} placeholder

* **Required Permissions:** `{perm}` on `{resource}`; `{perm}` on `{resource}`
  ← include for privesc scenarios; semicolon-separated

* **Helpful Permissions:** `{perm}` ({purpose}); `{perm}` ({purpose})
  ← omit entirely if none

* **MITRE Tactics:** {TA#### - Name}, {TA#### - Name}
* **MITRE Techniques:** {T####.### - Name}, {T####.### - Name}
```

**CSPM scenario additional fields** (after MITRE Techniques):
```
* **CSPM Rule ID:** {value}
* **CSPM Severity:** {value}
* **CSPM Expected Finding:** resource_type={value}; resource_id={value}; finding={value}
* **Risk Summary:** {value}
* **Risk Impact:** {item1}; {item2}; {item3}
* **Remediation:** {item1}; {item2}; {item3}
```

---

## Section Content Rules

### `## Attack Overview`

2-3 prose paragraphs explaining:
- What the vulnerability is and how it can be exploited
- Why it's dangerous
- When this configuration appears in real environments

### `### MITRE ATT&CK Mapping`

```
- **Tactic**: {TA#### - Name}
- **Technique**: {T####.### - Name}
- **Sub-technique**: {if applicable}
```

For scenarios with multiple tactics, list each on its own line under `**Tactics**:` and `**Techniques**:`.

### `### Principals in the attack path`

Bulleted list of all principals in order, each as a backtick-wrapped ARN followed by a parenthetical description. Use `PROD_ACCOUNT`, `DEV_ACCOUNT`, or `REGION` as placeholders.

### `### Attack Path Diagram`

Mermaid flowchart using `graph LR`. Color convention:
- Starting principal: `fill:#ff9999`
- Intermediate principals: `fill:#ffcc99`
- Target: `fill:#99ff99`

All nodes use `stroke:#333,stroke-width:2px`.

### `### Attack Steps`

Numbered list. Always starts with `**Initial Access**` and ends with `**Verification**`. Multi-hop scenarios label each hop explicitly (e.g., `**Hop 1 - ...**`, `**Hop 2 - ...**`).

### `### Scenario specific resources created`

Markdown table with columns `ARN` and `Purpose`. Full ARN format with account/region placeholders.

### `## Attack Lab`

### `### Prerequisites` — exact boilerplate, do not vary:

```
1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)
```

### `### Deploy with plabs non-interactive` — use the terraform variable name:

```
```bash
plabs enable {terraform_variable_name}
plabs apply
```
```

### `### Deploy with plabs tui` — exact boilerplate:

```
1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `space` to enable it
4. Press `d` to deploy
```

### `### Executing the automated demo_attack script`

Open with a "The script will:" numbered list describing what the demo does. Do NOT include a raw `./demo_attack.sh` bash block — use the sub-sections below instead.

#### `#### Resources created by attack script`

Bulleted list of every artifact the demo script creates (access keys, modified code, temp files, etc.).

#### `#### With plabs non-interactive`

```
```bash
plabs demo --list
plabs demo {scenario-directory-name}
```
```

`{scenario-directory-name}` is the scenario's directory name (e.g., `iam-002-iam-createaccesskey`, `lambda-004-to-iam-002-to-admin`).

#### `#### With plabs tui`

```
1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script
```

### `### Executing the attack manually`

Include for multi-hop and complex scenarios: full bash snippets walking through each step manually. Omit entirely for simple one-hop scenarios.

### `### Cleanup` — attack artifact cleanup (distinct from infrastructure teardown)

#### `#### With plabs non-interactive`

```
```bash
plabs cleanup --list
plabs cleanup {scenario-directory-name}
```
```

#### `#### With plabs tui`

```
1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script
```

### `### Teardown with plabs non-interactive` — infrastructure destruction:

```
```bash
plabs disable {terraform_variable_name}
plabs apply
```
```

### `### Teardown with plabs tui` — exact boilerplate:

```
1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy
```

### `## Detecting Misconfiguration (CSPM)`

### `### What CSPM tools should detect`

Bulleted list of specific, scenario-relevant findings. Not generic security advice — these should be detectable from policy analysis on the specific resources in this scenario.

### `### Prevention recommendations`

4-6 specific, actionable bullet points: SCPs, IAM conditions, monitoring rules, etc.

### `## Detection Abuse (CloudSIEM)`

### `### CloudTrail events to monitor`

Bulleted list. Each entry format: `` - `{Service}: {EventName}` — {description} ``

Service is the AWS service short name: `IAM`, `Lambda`, `STS`, `EC2`, `ECS`, `SSM`, `Glue`, `CloudFormation`, `CodeBuild`, `SageMaker`, `S3`, etc.

Example:
```
- `IAM: CreateAccessKey` — New access keys created for an IAM user; critical when the target has elevated permissions
- `Lambda: UpdateFunctionCode20150331v2` — Lambda function code modified; high severity when followed by an invocation
```

### `### Detonation logs` — exact boilerplate:

```
_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
```

### `## References`

Optional. Include when there are meaningful external links (pathfinding.cloud paths, MITRE ATT&CK technique pages, AWS documentation). Format:

```
- [{link text}]({url}) — {one-line description}
```

---

## Old → New Structure Migration Map

Use this table when migrating READMEs created before the tabbed-page structure was adopted.

| Old heading | New heading / action |
|---|---|
| `## Overview` | Rename to `## Attack Overview` |
| `## Understanding the attack scenario` | Remove this H2 header; its subsections stay and become nested under `## Attack Overview` |
| `### MITRE ATT&CK Mapping` (under Detection) | Move block to under `## Attack Overview`, after prose paragraphs, before `### Principals in the attack path` |
| `## Executing the attack` | Rename to `## Attack Lab` |
| `### Using the automated demo_attack.sh` | Replace with new demo script structure (see above) |
| Raw `./demo_attack.sh` bash block | Remove; replaced by `#### With plabs non-interactive` / `#### With plabs tui` subsections |
| `### Manual attack execution` | Rename to `### Executing the attack manually` |
| `### Cleaning up the attack artifacts` | Replace with `### Cleanup` section containing the two subsections |
| `## Detection and prevention` | Split: CSPM content → `## Detecting Misconfiguration (CSPM)`; CloudTrail/SIEM content → `## Detection Abuse (CloudSIEM)` |
| `## Prevention recommendations` (H2) | Move content under `### Prevention recommendations` (H3) inside `## Detecting Misconfiguration (CSPM)` |
| CloudTrail table (with columns Event/Description/Severity) | Convert to bullet list under `### CloudTrail events to monitor`; prefix each event with service name |
| CloudTrail bullets without service prefix (e.g., `` `CreateAccessKey` ``) | Add service prefix (e.g., `` `IAM: CreateAccessKey` ``) |
| Missing `### Prerequisites`, Deploy, Teardown sections | Add standard boilerplate |
| Missing `### Cleanup` section | Add with standard boilerplate |
| Missing `## Detection Abuse (CloudSIEM)` | Add with `### CloudTrail events to monitor` (best-effort content from what's available) and `### Detonation logs` placeholder |

---

## Compliance Checklist

A README is compliant if all of the following are true:

- [ ] `* **Schema Version:** {version}` is present in the metadata block and matches the current schema version (`1.0.0`)
- [ ] H2 sections are exactly: `Attack Overview`, `Attack Lab`, `Detecting Misconfiguration (CSPM)`, `Detection Abuse (CloudSIEM)` (plus optional `References`)
- [ ] `### MITRE ATT&CK Mapping` is under `## Attack Overview`, not under any detection section
- [ ] No `## Understanding the attack scenario` H2 header exists
- [ ] No `## Executing the attack` H2 header exists
- [ ] No `## Detection and prevention` H2 header exists
- [ ] No `## Prevention recommendations` H2 header exists (it must be H3 under CSPM)
- [ ] `## Attack Lab` contains `### Prerequisites`, `### Deploy with plabs non-interactive`, `### Deploy with plabs tui`
- [ ] `### Executing the automated demo_attack script` contains `#### Resources created by attack script`, `#### With plabs non-interactive`, `#### With plabs tui`
- [ ] No raw `cd ... && ./demo_attack.sh` bash block exists in the demo section
- [ ] `### Cleanup` section exists with `#### With plabs non-interactive` and `#### With plabs tui`
- [ ] `### Teardown with plabs non-interactive` and `### Teardown with plabs tui` exist
- [ ] `## Detection Abuse (CloudSIEM)` exists with `### CloudTrail events to monitor` and `### Detonation logs`
- [ ] All CloudTrail events use `` `Service: EventName` `` format
- [ ] `### Detonation logs` contains the standard placeholder text
