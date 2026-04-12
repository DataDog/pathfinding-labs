package cmd

import (
	"fmt"
	"strings"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/scenarios"
)

// Note: containsGlobPattern, matchByPatterns, matchesPattern, hasBothTargets, confirmAction
// are defined in helpers.go

var enableCmd = &cobra.Command{
	Use:   "enable [scenario-id | pattern ...]",
	Short: "Enable one or more scenarios",
	Long: `Enable scenarios by their pathfinding cloud ID or glob pattern.

Examples:
  plabs enable iam-002-to-admin                      # Enable a single scenario
  plabs enable iam-002-to-admin lambda-001-to-admin  # Enable multiple scenarios
  plabs enable lambda-*                              # Enable all lambda scenarios (glob)
  plabs enable --category=one-hop lambda-*           # Enable lambda one-hop scenarios
  plabs enable --category=one-hop --target=admin     # Enable all one-hop to-admin
  plabs enable --all                                 # Enable all scenarios
  plabs enable --all -y                              # Enable all without confirmation`,
	Args: func(cmd *cobra.Command, args []string) error {
		enableAll, _ := cmd.Flags().GetBool("all")
		category, _ := cmd.Flags().GetString("category")
		target, _ := cmd.Flags().GetString("target")
		// Allow if: --all flag, or category/target filters, or specific IDs/patterns
		if !enableAll && category == "" && target == "" && len(args) < 1 {
			return fmt.Errorf("requires scenario ID(s), pattern(s), --category/--target filters, or --all flag")
		}
		return nil
	},
	RunE: runEnable,
}

var (
	enableAll      bool
	enableCategory string
	enableTarget   string
	enableYes      bool
	enableDeploy   bool
)

func init() {
	enableCmd.Flags().BoolVar(&enableAll, "all", false, "Enable all scenarios (optionally filtered by --category/--target)")
	enableCmd.Flags().StringVar(&enableCategory, "category", "", "Filter by category (self-escalation, one-hop, multi-hop, cross-account, cspm-misconfig, cspm-toxic-combo)")
	enableCmd.Flags().StringVar(&enableTarget, "target", "", "Filter by target (admin, bucket)")
	enableCmd.Flags().BoolVarP(&enableYes, "yes", "y", false, "Skip confirmation prompts")
	enableCmd.Flags().BoolVar(&enableDeploy, "deploy", false, "Deploy immediately after enabling")
}

