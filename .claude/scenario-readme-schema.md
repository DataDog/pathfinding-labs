# Pathfinding Labs Scenario README Schema

**Current schema version: `4.7.1`**

This file is the canonical reference for the structure and content of all scenario README.md files. Both the `scenario-readme-creator` and `scenario-readme-migrator` agents read this file as their source of truth. Update this file when the standard changes -- bump the version following semver, record the change in `.claude/scenario-readme-changelog.md` (including a `migration:` YAML block with machine-readable rules), then run `/migrate-readmes` to propagate changes to all existing READMEs.

**Version bump guide:**
- **PATCH** (e.g., `1.0.0` -> `1.0.1`): boilerplate wording tweaks, content rule clarifications, no structural change
- **MINOR** (e.g., `1.0.0` -> `1.1.0`): new required H3/H4 section added, new required metadata field added
- **MAJOR** (e.g., `1.0.0` -> `2.0.0`): H2 section renamed, added, or removed; metadata field renamed or removed

**Companion files:**
- `.claude/scenario-attackmap-schema.md` -- schema for `attack_map.yaml` (structured attack graph data)
- `solution.md` -- narrative CTF writeup per scenario (see Solution Format below)

---

## Canonical Section Structure

The sections below must appear in this exact order with these exact H2/H3/H4 headings.

**Title rule:** The H1 is the `title` field from `scenario.yaml` verbatim — no category prefix. Example: `# Lambda Function Creation + Invocation to Admin`. Do not prepend "Privilege Escalation:", "CSPM Misconfiguration:", or any other category string.

```
# {Title}

{metadata bullet list}

## Objective
### Starting Permissions

## Self-hosted Lab Setup
### Prerequisites
### Deploy with plabs non-interactive
### Deploy with plabs tui

## Attack
### Scenario Specific Resources Created
### Modifications from Original Attack  <- Attack Simulation only
### Solution
### Automated Demo
#### Executing the automated demo_attack script
#### Resources Created by Attack Script
#### With plabs non-interactive
#### With plabs tui
### Cleanup
#### With plabs non-interactive
#### With plabs tui

## Teardown
### Teardown with plabs non-interactive
### Teardown with plabs tui

## Defend
### Detecting Misconfiguration (CSPM)
#### What CSPM tools should detect
#### Prevention Recommendations
### Detecting Abuse (CloudSIEM)
#### CloudTrail Events to Monitor
#### Detonation logs

## References                          <- optional
```

---

## Metadata Block

The metadata bullet list appears immediately after the H1 title, before any H2 sections. Each bullet is a `* **Field:** value` line.

**Required fields (all scenarios):**
```
* **Category:** {Privilege Escalation|CSPM: Misconfig|CSPM: Toxic Combination|Tool Testing|CTF|Attack Simulation}
* **Path Type:** {self-escalation|one-hop|multi-hop|cross-account|single-condition|toxic-combination|ctf|attack-simulation}
* **Target:** {to-admin|to-bucket}
* **Environments:** {prod|dev|operations|prod, dev}
* **Cost Estimate:** {value, e.g., "$0/mo"}
* **Cost Estimate When Demo Executed:** {value, e.g., "$0/mo"}
* **Technique:** {one-line description of the exploit}
* **Terraform Variable:** `{variable_name}`
* **Schema Version:** {current version from this file, e.g., 3.0.0}
```

`Schema Version` must always reflect the schema version in effect when the README was last created or migrated. It is the last required field in the metadata block, appearing after `Terraform Variable` and before any conditional fields.

