---
name: plabs-cli
description: >
  Guide for operating the `plabs` CLI to manage Pathfinding Labs AWS attack scenarios.
  Use this skill whenever you need to: list, enable, or disable scenarios; deploy or destroy
  infrastructure with Terraform; run or clean up attack demos; check deployment status; read
  scenario credentials; or configure the plabs environment. Trigger on any request involving
  plabs commands, pathfinding-labs scenarios, AWS attack path deployment, or demo execution.
  This skill is essential any time you're about to run a `plabs` command or reason about
  scenario state — use it proactively.
---

# plabs CLI Agent Guide

The `plabs` binary manages Pathfinding Labs AWS attack scenarios end-to-end: it wraps Terraform,
discovers scenario metadata, and runs demo scripts. Use this skill every time you interact with
`plabs` so you apply the right flags, avoid interactive prompts, and follow a safe workflow order.

## Quick Reference: Non-Interactive Flags

Agents must never trigger interactive prompts. Always include:

| Situation | Flag |
|-----------|------|
| `enable`, `disable` with confirmation | `-y` |
| `deploy`, `destroy` | `-y` or `--auto-approve` |
| Enabling then immediately deploying | `--deploy -y` on `enable` |

## Binary

```bash
# Build (required after any Go code change)
cd /Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs
go build -o plabs ./cmd/plabs

# Run without building
go run ./cmd/plabs <command>

# If plabs is in PATH
plabs <command>
```

> **Dev mode**: If `~/.plabs/plabs.yaml` has `dev_mode: true` and `dev_mode_path` set,
> `plabs` reads Terraform from the local repo instead of `~/.plabs/pathfinding-labs/`.
> Check `plabs info` to confirm the active working paths.

## Typical Agent Workflow

```bash
# 1. Understand current state
plabs status
plabs scenarios list --enabled

# 2. Find the right scenario
plabs scenarios list --category privilege-escalation --target to-admin
plabs scenarios show iam-002          # detailed info on a specific scenario

# 3. Enable (updates ~/.plabs/plabs.yaml + regenerates terraform.tfvars)
plabs enable iam-002 -y
# Or enable + deploy atomically:
plabs enable iam-002 -y --deploy

# 4. Deploy (if not done above)
plabs deploy -y

# 5. Verify
plabs status
plabs credentials iam-002             # show starting user credentials

# 6. Run demo
plabs demo iam-002

# 7. Cleanup demo artifacts (keeps infrastructure)
plabs cleanup iam-002

# 8. Teardown infrastructure when done
plabs destroy --scenarios-only -y     # only scenario modules, not base infra
# OR
plabs destroy --all -y                # everything including base infra
```

## Scenario IDs

- **Base ID**: `iam-002` — the `pathfinding-cloud-id` from `scenario.yaml`
- **Unique ID**: `iam-002-to-admin` — base ID + target suffix (use when a scenario has both `to-admin` and `to-bucket` variants)
- **Glob patterns**: `plabs enable "iam-*" -y` — shell-glob matching against base IDs

### Filtering Flags for `scenarios list` and `enable`

| Flag | Values / Example |
|------|-----------------|
| `--category` | `privilege-escalation`, `cspm-misconfig`, `cspm-toxic-combo`, `tool-testing` |
| `--target` | `to-admin`, `to-bucket` |
| `--enabled` | no value — shows only enabled scenarios |
| `--deployed` | no value — shows only deployed scenarios |
| `--demo-active` | no value — shows scenarios with a demo in progress |
| `--cost` | no value — adds cost column |
| `--wide` | no value — extra columns (subcategory, MITRE, etc.) |
| `--mitre` | e.g. `T1098.001` |

### Subcategory Values
`self-escalation`, `one-hop`, `multi-hop`, `cross-account`

## Four-State Scenario Status

When reading `plabs status` or `scenarios list`, each scenario is in one of four states:

| State | Meaning | Action needed |
|-------|---------|---------------|
| ● (green) | Enabled **and** deployed | Ready to demo |
| ● (yellow) | Enabled, **not yet** deployed | Run `plabs deploy -y` |
| ● (red) | Deployed but **disabled** | Run `plabs destroy --scenarios-only -y` or re-enable |
| ○ (dim) | Disabled and not deployed | Nothing required |

## Configuration

Config lives at `~/.plabs/plabs.yaml`. The config is the single source of truth —
`enable`/`disable` write to it, `deploy` generates `terraform.tfvars` from it.

```yaml
dev_mode: false
dev_mode_path: ""            # set to local repo path when dev_mode: true
aws:
  prod:
    profile: "prod-profile"
    region: "us-east-1"
  dev:
    profile: ""              # only needed for cross-account scenarios
    region: ""
  ops:
    profile: ""
    region: ""
  attacker:
    profile: ""
    mode: "profile"          # or "iam-user" for bootstrapped admin user
scenarios:
  enabled:
    - "iam-002"
    - "sts-001"
budget:
  enabled: false
initialized: true
```

Read/write individual keys:
```bash
plabs config list                              # show full config
plabs config get aws.prod.profile              # read a key
plabs config set aws.prod.profile my-profile   # write a key
```

## Demos

A demo runs `demo_attack.sh` from the scenario directory using credentials extracted from
Terraform outputs. The scenario must be **enabled and deployed** first.

```bash
plabs demo --list                # list scenarios with available demos
plabs demo iam-002               # run demo (blocks until complete)
plabs cleanup iam-002            # remove demo artifacts (NOT infra)
```

A `.demo_active` marker file is created during a running demo. `cleanup` removes it along with
any AWS resources created by the demo (e.g. extra access keys, modified policies).

## Reading Credentials

After deployment, starting-user credentials are in Terraform outputs. `plabs credentials`
surfaces them without you having to call `terraform output` directly:

```bash
plabs credentials iam-002        # prints access key ID, secret, region
```

Credentials are also embedded in the demo scripts automatically — you only need `plabs credentials`
when you want to run your own AWS CLI commands against a scenario's starting principal.

## Error & Recovery Patterns

| Symptom | Likely cause | Fix |
|---------|-------------|-----|
| `Error: terraform not initialized` | First run / stale state | `plabs init` |
| `Error: scenario not deployed` before demo | Forgot to deploy | `plabs deploy -y` |
| `Error: AWS credentials invalid` | Profile misconfigured | `plabs config set aws.prod.profile <name>` then re-validate with `plabs info` |
| Scenario stuck in red state (deployed but disabled) | Out-of-sync state | `plabs enable <id> -y` or `plabs destroy --scenarios-only -y` |
| `plabs: command not found` after code change | Stale binary | Rebuild: `go build -o plabs ./cmd/plabs` |

## Batch Operations

```bash
# Enable all CSPM misconfiguration scenarios
plabs enable --category cspm-misconfig -y

# Enable all privilege-escalation to-admin scenarios
plabs enable --category privilege-escalation --target to-admin -y

# Disable everything
plabs disable --all -y

# Deploy after bulk enable
plabs deploy -y
```

## More Detail

For full command and scenario reference, see:
- `references/commands.md` — complete flag reference for every command
- `references/scenarios.md` — full scenario taxonomy, naming conventions, directory layout