func runEnable(cmd *cobra.Command, args []string) error {
	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	// Load config (single source of truth)
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	singleAccountMode := cfg.IsSingleAccountMode()

	// Discover scenarios
	discovery := scenarios.NewDiscovery(paths.ScenariosPath())

	green := color.New(color.FgGreen).SprintFunc()
	yellow := color.New(color.FgYellow).SprintFunc()
	red := color.New(color.FgRed).SprintFunc()

	var toEnable []*scenarios.Scenario
	var notFound []string
	var skippedCrossAccount []*scenarios.Scenario

	// Get all scenarios for filtering
	allScenarios, err := discovery.DiscoverAll()
	if err != nil {
		return fmt.Errorf("failed to discover scenarios: %w", err)
	}

	// Determine if we're doing bulk enable (--all, --category, --target, or glob patterns)
	hasFilters := enableAll || enableCategory != "" || enableTarget != ""
	hasGlobPatterns := containsGlobPattern(args)

	// Get currently enabled scenarios for filtering
	enabledVars := cfg.GetEnabledScenarioVars()

	if hasFilters || hasGlobPatterns {
		// Apply category/target filters first
		filter := scenarios.Filter{
			Category: enableCategory,
			Target:   enableTarget,
		}
		filtered := scenarios.FilterScenarios(allScenarios, filter, nil)

		// If glob patterns provided, further filter by pattern matching
		if len(args) > 0 {
			toEnable = matchByPatterns(filtered, args)
			// Track patterns that matched nothing
			for _, pattern := range args {
				matched := false
				for _, s := range filtered {
					if matchesPattern(s.UniqueID(), pattern) || matchesPattern(s.ID(), pattern) {
						matched = true
						break
					}
				}
				if !matched && !strings.Contains(pattern, "*") && !strings.Contains(pattern, "?") {
					// Only add to notFound if it's not a glob pattern (exact ID that wasn't found)
					notFound = append(notFound, pattern)
				}
			}
		} else {
			// No patterns, use all filtered scenarios
			toEnable = filtered
		}
	} else {
		// Find specific scenarios by exact ID
		toEnable, notFound, err = discovery.FindByIDs(args)
		if err != nil {
			return fmt.Errorf("failed to find scenarios: %w", err)
		}
	}

	// Check for cross-account scenarios in single-account mode
	if singleAccountMode {
		var singleAccountScenarios []*scenarios.Scenario
		for _, s := range toEnable {
			if s.RequiresMultiAccount() {
				skippedCrossAccount = append(skippedCrossAccount, s)
			} else {
				singleAccountScenarios = append(singleAccountScenarios, s)
			}
		}
		toEnable = singleAccountScenarios
	}

	// Check if we need confirmation (both targets affected and no --target specified)
	if !enableYes && enableTarget == "" && hasBothTargets(toEnable) {
		fmt.Println()
		fmt.Printf("This will enable %d scenario(s) for BOTH to-admin and to-bucket targets.\n", len(toEnable))
		fmt.Println("Use --target=admin or --target=bucket to enable only one target.")
		fmt.Println()
		if !confirmAction("Continue?") {
			fmt.Println("Aborted.")
			return nil
		}
	}

	// Block if any scenario to enable is missing required config
	var configErrors []string
	for _, s := range toEnable {
		for _, cfgKey := range s.Config {
			if cfgKey.Required {
				val, _ := cfg.GetScenarioConfig(s.Name, cfgKey.Key)
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
		fmt.Println(red("Cannot enable: some scenarios have missing required configuration:"))
		fmt.Println()
		for _, e := range configErrors {
			fmt.Println(e)
		}
		fmt.Println()
		return nil
	}

	// Update config with enabled scenarios
	for _, s := range toEnable {
		cfg.EnableScenario(s.Terraform.VariableName)
	}

	// Save config (single source of truth)
	if err := cfg.Save(); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	// Regenerate terraform.tfvars
	if err := cfg.SyncTFVars(paths.TerraformDir); err != nil {
		return fmt.Errorf("failed to sync terraform.tfvars: %w", err)
	}

	// Print results
	fmt.Println()

	if len(toEnable) > 0 {
		fmt.Printf("%s Enabled %d scenario(s):\n", green("OK"), len(toEnable))
		for _, s := range toEnable {
			status := green("*")
			if enabledVars[s.Terraform.VariableName] {
				status = yellow("*") // Already was enabled
			}
			fmt.Printf("  %s %s - %s\n", status, s.UniqueID(), truncate(s.Description, 50))
		}
	}

	if len(notFound) > 0 {
		fmt.Println()
		fmt.Printf("%s Could not find %d scenario(s):\n", red("X"), len(notFound))
		for _, id := range notFound {
			fmt.Printf("  %s\n", id)
		}
		fmt.Println()
		fmt.Println("Use 'plabs' to browse scenarios in the TUI, or 'plabs scenarios list' for CLI")
	}

	if len(skippedCrossAccount) > 0 {
		fmt.Println()
		fmt.Printf("%s Skipped %d cross-account scenario(s) (single-account mode):\n", yellow("!"), len(skippedCrossAccount))
		for _, s := range skippedCrossAccount {
			fmt.Printf("  %s %s\n", yellow("o"), s.UniqueID())
		}
		fmt.Println()
		fmt.Println("To enable cross-account scenarios, configure dev/ops accounts:")
		fmt.Println("  plabs config set dev-profile <profile-name>")
	}

	if len(toEnable) > 0 {
		if enableDeploy {
			fmt.Println()
			// Run deploy
			if err := runDeploy(cmd, []string{}); err != nil {
				return err
			}
		} else {
			fmt.Println()
			fmt.Println("Run 'plabs deploy' to deploy the enabled scenarios")
		}
	}

	return nil
}
