package cmd

import (
	"fmt"
	"strings"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	"github.com/DataDog/pathfinding-labs/internal/demo"
	"github.com/DataDog/pathfinding-labs/internal/repo"
	"github.com/DataDog/pathfinding-labs/internal/scenarios"
	"github.com/DataDog/pathfinding-labs/internal/terraform"
)

var demoCmd = &cobra.Command{
	Use:   "demo <scenario-id>",
	Short: "Run a demo attack for a scenario",
	Long: `Execute the demo_attack.sh script for an enabled and deployed scenario.

The demo script will:
  - Use credentials from terraform outputs
  - Execute the attack step by step
  - Show explanations at each stage
  - Verify successful privilege escalation

Examples:
  plabs demo iam-002          # Run demo for iam-002 scenario
  plabs demo --list           # List available demos`,
	Args: func(cmd *cobra.Command, args []string) error {
		listDemos, _ := cmd.Flags().GetBool("list")
		if !listDemos && len(args) < 1 {
			return fmt.Errorf("requires a scenario ID (or --list flag)")
		}
		return nil
	},
	RunE: runDemo,
}

var listDemos bool

func init() {
	demoCmd.Flags().BoolVar(&listDemos, "list", false, "List available demos")
}

func runDemo(cmd *cobra.Command, args []string) error {
	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	// Discover scenarios
	discovery := scenarios.NewDiscovery(paths.ScenariosPath())

	// Get enabled and deployed status
	tfvars := terraform.NewTFVars(paths.TFVarsPath)
	enabledVars, err := tfvars.GetEnabledScenarios()
	if err != nil {
		enabledVars = make(map[string]bool)
	}

	// Get deployment status
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

	green := color.New(color.FgGreen).SprintFunc()
	yellow := color.New(color.FgYellow).SprintFunc()
	cyan := color.New(color.FgCyan).SprintFunc()
	dim := color.New(color.Faint).SprintFunc()

	if listDemos {
		return listAvailableDemos(discovery, enabledVars, outputs, deployedModules, paths)
	}

	// Find the scenario - use FindEnabledByID to handle cases where multiple scenarios
	// share the same ID (e.g., sts-001 for both to-admin and to-bucket)
	scenarioID := args[0]
	scenario, err := discovery.FindEnabledByID(scenarioID, enabledVars)
	if err != nil {
		return fmt.Errorf("failed to find scenario: %w", err)
	}

	if scenario == nil {
		fmt.Printf("Scenario '%s' not found.\n", scenarioID)
		fmt.Println()
		fmt.Println("Use 'plabs scenarios list' to see available scenarios")
		return fmt.Errorf("scenario not found")
	}

	// Check if scenario has a demo script
	if !scenario.HasDemo() {
		return fmt.Errorf("scenario '%s' does not have a demo script", scenario.UniqueID())
	}

	// Check if enabled (this should always be true since FindEnabledByID prefers enabled scenarios,
	// but we check anyway in case no variant is enabled)
	if !enabledVars[scenario.Terraform.VariableName] {
		fmt.Println()
		fmt.Printf("%s Scenario '%s' is not enabled.\n", yellow("!"), scenario.UniqueID())
		fmt.Println()
		fmt.Printf("Enable it first: %s\n", cyan(fmt.Sprintf("plabs enable %s", scenario.UniqueID())))
		return fmt.Errorf("scenario not enabled")
	}

	// Check if deployed (state is primary, outputs as fallback)
	outputName := strings.TrimPrefix(scenario.Terraform.VariableName, "enable_")
	isDeployed := (deployedModules != nil && deployedModules[outputName]) || (outputs != nil && outputs.IsDeployed(outputName))
	if !isDeployed {
		fmt.Println()
		fmt.Printf("%s Scenario '%s' is enabled but not deployed.\n", yellow("!"), scenario.UniqueID())
		fmt.Println()
		fmt.Printf("Deploy it first: %s\n", cyan("plabs deploy"))
		return fmt.Errorf("scenario not deployed")
	}

	// Run the demo
	fmt.Println()
	fmt.Println(cyan("════════════════════════════════════════════════════════════"))
	fmt.Printf(cyan("  Running Demo: %s\n"), scenario.UniqueID())
	fmt.Println(cyan("════════════════════════════════════════════════════════════"))
	fmt.Println()
	fmt.Printf("Description: %s\n", scenario.Description)
	fmt.Println()
	fmt.Println(dim("─────────────────────────────────────────────────────────────"))
	fmt.Println()

	demoRunner := demo.NewRunner(paths.RepoPath)
	if err := demoRunner.RunDemo(scenario.DirPath); err != nil {
		return err
	}

	fmt.Println()
	fmt.Println(green("════════════════════════════════════════════════════════════"))
	fmt.Println(green("  Demo Complete!"))
	fmt.Println(green("════════════════════════════════════════════════════════════"))
	fmt.Println()
	fmt.Printf("Run %s to clean up demo artifacts\n", cyan(fmt.Sprintf("plabs cleanup %s", scenario.UniqueID())))
	fmt.Println()

	return nil
}

