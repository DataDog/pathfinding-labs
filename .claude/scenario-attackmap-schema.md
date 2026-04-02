# Pathfinding Labs Attack Map Schema

**Current schema version: `1.0.0`**

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
| `subType` | Yes | `iam-user`, `iam-role`, `iam-group`, `apprunner-service`, `lambda-function`, `ec2-instance`, `ecs-task`, `s3-bucket`, `glue-job`, `codebuild-project`, `cloudformation-stack`, `sagemaker-notebook`, `ssm-document`, `bedrock-agent`, etc. |
| `isTarget` | No (default `false`) | Boolean. Exactly one node per map must have `isTarget: true` -- the final destination of the attack path. |
| `arn` | Yes | Full ARN with `{account_id}` and `{region}` placeholders |
| `description` | Yes | Second-person narrative. Starting node MUST begin with the standard prologue paragraph (see below). |

### Node Types

| type | When to use | Map visual |
|------|-------------|------------|
| `principal` | IAM user or role the attacker controls/traverses | Large island |
| `resource` | AWS resource used as a stepping stone (Lambda, App Runner, EC2, etc.) | Small island |

The `isTarget` flag marks the final destination node (admin role/user, S3 bucket, etc.) and controls distinct color/style rendering. Exactly one node per map must have `isTarget: true`.

### Standard Starting Node Prologue

Every starting node's `description` MUST begin with exactly:

> You have gained access to this principal's AWS IAM credentials. These could have been obtained through many real-world vectors: phishing a developer and gaining access to their workstation, compromising a browser session, exploiting a vulnerable workload running in this AWS account, discovering credentials in a public S3 bucket, or finding them hardcoded in source code or a CI/CD pipeline.
>
> Regardless of how you obtained them, you are now operating as this principal.

Followed by scenario-specific details about what permissions this principal has.

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

### Target Node Identity

The target node must represent the real infrastructure resource that grants the escalated access -- NOT the starting principal relabeled after exploitation. For PassRole + compute scenarios, the target is the admin role passed to the service. For direct assumption, the target is the admin role. For to-bucket scenarios, the target is the S3 bucket.

### No Duplicate ARNs

Each node must have a unique ARN. Two nodes with the same ARN means one is a "phantom" representing a state change (e.g., "starting user after gaining admin") rather than a distinct resource. Phantom nodes must be removed:

1. Read `scenario.yaml` -> `attack_path.principals` to find the real target ARN (typically the last principal that is not the starting user).
2. Find the node whose ARN matches the real target. Set `isTarget: true` on that node.
3. Remove the phantom node (duplicate ARN, usually labeled "Admin Access" or similar).
4. Remove or redirect any edge pointing to the phantom node. If the phantom's incoming edge carries commands, move them to the real target node's incoming edge. If the edge is a "verification" step (e.g., `iam:ListUsers`), append those commands to the previous edge's `commands` array.
5. The attack map should end at the real target node -- no further edges after it.

---

## Complete Example (one-hop to-admin)

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

    - id: target-user
      label: "Admin User"
      type: principal
      subType: iam-user
      isTarget: true
      arn: "arn:aws:iam::{account_id}:user/pl-prod-example-admin-user"
      description: >
        This IAM user has AdministratorAccess. By creating access keys for this user,
        you now have the ability to operate as an administrator in this AWS account.

  edges:
    - from: starting-principal
      to: target-user
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
```

---

## Compliance Checklist

An `attack_map.yaml` is compliant if all of the following are true:

- [ ] File exists at `{scenario_directory}/attack_map.yaml`
- [ ] Contains a single top-level `attackMap` key
- [ ] All nodes have required fields: `id`, `label`, `type`, `subType`, `arn`, `description`
- [ ] Node `type` is `principal` or `resource` only
- [ ] Exactly one node has `isTarget: true`
- [ ] Starting node description begins with the standard prologue paragraph
- [ ] All edges have required fields: `from`, `to`, `label`, `description`, `commands`, `hints`
- [ ] All edge `hints` arrays have 3-7 entries
- [ ] Hints are ordered by order of operations first, then vague to specific
- [ ] Hints do not reveal exact commands
- [ ] Hints include a pathfinding.cloud link where a path ID is relevant
- [ ] No duplicate ARNs across nodes (no phantom nodes)
- [ ] Target node represents the real infrastructure target, not the starting principal relabeled
- [ ] Self-escalation scenarios use a self-loop edge (`from` and `to` are the same node)
- [ ] Valid YAML that parses without errors
