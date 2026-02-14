# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Pathfinding Labs** is a modular platform for deploying intentionally vulnerable AWS configurations to validate Cloud Security Posture Management (CSPM) tools and train security teams. Think of it as "Stratus Red Team for CSPM validation."

### Purpose
- **Validate CSPM Detection**: Does your security tooling detect all vulnerable configurations?
- **Train Security Teams**: Provide hands-on experience with real attack scenarios
- **Answer Critical Questions**: Who has access to my most sensitive S3 bucket? If an attacker compromises one employee, what's the likelihood they reach critical resources?
- **Measure Coverage**: Identify gaps in security monitoring
- **Practice IAM Exploitation**: Sharpen privilege escalation skills with real scenarios
- **Build Attack Chains**: Learn complex multi-hop and cross-account techniques

### Key Features
- **Single-Account Support**: Works with just ONE AWS account (prod) for most scenarios
- **Multi-Account Support**: Optional dev/ops accounts for cross-account scenarios
- **Modular Architecture**: Enable/disable individual scenarios via boolean flags
- **Granular Control**: Each scenario is independently deployable
- **93 Scenarios Available**: Covering self-escalation, one-hop, multi-hop, toxic combinations, and cross-account paths

## Architecture

### Directory Structure

```
pathfinding-labs/
├── cmd/plabs/                # Go CLI entry point
│   └── main.go
├── internal/                 # Go CLI internal packages
│   ├── cmd/                  # Cobra commands
│   ├── tui/                  # Bubble Tea TUI components
│   ├── config/               # Configuration management
│   ├── scenarios/            # Scenario discovery
│   ├── terraform/            # Terraform orchestration
│   ├── repo/                 # Repository management
│   └── demo/                 # Demo script execution
│
├── modules/
│   ├── environments/         # Base infrastructure (always deployed)
│   │   ├── prod/             # Production environment base resources
│   │   ├── dev/              # Development environment base resources (optional)
│   │   └── operations/       # Operations environment base resources (optional)
│   │
│   └── scenarios/            # Attack scenarios (opt-in via boolean flags)
│       ├── prod/                 # Single-account scenarios (PRIMARY)
│       │   ├── one-hop/
│       │   │   ├── to-admin/    # Single-step privilege escalation to admin
│       │   │   └── to-bucket/   # Single-step escalation to S3 access
│       │   ├── multi-hop/
│       │   │   ├── to-admin/    # Multi-step escalation to admin
│       │   │   └── to-bucket/   # Multi-step escalation to S3 access
│       │   ├── cspm-misconfig/  # Single-condition security misconfigurations
│       │   └── cspm-toxic-combo/ # Multiple compounding misconfigurations
│       ├── tool-testing/         # Edge cases for testing detection engines
│       └── cross-account/
│           ├── dev-to-prod/     # Dev → Prod attack paths
│           └── ops-to-prod/     # Ops → Prod attack paths
│
├── main.tf                   # Root module with conditional instantiation
├── variables.tf              # Boolean flags for each scenario
├── outputs.tf                # Credential outputs for testing
├── terraform.tfvars          # Your configuration (gitignored)
└── go.mod / go.sum           # Go module dependencies
```

### Scenario Taxonomy

**One-Hop Privilege Escalation**
- Single principal traversal (regardless of action complexity)
- Pattern: `Principal A → [IAM actions] → Principal B (admin/bucket access)`
- Examples: `iam:PutRolePolicy`, `iam:PassRole + lambda:CreateFunction + lambda:InvokeFunction`
- Both role-based and user-based scenarios
- Deploy to: **prod account only**

**Multi-Hop Privilege Escalation**
- Multiple principal traversals (chaining 2+ one-hop paths)
- Pattern: `Principal A → Principal B → Principal C → Target`
- Examples: Role chains, multiple privilege escalation steps
- Deploy to: **prod account only** (for single-account) or **cross-account**

**CSPM Misconfig**
- Single-condition security misconfigurations
- Examples: EC2 with admin role, S3 bucket publicly accessible
- Focus on CSPM detection of individual misconfigurations
- Deploy to: **prod account only**

**CSPM Toxic Combinations**
- Multiple compounding security misconfigurations
- Examples: Public Lambda + Admin Role, Public S3 + Sensitive Data
- Focus on CSPM detection of combined risk scenarios
- Deploy to: **prod account only**

