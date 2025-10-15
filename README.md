# Pathfinder Labs 

**A modular platform for deploying intentionally vulnerable AWS configurations**

Pathfinder Labs helps security teams validate their Cloud Security Posture Management (CSPM) tools by deploying real-world attack scenarios in isolated AWS environments.

## Why does this exist? 

Who has access to my most sensitive S3 bucket? Is it 5% of my organization or 80%? You can ask the same question another way: **If an attacker compromises one of my employees, what is the likelihood they will be able to get to my most sensitive S3 bucket?**

You need tooling that can help you answer these questions. And you a way to deploy intentionally vulnerable resources so that you can test your tooling. That's my we created Pathfinder Labs. 
---

##  Who Is This For?

### **Blue Teamers**
- ✅ **Validate CSPM Detection**: Does your security tooling detect all vulnerable configurations?
- ✅ **Train Your Team**: Provide hands-on experience with real attack scenarios
- ✅ **Measure Coverage**: Identify gaps in your security monitoring

### **Red Teamers**
- ✅ **Practice IAM Exploitation**: Sharpen your privilege escalation skills
- ✅ **Test Your Tooling**: Does your toolset find all the paths?
- ✅ **Build Attack Chains**: Learn complex multi-hop and cross-account techniques
- ✅ **Demonstrate Risk**: Show stakeholders real-world attack scenarios

## What types of paths are supported?

<table>
  <thead>
    <tr>
      <th style="text-align:left;">Path Type</th>
      <th style="text-align:left;">Attack Example(s)</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><strong>Single-Hop<br>IAM Privesc to Admin</strong></td>
      <td>
        <pre><code>RoleA → iam:CreateAccessKey → RoleB
RoleA → iam:PassRole + ec2:RunInstances → RoleB</code></pre>
      </td>
    </tr>
    <tr>
      <td><strong>Single-Hop<br>IAM Privesc to Bucket</strong></td>
      <td>
        <pre><code>RoleA → iam:CreateAccessKey → RoleB → Sensitive-Bucket
RoleA → iam:PassRole + ec2:RunInstances → RoleB</code></pre>
      </td>
    </tr>
    <tr>
      <td><strong>Multi-Hop<br>IAM Privesc to Admin</strong></td>
      <td>
        <pre><code>RoleA → iam:CreateAccessKey → RoleB → sts:AssumeRole → RoleC</code></pre>
      </td>
    </tr>
    <tr>
      <td><strong>Multi-Hop<br>IAM Privesc to Bucket</strong></td>
      <td>
        <pre><code>RoleA → iam:CreateAccessKey → RoleB → sts:AssumeRole → RoleC → Sensitive-Bucket</code></pre>
      </td>
    </tr>
    <tr>
      <td><strong>Multi-Account<br>IAM Privesc to Admin</strong></td>
      <td>
        <pre><code>Account1:RoleA → iam:CreateAccessKey → Account1:RoleB → sts:AssumeRole → Account2:RoleC
</code></pre>
      </td>
    </tr>
    <tr>
      <td><strong>Multi-Account<br>IAM Privesc to Bucket</strong></td>
      <td>
        <pre><code>Account1:RoleA → iam:CreateAccessKey → Account1:RoleB → sts:AssumeRole → Account2:RoleC → Account2:Sensitive-Bucket</code></pre>
      </td>
    </tr>
    <tr>
      <td><strong>Toxic Combinations</strong></td>
      <td>
        <ul>
          <li><code>Lambda function is publicly accessible and has an administrative role attached</code></li>
          <li><code>S3 bucket publicly exposed with sensitive data</code></li>
        </ul>
      </td>
    </tr>
  </tbody>
</table>

## Quick Start

### Prerequisites
- One or more AWS accounts (playground/sandbox accounts recommended)
- AWS CLI configured with appropriate profiles
- Terraform 1.0+

### Setup in 5 Steps

```bash
# 1. Clone the repository
git clone https://github.com/your-org/pathfinder-labs.git
cd pathfinder-labs

# 2. Copy and configure your settings
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your account IDs and AWS profiles

# 3. Enable specific scenarios (edit terraform.tfvars)
enable_prod_one_hop_to_admin_iam_putrolepolicy = true

# 4. Deploy
terraform init
terraform apply

# 5. Create pathfinder profiles for testing
./create_pathfinder_profiles.sh
```

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

---

## Scenario Taxonomy

Pathfinder Labs organizes attack scenarios into four main categories:

### **One-Hop Privilege Escalation**
Single privilege escalation step from one principal to another. These are single-account scenarios within the prod environment.

**Examples:**
- `User → AssumeRole → Role(with iam:PutRolePolicy) → Admin`
- `Role → iam:CreateAccessKey → AdminUser → Admin`
- `Role → iam:PassRole + lambda:CreateFunction → AdminRole → Admin`

### **Multi-Hop Privilege Escalation**
Multiple privilege escalation steps chaining through multiple principals. These are single-account scenarios within the prod environment.

**Examples:**
- `User → AssumeRole → RoleA → iam:CreateAccessKey → UserB → AssumeRole → AdminRole`
- `RoleA → PutRolePolicy → RoleB → AssumeRole → RoleC → Sensitive Bucket`

### **Toxic Combinations**
Multiple misconfigurations that together create critical security risks. These are single-account scenarios within the prod environment.

