package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/repo"
)

var configCmd = &cobra.Command{
	Use:   "config",
	Short: "View or modify plabs configuration",
	Long: `View or modify the plabs configuration, including AWS account settings.

Per-scenario configuration:
  plabs config <scenario-name> list               Show all config values for a scenario
  plabs config <scenario-name> get <key>          Read one config value
  plabs config <scenario-name> set <key> <value>  Write a config value`,
	Args: cobra.ArbitraryArgs,
	RunE: runConfigScenarioOrHelp,
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
  dev-mode           Enable/disable development mode (true/false)
  include-beta       Show beta scenarios in listings and TUI (true/false)`,
	Args: cobra.ExactArgs(2),
	RunE: runConfigSet,
}

var configSyncCmd = &cobra.Command{
	Use:   "sync",
	Short: "Sync terraform.tfvars from config",
	Long:  `Regenerate terraform.tfvars from the current plabs configuration. Use this if terraform.tfvars gets out of sync.`,
	RunE:  runConfigSync,
}

var configLoadFlagsCmd = &cobra.Command{
	Use:   "load-flags [file]",
	Short: "Load CTF flag values from flags.default.yaml",
	Long: `Load CTF flag values into the active workspace configuration.

If no file argument is given, looks for flags.default.yaml in the Terraform directory.
After loading, syncs terraform.tfvars so that 'plabs apply' will write the real flag
values into SSM Parameter Store.`,
	Args: cobra.MaximumNArgs(1),
	RunE: runConfigLoadFlags,
}

func init() {
	configCmd.AddCommand(configShowCmd)
	configCmd.AddCommand(configSetCmd)
	configCmd.AddCommand(configSyncCmd)
	configCmd.AddCommand(configLoadFlagsCmd)
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

	ws := cfg.Active()

	// Show workspace context when multiple workspaces are configured
	if cfg.WorkspaceCount() > 1 {
		fmt.Printf("Workspace: %s\n", cyan(cfg.ActiveName()))
		wsNames := make([]string, 0, cfg.WorkspaceCount())
		for name := range cfg.Workspaces {
			wsNames = append(wsNames, name)
		}
		sort.Strings(wsNames)
		fmt.Printf("All workspaces: %s\n", strings.Join(wsNames, ", "))
		fmt.Println()
	}

	fmt.Println("AWS Accounts:")
	fmt.Printf("  prod-profile:  %s\n", valueOrNotSet(ws.AWS.Prod.Profile))
	fmt.Printf("  prod-region:   %s\n", valueOrNotSet(ws.AWS.Prod.Region))
	fmt.Printf("  dev-profile:   %s\n", valueOrNotSet(ws.AWS.Dev.Profile))
	fmt.Printf("  dev-region:    %s\n", valueOrNotSet(ws.AWS.Dev.Region))
	fmt.Printf("  ops-profile:       %s\n", valueOrNotSet(ws.AWS.Ops.Profile))
	fmt.Printf("  ops-region:        %s\n", valueOrNotSet(ws.AWS.Ops.Region))
	fmt.Printf("  attacker-profile:  %s\n", valueOrNotSet(ws.AWS.Attacker.Profile))
	fmt.Printf("  attacker-region:   %s\n", valueOrNotSet(ws.AWS.Attacker.Region))
	fmt.Println()

	fmt.Println("Mode:")
	if ws.DevMode {
		fmt.Printf("  dev-mode:      %s\n", green("enabled"))
		fmt.Printf("  dev-path:      %s\n", ws.DevModePath)
	} else {
		fmt.Printf("  dev-mode:      %s\n", "disabled")
	}
	if cfg.IncludeBeta {
		fmt.Printf("  include-beta:  %s\n", green("true"))
	} else {
		fmt.Printf("  include-beta:  false\n")
	}
	fmt.Println()

	fmt.Println("Paths:")
	fmt.Printf("  config:        %s\n", paths.ConfigPath)
	fmt.Printf("  terraform-dir: %s\n", paths.TerraformDir)
	fmt.Println()

	fmt.Printf("Enabled scenarios: %d\n", len(ws.Scenarios.Enabled))
	fmt.Println()

	if len(ws.ScenarioConfigs) > 0 {
		fmt.Println("Per-scenario config:")
		scenarioNames := make([]string, 0, len(ws.ScenarioConfigs))
		for name := range ws.ScenarioConfigs {
			scenarioNames = append(scenarioNames, name)
		}
		sort.Strings(scenarioNames)
		for _, name := range scenarioNames {
			vals := ws.ScenarioConfigs[name]
			keys := make([]string, 0, len(vals))
			for k := range vals {
				keys = append(keys, k)
			}
			sort.Strings(keys)
			fmt.Printf("  %s:\n", cyan(name))
			for _, k := range keys {
				fmt.Printf("    %s = %q\n", k, vals[k])
			}
		}
		fmt.Println()
	}

	fmt.Println(dim("Use 'plabs config set <key> <value>' to change settings"))
	fmt.Println()

	return nil
}

func runConfigSet(cmd *cobra.Command, args []string) error {
	key := strings.ToLower(args[0])
	value := args[1]

	cfg, err := config.Load()
	if err != nil {
		cfg = &config.Config{
			ActiveWorkspace: "default",
			Workspaces:      map[string]*config.WorkspaceConfig{"default": {}},
		}
	}

	green := color.New(color.FgGreen).SprintFunc()
	ws := cfg.Active() // pointer into cfg.Workspaces; mutations propagate on Save()

	switch key {
	case "prod-profile":
		ws.AWS.Prod.Profile = value
	case "prod-region":
		ws.AWS.Prod.Region = value
	case "dev-profile":
		ws.AWS.Dev.Profile = value
	case "dev-region":
		ws.AWS.Dev.Region = value
	case "ops-profile":
		ws.AWS.Ops.Profile = value
	case "ops-region":
		ws.AWS.Ops.Region = value
	case "attacker-profile":
		ws.AWS.Attacker.Profile = value
	case "attacker-region":
		ws.AWS.Attacker.Region = value
	case "dev-mode":
		lowerVal := strings.ToLower(value)
		if lowerVal == "true" || lowerVal == "1" || lowerVal == "yes" {
			cwd, err := os.Getwd()
			if err != nil {
				return fmt.Errorf("failed to get current directory: %w", err)
			}
			dir := cwd
			found := false
			for i := 0; i < 5; i++ {
				scenariosPath := filepath.Join(dir, "modules", "scenarios")
				if _, err := os.Stat(scenariosPath); err == nil {
					ws.DevMode = true
					ws.DevModePath = dir
					ws.Initialized = true
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
			ws.DevMode = false
			ws.DevModePath = ""
		} else {
			return fmt.Errorf("invalid value for dev-mode: %s (use true/false)", value)
		}
	case "dev-mode-path":
		// Explicit dev mode path override — useful when creating workspaces with dev mode pre-set
		scenariosPath := filepath.Join(value, "modules", "scenarios")
		if _, err := os.Stat(scenariosPath); err != nil {
			return fmt.Errorf("path does not appear to be a pathfinding-labs repository: %s", value)
		}
		ws.DevMode = true
		ws.DevModePath = value
		ws.Initialized = true
	case "include-beta":
		// include-beta is a global preference, not workspace-scoped
		lowerVal := strings.ToLower(value)
		if lowerVal == "true" || lowerVal == "1" || lowerVal == "yes" {
			cfg.IncludeBeta = true
		} else if lowerVal == "false" || lowerVal == "0" || lowerVal == "no" {
			cfg.IncludeBeta = false
		} else {
			return fmt.Errorf("invalid value for include-beta: %s (use true/false)", value)
		}
	default:
		return fmt.Errorf("unknown configuration key: %s\n\nValid keys: prod-profile, prod-region, dev-profile, dev-region, ops-profile, ops-region, attacker-profile, attacker-region, dev-mode, dev-mode-path, include-beta", key)
	}

	if err := cfg.Save(); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	// Regenerate terraform.tfvars (best-effort)
	if paths, pathErr := repo.GetPathsForWorkspace(cfg.ActiveName(), ws.DevMode, ws.DevModePath); pathErr == nil {
		if _, statErr := os.Stat(paths.TerraformDir); statErr == nil {
			_ = ws.SyncTFVars(paths.TerraformDir)
		}
	}

	fmt.Printf("%s Set %s = %s\n", green("OK"), key, value)
	if key == "dev-mode" && ws.DevMode {
		fmt.Printf("    Terraform will run in: %s\n", ws.DevModePath)
	}
	return nil
}

func runConfigSync(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	ws := cfg.Active()
	paths, err := repo.GetPathsForWorkspace(cfg.ActiveName(), ws.DevMode, ws.DevModePath)
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	if err := ws.SyncTFVars(paths.TerraformDir); err != nil {
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

// runConfigScenarioOrHelp handles "plabs config <scenario-name> [set|get|list] ..."
// It is called by configCmd when no registered subcommand (show/set/sync) matches.
func runConfigScenarioOrHelp(cmd *cobra.Command, args []string) error {
	if len(args) == 0 {
		return cmd.Help()
	}

	scenarioName := args[0]
	subCmd := "list"
	if len(args) >= 2 {
		subCmd = args[1]
	}

	switch subCmd {
	case "list":
		return runScenarioConfigList(scenarioName)
	case "get":
		if len(args) < 3 {
			return fmt.Errorf("usage: plabs config <scenario> get <key>")
		}
		return runScenarioConfigGet(scenarioName, args[2])
	case "set":
		if len(args) < 4 {
			return fmt.Errorf("usage: plabs config <scenario> set <key> <value>")
		}
		return runScenarioConfigSet(scenarioName, args[2], args[3])
	default:
		return fmt.Errorf("unknown subcommand %q\n\nValid subcommands: list, get, set", subCmd)
	}
}

func runScenarioConfigList(scenarioName string) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	cyan := color.New(color.FgCyan).SprintFunc()
	dim := color.New(color.Faint).SprintFunc()

	vals := cfg.Active().GetAllScenarioConfigs(scenarioName)
	fmt.Println()
	fmt.Println(cyan(fmt.Sprintf("Config for scenario: %s", scenarioName)))
	fmt.Println()

	if len(vals) == 0 {
		fmt.Println(dim("  (no values set)"))
	} else {
		for k, v := range vals {
			fmt.Printf("  %s = %q\n", k, v)
		}
	}
	fmt.Println()
	return nil
}

func runScenarioConfigGet(scenarioName, key string) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	val, ok := cfg.Active().GetScenarioConfig(scenarioName, key)
	if !ok {
		return fmt.Errorf("no value set for %s / %s", scenarioName, key)
	}
	fmt.Println(val)
	return nil
}

func runScenarioConfigSet(scenarioName, key, value string) error {
	cfg, err := config.Load()
	if err != nil {
		cfg = &config.Config{
			ActiveWorkspace: "default",
			Workspaces:      map[string]*config.WorkspaceConfig{"default": {}},
		}
	}

	ws := cfg.Active()
	ws.SetScenarioConfig(scenarioName, key, value)

	if err := cfg.Save(); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	// Sync tfvars (best-effort: dir may not exist yet)
	if paths, pathErr := repo.GetPathsForWorkspace(cfg.ActiveName(), ws.DevMode, ws.DevModePath); pathErr == nil {
		if _, statErr := os.Stat(paths.TerraformDir); statErr == nil {
			_ = ws.SyncTFVars(paths.TerraformDir)
		}
	}

	green := color.New(color.FgGreen).SprintFunc()
	fmt.Printf("%s Set %s / %s = %s\n", green("OK"), scenarioName, key, value)
	return nil
}

func runConfigLoadFlags(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	flagFilePath := ""
	if len(args) == 1 {
		flagFilePath = args[0]
	} else {
		candidate := filepath.Join(paths.TerraformDir, DefaultFlagFileName)
		if _, statErr := os.Stat(candidate); statErr == nil {
			flagFilePath = candidate
		}
	}

	if flagFilePath == "" {
		yellow := color.New(color.FgYellow).SprintFunc()
		fmt.Printf("%s No flag file found. Expected %s\n", yellow("!"), filepath.Join(paths.TerraformDir, DefaultFlagFileName))
		fmt.Println("  Provide a path: plabs config load-flags /path/to/flags.yaml")
		return nil
	}

	ws := cfg.Active()
	if err := ws.LoadFlagsFromFile(flagFilePath); err != nil {
		return fmt.Errorf("failed to load flag file: %w", err)
	}

	if err := cfg.Save(); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	if err := ws.SyncTFVars(paths.TerraformDir); err != nil {
		return fmt.Errorf("failed to sync tfvars: %w", err)
	}

	green := color.New(color.FgGreen).SprintFunc()
	fmt.Printf("%s Loaded %d CTF flag(s) from %s\n", green("OK"), len(ws.Flags), flagFilePath)
	fmt.Println("  Run 'plabs apply' to push the updated flag values to SSM Parameter Store.")
	return nil
}