func listAvailableDemos(discovery *scenarios.Discovery, enabledVars map[string]bool, outputs terraform.Outputs, deployedModules map[string]bool, paths *repo.Paths) error {
	allScenarios, err := discovery.DiscoverAll()
	if err != nil {
		return fmt.Errorf("failed to discover scenarios: %w", err)
	}

	green := color.New(color.FgGreen).SprintFunc()
	yellow := color.New(color.FgYellow).SprintFunc()
	dim := color.New(color.Faint).SprintFunc()
	bold := color.New(color.Bold).SprintFunc()

	fmt.Println()
	fmt.Println(bold("Available Demos"))
	fmt.Println()

	var available []*scenarios.Scenario
	var notDeployed []*scenarios.Scenario
	var notEnabled []*scenarios.Scenario

	for _, s := range allScenarios {
		if !s.HasDemo() {
			continue
		}

		isEnabled := enabledVars[s.Terraform.VariableName]
		outputName := strings.TrimPrefix(s.Terraform.VariableName, "enable_")
		// Check state first (primary), then outputs (fallback)
		isDeployed := (deployedModules != nil && deployedModules[outputName]) || (outputs != nil && outputs.IsDeployed(outputName))

		if isEnabled && isDeployed {
			available = append(available, s)
		} else if isEnabled && !isDeployed {
			notDeployed = append(notDeployed, s)
		} else {
			notEnabled = append(notEnabled, s)
		}
	}

	if len(available) > 0 {
		fmt.Printf("%s Ready to Run (%d)\n", green("●"), len(available))
		for _, s := range available {
			fmt.Printf("  %s %-20s %s\n", green("✓"), s.UniqueID(), truncate(s.Description, 40))
		}
		fmt.Println()
	}

	if len(notDeployed) > 0 {
		fmt.Printf("%s Enabled but not deployed (%d)\n", yellow("○"), len(notDeployed))
		for _, s := range notDeployed {
			fmt.Printf("  %s %s\n", yellow("○"), s.UniqueID())
		}
		fmt.Println()
	}

	if len(notEnabled) > 0 {
		fmt.Printf("%s Not enabled (%d)\n", dim("○"), len(notEnabled))
		// Only show first 5
		for i, s := range notEnabled {
			if i >= 5 {
				fmt.Printf("  %s ... and %d more\n", dim("○"), len(notEnabled)-5)
				break
			}
			fmt.Printf("  %s %s\n", dim("○"), s.UniqueID())
		}
		fmt.Println()
	}

	fmt.Println(dim("─────────────────────────────────────────────────────────────"))
	fmt.Printf("Run a demo: plabs demo <scenario-id>\n")
	fmt.Println()

	return nil
}