**Cross-Account Privilege Escalation**
- Privilege escalation paths spanning multiple AWS accounts
- Examples: Dev → Prod, Ops → Prod
- Deploy to: **dev/ops → prod accounts** (requires multi-account setup)

**Tool Testing**
- Edge cases and scenarios designed to test detection engine capabilities
- Not distinct escalation types, but scenarios to measure detection accuracy
- Examples: Resource policies that bypass IAM, complex policy conditions, false positive scenarios
- Can be single-account or cross-account, to-admin or to-bucket, one-hop or multi-hop
- Focus on testing CSPM and security tool detection rather than new attack techniques
- Deploy to: **prod account** (for single-account) or **cross-account**

### Account Usage Strategy

**Prod Account (PRIMARY)**
- All one-hop scenarios (to-admin and to-bucket)
- All single-account multi-hop scenarios
- All CSPM scenarios (cspm-misconfig and cspm-toxic-combo)
- **Users with only ONE AWS account can use just prod!**

**Dev/Ops Accounts (OPTIONAL)**
- Reserved for cross-account scenarios only
- Cross-account one-hop and multi-hop paths
- Not required for single-account testing

### Multi-Account Provider Pattern

- All modules use provider aliases: `aws.dev`, `aws.prod`, `aws.operations`
- Resources must specify the correct provider to deploy to the right account
- Account IDs are automatically derived from AWS profiles via `aws_caller_identity` data sources
- Account IDs are passed as variables to all modules (auto-derived, no manual input needed)
- Conditional module instantiation based on boolean flags

## The `plabs` CLI Binary

The project includes a Go-based CLI tool (`plabs`) with an interactive TUI dashboard for managing scenarios without manually editing Terraform files.

### Go Project Structure

```
pathfinding-labs/
├── cmd/plabs/
│   └── main.go                    # Entry point (calls cmd.Execute())
│
├── internal/
│   ├── cmd/                       # Cobra commands
│   │   ├── root.go               # Root command & command registration
│   │   ├── tui.go                # Interactive TUI dashboard
│   │   ├── init.go               # Initial setup & wizard
│   │   ├── config.go             # Configuration management
│   │   ├── scenarios.go          # Browse & list scenarios
│   │   ├── enable.go             # Enable scenarios
│   │   ├── disable.go            # Disable scenarios
│   │   ├── deploy.go             # Deploy to AWS
│   │   ├── plan.go               # Terraform plan
│   │   ├── destroy.go            # Destroy resources
│   │   ├── status.go             # Deployment status
│   │   ├── info.go               # Show configuration info
│   │   ├── update.go             # Update repo
│   │   └── helpers.go            # Shared utilities
│   │
│   ├── tui/                       # Terminal UI (Bubble Tea)
│   │   ├── model.go              # Main Bubble Tea model & state
│   │   ├── keys.go               # Keybindings
│   │   ├── styles.go             # Lipgloss styles & color palette
│   │   ├── environment.go        # Environment pane component
│   │   ├── scenarios.go          # Scenarios list pane
│   │   ├── details.go            # Details pane
│   │   ├── actions.go            # Actions/shortcuts pane
│   │   ├── info.go               # Info header pane
│   │   └── overlay.go            # Modal overlays
│   │
│   ├── config/                    # Configuration management
│   │   ├── config.go             # Config structure & persistence
│   │   └── wizard.go             # Interactive setup wizard
│   │
│   ├── scenarios/                 # Scenario discovery & metadata
│   │   ├── metadata.go           # Scenario struct (from scenario.yaml)
│   │   ├── discovery.go          # Scenario discovery engine
│   │   └── filter.go             # Scenario filtering
│   │
│   ├── terraform/                 # Terraform orchestration
│   │   ├── runner.go             # Execute terraform commands
│   │   ├── outputs.go            # Parse terraform outputs
│   │   ├── tfvars.go             # Generate terraform.tfvars
│   │   └── installer.go          # Download terraform binary
│   │
│   ├── repo/                      # Repository management
│   │   ├── paths.go              # Directory path management
│   │   ├── clone.go              # Clone repository
│   │   └── update.go             # Pull repository updates
│   │
│   └── demo/                      # Demo script execution
│       └── runner.go             # Execute demo_attack.sh scripts
│
└── go.mod / go.sum               # Go dependencies
```

### Key Dependencies

