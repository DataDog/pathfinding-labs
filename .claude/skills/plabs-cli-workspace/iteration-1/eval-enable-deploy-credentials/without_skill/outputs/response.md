# Step-by-Step Plan: Enable and Deploy iam-002 (createaccesskey one-hop to admin)

This plan covers enabling the `iam-002-to-admin` scenario, deploying it, and retrieving starting credentials. No AWS-affecting commands are run here — this is the exact command sequence you would execute.

---

## Prerequisites

- `plabs` binary built and available. If not, build it first:
  ```
  cd /Users/zander.mackie/go/src/github.com/DataDog/pathfinding-labs
  go build -o plabs ./cmd/plabs
  ```
- `plabs init` has already been run and your prod AWS profile is configured in `~/.plabs/plabs.yaml`.

---

## Step 1: Confirm the scenario exists and its ID

**Command:**
```
./plabs scenarios list --category=one-hop --target=admin
```

**Purpose:** Verify `iam-002-to-admin` appears in the list. The scenario's UniqueID is `iam-002-to-admin` (composed from the pathfinding-cloud-id `iam-002` plus the target suffix `to-admin`). You will see it listed under "Single Account > Privilege Escalation to Admin > One-Hop". The `○` (dim circle) indicator means it is currently disabled.

**What to look for:**
```
  ○ iam-002-to-admin       User with iam:CreateAccessKey can create credentials...
```

---

## Step 2: Enable the scenario

**Command:**
```
./plabs enable iam-002-to-admin
```

**Purpose:** This marks the `iam-002-to-admin` scenario as enabled in `~/.plabs/plabs.yaml` and syncs that change into the `terraform.tfvars` file in your working Terraform directory. Specifically, it sets:
```
enable_single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey = true
```

**Note on ambiguity:** Using `iam-002` (without the `-to-admin` suffix) would enable BOTH the to-admin AND the to-bucket variant of this scenario (since `iam-002` is also used for a to-bucket scenario). To target only the admin escalation path, use the full UniqueID `iam-002-to-admin`.

**Expected output:**
```
OK Enabled 1 scenario(s):
  * iam-002-to-admin - User with iam:CreateAccessKey can create credentials...

Run 'plabs deploy' to deploy the enabled scenarios
```

---

## Step 3: (Optional) Confirm the scenario is enabled but not yet deployed

**Command:**
```
./plabs status
```

**Purpose:** Shows the current state of all enabled scenarios. After step 2, `iam-002-to-admin` should appear with a `pending` status, meaning it is enabled in config but not yet deployed to AWS.

**Expected output:**
```
Scenario Status

--- Enabled Scenarios (1)

  * iam-002-to-admin        pending

---------------------------------------------------------
Total: 1 enabled | 0 deployed | 1 pending | Running cost: $0/mo

Run plabs deploy to deploy pending scenarios
```

---

## Step 4: Deploy the scenario

**Command:**
```
./plabs deploy
```

**Purpose:** Runs `terraform plan` followed by `terraform apply` to provision the AWS resources for `iam-002-to-admin` in your prod account. The deploy command:
1. Validates AWS credentials are accessible via your configured prod profile.
2. Detects existing service-linked roles (to avoid duplicate creation errors).
3. Syncs the `terraform.tfvars` from config.
4. Runs `terraform init` if not already initialized.
5. Runs `terraform plan` and shows you the diff.
6. Prompts you: `Do you want to apply these changes? [y/N]:`
7. On `y`, runs `terraform apply`.

**What gets created in AWS:**
- A starting IAM user (`pl-prod-iam-002-to-admin-starting-user`) with only `iam:CreateAccessKey` permission scoped to the target user.
- A target IAM admin user (`pl-prod-iam-002-to-admin-target-user`) with AdministratorAccess.
- Access keys for the starting user (stored in Terraform state/outputs).

**To skip the confirmation prompt:**
```
./plabs deploy --auto-approve
```
(or equivalently `./plabs deploy -y`)

**Expected output (after confirmation):**
```
Apply complete!

Run plabs status to see deployment status
Run plabs demo <scenario-id> to run a demo attack
```

---

## Step 5: Verify the scenario is deployed

**Command:**
```
./plabs status
```

**Purpose:** Confirm `iam-002-to-admin` now shows as `deployed` (green indicator).

**Expected output:**
```
  * iam-002-to-admin        deployed
```

---

## Step 6: Retrieve the starting credentials

**Command (default — environment variable export format):**
```
./plabs credentials iam-002-to-admin
```

**Purpose:** Reads the Terraform outputs for the `iam-002-to-admin` scenario and prints the starting user's AWS access key ID and secret access key. The default format is `env` (shell export statements).

**Expected output:**
```
export AWS_ACCESS_KEY_ID=AKIA...
export AWS_SECRET_ACCESS_KEY=...
```

**To load credentials directly into your shell:**
```
eval $(./plabs credentials iam-002-to-admin)
```

**Alternative formats:**

JSON format (useful for scripting):
```
./plabs credentials iam-002-to-admin --format=json
```
Output:
```json
{
  "access_key_id": "AKIA...",
  "secret_access_key": "..."
}
```

AWS credentials file format (useful for adding to `~/.aws/credentials`):
```
./plabs credentials iam-002-to-admin --format=profile
```
Output:
```
[iam-002-to-admin]
aws_access_key_id = AKIA...
aws_secret_access_key = ...
```

---

## Summary of Commands (in order)

```bash
# 1. Build binary (if not already done)
go build -o plabs ./cmd/plabs

# 2. Verify scenario is discoverable
./plabs scenarios list --category=one-hop --target=admin

# 3. Enable the scenario
./plabs enable iam-002-to-admin

# 4. Deploy to AWS (prompts for confirmation)
./plabs deploy

# 5. Verify it deployed
./plabs status

# 6. Get starting credentials
./plabs credentials iam-002-to-admin

# 6a. Or load them directly into your shell
eval $(./plabs credentials iam-002-to-admin)
```

---

## What the iam-002-to-admin scenario tests

Once you have the starting credentials loaded, you can manually exercise the attack path:

1. The starting user has only `iam:CreateAccessKey` scoped to `pl-prod-iam-002-to-admin-target-user`.
2. Call `aws iam create-access-key --user-name pl-prod-iam-002-to-admin-target-user` to create new credentials for the admin target user.
3. Switch to the newly created admin credentials.
4. Verify admin access with `aws sts get-caller-identity` and `aws iam list-users`.

This exercises MITRE ATT&CK technique T1098.001 (Account Manipulation: Additional Cloud Credentials).

---

## Cleanup

When finished testing, destroy the scenario resources:
```
./plabs disable iam-002-to-admin
./plabs deploy
```

Or to destroy everything:
```
./plabs destroy
```
