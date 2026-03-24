package cmd

import (
	"fmt"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/repo"
	"github.com/DataDog/pathfinding-labs/internal/scenarios"
	"github.com/DataDog/pathfinding-labs/internal/terraform"
)

var infoCmd = &cobra.Command{
	Use:   "info",
	Short: "Show plabs installation information",
	Long:  `Display information about the plabs installation, including paths, versions, and configuration.`,
	RunE:  runInfo,
}

func runInfo(cmd *cobra.Command, args []string) error {
	// Get the actual working paths (respects dev mode)
	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	cyan := color.New(color.FgCyan).SprintFunc()
	green := color.New(color.FgGreen).SprintFunc()
	yellow := color.New(color.FgYellow).SprintFunc()
	dim := color.New(color.Faint).SprintFunc()

	fmt.Println()
	fmt.Println(cyan("═══ Pathfinding Labs Info ═══"))
	fmt.Println()

	// Dev mode indicator
	if isDevMode() {
		fmt.Printf("  %s %s\n", yellow("⚠"), yellow("DEV MODE - Using local repository"))
		fmt.Println()
	}

	// Paths
	fmt.Println(cyan("Paths:"))
	fmt.Printf("  Repository:    %s\n", paths.RepoPath)
	fmt.Printf("  Scenarios:     %s\n", paths.ScenariosPath())
	fmt.Printf("  TFVars File:   %s\n", paths.TFVarsPath)
	fmt.Printf("  Config File:   %s\n", paths.ConfigPath)
	fmt.Printf("  Bin Directory: %s\n", paths.BinPath)
	fmt.Println()

	// Repository info
	fmt.Println(cyan("Repository:"))
	if paths.RepoExists() {
		commit, err := repo.GetCurrentCommit(paths.RepoPath)
		if err != nil {
			fmt.Printf("  Status: %s\n", yellow("Error getting commit"))
		} else {
			fmt.Printf("  Commit:  %s\n", commit)
		}

		branch, err := repo.GetCurrentBranch(paths.RepoPath)
		if err == nil {
			fmt.Printf("  Branch:  %s\n", branch)
		}

		remoteURL, err := repo.GetRemoteURL(paths.RepoPath)
		if err == nil {
			fmt.Printf("  Remote:  %s\n", remoteURL)
		}

		hasChanges, err := repo.HasLocalChanges(paths.RepoPath)
		if err == nil && hasChanges {
			fmt.Printf("  Changes: %s\n", yellow("Local modifications detected"))
		}
	} else {
		fmt.Printf("  Status: %s\n", yellow("Not cloned"))
	}
	fmt.Println()

	// Terraform info
	fmt.Println(cyan("Terraform:"))
	installer := terraform.NewInstaller(paths.BinPath)
	tfPath, err := installer.GetTerraformPath()
	if err != nil {
		fmt.Printf("  Status: %s\n", yellow("Not installed"))
	} else {
		fmt.Printf("  Path:    %s\n", tfPath)
		version, err := installer.GetVersion()
		if err == nil {
			fmt.Printf("  Version: %s\n", version)
		}
	}
	fmt.Println()

	// Configuration
	fmt.Println(cyan("Configuration:"))
	cfg, err := config.Load()
	if err != nil {
		fmt.Printf("  Status: %s\n", yellow("Not configured"))
	} else if cfg.AWS.Prod.Profile == "" {
		fmt.Printf("  Status: %s\n", yellow("Not configured (run 'plabs init')"))
	} else {
		fmt.Printf("  Production: %s\n", dim("profile: "+cfg.AWS.Prod.Profile))
		if cfg.AWS.Dev.Profile != "" {
			fmt.Printf("  Development: %s\n", dim("profile: "+cfg.AWS.Dev.Profile))
		}
		if cfg.AWS.Ops.Profile != "" {
			fmt.Printf("  Operations: %s\n", dim("profile: "+cfg.AWS.Ops.Profile))
		}
		if cfg.AWS.Attacker.Profile != "" {
			fmt.Printf("  Attacker:    %s\n", dim("profile: "+cfg.AWS.Attacker.Profile))
		}

		if !cfg.IsMultiAccountMode() {
			fmt.Printf("  Mode: %s\n", "Single-account")
		} else {
			fmt.Printf("  Mode: %s\n", "Multi-account")
		}
	}
	fmt.Println()

	// Scenarios
	fmt.Println(cyan("Scenarios:"))
	if paths.RepoExists() {
		discovery := scenarios.NewDiscovery(paths.ScenariosPath())
		allScenarios, err := discovery.DiscoverAll()
		if err != nil {
			fmt.Printf("  Error discovering scenarios: %v\n", err)
		} else {
			fmt.Printf("  Total Available: %d\n", len(allScenarios))

			// Count by category
			counts := scenarios.CountByCategory(allScenarios)
			for cat, count := range counts {
				fmt.Printf("    %s: %d\n", cat, count)
			}

			// Count enabled from config (source of truth)
			if cfg != nil {
				enabledVars := cfg.GetEnabledScenarioVars()
				enabledCount := 0
				for _, enabled := range enabledVars {
					if enabled {
						enabledCount++
					}
				}
				fmt.Printf("  Enabled: %s\n", green(fmt.Sprintf("%d", enabledCount)))
			}
		}
	} else {
		fmt.Printf("  Status: %s\n", yellow("Repository not cloned"))
	}
	fmt.Println()

	return nil
}