| Package | Purpose |
|---------|---------|
| `github.com/charmbracelet/bubbletea` | TUI framework (Elm architecture) |
| `github.com/charmbracelet/bubbles` | Pre-built TUI components |
| `github.com/charmbracelet/huh` | Interactive forms |
| `github.com/charmbracelet/lipgloss` | Terminal styling |
| `github.com/spf13/cobra` | CLI framework |
| `github.com/fatih/color` | Terminal colors |
| `gopkg.in/yaml.v3` | YAML parsing |

### CLI Commands (Cobra)

Running `plabs` with no arguments launches the interactive TUI dashboard.

| Command | Description |
|---------|-------------|
| `plabs` | Launch interactive TUI (default) |
| `plabs tui` | Launch interactive TUI explicitly |
| `plabs init` | Initial setup & configuration wizard |
| `plabs config` | Manage configuration |
| `plabs scenarios list` | List scenarios with filtering |
| `plabs enable [id\|pattern]` | Enable scenarios |
| `plabs disable [id\|pattern]` | Disable scenarios |
| `plabs deploy` | Deploy enabled scenarios |
| `plabs plan` | Show terraform plan |
| `plabs destroy` | Destroy infrastructure |
| `plabs status` | Show deployment status |
| `plabs info` | Show config info |
| `plabs update` | Update repository |

### TUI Architecture (Bubble Tea)

The TUI uses the Elm architecture via Bubble Tea:

**Pane System:**
- `PaneEnvironment` - Left: Account/environment status
- `PaneScenarios` - Center: Scrollable, filterable scenario list
- `PaneDetails` - Right: Scenario details & credentials

**Key Bindings:**
- Navigation: `↑↓`, `pgup/pgdown`, `home/end`
- Actions: `space`=toggle, `d`=deploy, `D`=destroy
- UI: `tab`=switch pane, `/`=filter, `.`=toggle enabled-only, `?`=help, `q`=quit

**Styling:**
- Centralized in `internal/tui/styles.go`
- Color palette: Purple primary, Cyan secondary, Green success, Red error
- All styles use Lipgloss

### Configuration Management

**Config Location:** `~/.plabs/plabs.yaml`

```yaml
dev_mode: false
dev_mode_path: ""
aws:
  prod:
    profile: "my-profile"
    region: "us-east-1"
  dev:
    profile: ""
    region: ""
  ops:
    profile: ""
    region: ""
scenarios:
  enabled:
    - "enable_single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey"
initialized: true
```

**Directory Structure:**
- `~/.plabs/plabs.yaml` - Config file
- `~/.plabs/pathfinding-labs/` - Cloned repository (normal mode)
- `~/.plabs/bin/` - Downloaded binaries (terraform)

**Dev Mode:**
- Set `dev_mode: true` and `dev_mode_path: /path/to/local/repo`
- Uses local repository instead of `~/.plabs/pathfinding-labs/`
- Useful when developing the CLI against local Terraform changes

### Building the plabs Binary

```bash
# Build the binary
go build -o plabs ./cmd/plabs

# Run directly without building
go run ./cmd/plabs

# Install to $GOPATH/bin
go install ./cmd/plabs
```

## plabs CLI Development Guidelines

### CRITICAL: Always Rebuild After Changes

**When making ANY changes to Go code in `cmd/` or `internal/`, you MUST rebuild the binary before testing:**

```bash
go build -o plabs ./cmd/plabs
```

This is the most common source of confusion during development - testing against a stale binary.

### Adding a New Cobra Command

1. Create a new file in `internal/cmd/` (e.g., `newcommand.go`)
2. Define the command:
   ```go
   var newcommandCmd = &cobra.Command{
       Use:   "newcommand [args]",
       Short: "Brief description",
       Long:  `Detailed help text with examples`,
       RunE:  runNewcommand,
   }

   func runNewcommand(cmd *cobra.Command, args []string) error {
       // Implementation - return error on failure
       return nil
   }
   ```
3. Register in `internal/cmd/root.go`'s `init()` function:
   ```go
   rootCmd.AddCommand(newcommandCmd)
   ```
4. **Rebuild the binary**

### Adding a New TUI Pane/Component

1. Create a new file in `internal/tui/` (e.g., `newpane.go`)
2. Define render function following existing patterns:
   ```go
   func (m Model) renderNewPane() string {
       // Use styles from styles.go
       return styles.PaneStyle.Render(content)
   }
   ```
3. Add to the main View() in `model.go`
4. Add any new keybindings to `keys.go`
5. **Rebuild the binary**