**Conditional fields:**
```
* **Sub-Category:** {self-escalation|principal-access|new-passrole|existing-passrole|credential-access}
  <- only for privesc self-escalation and one-hop scenarios

* **Pathfinding.cloud ID:** {e.g., iam-002}
  <- ONLY for scenarios with a 1:1 mapping to a single pathfinding.cloud path catalog entry (the ID must exist in pathfinding.cloud/data/paths/). Omit for multi-hop, cross-account, attack-simulation, tool-testing, and CSPM toxic-combo labs — these don't map to a single path entry and must not use composite values like "iam-002 + sts-001".

* **Interactive Demo:** Yes
  <- only if interactive_demo: true in scenario.yaml

* **MITRE Tactics:** {TA#### - Name}, {TA#### - Name}
* **MITRE Techniques:** {T####.### - Name}, {T####.### - Name}

* **Supports Online Mode:** Yes
  <- only if supports_online_mode: true in scenario.yaml

* **CTF Flag Location:** {ssm-parameter|s3-object}
  <- required on all scenarios EXCEPT those under tool-testing/. Value is the storage mechanism only.
     - `ssm-parameter` -- all to-admin scenarios. The flag lives at `/pathfinding-labs/flags/{scenario-id}` in SSM Parameter Store in the target account.
     - `s3-object` -- all to-bucket scenarios. The flag lives as `flag.txt` inside the scenario's target S3 bucket.
     The exact path/key is documented in the scenario's `attack_map.yaml` terminal node ARN and is retrievable via terraform outputs.

* **Required Preconditions:**
  - {resource}: {description}
  - [{type}] {description}
  <- only if required_preconditions is present in scenario.yaml. Render each entry as a bullet.
     For aws-resource entries: "- {resource}: {description}" (e.g., "- Lambda Function: with admin execution role attached")
     For all other types: "- [{type}] {description}" (e.g., "- [network] function must be publicly invocable")
     Place this field after CTF Flag Location and before any blank line ending the metadata block.
```

**CTF scenario additional fields** (in place of Sub-Category, after Cost Estimate):
```
* **Difficulty:** {beginner|intermediate|advanced}
* **Flag Location:** {description of where the flag is stored}
```

CTF scenarios omit the `### Automated Demo` section entirely (participants must discover the exploit themselves). They still include `### Solution` (linked to `solution.md`, which serves as the post-competition writeup/solution). CTF scenarios may have a `cleanup_attack.sh` if the attack modifies infrastructure state, but no `demo_attack.sh`.

**Attack Simulation scenario additional fields** (after Cost Estimate, before Technique):
```
* **Source URL:** {url}
* **Source Title:** {title}
* **Source Author:** {author/organization}
* **Source Date:** {YYYY-MM-DD}
* **Lab Modifications:** This lab was modified from the original attack. See [Modifications from Original Attack](#modifications-from-original-attack) for details.
```

Omit the `Lab Modifications` line entirely if the `modifications` list is absent or empty in `scenario.yaml`.

Attack Simulation scenarios omit `Sub-Category`. They include all standard sections (including `### Automated Demo`). They add a `### Modifications from Original Attack` section under `## Attack` (see Section Content Rules below) — that section is the canonical location for the full list of modifications.

**CSPM scenario additional fields** (after MITRE Techniques):
```
* **CSPM Rule ID:** {value}
* **CSPM Severity:** {value}
* **CSPM Expected Finding:** resource_type={value}; resource_id={value}; finding={value}
* **Risk Summary:** {value}
* **Risk Impact:** {item1}; {item2}; {item3}
* **Remediation:** {item1}; {item2}; {item3}
```

**Fields removed in v3.0.0** (data lives in `attack_map.yaml` and `## Objective`):
- `Attack Path` -- attack flow is rendered from `attack_map.yaml` edges
- `Attack Principals` -- principal ARNs are in `attack_map.yaml` nodes
- `Required Permissions` -- moved to `### Starting Permissions` section
- `Helpful Permissions` -- moved to `### Starting Permissions` section

---

## Section Content Rules

### `## Objective`

A single sentence using this exact template pattern:

```
Your objective is to learn how to exploit a [privilege escalation vulnerability | misconfiguration | combination of multiple misconfigurations] that allows you to move from the [initial entry point -- starting principal name, publicly accessible service, etc.] to [destination/target/conclusion of the attack -- admin role name, S3 bucket name, etc.] by [brief description of the technique].
```

The sentence should name the specific resources (e.g., `pl-prod-ssm-001-to-admin-starting-user`) rather than generic descriptions. Keep it to one sentence -- all the detailed context lives in `solution.md`.

Followed by structured context:

```
- **Start:** `{starting point -- IAM principal ARN with placeholders, OR public resource URL/description for anonymous-access scenarios}`
- **Destination resource:** `{target resource ARN with placeholders}`
```

**Example (ssm-001, IAM principal start):**

```
Your objective is to learn how to exploit a privilege escalation vulnerability that allows you to move from the `pl-prod-ssm-001-to-admin-starting-user` IAM user to the `pl-prod-ssm-001-to-admin-ec2-role` administrative role by starting an interactive SSM session on an EC2 instance and extracting credentials from the Instance Metadata Service (IMDS).
```

**Example (public/anonymous start -- CTF or CSPM):**

```
Your objective is to learn how to exploit a misconfiguration that allows you to move from the publicly accessible `pl-prod-ctf-001-acmebot` Lambda chatbot to the `pl-prod-ctf-001-chatbot-role` administrative IAM role by injecting a prompt that triggers shell execution and leaks execution role credentials.

- **Start:** `https://{function_url_id}.lambda-url.{region}.on.aws/` (public, no auth required)
- **Destination resource:** `arn:aws:iam::{account_id}:role/pl-prod-ctf-001-chatbot-role`
```

For public-start scenarios, the `- **Start:**` line uses a URL or plain description -- not a fabricated IAM ARN. Do not invent ARNs like `arn:aws:sts::{account_id}:assumed-role/unauthenticated/attacker`.

#### `### Starting Permissions`

Permissions are grouped by principal. Each principal gets its own **Required** and/or **Helpful** heading with the principal name in parentheses.

**Single principal (most one-hop scenarios):**

```
**Required** (`{principal_name}`):
- `{permission}` on `{resource}` -- {brief description}

**Helpful** (`{principal_name}`):
- `{permission}` -- {purpose/what it enables for recon}
```

**Multiple principals (multi-hop scenarios):**

```
**Required** (`{principal_name_1}`):
- `{permission}` on `{resource}` -- {brief description}

**Required** (`{principal_name_2}`):
- `{permission}` on `{resource}` -- {brief description}

**Helpful** (`{principal_name_1}`):
- `{permission}` -- {purpose}

**Helpful** (`{principal_name_2}`):
- `{permission}` -- {purpose}
```

If a principal has no helpful permissions, omit the Helpful heading for that principal. If no principals have helpful permissions, omit all Helpful headings.

**Public/anonymous starting point (CTF, CSPM Toxic Combo, CSPM Misconfig):**

When the scenario starts from unauthenticated or anonymous access, use the `principal_type: "public"` entry from `scenario.yaml` as the principal. Label it descriptively rather than as an ARN:

```
**Required** (`anonymous (public URL)`):
- `lambda:InvokeFunctionUrl` on `{resource}` -- no AWS credentials required; the resource accepts unauthenticated requests

**Helpful** (`{iam_principal_name}`):
- `{permission}` -- {purpose}
```

The "Helpful" block for public-start scenarios typically belongs to a low-privilege IAM user used for reconnaissance (e.g., discovering the public URL). If no IAM recon is needed, omit the Helpful block entirely.

Do NOT invent a fake ARN (e.g., `arn:aws:sts::{account_id}:assumed-role/unauthenticated/attacker`) for the anonymous attacker. Use a descriptive label in the heading and a URL or plain description in the `- **Start:**` line.

### `## Self-hosted Lab Setup`

Container section for deployment instructions. No prose content at this level.

#### `### Prerequisites` -- exact boilerplate, do not vary:

```
1. Install the `plabs` CLI:
   ```bash
   brew install pathfinding-labs/tap/plabs
   ```
2. Configure your AWS profiles in `~/.plabs/plabs.yaml` (or run `plabs init` if you haven't already)
```

#### `### Deploy with plabs non-interactive` -- use the scenario's plabs ID:

```
```bash
plabs enable {scenario_plabs_id}
plabs apply
```
```

