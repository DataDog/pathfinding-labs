# Pathfinding Labs Attack Map Schema

**Current schema version: `1.4.0`**

See `.claude/scenario-attackmap-changelog.md` for version history and migration rules.

This file is the canonical reference for the structure and content of all scenario `attack_map.yaml` files. Both the `scenario-readme-creator` and `scenario-readme-migrator` agents read this file when creating or extracting attack maps. Update this file when the standard changes.

Each scenario directory contains an `attack_map.yaml` file that defines the structured attack graph data used by the pathfinding.cloud frontend to render interactive attack maps in both CTF mode (progressive hints) and Walkthrough mode (full guide).

---

## File Format and Location

- **Filename**: `attack_map.yaml`
- **Location**: Same directory as the scenario's `README.md`, `main.tf`, and `demo_attack.sh`
- **Format**: Standard YAML with a single top-level `attackMap` key
- **Encoding**: UTF-8, no BOM

---

## Top-Level Structure

```yaml
attackMap:
  nodes:
    - {node object}
    - {node object}
  edges:
    - {edge object}
    - {edge object}
```

---

## Node Schema

| Field | Required | Description |
|-------|----------|-------------|
| `id` | Yes | Unique identifier within this attack map (e.g., `starting-principal`, `target-role`) |
| `label` | Yes | Short display label (2-4 words) |
| `type` | Yes | `principal` or `resource` |
| `subType` | Yes | `iam-user`, `iam-role`, `iam-group`, `apprunner-service`, `lambda-function`, `ec2-instance`, `ecs-task`, `s3-bucket`, `glue-job`, `codebuild-project`, `cloudformation-stack`, `sagemaker-notebook`, `ssm-document`, `ssm-parameter`, `bedrock-agent`, etc. |
| `isTarget` | No (default `false`) | Boolean. Exactly one node per map must have `isTarget: true` -- the final destination of the attack path (typically the CTF flag resource). Mutually exclusive with `isAttackerControlled` and with `isAdmin`. |
| `isAttackerControlled` | No (default `false`) | Boolean. Set to `true` on nodes representing infrastructure the attacker owns or controls (e.g., a script-hosting bucket, an exfil destination, a C2 endpoint). These nodes are NOT victim misconfigurations. A node cannot be both `isTarget` and `isAttackerControlled`. |
| `isAdmin` | No (default `false`) | Boolean. Set to `true` on `type: principal` nodes that hold administrator-equivalent permissions in their account (e.g., `AdministratorAccess` managed policy, wildcard inline policy). The frontend uses this to render admin-equivalent pivots distinctly. Mutually exclusive with `isTarget: true` on the same node — once flag resources became the canonical terminal, admin principals are pivots, not targets. Not mutually exclusive with `isAttackerControlled`. |
| `arn` | Yes | Full ARN with `{account_id}` and `{region}` placeholders |
| `access` | No (required on entry-point nodes) | Structured entry point for frontend display. Present only on nodes that represent a reachable starting point (public or internal network, or pre-given credentials). See Access Object below. |
| `description` | Yes | Second-person narrative. Starting node MUST begin with the standard prologue paragraph (see below). |

### Node Types

| type | When to use | Map visual |
|------|-------------|------------|
| `principal` | IAM user or role the attacker controls/traverses | Large island |
| `resource` | AWS resource used as a stepping stone (Lambda, App Runner, EC2, etc.) | Small island |

The `isTarget` flag marks the final destination node (CTF flag resource — usually an SSM parameter for to-admin or an S3 bucket holding a flag object for to-bucket) and controls distinct color/style rendering. Exactly one node per map must have `isTarget: true`. See the "CTF Flag Terminal Pattern" section below for the canonical shape of flag terminals.

The `isAttackerControlled` flag marks nodes that represent infrastructure the attacker owns — resources deployed in an attacker-controlled AWS account or otherwise part of the attacker's tooling rather than the victim environment. Examples: an S3 bucket hosting a malicious script, an exfil destination bucket, a C2 endpoint. These nodes participate in the attack path but are NOT victim misconfigurations. `isTarget` and `isAttackerControlled` are mutually exclusive.

