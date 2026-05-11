<div align="center">

<img width="3800" height="1930" alt="pathfinding-labs-3800x1930 (2)" src="https://github.com/user-attachments/assets/873fe49a-3646-4319-9e8b-6848ec8bafcd" />


**A modular platform for deploying intentionally vulnerable AWS configurations**

![Labs](https://img.shields.io/badge/Labs-100%2B-blue?style=for-the-badge)

[Quick Start](#quick-start) • [Lab Catalog](https://pathfinding.cloud/labs) • [How It Works](#how-it-works) • [Security](#what-gets-deployed) • [Contributing](#contributing)

</div>

---

Pathfinding Labs helps security teams learn how to atttack and defend exploitable identity misconfigurations by deploying intentionally vulnerable cloud resources to sandbox environments.

> **Full lab catalog, individual lab docs, and guided installation:** [pathfinding.cloud/labs](https://pathfinding.cloud/labs)
> This README is a quick-start guide and command reference for users working directly from the repository.

<img width="1440" height="1174" alt="pathfinding-labs-overview (1)" src="https://github.com/user-attachments/assets/41b74df4-c1a5-440d-aec1-d09ea0f57bec" />



## What types of labs are supported?

<img width="1280" height="1284" alt="pathfinding-lab-types (2)" src="https://github.com/user-attachments/assets/34bc2fdc-ed15-4135-bc21-9712f32c91e2" />



## Quick Start

### Prerequisites
- One or more AWS accounts (playground/sandbox accounts recommended)
- AWS CLI configured with appropriate profiles

### Install plabs

##### Direct Install
Requires Go 1.25+
```
go install -v github.com/DataDog/pathfinding-labs/cmd/plabs@latest
```

##### Homebrew 
```bash
brew tap DataDog/pathfinding-labs https://github.com/DataDog/pathfinding-labs
brew install DataDog/pathfinding-labs/plabs
```
#### Download from GitHub Releases
```bash
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m | sed 's/x86_64/amd64/')
VERSION=$(curl -fsSL https://api.github.com/repos/DataDog/pathfinding-labs/releases/latest | grep '"tag_name"' | cut -d'"' -f4 | tr -d 'v')
curl -fsSL "https://github.com/DataDog/pathfinding-labs/releases/download/v${VERSION}/plabs_${VERSION}_${OS}_${ARCH}.tar.gz" | tar -xz plabs
sudo mv plabs /usr/local/bin/
```

#### Build from source
```
git clone https://github.com/DataDog/pathfinding-labs.git
cd pathfinding-labs
go build -o plabs ./cmd/plabs
cp plabs /usr/local/bin/
chmod +x /usr/local/bin/plabs
```

### Setup

#### Initialize: 
Downloads terraform, clones repo, runs AWS profile setup wizard
```bash
plabs init
```
#### Open the TUI dashboard
```
plabs
```

<img width="1559" height="987" alt="plabs" src="https://github.com/user-attachments/assets/76a9f5d4-70fa-4645-a61b-e8a7ed4cc2dd" />


**In the TUI: use ↑↓ to browse labs, space to enable/disable labs, a to apply changes (deploy the enabled labs, tear down the disabled labs)**



# How It Works

**Modular Architecture**: Each attack lab is a self-contained, independently deployable module that can be enabled or disabled via `plabs`.

```
┌─────────────────────────────────────────────────────────┐
│  1. Select labs      (plabs TUI or plabs enable)        │
│     space to toggle in TUI, or: plabs enable <id>       │
├─────────────────────────────────────────────────────────┤
│  2. Deploy                (plabs apply)                 │
│     Creates vulnerable resources in your AWS account    │
├─────────────────────────────────────────────────────────┤
│  3. Test                  (plabs demo <id>)             │
│     Exploit OR detect with your CSPM                    │
├─────────────────────────────────────────────────────────┤
│  4. Clean Up              (plabs disable <id> &&        │
│                            plabs apply)                 │
└─────────────────────────────────────────────────────────┘
```

### Lab Outputs

All labs expose credentials and resource information via grouped Terraform outputs. Demo scripts read these automatically — no manual credential setup needed.

---

## Configuration

All configuration is managed through `plabs`. There is no need to edit Terraform files directly.

### Configuring AWS Profiles

Run the interactive setup wizard (recommended):

```bash
plabs init
```

Or set values directly (useful for CI/automation):

```bash
plabs config set prod-profile my-prod-profile
plabs config set prod-region us-east-1
```

| Key | Required | Description |
|-----|----------|-------------|
| `prod-profile` | Yes | AWS CLI profile for the prod account |
| `prod-region` | Yes | AWS region for the prod account |
| `dev-profile` | No | Dev account profile (cross-account labs only) |
| `dev-region` | No | Dev account region |
| `ops-profile` | No | Ops account profile (cross-account labs only) |
| `ops-region` | No | Ops account region |

**You only need ONE AWS account to use most of Pathfinding Labs.** All single-account labs deploy to `prod`. Dev and ops are only required for cross-account labs.


### Dev Mode

By default, `plabs` uses the repository it cloned into `~/.plabs/pathfinding-labs/`. If you are contributing and want to test local Terraform changes, enable dev mode from inside the repo:

```bash
# Run from inside your cloned pathfinding-labs directory
plabs config set dev-mode true
# plabs now uses local modules instead of ~/.plabs/pathfinding-labs/

plabs config set dev-mode false  # revert to the managed copy
```


### Enabling and Disabling labs

**Interactive (TUI):**

```bash
plabs       # open the dashboard
# ↑↓ to navigate, space to toggle, a to deploy
```

**CLI:**

```bash
# Enable by lab ID
plabs enable iam-002-iam-createaccesskey

# Enable multiple at once
plabs enable iam-002-iam-createaccesskey lambda-001-iam-passrole

# Disable
plabs disable iam-002-iam-createaccesskey
```

### Deploying

```bash
plabs apply        # shows plan, prompts for confirmation
plabs apply -y     # skip confirmation
plabs plan         # preview changes without deploying
```

---

## Running Attack Demonstrations

Each lab includes a demonstration script that shows how to exploit the vulnerability.

**Using plabs (recommended):**

```bash
plabs demo    iam-002-iam-createaccesskey
plabs cleanup iam-002-iam-createaccesskey
```

**Directly from the lab directory:**

```bash
cd modules/scenarios/single-account/privesc-one-hop/to-admin/iam-002-iam-createaccesskey
./demo_attack.sh
./cleanup_attack.sh
```

The demo scripts provide:
- ✅ Step-by-step exploitation walkthrough
- ✅ AWS CLI commands with explanations
- ✅ Real-time verification of privilege escalation
- ✅ Color-coded output for clarity
- ✅ **Automatic credential retrieval** — no manual AWS profile setup needed

<img width="1085" height="932" alt="Screenshot 2026-05-07 at 11 59 10 AM" src="https://github.com/user-attachments/assets/7c5cf6e6-53a1-47f2-8216-9ead4a05dfae" />

---

## What Gets Deployed

Understanding exactly what Pathfinding Labs creates in your account helps you assess the risk and plan your testing environment appropriately.

### IAM Resources

Every lab creates IAM principals (users, roles) and policies with deliberate misconfigurations. **No existing resources in your account are modified.** All created resources use the `pl-` prefix so they are easy to identify and audit.

### Starting Users

Each configured environment gets one dedicated starting user with **minimal permissions** — this is the simulated attacker's initial foothold:

| User | Environment |
|------|-------------|
| `pl-pathfinding-starting-user-prod` | Production |
| `pl-pathfinding-starting-user-dev` | Development |
| `pl-pathfinding-starting-user-operations` | Operations |

Starting users are granted only two permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sts:GetCallerIdentity",
        "iam:GetUser"
      ],
      "Resource": "*"
    }
  ]
}
```

### Cleanup Admin User

Each environment also includes one admin-level user used exclusively by cleanup scripts to revert demo artifacts:

- **`pl-admin-user-for-cleanup-scripts`**

This user has broad permissions. It exists so cleanup scripts can undo changes made during attack demonstrations (e.g., deleting access keys that were created, reverting modified policies). **This is another reason to keep your lab environment isolated from production.**

### Network Exposure by Lab Type

Not all labs expose resources to the internet:

| Category | Network Exposure |
|----------|-----------------|
| Privilege escalation (all hops) | None — IAM-only, no network resources |
| CSPM Misconfig / Toxic Combo | Some labs intentionally create public S3 buckets, Lambda function URLs, or open security groups |


Each scenario's README documents what it creates and any public-facing resources.

### Cost Guidance

Most labs are IAM-only and incur no AWS charges. Labs that deploy compute or storage resources (EC2, Lambda, ECS) incur small charges while deployed. Recommended: set a billing alert at $10–20/month as a safety net.

Tear down labs when not actively testing:

```bash
plabs disable <id> && plabs apply   # disable a specific scenario
plabs destroy                        # destroy all deployed resources
```

### Containment

All resources are created only in the accounts and regions you configure via `plabs config`. Teardown is complete — `plabs destroy` removes everything Pathfinding Labs created.

---

## Resource Naming Convention

All resources follow a consistent naming pattern:

```
pl-{resource-description}-{context}

