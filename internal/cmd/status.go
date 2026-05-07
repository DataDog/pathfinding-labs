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

	// Load config (single source of truth)
	cfg, _ := config.Load()

	fmt.Println()
	fmt.Println(bold("Environment Status"))
	fmt.Println()

	// Show dev mode warning and paths only when in dev mode
	if cfg != nil && cfg.DevMode {
		fmt.Printf("  %s %s\n", yellow("!"), yellow("DEV MODE - Using local repository"))
		fmt.Printf("  %s %s\n", dim("Repository:"), cfg.DevModePath)
		fmt.Println()
	}

	// Get terraform outputs and state to check deployment status
	runner := terraform.NewRunner(paths.BinPath, paths.TerraformDir)
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
	printEnvStatus := func(name, profile string) {
		if profile == "" {
			fmt.Printf("  %s %-12s %s\n", dim("o"), name+":", dim("not configured"))
			return
		}

		// Check if deployed: state first (primary), then outputs (fallback)
		// Environment module names in state are like "prod_environment", "dev_environment", "ops_environment"
		moduleName := name + "_environment"
		isDeployed := (deployedModules != nil && deployedModules[moduleName]) ||
			(outputs != nil && outputs.Exists(name+"_admin_user_for_cleanup_access_key_id"))

		if isDeployed {
			fmt.Printf("  %s %-12s %s %s\n", green("*"), name+":", profile, green("deployed"))
		} else {
			fmt.Printf("  %s %-12s %s %s\n", yellow("*"), name+":", profile, yellow("not deployed"))
		}
	}

	if cfg != nil {
		printEnvStatus("prod", cfg.AWS.Prod.Profile)
		printEnvStatus("dev", cfg.AWS.Dev.Profile)
		printEnvStatus("ops", cfg.AWS.Ops.Profile)
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
	fmt.Println(dim("---------------------------------------------------------"))

	// Discover scenarios
	discovery := newDiscovery(paths.ScenariosPath())
	allScenarios, err := discovery.DiscoverAll()
	if err != nil {
		return fmt.Errorf("failed to discover scenarios: %w", err)
	}

	// Get enabled status from config (single source of truth)
	enabledVars := make(map[string]bool)
	if cfg != nil {
		enabledVars = cfg.GetEnabledScenarioVars()
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
		fmt.Printf("%s Enabled Scenarios (%d)\n", cyan("---"), len(enabled))
		fmt.Println()

		warnStyle := color.New(color.FgHiYellow).SprintFunc()

		for _, s := range enabled {
			deployed := isScenarioDeployed(s, outputs, deployedModules)

			// Status indicator
			var status string
			if deployed {
				status = green("deployed")
			} else {
				status = yellow("pending")
			}

			// Build line - use UniqueID for clarity
			line := fmt.Sprintf("  %s %-20s %s", green("*"), s.UniqueID(), status)

			if showCost && s.CostEstimate != "" {
				line += fmt.Sprintf(" [%s]", s.CostEstimate)
			}

			// Demo active indicator
			if s.HasDemoActive() {
				line += " " + warnStyle("\u26a0 demo active")
			}

			fmt.Println(line)
		}
	} else {
		fmt.Println(dim("No scenarios enabled"))
		fmt.Println()
		fmt.Printf("Use %s to browse and enable scenarios interactively\n", cyan("plabs"))
		fmt.Printf("  or %s to enable via command line\n", cyan("plabs enable iam-002-to-admin"))
	}

	fmt.Println()

	// Summary
	deployedCount := 0
	pendingCount := 0
	demoActiveCount := 0
	var runningCost float64
	for _, s := range enabled {
		if isScenarioDeployed(s, outputs, deployedModules) {
			deployedCount++
			runningCost += parseCostString(s.CostEstimate)
		} else {
			pendingCount++
		}
		if s.HasDemoActive() {
			demoActiveCount++
		}
	}

	costColor := color.New(color.FgHiYellow).SprintFunc()

	fmt.Println(dim("---------------------------------------------------------"))

	summaryParts := []string{
		fmt.Sprintf("Total: %d enabled", len(enabled)),
		fmt.Sprintf("%s deployed", green(fmt.Sprintf("%d", deployedCount))),
		fmt.Sprintf("%s pending", yellow(fmt.Sprintf("%d", pendingCount))),
	}

	if demoActiveCount > 0 {
		summaryParts = append(summaryParts, fmt.Sprintf("%s demo active", costColor(fmt.Sprintf("%d \u26a0", demoActiveCount))))
	}

	if runningCost > 0 {
		costPerDay := runningCost / 30
		summaryParts = append(summaryParts,
			fmt.Sprintf("Running cost: %s %s",
				costColor(fmt.Sprintf("$%.0f/mo", runningCost)),
				dim(fmt.Sprintf("($%.2f/day)", costPerDay))))
	} else {
		summaryParts = append(summaryParts, fmt.Sprintf("Running cost: %s", dim("$0/mo")))
	}

	fmt.Println(strings.Join(summaryParts, " | "))

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