### TUI State Management

The TUI uses a single `Model` struct in `internal/tui/model.go`:

```go
type Model struct {
    // Pane management
    activePane    Pane

    // Data
    scenarios     []scenarios.Scenario
    enabled       map[string]bool
    deployed      map[string]bool

    // UI state
    cursor        int
    filter        string
    showEnabledOnly bool

    // Async operations
    loading       bool
    err           error
}
```

**Message Pattern for Async Operations:**
```go
// Define a message type
type scenariosLoadedMsg struct {
    scenarios []scenarios.Scenario
    err       error
}

// Return a command that sends the message
func loadScenarios() tea.Cmd {
    return func() tea.Msg {
        scenarios, err := discovery.LoadAll()
        return scenariosLoadedMsg{scenarios, err}
    }
}

// Handle in Update()
case scenariosLoadedMsg:
    m.scenarios = msg.scenarios
    m.err = msg.err
    m.loading = false
```

### Path Resolution Pattern

Always use `getWorkingPaths()` helper for consistent path resolution:

```go
func getWorkingPaths() (*WorkingPaths, error) {
    cfg, err := config.Load()
    if err != nil {
        return nil, err
    }
    return &WorkingPaths{
        TerraformDir: cfg.GetTerraformDir(),
        ConfigPath:   config.DefaultConfigPath(),
    }, nil
}
```

### Error Handling Pattern

Commands use `RunE` (returns error) not `Run`:

```go
func runCommand(cmd *cobra.Command, args []string) error {
    if err := doSomething(); err != nil {
        return fmt.Errorf("operation failed: %w", err)
    }
    return nil
}
```

### Testing Go Code

```bash
# Run all tests
go test ./...

# Run tests for specific package
go test ./internal/scenarios/...

# Run with verbose output
go test -v ./...
```

## Common Commands

### Using the plabs CLI

```bash
# Initial setup (interactive wizard)
plabs init

# Launch TUI dashboard
plabs

# List all scenarios
plabs scenarios list

# Enable scenarios by pattern
plabs enable iam-002
plabs enable "one-hop/*"

# Deploy enabled scenarios
plabs deploy

# Show deployment status
plabs status
```

### Initial Setup (Single Account)

```bash
# 1. Clone the repository
git clone https://github.com/your-org/pathfinding-labs.git
cd pathfinding-labs

# 2. Copy and configure your settings
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your AWS profile (account IDs are auto-derived!)

# 3. Enable specific scenarios (edit terraform.tfvars)
enable_single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey = true

# 4. Deploy
terraform init
terraform plan
terraform apply

# 5. Run demo scripts (credentials are automatically read from terraform outputs)
cd modules/scenarios/single-account/privesc-one-hop/to-admin/iam-002-iam-createaccesskey
./demo_attack.sh
```

### Initial Setup (Multi-Account with Dev/Ops)

```bash
# Same as above, but configure all three account profiles in terraform.tfvars:
# (Account IDs are automatically derived from the profiles!)
prod_account_aws_profile       = "my-prod-profile"
dev_account_aws_profile        = "my-dev-profile"
operations_account_aws_profile = "my-ops-profile"

# Enable cross-account scenarios
enable_cross_account_dev_to_prod_simple_role_assumption = true
```

### Running Attack Demonstrations

Each scenario includes demonstration scripts:

```bash
# Navigate to a specific scenario
cd modules/scenarios/single-account/privesc-one-hop/to-admin/iam-002-iam-createaccesskey

# Run the demonstration
./demo_attack.sh

# Clean up attack artifacts (keeps infrastructure)
./cleanup_attack.sh
```

Demo scripts provide:
- Step-by-step exploitation walkthrough
- AWS CLI commands with explanations
- Real-time verification of privilege escalation
- Color-coded output for clarity
- **Automatic credential retrieval from Terraform outputs** (no AWS profile configuration needed)

### Development Workflow
```bash
# Validate Terraform configuration
terraform validate

# Format Terraform files
terraform fmt -recursive

# Show current state
terraform show

# List all resources
terraform state list
```

## Available Scenarios

Scenarios use pathfinding.cloud IDs for consistent naming (e.g., `iam-002`, `ecs-006`).

