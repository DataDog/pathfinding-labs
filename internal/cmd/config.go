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
	"github.com/DataDog/pathfinding-labs/internal/terraform"
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
  prod-account     Production AWS account ID
  prod-profile     Production AWS CLI profile
  dev-account      Development AWS account ID
  dev-profile      Development AWS CLI profile
  ops-account      Operations AWS account ID
  ops-profile      Operations AWS CLI profile`,
	Args: cobra.ExactArgs(2),
	RunE: runConfigSet,
}

func init() {
	configCmd.AddCommand(configShowCmd)
	configCmd.AddCommand(configSetCmd)
}

func runConfigShow(cmd *cobra.Command, args []string) error {
	paths, err := repo.GetPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	cyan := color.New(color.FgCyan).SprintFunc()
	dim := color.New(color.Faint).SprintFunc()

	// Load CLI config
	cfg, err := config.Load(paths.ConfigPath)
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	// Also load from tfvars for account info
	tfvars := terraform.NewTFVars(paths.TFVarsPath)
	tfCfg, _ := tfvars.GetAccountConfig()

	// Merge - prefer tfvars for account info
	if tfCfg.ProdAccountID != "" {
		cfg.ProdAccountID = tfCfg.ProdAccountID
	}
	if tfCfg.ProdProfile != "" {
		cfg.ProdProfile = tfCfg.ProdProfile
	}
	if tfCfg.DevAccountID != "" {
		cfg.DevAccountID = tfCfg.DevAccountID
	}
	if tfCfg.DevProfile != "" {
		cfg.DevProfile = tfCfg.DevProfile
	}
	if tfCfg.OpsAccountID != "" {
		cfg.OpsAccountID = tfCfg.OpsAccountID
	}
	if tfCfg.OpsProfile != "" {
		cfg.OpsProfile = tfCfg.OpsProfile
	}

	fmt.Println()
	fmt.Println(cyan("Current Configuration"))
	fmt.Println()

	fmt.Println("AWS Accounts:")
	fmt.Printf("  prod-account:  %s\n", valueOrNotSet(cfg.ProdAccountID))
	fmt.Printf("  prod-profile:  %s\n", valueOrNotSet(cfg.ProdProfile))
	fmt.Printf("  dev-account:   %s\n", valueOrNotSet(cfg.DevAccountID))
	fmt.Printf("  dev-profile:   %s\n", valueOrNotSet(cfg.DevProfile))
	fmt.Printf("  ops-account:   %s\n", valueOrNotSet(cfg.OpsAccountID))
	fmt.Printf("  ops-profile:   %s\n", valueOrNotSet(cfg.OpsProfile))
	fmt.Println()

	fmt.Println("Paths:")
	fmt.Printf("  working-dir:   %s\n", valueOrNotSet(cfg.WorkingDirectory))
	if cfg.DevMode {
		fmt.Printf("  mode:          %s\n", "dev (using local repository)")
	} else {
		fmt.Printf("  mode:          %s\n", "normal")
	}
	fmt.Println()

	fmt.Println(dim("Use 'plabs config set <key> <value>' to change settings"))
	fmt.Println()

	return nil
}

func runConfigSet(cmd *cobra.Command, args []string) error {
	key := strings.ToLower(args[0])
	value := args[1]

	paths, err := repo.GetPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	// Load existing configs
	cfg, err := config.Load(paths.ConfigPath)
	if err != nil {
		cfg = &config.Config{}
	}

	tfvars := terraform.NewTFVars(paths.TFVarsPath)
	tfCfg, _ := tfvars.GetAccountConfig()

	green := color.New(color.FgGreen).SprintFunc()

	// Update the appropriate value
	switch key {
	case "prod-account", "prod_account_id":
		cfg.ProdAccountID = value
		tfCfg.ProdAccountID = value
	case "prod-profile", "prod_account_aws_profile":
		cfg.ProdProfile = value
		tfCfg.ProdProfile = value
	case "dev-account", "dev_account_id":
		cfg.DevAccountID = value
		tfCfg.DevAccountID = value
	case "dev-profile", "dev_account_aws_profile":
		cfg.DevProfile = value
		tfCfg.DevProfile = value
	case "ops-account", "operations_account_id":
		cfg.OpsAccountID = value
		tfCfg.OpsAccountID = value
	case "ops-profile", "operations_account_aws_profile":
		cfg.OpsProfile = value
		tfCfg.OpsProfile = value
	case "dev-mode":
		// Enable or disable dev mode
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
					cfg.WorkingDirectory = dir
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
			cfg.WorkingDirectory = paths.RepoPath // Reset to default ~/.plabs/pathfinding-labs
		} else {
			return fmt.Errorf("invalid value for dev-mode: %s (use true/false)", value)
		}
	default:
		return fmt.Errorf("unknown configuration key: %s\n\nValid keys: prod-account, prod-profile, dev-account, dev-profile, ops-account, ops-profile, dev-mode", key)
	}

	// Save CLI config
	if err := cfg.Save(paths.ConfigPath); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	// Update tfvars
	if paths.TFVarsExists() {
		if err := tfvars.InitFromConfig(tfCfg); err != nil {
			return fmt.Errorf("failed to update terraform.tfvars: %w", err)
		}
	}

	fmt.Printf("%s Set %s = %s\n", green("✓"), key, value)
	return nil
}

func valueOrNotSet(v string) string {
	if v == "" {
		return color.New(color.Faint).Sprint("(not set)")
	}
	return v
}
