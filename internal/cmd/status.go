package cmd

import (
	"fmt"
	"strings"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/scenarios"
	"github.com/DataDog/pathfinding-labs/internal/terraform"
)

var statusCmd = &cobra.Command{
	Use:   "status",
	Short: "Show enabled scenarios and deployment status",
	Long: `Show which scenarios are enabled and their deployment status.

This will display:
  - Enabled scenarios
  - Deployment status (deployed vs pending)
  - Cost estimates (with --cost flag)`,
	RunE: runStatus,
}

var showCost bool

func init() {
	statusCmd.Flags().BoolVar(&showCost, "cost", false, "Show cost estimates")
}

func runStatus(cmd *cobra.Command, args []string) error {
	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	// Colors
	green := color.New(color.FgGreen).SprintFunc()
	yellow := color.New(color.FgYellow).SprintFunc()
	cyan := color.New(color.FgCyan).SprintFunc()
	dim := color.New(color.Faint).SprintFunc()
	bold := color.New(color.Bold).SprintFunc()

	// Load config to show environment status
	cfg, _ := config.Load(paths.ConfigPath)

	fmt.Println()
	fmt.Println(bold("Environment Status"))
	fmt.Println()

	// Show dev mode warning and paths
	if isDevMode() {
		fmt.Printf("  %s %s\n", yellow("⚠"), yellow("DEV MODE - Using local repository"))
		fmt.Printf("  %s %s\n", dim("Repository:"), paths.RepoPath)
		fmt.Printf("  %s %s\n", dim("TFVars:"), paths.TFVarsPath)
		fmt.Println()
	}

	// Get terraform outputs and state to check deployment status
	runner := terraform.NewRunner(paths.BinPath, paths.RepoPath)
	var outputs terraform.Outputs
	var deployedModules map[string]bool

	if runner.IsInitialized() {
		outputJSON, err := runner.OutputJSON()
		if err == nil && outputJSON != "" {
			outputs, _ = terraform.ParseOutputs(outputJSON)
		}
		// Also get deployed modules from state (more reliable for scenarios without outputs)
		deployedModules = runner.GetDeployedModules()
	}

	// Show environment configuration and deployment status
	printEnvStatus := func(name, accountID, profile string) {
		if accountID == "" {
			fmt.Printf("  %s %-12s %s\n", dim("○"), name+":", dim("not configured"))
			return
		}

		// Check if deployed: state first (primary), then outputs (fallback)
		// Environment module names in state are like "prod_environment", "dev_environment", "ops_environment"
		moduleName := name + "_environment"
		isDeployed := (deployedModules != nil && deployedModules[moduleName]) ||
			(outputs != nil && outputs.Exists(name+"_admin_user_for_cleanup_access_key_id"))

		if isDeployed {
			fmt.Printf("  %s %-12s %s (profile: %s) %s\n", green("●"), name+":", accountID, profile, green("deployed"))
		} else {
			fmt.Printf("  %s %-12s %s (profile: %s) %s\n", yellow("●"), name+":", accountID, profile, yellow("not deployed"))
		}
	}

	if cfg != nil {
		printEnvStatus("prod", cfg.ProdAccountID, cfg.ProdProfile)
		printEnvStatus("dev", cfg.DevAccountID, cfg.DevProfile)
		printEnvStatus("ops", cfg.OpsAccountID, cfg.OpsProfile)
	} else {
		fmt.Printf("  %s\n", dim("No configuration found. Run 'plabs init' to configure."))
	}

	// Show account mode
	fmt.Println()
	if cfg != nil && cfg.IsMultiAccountMode() {
		fmt.Printf("  Accounts: %s (cross-account scenarios available)\n", cyan("multi-account"))
	} else {
		fmt.Printf("  Accounts: %s (cross-account scenarios unavailable)\n", yellow("single-account"))
	}

	fmt.Println()
	fmt.Println(dim("─────────────────────────────────────────────────────────────"))

	// Discover scenarios
	discovery := scenarios.NewDiscovery(paths.ScenariosPath())
	allScenarios, err := discovery.DiscoverAll()
	if err != nil {
		return fmt.Errorf("failed to discover scenarios: %w", err)
	}

	// Get enabled status
	tfvars := terraform.NewTFVars(paths.TFVarsPath)
	enabledVars, err := tfvars.GetEnabledScenarios()
	if err != nil {
		enabledVars = make(map[string]bool)
	}

	fmt.Println()
	fmt.Println(bold("Scenario Status"))
	fmt.Println()

	// Separate enabled and disabled
	var enabled []*scenarios.Scenario
	var disabled []*scenarios.Scenario

	for _, s := range allScenarios {
		if enabledVars[s.Terraform.VariableName] {
			enabled = append(enabled, s)
		} else {
			disabled = append(disabled, s)
		}
	}

	// Show enabled scenarios
	if len(enabled) > 0 {
		fmt.Printf("%s Enabled Scenarios (%d)\n", cyan("───"), len(enabled))
		fmt.Println()

		for _, s := range enabled {
			deployed := isScenarioDeployed(s, outputs, deployedModules)

			// Status indicator
			var status string
			if deployed {
				status = green("✓ deployed")
			} else {
				status = yellow("○ pending")
			}

			// Build line - use UniqueID for clarity
			line := fmt.Sprintf("  %s %-20s %s", green("●"), s.UniqueID(), status)

			if showCost && s.CostEstimate != "" {
				line += fmt.Sprintf(" [%s]", s.CostEstimate)
			}

			fmt.Println(line)
		}
	} else {
		fmt.Println(dim("No scenarios enabled"))
		fmt.Println()
		fmt.Printf("Use %s to enable scenarios\n", cyan("plabs enable <id>"))
	}

	fmt.Println()

	// Summary
	deployedCount := 0
	pendingCount := 0
	for _, s := range enabled {
		if isScenarioDeployed(s, outputs, deployedModules) {
			deployedCount++
		} else {
			pendingCount++
		}
	}

	fmt.Println(dim("─────────────────────────────────────────────────────────────"))
	fmt.Printf("Total: %d enabled | %s deployed | %s pending\n",
		len(enabled),
		green(fmt.Sprintf("%d", deployedCount)),
		yellow(fmt.Sprintf("%d", pendingCount)))

	if pendingCount > 0 {
		fmt.Println()
		fmt.Printf("Run %s to deploy pending scenarios\n", cyan("plabs deploy"))
	}

	fmt.Println()

	return nil
}

func getScenarioOutputName(s *scenarios.Scenario) string {
	// The output name is typically the variable name without the "enable_" prefix
	return strings.TrimPrefix(s.Terraform.VariableName, "enable_")
}

// isScenarioDeployed checks if a scenario is deployed using state (primary) and outputs (fallback)
func isScenarioDeployed(s *scenarios.Scenario, outputs terraform.Outputs, deployedModules map[string]bool) bool {
	outputName := getScenarioOutputName(s)

	// Primary: check terraform state (source of truth for what's actually deployed)
	if deployedModules != nil && deployedModules[outputName] {
		return true
	}

	// Fallback: check outputs (for edge cases where state parsing might miss something)
	if outputs != nil && outputs.IsDeployed(outputName) {
		return true
	}

	return false
}