Examples:
- pl-pathfinding-starting-user-prod
- pl-cak-admin (CreateAccessKey Admin)
- pl-prod-one-hop-putrolepolicy-role
```

Globally unique resources (S3 buckets) include a random suffix:
```
pl-{resource}-{account-id}-{random-6-char}

Example:
- pl-sensitive-data-954976316246-a3f9x2
```

---


## Lab Taxonomy

Pathfinding Labs organizes labs into five categories:

### **Self-Escalation**
Principal directly modifies itself to gain elevated privileges without traversing to another principal. This is the most direct form of privilege escalation where an entity grants itself additional permissions.

**Examples:**
- `Role → iam:PutRolePolicy (on self) → Admin`
- `User → iam:PutUserPolicy (on self) → Admin`
- `User → iam:AddUserToGroup → AdminGroup → Admin`
- `Role → iam:AttachRolePolicy (on self) → S3 Bucket Access`

### **One-Hop Privilege Escalation**
Single principal traversal labs where one principal gains access to another principal's privileges. These are single-account labs within the prod environment.

**Examples:**
- `Role → iam:CreateAccessKey → AdminUser → Admin`
- `Role → iam:PassRole + lambda:CreateFunction → AdminRole → Admin`
- `Role → lambda:UpdateFunctionCode → Lambda with Admin Role → Admin`
- `Role → ssm:SendCommand → EC2 with Admin Role → Admin`

### **Multi-Hop Privilege Escalation**
Multiple privilege escalation steps chaining through multiple principals. These are single-account labs within the prod environment.

**Examples:**
- `User → sts:AssumeRole → RoleA → iam:CreateAccessKey → UserB → AssumeRole → AdminRole`
- `RoleA → iam:PutRolePolicy → RoleB → AssumeRole → RoleC → Sensitive Bucket`

### **CSPM: Misconfig**
Single-condition security misconfigurations that CSPM tools should detect. These are single-account labs within the prod environment.

**Examples:**
- `EC2 Instance with Admin Role` - Overly permissive instance profile
- `S3 Bucket (public)` - Publicly accessible storage
- `Security Group (0.0.0.0/0)` - Unrestricted network access

### **CSPM: Toxic Combinations**
Multiple compounding misconfigurations that together create critical security risks. These are single-account labs within the prod environment.

**Examples:**
- `Lambda Function (publicly accessible) + Admin Role`
- `EC2 Instance (publicly accessible) + Critical CVE + Admin Role`
- `S3 Bucket (public) + Sensitive Data + No Encryption`

### **Cross-Account Privilege Escalation**
Privilege escalation paths that span multiple AWS accounts (dev, ops, prod). These labs demonstrate how compromise in one account can lead to access in another.

**Examples:**
- `Dev:User → AssumeRole → Prod:Role → Admin`
- `Dev:Role → Lambda:InvokeFunction → Prod:Lambda → Extract Credentials → Prod:Admin`
- `Ops:User → AssumeRole → Prod:Role → S3:SensitiveBucket`

---


## Architecture

### Directory Structure

```
pathfinding-labs/
├── modules/
│   ├── environments/          # Base infrastructure (always deployed)
│   │   ├── prod/             # Production environment base resources
│   │   ├── dev/              # Development environment base resources
│   │   └── operations/       # Operations environment base resources
│   │
│   └── scenarios/            # Attack labs (opt-in via flags)
│       ├── single-account/
│       │   ├── privesc-self-escalation/
│       │   │   ├── to-admin/    # Principal modifies itself to gain admin
│       │   │   └── to-bucket/   # Principal modifies itself for S3 access
│       │   ├── privesc-one-hop/
│       │   │   ├── to-admin/    # Single principal traversal to admin
│       │   │   └── to-bucket/   # Single principal traversal to S3 access
│       │   ├── privesc-multi-hop/
│       │   │   ├── to-admin/    # Multiple principal traversals to admin
│       │   │   └── to-bucket/   # Multiple principal traversals to S3 access
│       │   ├── cspm-misconfig/  # Single-condition security misconfigurations
│       │   └── cspm-toxic-combo/ # Multiple compounding misconfigurations
│       ├── tool-testing/         # Edge cases for testing detection engines
│       ├── ctf/                  # Capture-the-flag challenges (no demo scripts)
│       ├── attack-simulation/    # Recreations of real-world cloud breaches
│       └── cross-account/
│           ├── dev-to-prod/     # Dev → Prod attack paths
│           │   ├── one-hop/     # Single-hop cross-account escalation
│           │   └── multi-hop/   # Multi-hop cross-account escalation
│           └── ops-to-prod/     # Ops → Prod attack paths
│               └── one-hop/     # Single-hop cross-account escalation
│
├── main.tf                   # Root module with conditional instantiation
├── variables.tf              # Boolean flags for each scenario
├── outputs.tf                # Credential outputs for testing
└── terraform.tfvars          # Your configuration (gitignored)
```

### Module Structure

Each lab follows a standard structure:

```
scenario-name/
├── main.tf              # Terraform resources
├── variables.tf         # Input variables
├── outputs.tf           # Output values
├── README.md            # Documentation with mermaid diagrams
├── demo_attack.sh       # Exploitation demonstration
└── cleanup_attack.sh    # Artifact cleanup script
```

---

## CSPM Detection Examples

Each lab documents what a properly configured CSPM should detect:

### Example: iam-createaccesskey Scenario

**Expected CSPM Alerts:**
- ⚠️ IAM role can create access keys for privileged users
- ⚠️ Privilege escalation path detected
- ⚠️ Role has permissions on admin user
- ⚠️ Potential for credential theft

**MITRE ATT&CK Mapping:**
- **Tactic**: Privilege Escalation, Persistence
- **Technique**: T1098.001 - Account Manipulation: Additional Cloud Credentials

---

## Contributing

We welcome contributions! To add a new scenario:

1. **Create the lab directory** following the standard structure
2. **Implement resources** with proper provider configuration
3. **Write documentation** including mermaid diagrams and CSPM detection notes
4. **Create demo scripts** showing the exploitation technique
5. **Add to main.tf** with conditional instantiation
6. **Add boolean variable** to variables.tf
7. **Update terraform.tfvars.example**
8. **Test thoroughly** in an isolated AWS account — enable dev mode (`plabs config set dev-mode true`) to use your local copy, then `plabs enable <id> && plabs apply`
9. **Submit a pull request** with clear description

See our [Contributing Guide](CONTRIBUTING.md) for detailed instructions.

---

## Important Warnings

### **ONLY USE IN PLAYGROUND/SANDBOX ACCOUNTS**

- ❌ **NEVER** deploy to production AWS accounts
- ❌ **NEVER** deploy to accounts with real customer data
- ❌ **NEVER** deploy to accounts with production workloads
- ✅ **ALWAYS** use isolated playground/sandbox accounts
- ✅ **ALWAYS** tear down resources when finished
- ✅ **ALWAYS** monitor costs and set billing alarms

### Security Best Practices

1. **Use SCPs** to prevent accidental production deployment
2. **Set up billing alerts** to catch unexpected charges
3. **Use separate AWS Organizations** for testing
4. **Review each scenario** before enabling
5. **Document your testing** for compliance and audit purposes

---

## Additional Resources

- [IAM Vulnerable Project](https://github.com/bishopfox/iam-vulnerable) - Inspiration for single-account paths
- [MITRE ATT&CK Cloud Matrix](https://attack.mitre.org/matrices/enterprise/cloud/)
- [Stratus Red Team](https://github.com/DataDog/stratus-red-team) by Datadog

---

## License

This project is licensed under the [Apache License 2.0](LICENSE).

---