### Self-Escalation to Admin (8 scenarios)
| Scenario | Description |
|----------|-------------|
| `iam-001-iam-createpolicyversion` | Role creates new policy versions with elevated permissions |
| `iam-005-iam-putrolepolicy` | Role modifies its own inline policy to grant admin access |
| `iam-007-iam-putuserpolicy` | User adds inline admin policy to themselves |
| `iam-008-iam-attachuserpolicy` | User attaches managed admin policies to themselves |
| `iam-009-iam-attachrolepolicy` | Role attaches managed admin policies to itself |
| `iam-010-iam-attachgrouppolicy` | User attaches admin policies to their group |
| `iam-011-iam-putgrouppolicy` | User modifies group inline policy to grant admin access |
| `iam-013-iam-addusertogroup` | User adds themselves to an admin group |

### One-Hop to Admin (57 scenarios)
| Scenario | Description |
|----------|-------------|
| `iam-002-iam-createaccesskey` | Create access keys for admin user |
| `iam-003-iam-deleteaccesskey+createaccesskey` | Delete and recreate access keys for admin user |
| `iam-004-iam-createloginprofile` | Create console password for admin user |
| `iam-006-iam-updateloginprofile` | Reset console password for admin user |
| `iam-012-iam-updateassumerolepolicy` | Modify trust policy of admin role |
| `sts-001-sts-assumerole` | Directly assume role with admin permissions |
| ... and 51 more scenarios covering Lambda, EC2, ECS, Glue, CodeBuild, CloudFormation, SageMaker, SSM, AppRunner, Bedrock |

### Self-Escalation to Bucket (2 scenarios)
| Scenario | Description |
|----------|-------------|
| `iam-005-iam-putrolepolicy` | Role modifies its own policy for S3 access |
| `iam-009-iam-attachrolepolicy` | Role attaches S3 access policies to itself |

### One-Hop to Bucket (11 scenarios)
| Scenario | Description |
|----------|-------------|
| `iam-002-iam-createaccesskey` | Create keys for user with bucket access |
| `iam-012-iam-updateassumerolepolicy` | Modify trust to assume bucket-access roles |
| `sts-001-sts-assumerole` | Directly assume role with bucket permissions |
| ... and 8 more scenarios |

### Multi-Hop to Admin (1 scenario)
| Scenario | Description |
|----------|-------------|
| `multiple-paths-combined` | EC2, Lambda, CloudFormation paths to admin |

### Multi-Hop to Bucket (1 scenario)
| Scenario | Description |
|----------|-------------|
| `role-chain-to-s3` | Three-hop role assumption chain to S3 |

### Toxic Combo (1 scenario)
| Scenario | Description |
|----------|-------------|
| `public-lambda-with-admin` | Public Lambda with administrative role |

### Tool Testing (5 scenarios)
| Scenario | Description |
|----------|-------------|
| `resource-policy-bypass` | Tests resource policies that bypass IAM restrictions |
| `exclusive-resource-policy` | Tests exclusive resource policy configurations |
| `test-effective-permissions-evaluation` | Tests admin access patterns, denies, boundaries |
| `test-reverse-blast-radius-direct-and-indirect-through-admin` | Tests direct and indirect S3 access via admin |
| `test-reverse-blast-radius-direct-and-indirect-to-bucket` | Tests direct and indirect S3 bucket access |

### Cross-Account (6 scenarios)
| Scenario | Description |
|----------|-------------|
| `dev-to-prod/simple-role-assumption` | Direct cross-account role assumption |
| `dev-to-prod/root-trust-role-assumption` | Cross-account via :root trust |
| `dev-to-prod/passrole-lambda-admin` | PassRole escalation via Lambda |
| `dev-to-prod/multi-hop-both-sides` | Escalation in both accounts |
| `dev-to-prod/lambda-invoke-update` | Lambda code update for credential extraction |
| `ops-to-prod/simple-role-assumption` | Ops to prod role assumption |

## Development Guidelines

### Adding New Scenario Modules

Each scenario module follows a standard structure:

```
scenario-name/
├── main.tf              # Terraform resources (uses provider alias)
├── variables.tf         # Required: account_id, resource_suffix, environment
├── outputs.tf           # Credentials, ARNs, attack path info
├── README.md            # Documentation with mermaid diagrams
├── demo_attack.sh       # Exploitation demonstration
└── cleanup_attack.sh    # Artifact cleanup script
```

### Adding a New Scenario (Step-by-Step)