`{scenario_plabs_id}` is the scenario's unique ID used by the `plabs` CLI (e.g., `apprunner-001-to-admin`, `public-lambda-with-admin-to-admin`). For scenarios with a `pathfinding-cloud-id` in `scenario.yaml`, it is `{pathfinding-cloud-id}-{target}`. Otherwise it is `{name}-{target}`. For multi-hop and other labs without `pathfinding-cloud-id`, the `name` field in scenario.yaml must NOT include the target suffix — e.g., `name: "lambda-004-to-iam-002"` with `target: "to-admin"` produces the clean plabs ID `lambda-004-to-iam-002-to-admin`.

#### `### Deploy with plabs tui` -- use the scenario's plabs ID in the navigation instruction:

```
1. Launch the TUI: `plabs`
2. Navigate to `{scenario_plabs_id}` in the scenarios list
3. Press `space` to enable it
4. Press `a` to apply
```

### `## Attack`

Container section for attack content. No prose content at this level.

#### Attack Simulation Scenarios

Attack Simulation scenarios have these additional requirements under `## Attack`:

- **`### Modifications from Original Attack`** -- appears after `### Scenario Specific Resources Created` and before `### Solution`. Documents what was changed from the original real-world attack for the lab environment. Use a bulleted list:
  - Steps that were simplified (e.g., "Cross-account movement simplified to single-account role assumption")
  - Steps that were omitted (e.g., "GPU instance provisioning omitted for cost")
  - Steps that were simulated differently (e.g., "t3.micro used instead of p5.48xlarge")
  - Resource substitutions and cost-saving changes
- **`## Objective`** opening sentence references the real-world incident: "Your objective is to recreate the attack chain from [{source_title}]({source_url}), where an attacker moved from {starting point} to {target} by {technique summary}."
- **`## References`** MUST include the source blog post as the first reference
- **`### Automated Demo` description** should note that the demo script follows the chronological order of the original attack, including recon and failed attempts as described in the source blog post

#### `### Scenario Specific Resources Created`

Markdown table with columns `ARN` and `Purpose`. Full ARN format with account/region placeholders.

#### `### Solution`

Link to the companion walkthrough file:

```
For a narrative, step-by-step walkthrough of this attack (CTF writeup style), see:

[Solution](solution.md)
```

#### `### Automated Demo`

Container section for the automated demo script. No prose at this level.

##### `#### Executing the automated demo_attack script`

Open with a "The script will:" numbered list describing what the demo does. Do NOT include a raw `./demo_attack.sh` bash block.

##### `#### Resources Created by Attack Script`

Bulleted list of every artifact the demo script creates (access keys, modified code, temp files, etc.).

##### `#### With plabs non-interactive`

```
```bash
plabs demo --list
plabs demo {scenario-directory-name}
```
```

`{scenario-directory-name}` is the scenario's directory name (e.g., `iam-002-iam-createaccesskey`, `lambda-004-to-iam-002-to-admin`).

##### `#### With plabs tui`

```
1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `r` to run the demo script
```

#### `### Cleanup` -- attack artifact cleanup (distinct from infrastructure teardown)

##### `#### With plabs non-interactive`

```
```bash
plabs cleanup --list
plabs cleanup {scenario-directory-name}
```
```

##### `#### With plabs tui`

```
1. Launch the TUI: `plabs`
2. Navigate to this scenario in the scenarios list
3. Press `c` to run the cleanup script
```

### `## Teardown`

Container section for infrastructure destruction.

#### `### Teardown with plabs non-interactive` -- infrastructure destruction:

```
```bash
plabs disable {scenario_plabs_id}
plabs apply
```
```

#### `### Teardown with plabs tui` -- use the scenario's plabs ID in the navigation instruction:

```
1. Launch the TUI: `plabs`
2. Navigate to `{scenario_plabs_id}` in the scenarios list
3. Press `space` to disable it
4. Press `D` to destroy
```

### `## Defend`

Container section for detection and prevention guidance. No prose at this level.

#### `### Detecting Misconfiguration (CSPM)`

##### `#### What CSPM tools should detect`

Bulleted list of specific, scenario-relevant findings. Not generic security advice -- these should be detectable from policy analysis on the specific resources in this scenario.

##### `#### Prevention Recommendations`

4-6 specific, actionable bullet points: SCPs, IAM conditions, monitoring rules, etc.

#### `### Detecting Abuse (CloudSIEM)`

