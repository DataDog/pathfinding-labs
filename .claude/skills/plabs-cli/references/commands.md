# plabs Command Reference

## Global Behavior

- `plabs` with no arguments launches the interactive TUI — **avoid in agent contexts**
- Most write commands (`enable`, `disable`, `deploy`, `destroy`) require `-y` to skip confirmation
- Commands load `~/.plabs/plabs.yaml` as the source of truth on every invocation

---

## plabs init

Initial setup: creates `~/.plabs/`, clones the repo, runs setup wizard, runs `terraform init`.

```bash
plabs init
```

Interactive — run only during setup, not in automated workflows. After init, use `plabs info`
to confirm the configuration.

---

## plabs info

Shows active configuration and path resolution.

```bash
plabs info
```

Useful for confirming dev mode paths, AWS profiles, and terraform binary location.

---

## plabs scenarios list

Lists all discovered scenarios with their current state.

```bash
plabs scenarios list [flags]
```

| Flag | Description |
|------|-------------|
| `--category <cat>` | Filter by category |
| `--target <target>` | Filter by target (`to-admin`, `to-bucket`) |
| `--enabled` | Show only enabled scenarios |
| `--deployed` | Show only deployed scenarios |
| `--demo-active` | Show only scenarios with an active demo |
| `--cost` | Include cost estimate column |
| `--wide` | Extra columns (subcategory, MITRE techniques, etc.) |
| `--mitre <id>` | Filter by MITRE ATT&CK technique ID |

---

## plabs scenarios show

Shows detailed metadata for a single scenario.

```bash
plabs scenarios show <id>
```

Displays: description, attack path principals, required permissions, MITRE mapping, cost, demo/cleanup availability.

---

## plabs enable

Enables one or more scenarios (updates config + regenerates tfvars).

```bash
plabs enable <id> [flags]
plabs enable "iam-*" [flags]       # glob pattern
```

| Flag | Description |
|------|-------------|
| `-y`, `--yes` | Skip confirmation prompt (required in agent context) |
| `--all` | Enable all available scenarios |
| `--category <cat>` | Enable all in category |
| `--target <target>` | Combined with --category to narrow scope |
| `--deploy` | Run `terraform apply` immediately after enabling |

---

## plabs disable

Disables one or more scenarios (updates config + regenerates tfvars). Does **not** destroy deployed infrastructure — run `plabs destroy` separately to remove AWS resources.

```bash
plabs disable <id> [flags]
plabs disable --all -y
```

| Flag | Description |
|------|-------------|
| `-y`, `--yes` | Skip confirmation |
| `--all` | Disable all enabled scenarios |

---

## plabs deploy / apply

Runs `terraform apply`. Validates AWS credentials, auto-downloads terraform if needed,
syncs tfvars, then applies.

```bash
plabs deploy [flags]
plabs apply [flags]          # alias
```

| Flag | Description |
|------|-------------|
| `-y`, `--auto-approve` | Skip plan confirmation |

For the attacker account in `iam-user` mode, the first deploy bootstraps an IAM admin user
and stores credentials in memory for the session (never written to disk unencrypted).

---

## plabs plan

Runs `terraform plan` without applying. Good for verifying what would change.

```bash
plabs plan
```

---

## plabs destroy

Destroys Terraform-managed resources.

```bash
plabs destroy [flags]
```

| Flag | Description |
|------|-------------|
| `-y`, `--auto-approve` | Skip confirmation |
| `--scenarios-only` | Only destroy scenario modules, not base environment |
| `--all` | Destroy everything including base infrastructure |

> Prefer `--scenarios-only` when you just want to clean up scenario resources while keeping
> the base environment (starting users, etc.) intact.

---

## plabs status

Shows deployment status for all enabled scenarios.

```bash
plabs status [--cost]
```

| Flag | Description |
|------|-------------|
| `--cost` | Show estimated monthly cost for deployed scenarios |

---

## plabs credentials

Prints the starting-user credentials for a deployed scenario (extracted from terraform outputs).

```bash
plabs credentials <id>
```

Output includes: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION.

---

## plabs demo

Runs the `demo_attack.sh` script for a deployed scenario.

```bash
plabs demo <id>
plabs demo --list            # list scenarios with available demos
```

The scenario must be enabled **and** deployed. Demo scripts are blocking — they run
step-by-step and show colored output. A `.demo_active` marker is created during execution.

---

## plabs cleanup

Runs the `cleanup_attack.sh` script to remove demo artifacts (not infrastructure).

```bash
plabs cleanup <id>
```

Use after `plabs demo` to restore the scenario to its pre-demo state (removes extra access keys,
restores modified policies, deletes the `.demo_active` marker).

---

## plabs config

Read and write configuration values.

```bash
plabs config list                              # show all config
plabs config get <key>                         # read a key (dot-separated path)
plabs config set <key> <value>                 # write a key
plabs config clear <key>                       # clear a key to empty
```

Common keys:
- `aws.prod.profile` — AWS profile for prod account
- `aws.prod.region` — Region for prod account
- `dev_mode` — `true`/`false`
- `dev_mode_path` — path to local repo (when dev_mode is true)

---

## plabs update

Pulls the latest pathfinding-labs repo from origin.

```bash
plabs update
```

---

## plabs version

Prints the plabs binary version.

```bash
plabs version
```