1. **Create the scenario directory** under the appropriate path:
   - One-hop to admin: `modules/scenarios/single-account/privesc-one-hop/to-admin/scenario-name/`
   - One-hop to bucket: `modules/scenarios/single-account/privesc-one-hop/to-bucket/scenario-name/`
   - Multi-hop to admin: `modules/scenarios/single-account/privesc-multi-hop/to-admin/scenario-name/`
   - Multi-hop to bucket: `modules/scenarios/single-account/privesc-multi-hop/to-bucket/scenario-name/`
   - CSPM Misconfig: `modules/scenarios/single-account/cspm-misconfig/scenario-name/`
   - CSPM Toxic combo: `modules/scenarios/single-account/cspm-toxic-combo/scenario-name/`
   - Tool testing: `modules/scenarios/tool-testing/scenario-name/`
   - Cross-account: `modules/scenarios/cross-account/dev-to-prod/[one-hop|multi-hop]/scenario-name/`

2. **Implement Terraform resources** in `main.tf`:
   ```hcl
   # For single-account (prod) scenarios
   resource "aws_iam_role" "example" {
     provider = aws.prod
     name     = "pl-${var.scenario_name}-role"
     # ...
   }
   ```

3. **Add variables** in `variables.tf`:
   ```hcl
   variable "account_id" {
     description = "AWS Account ID"
     type        = string
   }

   variable "resource_suffix" {
     description = "Random suffix for globally unique resources"
     type        = string
   }

   variable "environment" {
     description = "Environment name (prod, dev, operations)"
     type        = string
     default     = "prod"
   }
   ```

4. **Add outputs** in `outputs.tf`:
   ```hcl
   output "starting_role_arn" {
     description = "ARN of the starting role for this attack path"
     value       = aws_iam_role.starting_role.arn
   }
   ```

5. **Create README.md** with:
   - Attack path description
   - Mermaid diagram showing the path
   - CSPM detection guidance
   - MITRE ATT&CK mapping

6. **Create demo_attack.sh** demonstrating the exploit

7. **Create cleanup_attack.sh** to revert demo changes

8. **Add boolean variable** to root `variables.tf`:
   ```hcl
   variable "enable_single_account_privesc_one_hop_to_admin_iam_099_iam_newscenario" {
     description = "Enable: single-account → privesc-one-hop → to-admin → iam-099-iam-newscenario"
     type        = bool
     default     = false
   }
   ```

9. **Add module instantiation** to root `main.tf`:
   ```hcl
   module "single_account_privesc_one_hop_to_admin_iam_099_iam_newscenario" {
     count  = var.enable_single_account_privesc_one_hop_to_admin_iam_099_iam_newscenario ? 1 : 0
     source = "./modules/scenarios/single-account/privesc-one-hop/to-admin/iam-099-iam-newscenario"

     providers = {
       aws = aws.prod
     }

     account_id       = var.prod_account_id
     environment      = "prod"
     resource_suffix  = random_string.resource_suffix.result
   }
   ```

10. **Add grouped output** to root `outputs.tf`:
   ```hcl
   output "single_account_privesc_one_hop_to_admin_iam_099_iam_newscenario" {
     description = "All outputs for iam-099-iam-newscenario one-hop to-admin scenario"
     value = var.enable_single_account_privesc_one_hop_to_admin_iam_099_iam_newscenario ? {
       starting_user_name              = module.single_account_privesc_one_hop_to_admin_iam_099_iam_newscenario[0].starting_user_name
       starting_user_arn               = module.single_account_privesc_one_hop_to_admin_iam_099_iam_newscenario[0].starting_user_arn
       starting_user_access_key_id     = module.single_account_privesc_one_hop_to_admin_iam_099_iam_newscenario[0].starting_user_access_key_id
       starting_user_secret_access_key = module.single_account_privesc_one_hop_to_admin_iam_099_iam_newscenario[0].starting_user_secret_access_key
       attack_path                     = module.single_account_privesc_one_hop_to_admin_iam_099_iam_newscenario[0].attack_path
     } : null
     sensitive = true
   }
   ```

11. **Update terraform.tfvars.example** with the new boolean flag

12. **Test thoroughly** in an isolated AWS account

### Demo Script Best Practices