The `isAdmin` flag marks principal nodes (`type: principal`) that hold administrator-equivalent permissions in their account. In to-admin scenarios, the admin role is a *pivot* that reaches the flag — not the terminal itself — so it takes `isAdmin: true` rather than `isTarget: true`. In multi-hop to-bucket scenarios where the chain passes through an admin principal on the way to the bucket, that intermediate principal also takes `isAdmin: true`. The frontend uses this flag to visually distinguish admin-equivalent pivots from scoped intermediate principals. `isAdmin` and `isTarget` are mutually exclusive on the same node.

### Access Object

The `access` field is an optional object present only on nodes that serve as the entry point for the attack. It gives the frontend a machine-readable address to display alongside the node — something the attacker can actually reach, not just an ARN.

```yaml
access:
  type: public-network      # required — see enum below
  url: "https://{function_url_id}.lambda-url.{region}.on.aws/"
  # OR ip: "{public_ip}"
  # OR domain: "{cloudfront_domain}"
```

| Sub-field | Required | Description |
|-----------|----------|-------------|
| `type` | Yes | Enum — see below |
| `url` | Conditional | Full HTTPS URL. Use for Lambda Function URLs, API Gateway, App Runner, or any HTTP/S endpoint. |
| `ip` | Conditional | Public IP address. Use for EC2 instances without a load balancer or CDN in front. |
| `domain` | Conditional | DNS hostname without a scheme or path. Use for CloudFront distributions, ALBs, or other DNS-named endpoints that are not themselves full URLs. |

**`type` enum:**

| Value | Meaning |
|-------|---------|
| `public-network` | Resource is reachable from the open internet. No prior access required. |
| `assumed-breach-network` | Resource is reachable from inside a specific network boundary (VPC, corporate LAN). Attacker is assumed to have network presence. |
| `assumed-breach-credentials` | Attacker already holds IAM credentials for this principal. No network traversal is modeled. |

**Rules:**
- Exactly one of `url`, `ip`, or `domain` must be present when `type` is `public-network` or `assumed-breach-network`.
- All three endpoint sub-fields are optional when `type` is `assumed-breach-credentials` (the credentials are the entry point).
- All values use the same `{placeholder}` convention used in `arn` fields.
- Place `access` after `arn` and before `description` in the node object.

---

### Standard Starting Node Prologue

**For IAM principal starting nodes** (attacker has credentials), the `description` MUST begin with exactly:

> You have gained access to this principal's AWS IAM credentials. These could have been obtained through many real-world vectors: phishing a developer and gaining access to their workstation, compromising a browser session, exploiting a vulnerable workload running in this AWS account, discovering credentials in a public S3 bucket, or finding them hardcoded in source code or a CI/CD pipeline.
>
> Regardless of how you obtained them, you are now operating as this principal.

Followed by scenario-specific details about what permissions this principal has.

**For public/anonymous starting nodes** (no AWS credentials required), the `description` MUST begin with exactly:

> This resource is publicly accessible without AWS credentials. Any attacker on the internet can reach it directly -- no IAM credentials, no AWS signature, no prior access required. This is your entry point.

Followed by scenario-specific details about what the resource does, why it is vulnerable, and any optional IAM recon steps that can help discover it (e.g., `lambda:ListFunctions` if a low-privilege user is available).

**Which prologue to use:** Check `scenario.yaml` → `permissions.required`. If the first entry has `principal_type: "public"`, use the public prologue. Otherwise, use the IAM prologue.

---

## Edge Schema

| Field | Required | Description |
|-------|----------|-------------|
| `from` | Yes | Source node `id` |
| `to` | Yes | Destination node `id` |
| `label` | Yes | Short label -- typically the AWS permission(s) used |
| `description` | Yes | What this transition does |
| `commands` | Yes | Array of `{description, command}` objects -- the AWS CLI commands from demo_attack.sh. May be empty (`[]`) for implicit edges like instance profiles. |
| `hints` | Yes | Ordered array of progressive hints guiding the attacker toward completing this edge. See Hints Design Principles below. |

