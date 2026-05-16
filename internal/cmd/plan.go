package cmd

import (
	"fmt"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	plabsaws "github.com/DataDog/pathfinding-labs/internal/aws"
	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/scenarios"
	"github.com/DataDog/pathfinding-labs/internal/terraform"
)

var planCmd = &cobra.Command{
	Use:   "plan",
	Short: "Preview changes before deployment",
	Long: `Show what changes would be made by deploying the current configuration.

This runs 'terraform plan' to preview the AWS resources that would be
created, modified, or destroyed.`,
	RunE: runPlan,
}

func runPlan(cmd *cobra.Command, args []string) error {
	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	// Check for enabled cross-account scenarios missing required environment profiles
	{
		discovery := newDiscovery(paths.ScenariosPath())
		allScenarios, discoverErr := discovery.DiscoverAll()
		if discoverErr == nil {
			enabledVars := cfg.Active().GetEnabledScenarioVars()
			var enabledScenarios []*scenarios.Scenario
			for _, s := range allScenarios {
				if enabledVars[s.Terraform.VariableName] {
					enabledScenarios = append(enabledScenarios, s)
				}
			}
			if envErrors := crossAccountEnvErrors(enabledScenarios, cfg.Active()); len(envErrors) > 0 {
				red := color.New(color.FgRed).SprintFunc()
				fmt.Println()
				fmt.Println(red("Cannot plan: some enabled scenarios require additional AWS account profiles:"))
				fmt.Println()
				for _, e := range envErrors {
					fmt.Println(e)
				}
				fmt.Println()
				return fmt.Errorf("missing required AWS account profile for cross-account scenario")
			}
		}
	}

	// Validate AWS credentials before running terraform
	if err := validateAWSCredentials(cfg); err != nil {
		return err
	}

	cyan := color.New(color.FgCyan).SprintFunc()
	yellow := color.New(color.FgYellow).SprintFunc()

	// Create runner early so we can check state for SLR detection.
	runner := terraform.NewRunner(paths.BinPath, paths.TerraformDir)
	runner.SetExtraEnv(cfg.Active().GetAttackerTFVarEnv())

	// Detect existing service-linked roles to avoid creation conflicts.
	// Rule: create=true UNLESS the SLR exists in AWS AND is NOT in Terraform state.
	slrStatus, err := plabsaws.DetectExistingServiceLinkedRoles(cfg.Active().AWS.Prod.Profile)
	if err != nil {
		fmt.Printf("Warning: could not detect existing service-linked roles: %v\n", err)
	} else {
		inState := &plabsaws.ServiceLinkedRoleStatus{}
		if runner.IsInitialized() {
			if stateResources, stateErr := runner.StateList(); stateErr == nil {
				inState = plabsaws.SLRInState(stateResources)
			}
		}
		cfg.Active().SLRFlags = &config.ServiceLinkedRoleFlags{
			CreateAutoScaling: !slrStatus.AutoScalingExists || inState.AutoScalingExists,
			CreateSpot:        !slrStatus.SpotExists || inState.SpotExists,
			CreateAppRunner:   !slrStatus.AppRunnerExists || inState.AppRunnerExists,
		}
	}

	// Sync tfvars from config before running terraform
	if err := cfg.Active().SyncTFVars(paths.TerraformDir); err != nil {
		return fmt.Errorf("failed to sync tfvars: %w", err)
	}

	fmt.Println()
	fmt.Println(cyan("Planning Pathfinding Labs deployment..."))

	// Show mode indicator only in dev mode
	if cfg.Active().DevMode {
		fmt.Println()
		fmt.Printf("%s Running in dev mode: %s\n", yellow("!"), cfg.Active().DevModePath)
	}
	fmt.Println()

	// Ensure terraform is initialized
	if !runner.IsInitialized() {
		fmt.Println("Running terraform init...")
		if err := runner.Init(); err != nil {
			return fmt.Errorf("terraform init failed: %w", err)
		}
		fmt.Println()
	}

	// Run plan
	if err := runner.Plan(); err != nil {
		return fmt.Errorf("terraform plan failed: %w", err)
	}

	fmt.Println()
	fmt.Printf("Run %s to apply these changes\n", cyan("plabs apply"))
	fmt.Println()

	return nil
}