Demo scripts should:
- Use color-coded output for clarity (red/green/yellow)
- Show step-by-step exploitation with explanations
- Verify privilege escalation actually works
- Include AWS CLI commands with comments
- **Read credentials from grouped Terraform outputs** using this pattern:
  ```bash
  cd ../../../../../..  # Navigate to project root
  MODULE_OUTPUT=$(terraform output -json 2>/dev/null | jq -r '.single_account_privesc_CATEGORY_SCENARIO.value // empty')
  ACCESS_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_access_key_id')
  SECRET_KEY=$(echo "$MODULE_OUTPUT" | jq -r '.starting_user_secret_access_key')
  cd - > /dev/null  # Return to scenario directory
  ```
- **Use 15-second waits** for IAM policy propagation (not 5 seconds)
- Clean up any temporary resources created during demo

### Cleanup Script Best Practices

Cleanup scripts should:
- **Use admin credentials from Terraform outputs** for cleanup operations:
  ```bash
  cd ../../../../../..  # Navigate to project root
  ADMIN_ACCESS_KEY=$(terraform output -raw prod_admin_user_for_cleanup_access_key_id 2>/dev/null)
  ADMIN_SECRET_KEY=$(terraform output -raw prod_admin_user_for_cleanup_secret_access_key 2>/dev/null)
  export AWS_ACCESS_KEY_ID="$ADMIN_ACCESS_KEY"
  export AWS_SECRET_ACCESS_KEY="$ADMIN_SECRET_KEY"
  unset AWS_SESSION_TOKEN
  cd - > /dev/null  # Return to scenario directory
  ```
- Remove attack artifacts (access keys, modified policies, etc.)
- **Preserve infrastructure** - cleanup scripts remove demo artifacts, not the terraform resources
- Provide clear feedback about what was cleaned up
- Use color-coded output to show cleanup progress

### Resource Naming Convention

All resources follow a consistent naming pattern:

- **Prefix**: `pl-` (Pathfinding Labs)
- **Format**: `pl-{resource-description}-{context}`
- **Examples**:
  - `pl-pathfinding-starting-user-prod`
  - `pl-cak-admin` (CreateAccessKey Admin)
  - `pl-prod-one-hop-putrolepolicy-role`

Globally unique resources (S3 buckets) include account ID and random suffix:
- **Format**: `pl-{resource}-{account-id}-{random-6-char}`
- **Example**: `pl-sensitive-data-954976316246-a3f9x2`
- Use the `resource_suffix` variable for consistent random suffixes

## Configuration

### Required Variables (Single Account)

Configure these in `terraform.tfvars`:

```hcl
# Minimal configuration for single-account scenarios
# NOTE: Account IDs are automatically derived from your AWS profile!
prod_account_aws_profile = "my-playground-account"

# Enable specific scenarios (use pathfinding.cloud IDs)
enable_single_account_privesc_self_escalation_to_admin_iam_005_iam_putrolepolicy = true
enable_single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey = true
enable_single_account_cspm_toxic_combo_public_lambda_with_admin = true

# Keep everything else disabled
enable_single_account_privesc_multi_hop_to_bucket_role_chain_to_s3 = false
# ... etc
```

### Optional Variables (Multi-Account)

For cross-account scenarios:

```hcl
# Add dev and ops account profiles (account IDs auto-derived!)
dev_account_aws_profile        = "my-dev-profile"
operations_account_aws_profile = "my-ops-profile"

# Enable cross-account scenarios
enable_cross_account_dev_to_prod_simple_role_assumption = true
```

### Boolean Variable Convention

Each scenario has a corresponding boolean variable using pathfinding.cloud IDs:

```hcl
# Format: enable_single_account_privesc_{category}_to_{target}_{path_id}_{technique}
# Note: Use underscores in variable names (not hyphens)
enable_single_account_privesc_self_escalation_to_admin_iam_005_iam_putrolepolicy = true
enable_single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey = true
enable_single_account_privesc_multi_hop_to_bucket_role_chain_to_s3 = true
enable_tool_testing_resource_policy_bypass = true
enable_cross_account_dev_to_prod_multi_hop_passrole_lambda_admin = true
```

## Pathfinding Starting Users

The project creates standardized starting users for each environment to serve as initial access points:

### Available Users
- `pl-pathfinding-starting-user-dev` - Development environment
- `pl-pathfinding-starting-user-prod` - Production environment
- `pl-pathfinding-starting-user-operations` - Operations environment

### Permissions
Each pathfinding starting user has minimal permissions:
- `sts:GetCallerIdentity` - Can identify themselves
- `iam:GetUser` - Can get their own user information

