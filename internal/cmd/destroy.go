package cmd

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/repo"
	"github.com/DataDog/pathfinding-labs/internal/scenarios"
	"github.com/DataDog/pathfinding-labs/internal/terraform"
)

var destroyCmd = &cobra.Command{
	Use:   "destroy",
	Short: "Destroy deployed infrastructure",
	Long: `Destroy Pathfinding Labs infrastructure.

By default, this destroys ALL infrastructure including base environment modules.

To remove only scenarios (keeping base infrastructure):
  plabs destroy --scenarios-only

To destroy everything:
  plabs destroy --all

WARNING: Use with caution. This removes AWS resources.`,
	RunE: runDestroy,
}

var (
	destroyAutoApprove   bool
	destroyAll           bool
	destroyScenariosOnly bool
)

func init() {
	destroyCmd.Flags().BoolVarP(&destroyAutoApprove, "auto-approve", "y", false, "Skip interactive approval")
	destroyCmd.Flags().BoolVar(&destroyAll, "all", false, "Destroy ALL infrastructure including base environment")
	destroyCmd.Flags().BoolVar(&destroyScenariosOnly, "scenarios-only", false, "Only remove scenarios (disable all + deploy)")
}

func runDestroy(cmd *cobra.Command, args []string) error {
	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	cfg, _ := config.Load()

	red := color.New(color.FgRed).SprintFunc()
	yellow := color.New(color.FgYellow).SprintFunc()
	green := color.New(color.FgGreen).SprintFunc()
	cyan := color.New(color.FgCyan).SprintFunc()

	// Show mode indicator only in dev mode
	if cfg != nil && cfg.DevMode {
		fmt.Println()
		fmt.Printf("%s Running in dev mode: %s\n", yellow("!"), cfg.DevModePath)
	}

	// Require explicit flag (check before validating credentials)
	if !destroyAll && !destroyScenariosOnly {
		fmt.Println()
		fmt.Println(yellow("Please specify what to destroy:"))
		fmt.Println()
		fmt.Printf("  %s  Remove only scenarios (keeps base infrastructure)\n", cyan("plabs destroy --scenarios-only"))
		fmt.Printf("  %s             Destroy ALL infrastructure\n", cyan("plabs destroy --all"))
		fmt.Println()
		return nil
	}

	// Validate AWS credentials before running terraform
	if err := validateAWSCredentials(cfg); err != nil {
		return err
	}

	// Handle --scenarios-only: disable all scenarios and deploy
	if destroyScenariosOnly {
		return destroyScenarios(paths, cfg, green, yellow)
	}

	// Handle --all: full terraform destroy
	return destroyEverything(paths, cfg, red, yellow, green)
}

func destroyScenarios(paths *repo.Paths, cfg *config.Config, green, yellow func(a ...interface{}) string) error {
	fmt.Println()
	fmt.Println(yellow("Removing all scenarios (keeping base infrastructure)..."))
	fmt.Println()

	// Discover and disable all scenarios
	discovery := scenarios.NewDiscovery(paths.ScenariosPath())
	allScenarios, err := discovery.DiscoverAll()
	if err != nil {
		return fmt.Errorf("failed to discover scenarios: %w", err)
	}

	// Get current enabled status from config
	enabledVars := cfg.GetEnabledScenarioVars()

	var toDisable []string
	for _, s := range allScenarios {
		if enabledVars[s.Terraform.VariableName] {
			toDisable = append(toDisable, s.Terraform.VariableName)
		}
	}

	if len(toDisable) == 0 {
		fmt.Println(yellow("No scenarios are currently enabled."))
		return nil
	}

	fmt.Printf("Disabling %d scenario(s)...\n", len(toDisable))

	// Disable all scenarios in config
	for _, varName := range toDisable {
		cfg.DisableScenario(varName)
	}

	// Save config
	if err := cfg.Save(); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	// Regenerate terraform.tfvars
	if err := cfg.SyncTFVars(paths.TerraformDir); err != nil {
		return fmt.Errorf("failed to sync terraform.tfvars: %w", err)
	}

	// Run terraform apply to remove the scenarios
	fmt.Println()
	fmt.Println("Running terraform apply to remove scenarios...")
	fmt.Println()

	runner := terraform.NewRunner(paths.BinPath, paths.TerraformDir)
	if err := runner.Apply(true); err != nil {
		return fmt.Errorf("terraform apply failed: %w", err)
	}

	fmt.Println()
	fmt.Println(green("========================================================"))
	fmt.Println(green("  All scenarios removed! Base infrastructure preserved."))
	fmt.Println(green("========================================================"))
	fmt.Println()

	return nil
}

