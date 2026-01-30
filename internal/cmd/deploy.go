package cmd

import (
	"bufio"
	"fmt"
	"os"
	"strings"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	"github.com/DataDog/pathfinding-labs/internal/terraform"
)

var deployCmd = &cobra.Command{
	Use:   "deploy",
	Short: "Deploy enabled scenarios to AWS",
	Long: `Deploy all enabled scenarios to your AWS account(s).

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

	cyan := color.New(color.FgCyan).SprintFunc()
	yellow := color.New(color.FgYellow).SprintFunc()
	green := color.New(color.FgGreen).SprintFunc()

	fmt.Println()
	fmt.Println(cyan("Deploying Pathfinding Labs..."))
	fmt.Println()

	// Show enabled environments and scenarios count
	tfvars := terraform.NewTFVars(paths.TFVarsPath)
	enabledList, err := tfvars.ListEnabledScenarios()
	if err != nil {
		return fmt.Errorf("failed to list enabled scenarios: %w", err)
	}

	// Separate environments from scenarios
	var environments []string
	var scenarios []string
	for _, name := range enabledList {
		if strings.HasSuffix(name, "_environment") {
			environments = append(environments, name)
		} else {
			scenarios = append(scenarios, name)
		}
	}

	fmt.Printf("Enabled environments: %d\n", len(environments))
	if len(scenarios) == 0 {
		fmt.Println(yellow("No scenarios are currently enabled."))
		fmt.Println("Running terraform apply to sync state (this may destroy previously enabled scenarios)...")
	} else {
		fmt.Printf("Enabled scenarios: %d\n", len(scenarios))
	}
	fmt.Println()

	// Create runner
	runner := terraform.NewRunner(paths.BinPath, paths.RepoPath)

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
			fmt.Println("Deployment cancelled.")
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
	fmt.Println(green("════════════════════════════════════════════════════════════"))
	fmt.Println(green("  Deployment complete!"))
	fmt.Println(green("════════════════════════════════════════════════════════════"))
	fmt.Println()
	fmt.Printf("Run %s to see deployment status\n", cyan("plabs status"))
	fmt.Printf("Run %s to run a demo attack\n", cyan("plabs demo <scenario-id>"))
	fmt.Println()

	return nil
}