### Usage in Scenarios
- **User-based scenarios**: Use the pathfinding starting user directly
- **Role-based scenarios**: Initial roles trust the pathfinding starting user instead of `:root`
- **Cross-account scenarios**: Each environment's pathfinding user can assume trusted roles

## Attack Path Types

Pathfinding Labs supports diverse attack scenarios:

### One-Hop Paths
```
RoleA → iam:CreateAccessKey → RoleB (Admin)
RoleA → iam:PassRole + ec2:RunInstances → RoleB (Admin)
RoleA → iam:PutRolePolicy → Self (Admin)
```

### Multi-Hop Paths
```
RoleA → iam:CreateAccessKey → RoleB → sts:AssumeRole → RoleC (Admin)
RoleA → iam:PutRolePolicy → RoleB → sts:AssumeRole → RoleC → Sensitive-Bucket
```

### Cross-Account Paths
```
Account1:RoleA → iam:CreateAccessKey → Account1:RoleB → sts:AssumeRole → Account2:RoleC (Admin)
Account1:RoleA → iam:CreateAccessKey → Account1:RoleB → sts:AssumeRole → Account2:RoleC → Account2:Sensitive-Bucket
```

### Toxic Combinations
```
Lambda Function (publicly accessible) + Admin Role
EC2 Instance (internet-facing) + Critical CVE + Admin Role
S3 Bucket (public) + Sensitive Data + No Encryption
```

## CSPM Detection Examples

Each scenario documents what a properly configured CSPM should detect:

### Example: iam-createaccesskey Scenario

**Expected CSPM Alerts:**
- IAM role can create access keys for privileged users
- Privilege escalation path detected
- Role has permissions on admin user
- Potential for credential theft

**MITRE ATT&CK Mapping:**
- **Tactic**: Privilege Escalation, Persistence
- **Technique**: T1098.001 - Account Manipulation: Additional Cloud Credentials

## Use Cases

### 1. CSPM Validation
Deploy known vulnerabilities and verify your CSPM detects them:
```bash
enable_single_account_cspm_toxic_combo_public_lambda_with_admin = true
terraform apply
# Check if CSPM alerts on: Lambda function publicly accessible + administrative permissions
```

### 2. Red Team Training
Practice exploitation techniques:
```bash
enable_single_account_privesc_self_escalation_to_admin_iam_005_iam_putrolepolicy = true
terraform apply
cd modules/scenarios/single-account/privesc-self-escalation/to-admin/iam-005-iam-putrolepolicy
./demo_attack.sh
```

### 3. Security Tool Testing
Deploy multiple scenarios and test if your tooling finds all paths:
```bash
enable_single_account_privesc_self_escalation_to_admin_iam_005_iam_putrolepolicy = true
enable_single_account_privesc_one_hop_to_admin_iam_002_iam_createaccesskey = true
enable_single_account_privesc_multi_hop_to_admin_multiple_paths_combined = true
terraform apply
# Test your security tools against these scenarios
```

### 4. Incident Response Practice
Create realistic compromise scenarios and practice detection/response:
```bash
enable_cross_account_dev_to_prod_multi_hop_lambda_invoke_update = true
terraform apply
# Practice using CloudTrail, GuardDuty, and other AWS security services
```

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

## Documentation Standards

- README files must include mermaid diagrams showing attack paths
- Use format: `graph LR` with nodes showing the escalation flow
- Document each step of the privilege escalation path
- Include CSPM detection guidance and MITRE ATT&CK mappings
- Provide usage instructions and prerequisites

## Future Roadmap

- [ ] Web interface for scenario management
- [x] Go CLI for easier configuration (`plabs` binary)
- [x] Interactive TUI dashboard
- [ ] More toxic combination scenarios
- [ ] GCP and Azure support
- [ ] Integration with popular CSPM tools
- [ ] Automated testing framework
- [ ] Video walkthroughs for each scenario

## Additional Resources

- [README.md](README.md) - Complete project documentation
- [RESTRUCTURE_PLAN.md](RESTRUCTURE_PLAN.md) - Architecture evolution details
- [IAM Vulnerable Project](https://github.com/bishopfox/iam-vulnerable) - Inspiration for single-account paths
- [Stratus Red Team](https://github.com/DataDog/stratus-red-team) - Similar approach for adversary emulation
- [MITRE ATT&CK Cloud Matrix](https://attack.mitre.org/matrices/enterprise/cloud/)