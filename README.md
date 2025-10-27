<div align="center">

# Pathfinder Labs



**A modular platform for deploying intentionally vulnerable AWS configurations**

![Scenarios](https://img.shields.io/badge/Scenarios-40+-blue?style=for-the-badge)
![AWS](https://img.shields.io/badge/AWS-Support-orange?style=for-the-badge&logo=amazon-aws)

[Quick Start](#quick-start) • [Scenarios](#available-scenarios---single-account) • [Documentation](#architecture) • [Contributing](#contributing)

</div>

---

Pathfinder Labs helps security teams validate their Cloud Security Posture Management (CSPM) tools by deploying intentionally vulnerable cloud resources to sandbox environments.


### How Pathfinder Labs Works

```mermaid
graph LR
    A[Select<br/>Scenarios] --> B{Deploy<br/>Infrastructure}
    B -->|Blue Team| D[ Validate<br/>CSPM Detection]
    B -->|Red Team| E[ Validate <br/>your tools<br>& skills]
    D --> F[Measure<br/>Coverage Gaps]
    E --> G[Run Attack<br/>Demonstrations] 
    F --> H[Cleanup<br/>Artifacts]
    G --> H

    style A fill:#e1f5ff
    style B fill:#fff4e1
    style D fill:#e8f5e9
    style E fill:#ffebee
    style F fill:#f3e5f5
    style G fill:#fce4ec
```

##  Who Is This For?

<table>
<tr>
<td width="50%" valign="top">

### 🛡️ **Blue Teamers**
- ✅ **Validate CSPM Detection**: Does your security tooling detect all vulnerable configurations?
- ✅ **Train Your Team**: Provide hands-on experience with real attack scenarios
- ✅ **Measure Coverage**: Identify gaps in your security monitoring

</td>
<td width="50%" valign="top">

### ⚔️ **Red Teamers**
- ✅ **Practice IAM Exploitation**: Sharpen your privilege escalation skills
- ✅ **Test Your Tooling**: Does your toolset find all the paths?
- ✅ **Build Attack Chains**: Learn complex multi-hop and cross-account techniques
- ✅ **Demonstrate Risk**: Show stakeholders real-world attack scenarios

</td>
</tr>
</table>

## What types of paths are supported?


<table>
<tr>
<td align="center" colspan="4">

**💀 Privilege Escalation Scenarios**
</td>
</tr>
<tr>
<td align="center" width="25%">

**🎯 Self-Escalation**

Principal modifies itself

To Admin | To Bucket

</td>
<td align="center" width="25%">

**⚡ One-Hop**

Single principal traversal

To Admin | To Bucket

</td>
<td align="center" width="25%">

**🔗 Multi-Hop**

Multiple principal traversals

To Admin | To Bucket

</td>
<td align="center" width="25%">

**🌐 Cross-Account**

Spans multiple accounts

To Admin | To Bucket

</td>
</tr>
<tr>
<td align="center" colspan="4">

**💀 CSPM Finding Scenarios** — Simple cloud misconfiguration
</td>
<tr>
<td align="center" colspan="4">

**💀 Toxic Combination Scenarios** — Multiple misconfigurations that amplify risk

</td>
</tr>
</table>



## Quick Start

### Prerequisites
- One or more AWS accounts (playground/sandbox accounts recommended)
- AWS CLI configured with appropriate profiles
- Terraform 1.0+

### Setup in 5 Steps

```bash
# 1. Clone the repository
git clone https://github.com/DataDog/pathfinder-labs.git
cd pathfinder-labs

# 2. Copy and configure your settings
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your account IDs and AWS profiles

# 3. Enable specific scenarios (edit terraform.tfvars)
enable_prod_one_hop_to_admin_iam_putrolepolicy = true

# 4. Deploy
terraform init
terraform apply

# 5. Run demo scripts (credentials are automatically read from terraform outputs)
cd modules/scenarios/single-account/privesc-one-hop/to-admin/iam-createaccesskey
./demo_attack.sh
```

---

## Available Scenarios - Single Account

All scenarios below deploy to a single AWS account (prod) and can be used with just one playground account.

### Privilege Escalation to Admin

Traditional IAM privilege escalation scenarios or chains of traditional scenarios. Grouped according to how many hops between principals are involved. 

#### Self-Escalation to Admin (8 scenarios)

In these scenarios, an IAM principal has the permission to update their own permissions! Some tools consider these permissions equivalent to that of an administrator, some use the term "effective administrator", and some treat these the same as the one-hop scenarios below.

| Scenario | Description |
|----------|-------------|
| `iam-putrolepolicy` | Role modifies its own inline policy to grant admin access |
| `iam-attachrolepolicy` | Role attaches managed admin policies to itself |
| `iam-createpolicyversion` | Role creates new policy versions with elevated permissions |
| `iam-putuserpolicy` | User adds inline admin policy to themselves |
| `iam-attachuserpolicy` | User attaches managed admin policies to themselves |
| `iam-putgrouppolicy` | User modifies group inline policy to grant admin access |
| `iam-attachgrouppolicy` | User attaches admin policies to their group |
| `iam-addusertogroup` | User adds themselves to an admin group |

#### One-Hop to Admin (14 scenarios)

In these scenarios, one principal has enough permissions to gain access to another principal, and that principal has administrative access.

| Scenario | Description |
|----------|-------------|
| `iam-createaccesskey` | User creates access keys for an admin user |
| `iam-createloginprofile` | User creates console password for an admin user |
| `iam-updateloginprofile` | User resets console password for an admin user |
| `iam-putuserpolicy+iam-createaccesskey` | User adds admin inline policy to target user and creates access keys for them |
| `iam-attachuserpolicy+iam-createaccesskey` | User attaches AWS-managed AdministratorAccess to target user and creates access keys for them |
| `sts-assumerole` | Role directly assumes another role with admin permissions |
| `iam-updateassumerolepolicy` | User modifies trust policy of admin role to grant access |
| `iam-putrolepolicy+sts-assumerole` | User adds inline admin policy to assumable role then assumes it |
| `iam-passrole+ec2-runinstances` | User passes admin role to EC2 instance for credential extraction |
| `iam-passrole+lambda-createfunction+lambda-invokefunction` | User creates Lambda with admin role and invokes to extract credentials |
| `iam-passrole+lambda-createfunction+<br>createeventsourcemapping-dynamodb` | User creates Lambda with admin role triggered by DynamoDB events |
| `iam-passrole-cloudformation` | User passes admin role to CloudFormation to create escalated resources |
| `lambda-updatefunctioncode` | User modifies existing Lambda function code to execute under privileged role |
| `ssm-sendcommand` | User executes commands on EC2 instances with admin roles to extract credentials |

#### Multi-Hop to Admin (2 scenarios)

While everything above is consider an "atomic" privilege escalation path, these scenarios demonstrate what is commonly observed in AWS environments - multi-step paths that lead to administrative access. 

| Scenario | Hops | Description |
|----------|------|-------------|
| `multiple-paths-combined` | 2-3 | Combines EC2, Lambda, and CloudFormation paths to admin |
| `putrolepolicy-on-other` | 2 | Role can modify another role's policy to gain admin access |

---

### Lateral movement to an target S3 Bucket

The attacker uses the same privesc mechanisms as above, but the attacker never gets full admin permissions - they only get to the destination bucket. 


#### Self-Escalation to Bucket (2 scenarios)

| Scenario | Description |
|----------|-------------|
| `iam-putrolepolicy` | Role modifies its own inline policy to grant S3 bucket access |
| `iam-attachrolepolicy` | Role attaches S3 access policies to itself |


#### One-Hop to Bucket (6 scenarios)

| Scenario | Description |
|----------|-------------|
| `iam-createaccesskey` | User creates keys for user with bucket access |
| `iam-createloginprofile` | User creates console password for user with bucket access |
| `iam-updateloginprofile` | User resets console password for user with bucket access |
| `iam-updateassumerolepolicy` | User modifies trust policies to assume bucket-access roles |
| `sts-assumerole` | Role directly assumes another role with bucket permissions |
| `ssm-sendcommand` | User executes commands on EC2 instances with bucket access roles |

#### Multi-Hop to Bucket (3 scenarios)

| Scenario | Hops | Description |
|----------|------|-------------|
| `role-chain-to-s3` | 3 | Three-hop role assumption chain ending at S3 bucket |
| `resource-policy-bypass` | 2 | Bypass S3 bucket resource policy restrictions by assuming role with bucket access |
| `exclusive-resource-policy` | 2 | Access S3 bucket with exclusive resource policy that denies all except specific role |


---

### Toxic Combinations (1 scenario)

Toxic combinations are cases 

| Scenario | Risk Level | Description |
|----------|------------|-------------|
| `public-lambda-with-admin` | 🔴 Critical | Publicly accessible Lambda function with administrative role |

---

### Tool Testing Scenarios

Edge cases and scenarios designed to test detection engine capabilities.

#### Tool Testing (2 scenarios)

| Scenario | Focus | Description |
|----------|-------|-------------|
| `resource-policy-bypass` | Edge case detection | Tests detection of resource policies that bypass IAM restrictions |
| `exclusive-resource-policy` | Policy parsing | Tests detection of exclusive resource policy configurations |

---

### Cross-Account Scenarios

Privilege escalation paths that span multiple AWS accounts. These scenarios require at least two AWS accounts (dev/ops and prod).

#### Cross-Account Dev-to-Prod (5 scenarios)

| Scenario | Hops | Description |
|----------|------|-------------|
| `simple-role-assumption` | 1 | Direct cross-account role assumption from dev to prod |
| `root-trust-role-assumption` | 1 | Cross-account role assumption exploiting :root trust (any dev principal can assume) |
| `passrole-lambda-admin` | 1 | PassRole privilege escalation via Lambda across accounts |
| `multi-hop-both-sides` | 3 | Privilege escalation in both accounts before crossing |
| `lambda-invoke-update` | 2 | Lambda function code update to extract prod credentials |

#### Cross-Account Ops-to-Prod (1 scenario)

| Scenario | Type | Description |
|----------|------|-------------|
| `simple-role-assumption` | 1 | Direct cross-account role assumption from ops to prod |

---



## How It Works

**Modular Architecture**: Each attack scenario is a self-contained, independently deployable module that can be enabled or disabled via boolean flags.

```
┌─────────────────────────────────────────────────────────┐
│  1. Select Scenarios      (terraform.tfvars)            │
│     enable_scenario_x = true                            │
├─────────────────────────────────────────────────────────┤
│  2. Deploy                (terraform apply)             │
│     Creates vulnerable resources in your AWS account    │
├─────────────────────────────────────────────────────────┤
│  3. Test                  (demo_attack.sh)              │
│     Exploit OR detect with your CSPM                    │
├─────────────────────────────────────────────────────────┤
│  4. Clean Up              (terraform apply)             │
│     enable_scenario_x = false                           │
└─────────────────────────────────────────────────────────┘
```

### Terraform Outputs

All scenarios provide **grouped outputs** that bundle all credentials and resource information into a single JSON object:

```bash
# Example: Get all outputs for a scenario
terraform output -json | jq '.single_account_privesc_one_hop_to_admin_iam_createaccesskey'

# Demo scripts automatically parse these outputs
# No need to manually configure AWS profiles or copy credentials!
```

---

## Scenario Taxonomy

Pathfinder Labs organizes attack scenarios into five main categories:

### **Self-Escalation**
Principal directly modifies itself to gain elevated privileges without traversing to another principal. This is the most direct form of privilege escalation where an entity grants itself additional permissions.

**Examples:**
- `Role → iam:PutRolePolicy (on self) → Admin`
- `User → iam:PutUserPolicy (on self) → Admin`
- `User → iam:AddUserToGroup → AdminGroup → Admin`
- `Role → iam:AttachRolePolicy (on self) → S3 Bucket Access`

### **One-Hop Privilege Escalation**
Single principal traversal scenarios where one principal gains access to another principal's privileges. These are single-account scenarios within the prod environment.

**Examples:**
- `Role → iam:CreateAccessKey → AdminUser → Admin`
- `Role → iam:PassRole + lambda:CreateFunction → AdminRole → Admin`
- `Role → lambda:UpdateFunctionCode → Lambda with Admin Role → Admin`
- `Role → ssm:SendCommand → EC2 with Admin Role → Admin`

### **Multi-Hop Privilege Escalation**
Multiple privilege escalation steps chaining through multiple principals. These are single-account scenarios within the prod environment.

**Examples:**
- `User → sts:AssumeRole → RoleA → iam:CreateAccessKey → UserB → AssumeRole → AdminRole`
- `RoleA → iam:PutRolePolicy → RoleB → AssumeRole → RoleC → Sensitive Bucket`

### **Toxic Combinations**
Multiple misconfigurations that together create critical security risks. These are single-account scenarios within the prod environment.

**Examples:**
- `Lambda Function (publicly accessible) + Admin Role`
- `EC2 Instance (publicly accessible) + Critical CVE + Admin Role`
- `S3 Bucket (public) + Sensitive Data + No Encryption`

### **Cross-Account Privilege Escalation**
Privilege escalation paths that span multiple AWS accounts (dev, ops, prod). These scenarios demonstrate how compromise in one account can lead to access in another.

**Examples:**
- `Dev:User → AssumeRole → Prod:Role → Admin`
- `Dev:Role → Lambda:InvokeFunction → Prod:Lambda → Extract Credentials → Prod:Admin`
- `Ops:User → AssumeRole → Prod:Role → S3:SensitiveBucket`

### **Tool Testing**
Edge cases and scenarios designed to test detection engine capabilities. These scenarios aren't distinct escalation types, but rather configurations that challenge CSPM and security tool detection accuracy.

**Focus Areas:**
- Resource policies that bypass IAM restrictions
- Complex policy condition evaluation
- False positive scenarios
- Policy parsing edge cases

**Examples:**
- `Resource policy granting exclusive bucket access, bypassing IAM policies`
- `Complex condition keys that tools may misinterpret`
- `Legitimate configurations that appear vulnerable`

--- 

## Configuration

### Enabling Scenarios

Edit your `terraform.tfvars` file:

```hcl
# Account Configuration
prod_account_id        = "111111111111"
dev_account_id         = "222222222222"
operations_account_id  = "333333333333"

prod_account_aws_profile       = "my-prod-profile"
dev_account_aws_profile        = "my-dev-profile"
operations_account_aws_profile = "my-ops-profile"

# Enable specific scenarios
enable_prod_one_hop_to_admin_iam_putrolepolicy = true
enable_prod_one_hop_to_admin_iam_createaccesskey = true
enable_prod_toxic_combo_public_lambda_with_admin = true

# Keep everything else disabled
enable_prod_multi_hop_to_bucket_role_chain_to_s3 = false
# ... etc
```

### Single Account Mode

**You only need ONE AWS account to use most of Pathfinder Labs!**

All single-account scenarios deploy to the `prod` account. The `dev` and `ops` accounts are only required for cross-account scenarios.

```hcl
# Minimal configuration (single account)
prod_account_id          = "111111111111"
prod_account_aws_profile = "my-playground-account"

# These are optional and only needed for cross-account scenarios
# dev_account_id         = ""
# operations_account_id  = ""
```

---

## Running Attack Demonstrations

Each scenario includes a demonstration script that shows how to exploit the vulnerability:

```bash
# Navigate to a specific scenario
cd modules/scenarios/single-account/privesc-one-hop/to-admin/iam-createaccesskey

# Run the demonstration
./demo_attack.sh

# Clean up attack artifacts (keeps infrastructure)
./cleanup_attack.sh
```

The demo scripts provide:
- ✅ Step-by-step exploitation walkthrough
- ✅ AWS CLI commands with explanations
- ✅ Real-time verification of privilege escalation
- ✅ Color-coded output for clarity
- ✅ **Automatic credential retrieval** - No AWS profile configuration needed!

**How it works:** Demo scripts automatically read credentials from Terraform's grouped outputs, so you can run them immediately after `terraform apply` without any additional setup.

**Optional:** If you want to configure AWS CLI profiles for manual testing, you can run `./create_pathfinder_profiles.sh` to create profiles for the pathfinder starting users.

---

## Security Practices

### Pathfinder Starting Users

Each environment has a dedicated starting user with **minimal permissions**:

- **`pl-pathfinder-starting-user-prod`** - Production starting point
- **`pl-pathfinder-starting-user-dev`** - Development starting point  
- **`pl-pathfinder-starting-user-operations`** - Operations starting point

**Permissions:**
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

### Cleanup Users

Each environment includes an admin cleanup user for easy teardown:
- **`pl-admin-user-for-cleanup-scripts`**

---

## Resource Naming Convention

All resources follow a consistent naming pattern:

```
pl-{resource-description}-{context}

Examples:
- pl-pathfinder-starting-user-prod
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

## Architecture

### Directory Structure

```
pathfinder-labs/
├── environments/              # Base infrastructure (always deployed)
│   ├── prod/                 # Production environment base resources
│   ├── dev/                  # Development environment base resources
│   └── operations/           # Operations environment base resources
│
├── modules/scenarios/        # Attack scenarios (opt-in via flags)
│   ├── single-account/
│   │   ├── privesc-self-escalation/
│   │   │   ├── to-admin/    # Principal modifies itself to gain admin
│   │   │   └── to-bucket/   # Principal modifies itself for S3 access
│   │   ├── privesc-one-hop/
│   │   │   ├── to-admin/    # Single principal traversal to admin
│   │   │   └── to-bucket/   # Single principal traversal to S3 access
│   │   ├── privesc-multi-hop/
│   │   │   ├── to-admin/    # Multiple principal traversals to admin
│   │   │   └── to-bucket/   # Multiple principal traversals to S3 access
│   │   └── toxic-combo/     # Multiple misconfigurations combined
│   ├── tool-testing/         # Edge cases for testing detection engines
│   └── cross-account/
│       ├── dev-to-prod/     # Dev → Prod attack paths
│       │   ├── one-hop/     # Single-hop cross-account escalation
│       │   └── multi-hop/   # Multi-hop cross-account escalation
│       └── ops-to-prod/     # Ops → Prod attack paths
│           └── one-hop/     # Single-hop cross-account escalation
│
├── main.tf                   # Root module with conditional instantiation
├── variables.tf              # Boolean flags for each scenario
├── outputs.tf                # Credential outputs for testing
└── terraform.tfvars          # Your configuration (gitignored)
```

### Module Structure

Each scenario follows a standard structure:

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

## 🎯 Use Cases

### 1. CSPM Validation
```bash
# Deploy a known vulnerability
enable_prod_toxic_combo_public_lambda_with_admin = true
terraform apply

# Check if your CSPM detects it
# Expected alerts:
# - Lambda function publicly accessible
# - Lambda function has administrative permissions
# - Critical risk: Toxic combination detected
```

### 2. Red Team Training
```bash
# Deploy privilege escalation paths
enable_prod_one_hop_to_admin_iam_putrolepolicy = true
terraform apply

# Practice exploitation
cd modules/scenarios/single-account/privesc-one-hop/to-admin/iam-putrolepolicy
./demo_attack.sh

# Learn the technique, modify the script, try variations
```

### 3. Security Tool Testing
```bash
# Deploy multiple scenarios
enable_prod_one_hop_to_admin_iam_putrolepolicy = true
enable_prod_one_hop_to_admin_iam_createaccesskey = true
enable_prod_multi_hop_to_admin_multiple_paths_combined = true
terraform apply

# Test if your tooling finds all paths
# Compare results across different security tools
```

### 4. Incident Response Practice
```bash
# Create a realistic compromise scenario
enable_cross_account_dev_to_prod_multi_hop_lambda_invoke_update = true
terraform apply

# Practice detection, investigation, and response
# Use CloudTrail, GuardDuty, and other AWS security services
```

---

## CSPM Detection Examples

Each scenario documents what a properly configured CSPM should detect:

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

1. **Create the scenario directory** following the standard structure
2. **Implement resources** with proper provider configuration
3. **Write documentation** including mermaid diagrams and CSPM detection notes
4. **Create demo scripts** showing the exploitation technique
5. **Add to main.tf** with conditional instantiation
6. **Add boolean variable** to variables.tf
7. **Update terraform.tfvars.example**
8. **Test thoroughly** in an isolated AWS account
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

## Current Status

- ✅ **40 scenarios** available
  - 8 Self-Escalation to Admin
  - 2 Self-Escalation to Bucket
  - 13 One-Hop to Admin
  - 6 One-Hop to Bucket
  - 2 Multi-Hop to Admin
  - 3 Multi-Hop to Bucket
  - 1 Toxic Combo
  - 5 Cross-Account (4 dev-to-prod, 1 ops-to-prod)
- ✅ **Single-account support** (works with just one AWS account)
- ✅ **Multi-account support** (optional cross-account scenarios)
- ✅ **Modular architecture** (enable/disable any scenario)
- ✅ **Demo scripts** for all scenarios
- ✅ **CSPM detection guidance** included

---

## Roadmap

- [ ] Web interface for scenario management
- [ ] Go CLI for easier configuration
- [ ] More toxic combination scenarios
- [ ] GCP and Azure support
- [ ] Integration with popular CSPM tools
- [ ] Automated testing framework
- [ ] Video walkthroughs for each scenario

---

## Additional Resources

- [IAM Vulnerable Project](https://github.com/bishopfox/iam-vulnerable) - Inspiration for single-account paths
- [MITRE ATT&CK Cloud Matrix](https://attack.mitre.org/matrices/enterprise/cloud/)

---

## License

[Add your license here]

---

## Acknowledgments

Built with inspiration from:
- [IAM Vulnerable](https://github.com/bishopfox/iam-vulnerable) by Bishop Fox
- [Stratus Red Team](https://github.com/DataDog/stratus-red-team) by Datadog
- AWS Security community