##### `#### CloudTrail Events to Monitor`

Bulleted list. Each entry format: `` - `{service}:{EventName}` -- {description} ``

Service prefix is the AWS service short name in **lowercase** with **no space** after the colon: `iam`, `lambda`, `sts`, `ec2`, `ecs`, `ssm`, `glue`, `cloudformation`, `codebuild`, `sagemaker`, `s3`, `apprunner`, `mwaa`, `datapipeline`, `dynamodb`, etc.

Separator between event name and description is always `--` (double dash, never an em dash `—`).

Example:
```
- `iam:CreateAccessKey` -- new access keys created for an IAM user; critical when the target has elevated permissions
- `lambda:UpdateFunctionCode20150331v2` -- Lambda function code modified; high severity when followed by an invocation
```

##### `#### Detonation logs` -- exact boilerplate:

```
_Detonation log integration (Stratus Red Team / Grimoire) is planned for a future release._
```

### `## References`

Optional. Include when there are meaningful external links (pathfinding.cloud paths, MITRE ATT&CK technique pages, AWS documentation). Format:

```
- [{link text}]({url}) -- {one-line description}
```

---

## Solution Format (`solution.md`)

A separate file per scenario, located in the same directory as the README. Written as a **narrative CTF writeup** -- the kind of post you'd read on a security blog after a CTF competition. Linked from `### Solution` in the README.

**Structure:**

1. **Title** -- `# Solution: {Scenario Title}`
2. **Opening** -- the Attack Overview prose (relocated from README v2.x). Frames the challenge: what kind of vulnerability, why it's dangerous, when it appears in real environments. 2-3 paragraphs.
3. **The Challenge** (`## The Challenge`) -- what you start with (your principal, your permissions) and what you need to achieve (the target). References Terraform-created resources where relevant.
4. **Reconnaissance** (`## Reconnaissance`) -- walks through discovery steps using helpful permissions. Narrative tone: "First, let's figure out what we're working with..." Includes AWS CLI commands inline in code blocks.
5. **Exploitation** (`## Exploitation`) -- step-by-step walkthrough of the attack, matching demo_attack.sh flow. Explains the *why* behind each step, not just the *what*. Multi-hop scenarios use subsections for each hop (e.g., `### Hop 1: ...`).
6. **Verification** (`## Verification`) -- confirming the escalation worked. "Now let's verify we have admin access..."
7. **Capture the Flag** (`## Capture the Flag`) -- the final step, required on every non-tool-testing scenario. Retrieve the CTF flag from its terminal location using the credentials/access you gained in the previous steps. Show the exact AWS CLI command but NOT the flag value (the value is deployment-specific and comes from `flags.default.yaml` or a vendor override). For to-admin scenarios: `aws ssm get-parameter --name /pathfinding-labs/flags/<scenario-id> --query 'Parameter.Value' --output text`. For to-bucket scenarios: `aws s3 cp s3://<bucket>/flag.txt -`. 1-2 paragraphs explaining why these credentials grant flag access (admin has `ssm:GetParameter` implicitly via `AdministratorAccess`; bucket-access principal already has `s3:GetObject`).
8. **What Happened** (`## What Happened`) -- brief summary of the attack chain, connecting it back to real-world implications. 1-2 paragraphs.

**Tone:** Second person ("you"), narrative, educational. Like explaining the attack to a colleague over coffee. Not a dry list of commands -- a story with commands embedded in it.

**Source material:** Attack Overview prose + Attack Steps + "Executing the attack manually" content + demo_attack.sh commands and flow.

**Forbidden H2 headings** (these belong in README.md, never in solution.md): `## Prerequisites`, `## Setup`, `## Environment Setup`, `## Cleanup`, `## Teardown`, `## How to Run`, `## Running the Lab`, and any numbered step format (`## Step 1`, `## Step 2`, `## Step N:`, etc.).

**Required H2 headings** (exact text, in order): `## The Challenge`, `## Reconnaissance`, `## Exploitation`, `## Verification`, `## Capture the Flag`, `## What Happened`. Do not rename, reorder, or substitute numbered steps for these semantic sections.

---

## Old -> New Structure Migration Map (v2.0.1 -> v3.0.0)

