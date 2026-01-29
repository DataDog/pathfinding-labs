package cmd

import (
	"fmt"
	"strings"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	"github.com/DataDog/pathfinding-labs/internal/demo"
	"github.com/DataDog/pathfinding-labs/internal/scenarios"
	"github.com/DataDog/pathfinding-labs/internal/terraform"
)

var cleanupCmd = &cobra.Command{
	Use:   "cleanup <scenario-id>",
	Short: "Clean up demo artifacts for a scenario",
	Long: `Execute the cleanup_attack.sh script for a scenario.

This removes artifacts created during demo execution (like access keys,
modified policies, etc.) while preserving the infrastructure.

Examples:
  plabs cleanup iam-002`,
	Args: cobra.ExactArgs(1),
	RunE: runCleanup,
}

func runCleanup(cmd *cobra.Command, args []string) error {
	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	// Discover scenarios
	discovery := scenarios.NewDiscovery(paths.ScenariosPath())

	// Get enabled status
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

	// Check if scenario has a cleanup script
	if !scenario.HasCleanup() {
		return fmt.Errorf("scenario '%s' does not have a cleanup script", scenario.UniqueID())
	}

	// Check if enabled
	if !enabledVars[scenario.Terraform.VariableName] {
		fmt.Println()
		fmt.Printf("%s Scenario '%s' is not enabled.\n", yellow("!"), scenario.UniqueID())
		fmt.Println()
		fmt.Println(dim("Nothing to clean up."))
		return nil
	}

	// Check if deployed (state is primary, outputs as fallback)
	outputName := strings.TrimPrefix(scenario.Terraform.VariableName, "enable_")
	isDeployed := (deployedModules != nil && deployedModules[outputName]) || (outputs != nil && outputs.IsDeployed(outputName))
	if !isDeployed {
		fmt.Println()
		fmt.Printf("%s Scenario '%s' is not deployed.\n", yellow("!"), scenario.UniqueID())
		fmt.Println()
		fmt.Println(dim("Nothing to clean up."))
		return nil
	}

	// Run the cleanup
	fmt.Println()
	fmt.Println(cyan("════════════════════════════════════════════════════════════"))
	fmt.Printf(cyan("  Cleaning up: %s\n"), scenario.UniqueID())
	fmt.Println(cyan("════════════════════════════════════════════════════════════"))
	fmt.Println()
	fmt.Println(dim("─────────────────────────────────────────────────────────────"))
	fmt.Println()

	demoRunner := demo.NewRunner(paths.RepoPath)
	if err := demoRunner.RunCleanup(scenario.DirPath); err != nil {
		return err
	}

	fmt.Println()
	fmt.Println(green("════════════════════════════════════════════════════════════"))
	fmt.Println(green("  Cleanup Complete!"))
	fmt.Println(green("════════════════════════════════════════════════════════════"))
	fmt.Println()

	return nil
}
