package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/repo"
)

var configCmd = &cobra.Command{
	Use:   "config",
	Short: "View or modify plabs configuration",
	Long:  `View or modify the plabs configuration, including AWS account settings.`,
}

var configShowCmd = &cobra.Command{
	Use:   "show",
	Short: "Show current configuration",
	RunE:  runConfigShow,
}

var configSetCmd = &cobra.Command{
	Use:   "set <key> <value>",
	Short: "Set a configuration value",
	Long: `Set a configuration value.

Available keys:
  prod-profile       Production AWS CLI profile
  prod-region        Production AWS region
  dev-profile        Development AWS CLI profile
  dev-region         Development AWS region
  ops-profile        Operations AWS CLI profile
  ops-region         Operations AWS region
  attacker-profile   Attacker AWS CLI profile
  attacker-region    Attacker AWS region
  dev-mode           Enable/disable development mode (true/false)`,
	Args: cobra.ExactArgs(2),
	RunE: runConfigSet,
}

var configSyncCmd = &cobra.Command{
	Use:   "sync",
	Short: "Sync terraform.tfvars from config",
	Long:  `Regenerate terraform.tfvars from the current plabs configuration. Use this if terraform.tfvars gets out of sync.`,
	RunE:  runConfigSync,
}

func init() {
	configCmd.AddCommand(configShowCmd)
	configCmd.AddCommand(configSetCmd)
	configCmd.AddCommand(configSyncCmd)
}

func runConfigShow(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	cyan := color.New(color.FgCyan).SprintFunc()
	dim := color.New(color.Faint).SprintFunc()
	green := color.New(color.FgGreen).SprintFunc()

	fmt.Println()
	fmt.Println(cyan("Current Configuration"))
	fmt.Println()

	fmt.Println("AWS Accounts:")
	fmt.Printf("  prod-profile:  %s\n", valueOrNotSet(cfg.AWS.Prod.Profile))
	fmt.Printf("  prod-region:   %s\n", valueOrNotSet(cfg.AWS.Prod.Region))
	fmt.Printf("  dev-profile:   %s\n", valueOrNotSet(cfg.AWS.Dev.Profile))
	fmt.Printf("  dev-region:    %s\n", valueOrNotSet(cfg.AWS.Dev.Region))
	fmt.Printf("  ops-profile:       %s\n", valueOrNotSet(cfg.AWS.Ops.Profile))
	fmt.Printf("  ops-region:        %s\n", valueOrNotSet(cfg.AWS.Ops.Region))
	fmt.Printf("  attacker-profile:  %s\n", valueOrNotSet(cfg.AWS.Attacker.Profile))
	fmt.Printf("  attacker-region:   %s\n", valueOrNotSet(cfg.AWS.Attacker.Region))
	fmt.Println()

	fmt.Println("Mode:")
	if cfg.DevMode {
		fmt.Printf("  dev-mode:      %s\n", green("enabled"))
		fmt.Printf("  dev-path:      %s\n", cfg.DevModePath)
	} else {
		fmt.Printf("  dev-mode:      %s\n", "disabled")
	}
	fmt.Println()

	fmt.Println("Paths:")
	fmt.Printf("  config:        %s\n", paths.ConfigPath)
	fmt.Printf("  terraform-dir: %s\n", paths.TerraformDir)
	fmt.Println()

	// Show enabled scenarios count
	fmt.Printf("Enabled scenarios: %d\n", len(cfg.Scenarios.Enabled))
	fmt.Println()

	fmt.Println(dim("Use 'plabs config set <key> <value>' to change settings"))
	fmt.Println()

	return nil
}

func runConfigSet(cmd *cobra.Command, args []string) error {
	key := strings.ToLower(args[0])
	value := args[1]

	cfg, err := config.Load()
	if err != nil {
		cfg = &config.Config{}
	}

	green := color.New(color.FgGreen).SprintFunc()

	// Update the appropriate value
	switch key {
	case "prod-profile":
		cfg.AWS.Prod.Profile = value
	case "prod-region":
		cfg.AWS.Prod.Region = value
	case "dev-profile":
		cfg.AWS.Dev.Profile = value
	case "dev-region":
		cfg.AWS.Dev.Region = value
	case "ops-profile":
		cfg.AWS.Ops.Profile = value
	case "ops-region":
		cfg.AWS.Ops.Region = value
	case "attacker-profile":
		cfg.AWS.Attacker.Profile = value
	case "attacker-region":
		cfg.AWS.Attacker.Region = value
	case "dev-mode":
		lowerVal := strings.ToLower(value)
		if lowerVal == "true" || lowerVal == "1" || lowerVal == "yes" {
			// Find the local repo directory
			cwd, err := os.Getwd()
			if err != nil {
				return fmt.Errorf("failed to get current directory: %w", err)
			}
			// Look for modules/scenarios in current or parent directories
			dir := cwd
			found := false
			for i := 0; i < 5; i++ {
				scenariosPath := filepath.Join(dir, "modules", "scenarios")
				if _, err := os.Stat(scenariosPath); err == nil {
					cfg.DevMode = true
					cfg.DevModePath = dir
					found = true
					break
				}
				parentDir := filepath.Dir(dir)
				if parentDir == dir {
					break
				}
				dir = parentDir
			}
			if !found {
				return fmt.Errorf("cannot enable dev mode: not in a pathfinding-labs repository\n\nRun this command from within the cloned pathfinding-labs directory")
			}
		} else if lowerVal == "false" || lowerVal == "0" || lowerVal == "no" {
			cfg.DevMode = false
			cfg.DevModePath = ""
		} else {
			return fmt.Errorf("invalid value for dev-mode: %s (use true/false)", value)
		}
	default:
		return fmt.Errorf("unknown configuration key: %s\n\nValid keys: prod-profile, prod-region, dev-profile, dev-region, ops-profile, ops-region, attacker-profile, attacker-region, dev-mode", key)
	}

	// Save config (single source of truth)
	if err := cfg.Save(); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	// Regenerate terraform.tfvars
	paths, err := repo.GetPathsForMode(cfg.DevMode, cfg.DevModePath)
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	if err := cfg.SyncTFVars(paths.TerraformDir); err != nil {
		return fmt.Errorf("failed to sync terraform.tfvars: %w", err)
	}

	fmt.Printf("%s Set %s = %s\n", green("OK"), key, value)
	if key == "dev-mode" && cfg.DevMode {
		fmt.Printf("    Terraform will run in: %s\n", cfg.DevModePath)
	}
	return nil
}

func runConfigSync(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	paths, err := repo.GetPathsForMode(cfg.DevMode, cfg.DevModePath)
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	if err := cfg.SyncTFVars(paths.TerraformDir); err != nil {
		return fmt.Errorf("failed to sync terraform.tfvars: %w", err)
	}

	green := color.New(color.FgGreen).SprintFunc()
	fmt.Printf("%s Synced terraform.tfvars to %s\n", green("OK"), paths.TFVarsPath)
	return nil
}

func valueOrNotSet(v string) string {
	if v == "" {
		return color.New(color.Faint).Sprint("(not set)")
	}
	return v
}