---

## Hints Design Principles

Hints are the core of the CTF experience. They guide the attacker through each edge without giving away the answer. The frontend reveals them one at a time.

### Ordering Rules

1. **Primary ordering: order of operations** -- hints follow the sequence you'd need them to complete the edge. If step A must happen before step B, the hint for A comes first.
2. **Secondary ordering: vague to specific** -- within a given operational step, hints progress from a general nudge to a more specific pointer.

### Quantity Rules

- **Minimum**: 3 hints per edge
- **Maximum**: 7 hints per edge

### Content Rules

- Hints should NOT reveal exact commands (that's what the `commands` array is for)
- Focus on using helpful permissions for reconnaissance -- guide the attacker to discover what they need
- Derived from demo_attack.sh steps and real attacker workflow
- Whenever a pathfinding.cloud path ID is relevant to the edge's technique, include a link to `https://pathfinding.cloud/paths/{path-id}` as a hint (typically the last or second-to-last hint)
- Hints should read as advice from a mentor, not as documentation

### Example (ssm-001, edge starting-principal to ec2-instance)

```yaml
hints:
  - "With this permission, you can start an SSM session (like an SSH session) with whatever instances are listed in the resources section."
  - "Use the aws ec2 describe-instances command to list the running instances, making sure to look at all regions."
  - "Review the policy attached to this starting principal to see which instances they have this permission on."
  - "Check SSM agent status with ssm:DescribeInstanceInformation to confirm the target is SSM-managed."
  - "You will need to install the AWS SSM Session Manager plugin for your local AWS CLI for the start-session command to work locally."
```

### Example (iam-002, edge starting-principal to target-user)

```yaml
hints:
  - "You can create credentials for other IAM users."
  - "Look at the policy attached to this principal -- which users can you create access keys for?"
  - "Use iam:ListUsers or iam:GetUser to discover which users exist and what policies they have."
  - "Look for users with elevated permissions like AdministratorAccess."
  - "Browse to https://pathfinding.cloud/paths/iam-002 for technique details."
```

---

## Pattern Rules

### Self-Escalation Self-Loop

Self-escalation scenarios use a self-loop edge where `from` and `to` are the same node. The starting role is both the actor and the target (`isTarget: true`). Example: a role with `iam:PutRolePolicy` modifies its own policy. The map has 2 nodes (starting user + starting role) and 2 edges (assume role + self-loop).

### Multi-Hop Pattern

Intermediate principals get `type: principal`. Resources used as stepping stones get `type: resource`. The final destination gets `isTarget: true`.

### CSPM Scenario Pattern

Simpler maps with fewer/no commands (focus on detection, not exploitation). The `commands` array may be empty. Hints still guide understanding of the misconfiguration.

### Public/Anonymous Entry Point Pattern

For CTF, CSPM Toxic Combo, and CSPM Misconfig scenarios where the attack starts from unauthenticated public access:

- **The publicly accessible resource itself is the starting node** -- do NOT add a separate "public internet" or IAM recon user node before it
- The starting node uses `type: resource` with the appropriate `subType` (e.g., `lambda-function`, `s3-bucket`)
- The starting node description uses the public access prologue (not the IAM prologue)
- The `arn` field holds the real AWS ARN of the public resource -- do NOT use fabricated ARNs like `arn:aws:sts::{account_id}:assumed-role/unauthenticated/attacker`
- **The starting node MUST have an `access` field** with `type: public-network` and exactly one of `url`, `ip`, or `domain` set to the network address where the resource is reachable. Use `{placeholder}` syntax for values that are only known after deployment (e.g., `{function_url_id}`, `{public_ip}`).
- Optional IAM recon (e.g., using `lambda:ListFunctions` to discover the resource) is mentioned in the starting node description or first edge description, not modeled as a separate graph node
- The first edge represents the actual attack on the public resource (e.g., HTTP invocation, prompt injection), not an IAM permission use

### CTF Scenario Pattern

CTF scenarios use the same YAML structure as privesc scenarios but apply different content rules to preserve the challenge. The frontend renders attack maps in two modes: **CTF mode** (hints only, progressive disclosure) and **Walkthrough mode** (commands shown). The rules below ensure CTF mode doesn't hand players the answer while still making Walkthrough mode useful after the challenge is complete.

**Node descriptions:**
- Describe what the resource *is* (type, function, role in the architecture) without listing its IAM permissions or revealing its relationship to the attack path.
- Let the player discover permissions through enumeration (e.g., `iam:ListAttachedRolePolicies`, `lambda:ListFunctions`). A description like "The Lambda execution role for AcmeBot" is appropriate; "The Lambda execution role -- it has `lambda:UpdateFunctionCode` on the data processor" gives away the pivot.
- The target node description should indicate that credentials for this role are the objective, without revealing what policies it holds or where the flag is stored.

**Edge labels:**
- Use descriptive action phrases, not AWS permission names. Use `"Prompt injection"` not `"prompt injection → run_command"`. Use `"Code replacement"` not `"lambda:UpdateFunctionCode"`. Use `"Privileged invocation"` not `"lambda:InvokeFunction → extract credentials"`.
- Exception: the label may name a permission when that permission is already obvious from the node types (e.g., an `sts:AssumeRole` edge between two IAM roles).

**Hints:**
- Guide the player toward *discovering* the technique rather than naming it. Instead of "You have `lambda:UpdateFunctionCode` on the data processor function", write "Find a Lambda whose role suggests elevated privileges -- then consider what write access to a function's code actually gives you."
- Do not reveal exact shell commands, exact resource names, or exact IAM permission names.
- Do not reveal the SSM parameter path, S3 key, or other specific location of the flag. Guide toward the service category instead: "consider what AWS service is commonly used to securely store secrets and configuration values."
- The final hint(s) may be more specific but should still require the player to figure out the exact invocation.

**Commands:**
- Commands are shown only in Walkthrough mode, so they may be complete and exact.
- For resource names the player must discover through enumeration (function names, role names, bucket names), use `<placeholder>` syntax rather than hardcoding the real value. This signals that the player must enumerate to find the value rather than treating the command as a copy-paste answer.
- Conceptual steps (e.g., "write a handler that reads environment variables") should be expressed as a comment (`# ...`) rather than providing complete working code.

**Contrast with privesc scenarios:**
Privesc scenarios are educational and guided -- they name permissions explicitly, show exact commands, and walk the player step by step. CTF scenarios are challenges -- they point in the right direction without spelling out the path. Apply these rules only to scenarios in the `ctf/` directory.

### Attacker-Controlled Infrastructure Pattern

Some scenarios include nodes representing infrastructure the attacker owns — a bucket hosting a malicious script, an exfil destination, a C2 endpoint. These are attacker tooling, not victim misconfigurations.

Rules for these nodes:
- Set `isAttackerControlled: true` on the node. Do NOT set `isTarget: true`.
- The node's description must make clear this is attacker-owned infrastructure, not a victim misconfiguration.
- `isTarget: true` always stays on the victim side — the data or access the attacker is trying to reach.
- Edge hints involving attacker-controlled nodes should frame them as attacker tradecraft, not as a vulnerability in the victim environment.

### CTF Flag Terminal Pattern

Every scenario (except those under `tool-testing/`) ends with a CTF flag that the attacker must retrieve. The flag is the `isTarget: true` node.

**to-admin scenarios:**
- Add a new node representing the flag SSM parameter:
  - `type: resource`
  - `subType: ssm-parameter`
  - `arn: "arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/{scenario-id}"`
  - `isTarget: true`
  - Description: explains this is the CTF flag and how the compromised admin principal reads it. Does NOT reveal the flag value.
- The admin principal (`iam-role` or `iam-user` that holds `AdministratorAccess` or equivalent) takes `isAdmin: true` instead of `isTarget: true`.
- Add a final edge from the admin principal to the SSM parameter node, labeled "Read CTF flag" (or similar). The edge's `commands` array includes an `aws ssm get-parameter --name /pathfinding-labs/flags/{scenario-id}` command.

**to-bucket scenarios:**
- The existing target bucket keeps `isTarget: true` — it is still the terminal resource. No new node is added.
- The flag lives inside the bucket as `flag.txt`. The final edge's `commands` array gains a `aws s3 cp s3://{bucket}/flag.txt -` entry to retrieve it.
- Any mid-chain principal nodes that reach administrator-equivalent permissions before arriving at the bucket take `isAdmin: true`.

**Tool-testing scenarios:** exempt from the flag terminal pattern. These scenarios exist for detection-engine testing, not CTF gameplay; their attack maps follow pre-1.4.0 rules (admin role may take `isTarget: true`).

### Target Node Identity

The target node must represent the CTF flag resource (SSM parameter or S3 bucket holding `flag.txt`), NOT the pivot principal that reached admin, NOT the starting principal relabeled after exploitation. For to-admin scenarios, the target is the SSM parameter terminal; the admin principal it pivoted through takes `isAdmin: true`. For to-bucket scenarios, the target is the S3 bucket.

### No Duplicate ARNs

Each node must have a unique ARN. Two nodes with the same ARN means one is a "phantom" representing a state change (e.g., "starting user after gaining admin") rather than a distinct resource. Phantom nodes must be removed:

1. Read `scenario.yaml` -> `attack_path.principals` to find the real target ARN (typically the last principal that is not the starting user).
2. Find the node whose ARN matches the real target. Set `isTarget: true` on that node.
3. Remove the phantom node (duplicate ARN, usually labeled "Admin Access" or similar).
4. Remove or redirect any edge pointing to the phantom node. If the phantom's incoming edge carries commands, move them to the real target node's incoming edge. If the edge is a "verification" step (e.g., `iam:ListUsers`), append those commands to the previous edge's `commands` array.
5. The attack map should end at the real target node -- no further edges after it.

---

## Complete Example (one-hop to-admin with CTF flag terminal)

```yaml
attackMap:
  nodes:
    - id: starting-principal
      label: "Starting User"
      type: principal
      subType: iam-user
      arn: "arn:aws:iam::{account_id}:user/pl-prod-example-starting-user"
      description: >
        You have gained access to this principal's AWS IAM credentials. These could
        have been obtained through many real-world vectors: phishing a developer and
        gaining access to their workstation, compromising a browser session, exploiting
        a vulnerable workload running in this AWS account, discovering credentials in
        a public S3 bucket, or finding them hardcoded in source code or a CI/CD pipeline.

        Regardless of how you obtained them, you are now operating as this principal.
        This IAM user has iam:CreateAccessKey permission on the target admin user.

    - id: admin-user
      label: "Admin User"
      type: principal
      subType: iam-user
      isAdmin: true
      arn: "arn:aws:iam::{account_id}:user/pl-prod-example-admin-user"
      description: >
        This IAM user has AdministratorAccess. By creating access keys for this user,
        you gain the ability to operate as an administrator in this AWS account — including
        the ability to read the CTF flag from SSM Parameter Store.

    - id: ctf-flag
      label: "CTF Flag"
      type: resource
      subType: ssm-parameter
      isTarget: true
      arn: "arn:aws:ssm:{region}:{account_id}:parameter/pathfinding-labs/flags/iam-002-to-admin"
      description: >
        The CTF flag for this scenario, stored as an SSM parameter. Retrieving it requires
        administrator-equivalent permissions in this account. Your goal is to read this
        parameter's value using the credentials you gained from the admin pivot.

  edges:
    - from: starting-principal
      to: admin-user
      label: "iam:CreateAccessKey"
      description: >
        Create a new set of access keys for the admin user, gaining full
        administrative access to the AWS account.
      hints:
        - "You can create credentials for other IAM users."
        - "Look at the policy attached to this principal -- which users can you create access keys for?"
        - "Use iam:ListUsers or iam:GetUser to discover which users exist and what policies they have."
        - "Look for users with elevated permissions like AdministratorAccess."
        - "Browse to https://pathfinding.cloud/paths/iam-002 for technique details."
      commands:
        - description: "Create access keys for the admin user"
          command: "aws iam create-access-key --user-name pl-prod-example-admin-user"
        - description: "Verify admin access"
          command: "aws iam list-users --max-items 1"

    - from: admin-user
      to: ctf-flag
      label: "Read CTF flag"
      description: >
        Using the admin credentials from the previous step, read the flag from SSM
        Parameter Store. Administrator permissions grant ssm:GetParameter on all
        parameters in the account.
      hints:
        - "You now hold admin-equivalent credentials. The flag is stored in a well-known AWS service for configuration and secrets."
        - "Consider the SSM Parameter Store hierarchy — scenario flags live under a common prefix."
        - "Use ssm:GetParameter with the scenario-specific parameter name to retrieve the flag."
      commands:
        - description: "Retrieve the CTF flag"
          command: "aws ssm get-parameter --name /pathfinding-labs/flags/iam-002-to-admin --query 'Parameter.Value' --output text"
```

---

## Compliance Checklist

An `attack_map.yaml` is compliant if all of the following are true:

- [ ] File exists at `{scenario_directory}/attack_map.yaml`
- [ ] Contains a single top-level `attackMap` key
- [ ] All nodes have required fields: `id`, `label`, `type`, `subType`, `arn`, `description`
- [ ] Node `type` is `principal` or `resource` only
- [ ] Exactly one node has `isTarget: true`
- [ ] No node has both `isTarget: true` and `isAttackerControlled: true`
- [ ] No node has both `isTarget: true` and `isAdmin: true`
- [ ] `isAttackerControlled: true` is set on any node representing attacker-owned infrastructure (e.g., script-hosting bucket, exfil destination, C2 endpoint); these nodes describe attacker tooling, not victim misconfigurations
- [ ] `isAdmin: true` is set on any `type: principal` node that holds administrator-equivalent permissions (scenarios outside `tool-testing/`)
- [ ] **Non-tool-testing scenarios only**: the `isTarget: true` node is a CTF flag resource — either an `ssm-parameter` node (to-admin) or an `s3-bucket` node containing `flag.txt` (to-bucket); the final edge's `commands` array retrieves the flag
- [ ] Starting node description begins with the standard IAM credentials prologue (for IAM principal starting nodes) OR the standard public access prologue (for publicly accessible resource starting nodes -- `principal_type: "public"` in scenario.yaml)
- [ ] Nodes using the public access prologue have an `access` field with `type: public-network` and exactly one of `url`, `ip`, or `domain`
- [ ] All edges have required fields: `from`, `to`, `label`, `description`, `commands`, `hints`
- [ ] All edge `hints` arrays have 3-7 entries
- [ ] Hints are ordered by order of operations first, then vague to specific
- [ ] Hints do not reveal exact commands
- [ ] Hints include a pathfinding.cloud link where a path ID is relevant
- [ ] No duplicate ARNs across nodes (no phantom nodes)
- [ ] Target node represents the real infrastructure target, not the starting principal relabeled
- [ ] Self-escalation scenarios use a self-loop edge (`from` and `to` are the same node)
- [ ] **CTF scenarios only**: Node descriptions do not list IAM permissions or reveal the attack path; edge labels use descriptive phrases, not permission names; hints guide toward discovery without naming exact permissions, commands, resource names, or flag location; commands use `<placeholder>` syntax for enumerated resource names
- [ ] Valid YAML that parses without errors