Use this table when migrating READMEs from v2.0.1 to v3.0.0.

| Old heading / content | New heading / action |
|---|---|
| `## Attack Overview` (H2) | Prose moves to `solution.md` opening. Remove H2. |
| `### MITRE ATT&CK Mapping` (prose section) | Remove section. Data stays in metadata fields only. |
| `### Principals in the attack path` | Remove section. Data lives in `attack_map.yaml` nodes. |
| `### Attack Path Diagram` (mermaid) | Remove section. Frontend renders from `attack_map.yaml`. |
| `### Attack Steps` | Content moves to `solution.md`. Remove section. |
| `### Attack Map` (embedded YAML) | Extract YAML to `attack_map.yaml` file. Remove section. |
| `### Scenario specific resources created` | Move to `### Scenario Specific Resources Created` under `## Attack`. |
| `## Attack Lab` | Split into `## Self-hosted Lab Setup` + `## Attack`. |
| `### Prerequisites` | Move under `## Self-hosted Lab Setup`. |
| `### Deploy with plabs non-interactive` | Move under `## Self-hosted Lab Setup`. |
| `### Deploy with plabs tui` | Move under `## Self-hosted Lab Setup`. |
| `### Executing the automated demo_attack script` | Move under `### Automated Demo` -> `#### Executing the automated demo_attack script`. |
| `#### Resources created by attack script` | Rename to `#### Resources Created by Attack Script` under `### Automated Demo`. |
| `#### With plabs non-interactive` (demo) | Move under `### Automated Demo`. |
| `#### With plabs tui` (demo) | Move under `### Automated Demo`. |
| `### Executing the attack manually` | Content moves to `solution.md`. Remove section. |
| `### Cleanup` | Move under `## Attack`. |
| `### Teardown with plabs non-interactive` | Move under `## Teardown`. |
| `### Teardown with plabs tui` | Move under `## Teardown`. |
| `## Detecting Misconfiguration (CSPM)` | Becomes `### Detecting Misconfiguration (CSPM)` under `## Defend`. Sub-sections become H4. |
| `### What CSPM tools should detect` | Becomes `#### What CSPM tools should detect` under `### Detecting Misconfiguration (CSPM)`. |
| `### Prevention recommendations` | Becomes `#### Prevention Recommendations` under `### Detecting Misconfiguration (CSPM)`. |
| `## Detection Abuse (CloudSIEM)` | Becomes `### Detecting Abuse (CloudSIEM)` under `## Defend`. Sub-sections become H4. |
| `### CloudTrail events to monitor` | Becomes `#### CloudTrail Events to Monitor` under `### Detecting Abuse (CloudSIEM)`. |
| `### Detonation logs` | Becomes `#### Detonation logs` under `### Detecting Abuse (CloudSIEM)`. |
| `## References` | Stays as `## References` (no change). |
| Metadata: `Attack Path` | Remove line. |
| Metadata: `Attack Principals` | Remove line. |
| Metadata: `Required Permissions` | Remove line. Move data to `### Starting Permissions`. |
| Metadata: `Helpful Permissions` | Remove line. Move data to `### Starting Permissions`. |

**New sections to create during migration:**
- `## Objective` -- single sentence using the "Your objective is to learn how to exploit..." template (see Section Content Rules)
- `### Starting Permissions` -- build from removed metadata fields, using per-principal format from scenario.yaml
- `## Self-hosted Lab Setup` -- wrapper for existing Prerequisites/Deploy sections
- `## Attack` -- wrapper for resources, walkthrough, demo, cleanup
- `### Solution` -- link to new `solution.md` file
- `### Automated Demo` -- wrapper for existing demo sub-sections
- `## Teardown` -- wrapper for existing teardown sections
- `## Defend` -- wrapper for existing CSPM and CloudSIEM sections

**New companion files to create during migration:**
- `attack_map.yaml` -- extracted from `### Attack Map` embedded YAML
- `solution.md` -- synthesized from Attack Overview + Attack Steps + manual execution + demo_attack.sh

---

## Migration: v3.0.0 -> v4.0.0

