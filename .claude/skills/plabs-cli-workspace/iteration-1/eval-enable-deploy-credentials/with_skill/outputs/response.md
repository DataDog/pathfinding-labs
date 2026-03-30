# Task: Enable and Deploy iam-002, Then Show Starting Credentials

**Task**: Enable the `iam-002` scenario (CreateAccessKey one-hop to admin), deploy it, and retrieve
the starting credentials for manual testing.

**Note**: This is a dry-run plan. No AWS-affecting commands have been executed.

---

## Step-by-Step Plan

### Step 1: Check Current State

```bash
plabs status
```

**Purpose**: Understand what is currently deployed and enabled before making changes.
This shows the four-state status (enabled+deployed, enabled-not-deployed, deployed-disabled,
disabled-not-deployed) for all scenarios. Helps avoid surprises during deployment.

---

### Step 2: Confirm the Scenario Exists and Review It

```bash
plabs scenarios show iam-002
```

**Purpose**: View the full metadata for `iam-002` before enabling it — confirms the correct
scenario ID, category (`privilege-escalation / one-hop / to-admin`), description, and any
prerequisite notes. This is especially useful when there are both `to-admin` and `to-bucket`
variants (use `iam-002-to-admin` as the unique ID if disambiguation is needed).

---

### Step 3: Enable the Scenario

```bash
plabs enable iam-002 -y
```

**Purpose**: Marks `iam-002` as enabled in `~/.plabs/plabs.yaml` and regenerates
`terraform.tfvars` to include the corresponding boolean flag:

```hcl
enable_single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey = true
```

**Flag explanation**:
- `iam-002` — the base scenario ID (pathfinding-cloud-id from `scenario.yaml`)
- `-y` — auto-confirms the "are you sure?" prompt so the command runs non-interactively

**Alternative (enable + deploy in one step)**:

```bash
plabs enable iam-002 -y --deploy
```

This is the atomic form: enable and immediately trigger a `terraform apply`. Use it when you
are confident and want to skip the separate deploy step.

---

### Step 4: Verify the Enable Took Effect

```bash
plabs scenarios list --enabled
```

**Purpose**: Confirms `iam-002` now appears in the enabled list (yellow dot = enabled but not
yet deployed) before running a potentially slow `terraform apply`.

---

### Step 5: Deploy the Infrastructure

```bash
plabs deploy -y
```

**Purpose**: Generates the final `terraform.tfvars` from the config, then runs
`terraform init` (if needed) and `terraform apply` against the working directory
(either `~/.plabs/pathfinding-labs/` in normal mode, or the local repo path in dev mode).

**Flag explanation**:
- `-y` / `--auto-approve` — passes `-auto-approve` to Terraform, skipping the interactive
  "Do you want to perform these actions?" prompt.

Terraform will create the IAM resources for `iam-002`:
- A starting IAM user (`pl-pathfinding-starting-user-prod` or scenario-specific user)
- The target admin IAM user (`pl-cak-admin` or similar)
- An IAM policy granting `iam:CreateAccessKey` on the target

**Expected duration**: 1–3 minutes for a single scenario.

---

### Step 6: Confirm Deployment

```bash
plabs status
```

**Purpose**: After `terraform apply` completes, this should now show `iam-002` as green
(enabled AND deployed). If it still shows yellow, the deploy may have failed — check the
Terraform output for errors.

---

### Step 7: Retrieve the Starting Credentials

```bash
plabs credentials iam-002
```

**Purpose**: Reads the Terraform outputs for the `iam-002` module and displays the starting
principal's credentials in a human-readable format. Output looks like:

```
Scenario: iam-002 (CreateAccessKey One-Hop to Admin)
─────────────────────────────────────────────────────
AWS_ACCESS_KEY_ID:     AKIA...XXXX
AWS_SECRET_ACCESS_KEY: wJal...XXXX
AWS_DEFAULT_REGION:    us-east-1

Starting principal: pl-pathfinding-starting-user-prod (IAM User)
Target:             pl-cak-admin (IAM User with AdministratorAccess)
Attack technique:   iam:CreateAccessKey on target user
```

**Under the hood**, this is equivalent to:

```bash
cd ~/.plabs/pathfinding-labs    # or dev_mode_path
terraform output -json \
  single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey
```

...but `plabs credentials` formats it cleanly and handles the sensitive-value flag for you.

---

## Using the Credentials Manually

Once you have the starting credentials from Step 7, export them in your shell:

```bash
export AWS_ACCESS_KEY_ID=AKIA...XXXX
export AWS_SECRET_ACCESS_KEY=wJal...XXXX
export AWS_DEFAULT_REGION=us-east-1
unset AWS_SESSION_TOKEN   # ensure no leftover session token
```

Then verify the starting identity:

```bash
aws sts get-caller-identity
```

You should see the starting IAM user, NOT an admin. From there you can manually execute the
`iam:CreateAccessKey` privilege escalation:

```bash
# Identify the target admin user
aws iam list-users

# Create a new access key for the admin user (the escalation step)
aws iam create-access-key --user-name pl-cak-admin

# Use the new admin credentials to verify escalation
export AWS_ACCESS_KEY_ID=<new-key-id>
export AWS_SECRET_ACCESS_KEY=<new-secret>
aws sts get-caller-identity    # should now show admin user
aws iam list-attached-user-policies --user-name pl-cak-admin  # should show AdministratorAccess
```

---

## Cleanup (When Done)

Remove demo artifacts (extra access keys created during the attack) without destroying infra:

```bash
plabs cleanup iam-002
```

Destroy the infrastructure entirely when finished:

```bash
plabs destroy --scenarios-only -y
```

Or destroy everything (scenarios + base infra):

```bash
plabs destroy --all -y
```

---

## Summary of Commands in Order

| # | Command | Purpose |
|---|---------|---------|
| 1 | `plabs status` | See current state |
| 2 | `plabs scenarios show iam-002` | Review scenario details |
| 3 | `plabs enable iam-002 -y` | Enable (write config + regenerate tfvars) |
| 4 | `plabs scenarios list --enabled` | Verify enable took effect |
| 5 | `plabs deploy -y` | Apply Terraform (creates AWS resources) |
| 6 | `plabs status` | Confirm green (deployed) state |
| 7 | `plabs credentials iam-002` | Retrieve starting credentials |

**Key non-interactive flag**: Always pass `-y` to `enable`, `disable`, `deploy`, and `destroy`
to avoid interactive confirmation prompts when running as an agent.
