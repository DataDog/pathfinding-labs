package cmd

import (
	"fmt"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

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

	cyan := color.New(color.FgCyan).SprintFunc()

	fmt.Println()
	fmt.Println(cyan("Planning Pathfinding Labs deployment..."))
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

	// Run plan
	if err := runner.Plan(); err != nil {
		return fmt.Errorf("terraform plan failed: %w", err)
	}

	fmt.Println()
	fmt.Printf("Run %s to apply these changes\n", cyan("plabs deploy"))
	fmt.Println()

	return nil
}