func destroyEverything(paths *repo.Paths, cfg *config.Config, red, yellow, green func(a ...interface{}) string) error {
	fmt.Println()
	fmt.Println(red("+----------------------------------------------------------+"))
	fmt.Println(red("|                         WARNING                          |"))
	fmt.Println(red("|  This will destroy ALL deployed Pathfinding Labs resources|"))
	fmt.Println(red("|  including base environment infrastructure.              |"))
	fmt.Println(red("+----------------------------------------------------------+"))
	fmt.Println()

	// Create runner
	runner := terraform.NewRunner(paths.BinPath, paths.TerraformDir)

	// Check if there's anything to destroy
	if !runner.IsInitialized() {
		fmt.Println(yellow("Terraform is not initialized. Nothing to destroy."))
		return nil
	}

	// Get list of resources
	resources, err := runner.StateList()
	if err != nil {
		return fmt.Errorf("failed to list resources: %w", err)
	}

	if len(resources) == 0 {
		fmt.Println(yellow("No resources found. Nothing to destroy."))
		return nil
	}

	fmt.Printf("Found %d resources to destroy.\n", len(resources))
	fmt.Println()

	// Confirm unless auto-approve
	if !destroyAutoApprove {
		fmt.Print(red("Type 'destroy' to confirm: "))

		reader := bufio.NewReader(os.Stdin)
		response, err := reader.ReadString('\n')
		if err != nil {
			return err
		}

		response = strings.ToLower(strings.TrimSpace(response))
		if response != "destroy" {
			fmt.Println("Destroy cancelled.")
			return nil
		}
	}

	// If attacker is in IAM user mode, switch to setup profile for destroy
	// The IAM user can't destroy itself, so we need the original profile
	if cfg != nil && cfg.AWS.Attacker.Mode == "iam-user" && cfg.AWS.Attacker.SetupProfile != "" {
		fmt.Println("Switching attacker account to setup profile for teardown...")
		originalIAMAccessKey := cfg.AWS.Attacker.IAMAccessKeyID
		originalIAMSecretKey := cfg.AWS.Attacker.IAMSecretKey

		// Temporarily clear IAM creds and set profile for destroy
		cfg.AWS.Attacker.IAMAccessKeyID = ""
		cfg.AWS.Attacker.IAMSecretKey = ""
		cfg.AWS.Attacker.Profile = cfg.AWS.Attacker.SetupProfile

		if err := cfg.SyncTFVars(paths.TerraformDir); err != nil {
			// Restore on failure
			cfg.AWS.Attacker.IAMAccessKeyID = originalIAMAccessKey
			cfg.AWS.Attacker.IAMSecretKey = originalIAMSecretKey
			return fmt.Errorf("failed to sync tfvars for destroy: %w", err)
		}
	}

	// Destroy
	fmt.Println()
	fmt.Println("Destroying infrastructure...")
	fmt.Println()

	if err := runner.Destroy(true); err != nil {
		return fmt.Errorf("terraform destroy failed: %w", err)
	}

	// Clean up attacker IAM user credentials from config after successful destroy
	if cfg != nil && cfg.AWS.Attacker.Mode == "iam-user" {
		cfg.AWS.Attacker.IAMAccessKeyID = ""
		cfg.AWS.Attacker.IAMSecretKey = ""
		if err := cfg.Save(); err != nil {
			fmt.Printf("%s Failed to clean up attacker credentials from config: %v\n", yellow("!"), err)
		}
	}

	fmt.Println()
	fmt.Println(green("========================================================"))
	fmt.Println(green("  All infrastructure destroyed!"))
	fmt.Println(green("========================================================"))
	fmt.Println()

	return nil
}