**Change:** `### Starting Permissions` now groups both Required and Helpful permissions by principal name.

| Old format | New format |
|---|---|
| `**Required:**` (flat list) | `**Required** ({principal_name}):` (per-principal list) |
| `**Helpful:**` (flat list) | `**Helpful** ({principal_name}):` (per-principal list) |

**Migration steps:**
1. Read `scenario.yaml` `permissions.required` and `permissions.helpful` (now per-principal format)
2. For each principal entry, emit a `**Required** ({principal_name}):` or `**Helpful** ({principal_name}):` heading
3. List permissions under each heading
4. Stamp `Schema Version: 4.0.0`

For single-principal scenarios (most one-hop), the visual difference is small -- just the principal name added to the heading. For multi-hop scenarios, permissions are now properly separated by principal.

---

## Compliance Checklist

A README is compliant if all of the following are true:

- [ ] `* **Schema Version:** {version}` is present in the metadata block and matches the current schema version (`4.6.1`)
- [ ] H2 sections are exactly: `Objective`, `Self-hosted Lab Setup`, `Attack`, `Teardown`, `Defend` (plus optional `References`)
- [ ] No `## Attack Overview` H2 exists (moved to `solution.md`)
- [ ] No `## Attack Lab` H2 exists (split into `Self-hosted Lab Setup` + `Attack`)
- [ ] No `## Detecting Misconfiguration (CSPM)` H2 exists (now H3 under `Defend`)
- [ ] No `## Detection Abuse (CloudSIEM)` H2 exists (now H3 under `Defend`)
- [ ] No `### MITRE ATT&CK Mapping` section exists (data in metadata only)
- [ ] No `### Principals in the attack path` section exists (data in `attack_map.yaml`)
- [ ] No `### Attack Path Diagram` section exists (rendered from `attack_map.yaml`)
- [ ] No `### Attack Steps` section exists (moved to `solution.md`)
- [ ] No `### Attack Map` embedded YAML section exists (extracted to `attack_map.yaml`)
- [ ] No `### Executing the attack manually` section exists (moved to `solution.md`)
- [ ] Metadata does not contain `Attack Path`, `Attack Principals`, `Required Permissions`, or `Helpful Permissions` fields
- [ ] `## Objective` contains `### Starting Permissions` with per-principal Required and Helpful sub-lists. For IAM principals, the heading includes the principal name in parentheses. For anonymous/public starting points, the heading uses a descriptive label (e.g., `anonymous (public URL)`, `unauthenticated attacker`) and the `- **Start:**` line uses a URL or description rather than an ARN.
- [ ] `## Self-hosted Lab Setup` contains `### Prerequisites`, `### Deploy with plabs non-interactive`, `### Deploy with plabs tui`
- [ ] `### Solution` exists under `## Attack` with link to `solution.md`
- [ ] `### Automated Demo` contains `#### Executing the automated demo_attack script`, `#### Resources Created by Attack Script`, `#### With plabs non-interactive`, `#### With plabs tui` *(CTF scenarios: omit this entire section)*
- [ ] `### Cleanup` exists under `## Attack` with `#### With plabs non-interactive` and `#### With plabs tui` *(CTF scenarios: omit if no attack artifacts to clean)*
- [ ] `## Teardown` contains `### Teardown with plabs non-interactive` and `### Teardown with plabs tui`
- [ ] `## Defend` contains `### Detecting Misconfiguration (CSPM)` and `### Detecting Abuse (CloudSIEM)`
- [ ] `#### CloudTrail Events to Monitor` uses `` `service:EventName` `` format (lowercase service prefix, no space after colon, `--` separator — never an em dash)
- [ ] `#### Detonation logs` contains the standard placeholder text
- [ ] Companion `attack_map.yaml` file exists (validated separately per attackmap schema)
- [ ] Companion `solution.md` file exists with link from README
- [ ] *Non-tool-testing scenarios only*: metadata block contains `* **CTF Flag Location:** {ssm-parameter|s3-object}`
- [ ] *Non-tool-testing scenarios only*: `solution.md` contains a `## Capture the Flag` section that shows the retrieval command (not the value) for the scenario's flag terminal
