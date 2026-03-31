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

	// Validate AWS credentials before running terraform
	if err := validateAWSCredentials(cfg); err != nil {
		return err
	}

	// Detect which service-linked roles already exist in the prod account
	// so Terraform doesn't try to create duplicates
	slrStatus, err := plabsaws.DetectExistingServiceLinkedRoles(cfg.AWS.Prod.Profile)
	if err != nil {
		// Non-fatal: if detection fails, default to creating all SLRs (original behavior)
		fmt.Printf("Warning: could not detect existing service-linked roles: %v\n", err)
		fmt.Println("Terraform will attempt to create all service-linked roles.")
	} else {
		cfg.SLRFlags = &config.ServiceLinkedRoleFlags{
			CreateAutoScaling: !slrStatus.AutoScalingExists,
			CreateSpot:        !slrStatus.SpotExists,
			CreateAppRunner:   !slrStatus.AppRunnerExists,
			CreateMWAA:        !slrStatus.MWAAExists,
		}
	}

	// Sync tfvars from config before running terraform
	if err := cfg.SyncTFVars(paths.TerraformDir); err != nil {
		return fmt.Errorf("failed to sync tfvars: %w", err)
	}

	cyan := color.New(color.FgCyan).SprintFunc()
	yellow := color.New(color.FgYellow).SprintFunc()
	green := color.New(color.FgGreen).SprintFunc()
	dim := color.New(color.Faint).SprintFunc()

	// Create runner early so bootstrap can use it
	runner := terraform.NewRunner(paths.BinPath, paths.TerraformDir)

	// Bootstrap attacker IAM user if needed
	if cfg.HasAttackerAccount() && cfg.AWS.Attacker.Mode == "iam-user" && cfg.AWS.Attacker.IAMAccessKeyID == "" {
		fmt.Println()
		fmt.Println(cyan("Bootstrapping attacker account IAM admin user..."))
		fmt.Println()

		if err := bootstrapAttackerIAMUser(runner, cfg); err != nil {
			return fmt.Errorf("attacker IAM user bootstrap failed: %w", err)
		}

		// Re-sync tfvars now that bootstrap credentials are stored
		if err := cfg.SyncTFVars(paths.TerraformDir); err != nil {
			return fmt.Errorf("failed to sync tfvars after bootstrap: %w", err)
		}

		fmt.Println(green("Attacker IAM admin user bootstrapped successfully."))
		fmt.Println()
	}

	fmt.Println()
	fmt.Println(cyan("Applying Pathfinding Labs..."))

	// Show mode indicator only in dev mode
	if cfg.DevMode {
		fmt.Println()
		fmt.Printf("%s Running in dev mode: %s\n", yellow("!"), cfg.DevModePath)
	}
	fmt.Println()

	// Show enabled scenarios count from config
	enabledCount := len(cfg.Scenarios.Enabled)

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

	// Apply addon if configured
	if cfg.HasAddon() {
		fmt.Println()
		fmt.Printf("%s Applying addon: %s\n", cyan("→"), cfg.Addon.Path)
		fmt.Println()

		addon := buildAddon(cfg)
		if addon != nil {
			if !addon.IsInitialized() {
				fmt.Println("Running terraform init (addon)...")
				if err := addon.Init(); err != nil {
					return fmt.Errorf("addon init failed: %w", err)
				}
				fmt.Println()
			}
			if err := addon.Apply(); err != nil {
				return fmt.Errorf("addon apply failed: %w", err)
			}
		}
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
	cfg.AWS.Attacker.IAMAccessKeyID = accessKeyID
	cfg.AWS.Attacker.IAMSecretKey = secretKey

	// Save updated config
	if err := cfg.Save(); err != nil {
		return fmt.Errorf("failed to save config with attacker credentials: %w", err)
	}

	return nil
}
