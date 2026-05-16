package cmd

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	plabsaws "github.com/DataDog/pathfinding-labs/internal/aws"
	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/scenarios"
	"github.com/DataDog/pathfinding-labs/internal/terraform"
)

var deployCmd = &cobra.Command{
	Use:     "apply",
	Aliases: []string{"deploy"},
	Short:   "Apply enabled scenarios to AWS",
	Long: `Apply all enabled scenarios to your AWS account(s).

This runs 'terraform apply' to create the AWS resources for enabled scenarios.

You will be prompted for confirmation unless you use the --auto-approve flag.`,
	RunE: runDeploy,
}

var autoApprove bool

func init() {
	deployCmd.Flags().BoolVarP(&autoApprove, "auto-approve", "y", false, "Skip interactive approval")
}

func runDeploy(cmd *cobra.Command, args []string) error {
	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	// Check for enabled scenarios with missing required environment profiles or config before doing any AWS calls
	{
		discovery := newDiscovery(paths.ScenariosPath())
		allScenarios, discoverErr := discovery.DiscoverAll()
		if discoverErr == nil {
			red := color.New(color.FgRed).SprintFunc()
			enabledVars := cfg.Active().GetEnabledScenarioVars()
			var enabledScenarios []*scenarios.Scenario
			for _, s := range allScenarios {
				if enabledVars[s.Terraform.VariableName] {
					enabledScenarios = append(enabledScenarios, s)
				}
			}

			if envErrors := crossAccountEnvErrors(enabledScenarios, cfg.Active()); len(envErrors) > 0 {
				fmt.Println()
				fmt.Println(red("Cannot deploy: some enabled scenarios require additional AWS account profiles:"))
				fmt.Println()
				for _, e := range envErrors {
					fmt.Println(e)
				}
				fmt.Println()
				return fmt.Errorf("missing required AWS account profile for cross-account scenario")
			}

			var configErrors []string
			for _, s := range enabledScenarios {
				for _, cfgKey := range s.Config {
					if cfgKey.Required {
						val, _ := cfg.Active().GetScenarioConfig(s.Name, cfgKey.Key)
						if val == "" {
							configErrors = append(configErrors, fmt.Sprintf(
								"  %s: key %q is required\n    Set with: plabs config %s set %s <value>",
								s.Name, cfgKey.Key, s.Name, cfgKey.Key))
						}
					}
				}
			}
			if len(configErrors) > 0 {
				fmt.Println()
				fmt.Println(red("Cannot deploy: some enabled scenarios have missing required configuration:"))
				fmt.Println()
				for _, e := range configErrors {
					fmt.Println(e)
				}
				fmt.Println()
				return fmt.Errorf("missing required scenario configuration")
			}
		}
	}

	// Validate AWS credentials before running terraform
	if err := validateAWSCredentials(cfg); err != nil {
		return err
	}

	cyan := color.New(color.FgCyan).SprintFunc()
	yellow := color.New(color.FgYellow).SprintFunc()
	green := color.New(color.FgGreen).SprintFunc()
	dim := color.New(color.Faint).SprintFunc()

	// Create runner early — needed for state inspection and bootstrap.
	// Inject attacker IAM credentials as TF_VAR_* env vars so they are never
	// written to terraform.tfvars on disk (mirrors TUI behavior).
	runner := terraform.NewRunner(paths.BinPath, paths.TerraformDir)
	runner.SetExtraEnv(cfg.Active().GetAttackerTFVarEnv())

	// Detect which service-linked roles already exist in the prod account
	// so Terraform doesn't try to create duplicates.
	//
	// Rule: create=true UNLESS the SLR exists in AWS AND is NOT in Terraform state.
	// If Terraform already owns the SLR in state, keep create=true — flipping it to
	// false would make count=0 and cause Terraform to destroy the SLR.
	slrStatus, err := plabsaws.DetectExistingServiceLinkedRoles(cfg.Active().AWS.Prod.Profile)
	if err != nil {
		// Non-fatal: if detection fails, default to creating all SLRs (original behavior)
		fmt.Printf("Warning: could not detect existing service-linked roles: %v\n", err)
		fmt.Println("Terraform will attempt to create all service-linked roles.")
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

	// Bootstrap attacker IAM user if needed
	if cfg.Active().HasAttackerAccount() && cfg.Active().AWS.Attacker.Mode == "iam-user" && cfg.Active().AWS.Attacker.IAMAccessKeyID == "" {
		fmt.Println()
		fmt.Println(cyan("Bootstrapping attacker account IAM admin user..."))
		fmt.Println()

		if err := bootstrapAttackerIAMUser(runner, cfg); err != nil {
			return fmt.Errorf("attacker IAM user bootstrap failed: %w", err)
		}

		// Re-sync tfvars now that bootstrap credentials are stored
		if err := cfg.Active().SyncTFVars(paths.TerraformDir); err != nil {
			return fmt.Errorf("failed to sync tfvars after bootstrap: %w", err)
		}

		// Re-inject credentials into runner now that they exist
		runner.SetExtraEnv(cfg.Active().GetAttackerTFVarEnv())

		fmt.Println(green("Attacker IAM admin user bootstrapped successfully."))
		fmt.Println()
	}

	fmt.Println()
	fmt.Println(cyan("Applying Pathfinding Labs..."))

	// Show mode indicator only in dev mode
	if cfg.Active().DevMode {
		fmt.Println()
		fmt.Printf("%s Running in dev mode: %s\n", yellow("!"), cfg.Active().DevModePath)
	}
	fmt.Println()

	// Show enabled scenarios count from config
	enabledCount := len(cfg.Active().Scenarios.Enabled)

	fmt.Printf("Enabled scenarios: %d\n", enabledCount)
	if enabledCount == 0 {
		fmt.Println(yellow("No scenarios are currently enabled."))
		fmt.Println("Running terraform apply to sync state (this may destroy previously enabled scenarios)...")
	}
	fmt.Println()

	// Show terraform directory
	fmt.Printf("%s Terraform directory: %s\n", dim("->"), paths.TerraformDir)
	fmt.Println()

	// Ensure terraform is initialized
	if !runner.IsInitialized() {
		fmt.Println("Running terraform init...")
		if err := runner.Init(); err != nil {
			return fmt.Errorf("terraform init failed: %w", err)
		}
		fmt.Println()
	}

	// Show what will be deployed
	fmt.Println("Running terraform plan...")
	fmt.Println()
	if err := runner.Plan(); err != nil {
		return fmt.Errorf("terraform plan failed: %w", err)
	}

	// Confirm unless auto-approve
	if !autoApprove {
		fmt.Println()
		fmt.Print(yellow("Do you want to apply these changes? [y/N]: "))

		reader := bufio.NewReader(os.Stdin)
		response, err := reader.ReadString('\n')
		if err != nil {
			return err
		}

		response = strings.ToLower(strings.TrimSpace(response))
		if response != "y" && response != "yes" {
			fmt.Println("Apply cancelled.")
			return nil
		}
	}

	// Apply
	fmt.Println()
	fmt.Println("Applying changes...")
	fmt.Println()

	if err := runner.Apply(true); err != nil {
		return fmt.Errorf("terraform apply failed: %w", err)
	}

	fmt.Println()
	fmt.Println(green("========================================================"))
	fmt.Println(green("  Apply complete!"))
	fmt.Println(green("========================================================"))
	fmt.Println()
	fmt.Printf("Run %s to see deployment status\n", cyan("plabs status"))
	fmt.Printf("Run %s to run a demo attack\n", cyan("plabs demo <scenario-id>"))
	fmt.Println()

	return nil
}

// bootstrapAttackerIAMUser performs the one-time bootstrap of the attacker IAM admin user.
// It uses the setup profile to deploy the attacker environment module, extracts the
// generated IAM credentials, and stores them in the config for future use.
func bootstrapAttackerIAMUser(runner *terraform.Runner, cfg *config.Config) error {
	// Ensure terraform is initialized before bootstrap
	if !runner.IsInitialized() {
		if err := runner.Init(); err != nil {
			return fmt.Errorf("terraform init failed: %w", err)
		}
	}

	// Apply only the attacker environment module
	if err := runner.ApplyTarget("module.attacker_environment", true); err != nil {
		return fmt.Errorf("failed to apply attacker environment: %w", err)
	}

	// Extract credentials from terraform output
	outputJSON, err := runner.OutputJSON()
	if err != nil {
		return fmt.Errorf("failed to read terraform outputs: %w", err)
	}

	var outputs map[string]struct {
		Value     interface{} `json:"value"`
		Sensitive bool        `json:"sensitive"`
	}
	if err := json.Unmarshal([]byte(outputJSON), &outputs); err != nil {
		return fmt.Errorf("failed to parse terraform outputs: %w", err)
	}

	accessKeyOutput, ok := outputs["attacker_admin_user_access_key_id"]
	if !ok {
		return fmt.Errorf("attacker_admin_user_access_key_id output not found")
	}
	secretKeyOutput, ok := outputs["attacker_admin_user_secret_access_key"]
	if !ok {
		return fmt.Errorf("attacker_admin_user_secret_access_key output not found")
	}

	accessKeyID, ok := accessKeyOutput.Value.(string)
	if !ok || accessKeyID == "" {
		return fmt.Errorf("attacker_admin_user_access_key_id output is empty or not a string")
	}
	secretKey, ok := secretKeyOutput.Value.(string)
	if !ok || secretKey == "" {
		return fmt.Errorf("attacker_admin_user_secret_access_key output is empty or not a string")
	}

	// Store credentials in config
	cfg.Active().AWS.Attacker.IAMAccessKeyID = accessKeyID
	cfg.Active().AWS.Attacker.IAMSecretKey = secretKey

	// Save updated config
	if err := cfg.Save(); err != nil {
		return fmt.Errorf("failed to save config with attacker credentials: %w", err)
	}

	return nil
}