**Examples:**
- `Lambda Function (publicly accessible) + Admin Role`
- `EC2 Instance (internet-facing) + Critical CVE + Admin Role`
- `S3 Bucket (public) + Sensitive Data + No Encryption`

### **Cross-Account Privilege Escalation**
Privilege escalation paths that span multiple AWS accounts (dev, ops, prod). These scenarios demonstrate how compromise in one account can lead to access in another.

**Examples:**
- `Dev:User → AssumeRole → Prod:Role → Admin`
- `Dev:Role → Lambda:InvokeFunction → Prod:Lambda → Extract Credentials → Prod:Admin`
- `Ops:User → AssumeRole → Prod:Role → S3:SensitiveBucket`

---

## Available Scenarios

### One-Hop to Admin (4 scenarios)

| Scenario | Attack Vector | Description |
|----------|---------------|-------------|
| `iam-putrolepolicy` | Self-modification | Role can modify its own inline policy to grant admin access |
| `iam-attachrolepolicy` | Self-modification | Role can attach managed policies to itself for escalation |
| `iam-createpolicyversion` | Policy versioning | Role can create new policy versions with elevated permissions |
| `iam-createaccesskey` | Credential creation | Role can create access keys for an admin user |

### One-Hop to Bucket (5 scenarios)

| Scenario | Attack Vector | Description |
|----------|---------------|-------------|
| `iam-putrolepolicy` | Self-modification | Role can grant itself S3 bucket access via inline policy |
| `iam-attachrolepolicy` | Self-modification | Role can attach S3 access policies to itself |
| `iam-createaccesskey` | Credential creation | Role can create keys for user with bucket access |
| `iam-updateassumerolepolicy` | Trust policy modification | Role can modify trust policies to assume bucket-access roles |
| `sts-assumerole` | Direct assumption | Role can directly assume another role with bucket permissions |

### Multi-Hop to Admin (2 scenarios)

| Scenario | Hops | Description |
|----------|------|-------------|
| `multiple-paths-combined` | 2-3 | Combines EC2, Lambda, and CloudFormation paths to admin |
| `putrolepolicy-on-other` | 2 | Role can modify another role's policy to gain admin access |

### Multi-Hop to Bucket (3 scenarios)

| Scenario | Hops | Description |
|----------|------|-------------|
| `resource-policy-bypass` | 2 | Access bucket through resource policy bypassing IAM restrictions |
| `exclusive-resource-policy` | 2 | Exclusive bucket access via restrictive resource policy |
| `role-chain-to-s3` | 3 | Three-hop role assumption chain ending at S3 bucket |

### Toxic Combo (1 scenario)

| Scenario | Risk Level | Description |
|----------|------------|-------------|
| `public-lambda-with-admin` | 🔴 Critical | Publicly accessible Lambda function with administrative role |

### Cross-Account Dev-to-Prod (4 scenarios)

| Scenario | Type | Description |
|----------|------|-------------|
| `simple-role-assumption` | One-hop | Direct cross-account role assumption from dev to prod |
| `passrole-lambda-admin` | Multi-hop | PassRole privilege escalation via Lambda across accounts |
| `multi-hop-both-sides` | Multi-hop | Privilege escalation in both accounts before crossing |
| `lambda-invoke-update` | Multi-hop | Lambda function code update to extract prod credentials |

### Cross-Account Ops-to-Prod (1 scenario)

| Scenario | Type | Description |
|----------|------|-------------|
| `simple-role-assumption` | One-hop | Direct cross-account role assumption from ops to prod |

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
cd modules/scenarios/prod/one-hop/to-admin/iam-createaccesskey

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
│   ├── prod/
│   │   ├── one-hop/
│   │   │   ├── to-admin/    # Single-step privilege escalation to admin
│   │   │   └── to-bucket/   # Single-step escalation to S3 access
│   │   ├── multi-hop/
│   │   │   ├── to-admin/    # Multi-step escalation to admin
│   │   │   └── to-bucket/   # Multi-step escalation to S3 access
│   │   └── toxic-combo/     # Attack paths with multiple conditions
│   └── cross-account/
│       ├── dev-to-prod/     # Dev → Prod attack paths
│       └── ops-to-prod/     # Ops → Prod attack paths
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
cd modules/scenarios/prod/one-hop/to-admin/iam-putrolepolicy
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

## 🔍 CSPM Detection Examples

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

## 📊 Current Status

- ✅ **20 scenarios** available
- ✅ **Single-account support** (works with just one AWS account)
- ✅ **Multi-account support** (optional cross-account scenarios)
- ✅ **Modular architecture** (enable/disable any scenario)
- ✅ **Demo scripts** for all scenarios
- ✅ **CSPM detection guidance** included

---

## 🗺️ Roadmap

- [ ] Web interface for scenario management
- [ ] Go CLI for easier configuration
- [ ] More toxic combination scenarios
- [ ] GCP and Azure support
- [ ] Integration with popular CSPM tools
- [ ] Automated testing framework
- [ ] Video walkthroughs for each scenario

---

## Additional Resources

- [Scenario Migration Guide](MIGRATION_COMPARISON.md)
- [Restructure Plan](RESTRUCTURE_PLAN.md)
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

---

**⭐ If you find Pathfinder Labs useful, please star the repository!**

*Made with ☕ for the cloud security community*
