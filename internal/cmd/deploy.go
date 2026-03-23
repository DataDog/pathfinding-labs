package cmd

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

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

	// Sync tfvars from config before running terraform
	if err := cfg.SyncTFVars(paths.TerraformDir); err != nil {
		return fmt.Errorf("failed to sync tfvars: %w", err)
	}

	cyan := color.New(color.FgCyan).SprintFunc()
	yellow := color.New(color.FgYellow).SprintFunc()
	green := color.New(color.FgGreen).SprintFunc()
	dim := color.New(color.Faint).SprintFunc()

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

	// Create runner
	runner := terraform.NewRunner(paths.BinPath, paths.TerraformDir)

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
