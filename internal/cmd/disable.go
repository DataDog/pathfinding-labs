package cmd

import (
	"fmt"
	"strings"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/scenarios"
)

var disableCmd = &cobra.Command{
	Use:   "disable [scenario-id | pattern ...]",
	Short: "Disable one or more scenarios",
	Long: `Disable scenarios by their pathfinding cloud ID or glob pattern.

Examples:
  plabs disable iam-002-to-admin                     # Disable a single scenario
  plabs disable iam-002-to-admin lambda-001-to-admin # Disable multiple scenarios
  plabs disable lambda-*                             # Disable all lambda scenarios (glob)
  plabs disable --category=one-hop lambda-*          # Disable lambda one-hop scenarios
  plabs disable --category=one-hop --target=admin    # Disable all one-hop to-admin
  plabs disable --all                                # Disable all enabled scenarios
  plabs disable --all -y                             # Disable all without confirmation`,
	Args: func(cmd *cobra.Command, args []string) error {
		disableAll, _ := cmd.Flags().GetBool("all")
		category, _ := cmd.Flags().GetString("category")
		target, _ := cmd.Flags().GetString("target")
		// Allow if: --all flag, or category/target filters, or specific IDs/patterns
		if !disableAll && category == "" && target == "" && len(args) < 1 {
			return fmt.Errorf("requires scenario ID(s), pattern(s), --category/--target filters, or --all flag")
		}
		return nil
	},
	RunE: runDisable,
}

var (
	disableAllFlag  bool
	disableCategory string
	disableTarget   string
	disableYes      bool
	disableDeploy   bool
)

func init() {
	disableCmd.Flags().BoolVar(&disableAllFlag, "all", false, "Disable all enabled scenarios")
	disableCmd.Flags().StringVar(&disableCategory, "category", "", "Filter by category (self-escalation, one-hop, multi-hop, toxic-combo, cross-account)")
	disableCmd.Flags().StringVar(&disableTarget, "target", "", "Filter by target (admin, bucket)")
	disableCmd.Flags().BoolVarP(&disableYes, "yes", "y", false, "Skip confirmation prompts")
	disableCmd.Flags().BoolVar(&disableDeploy, "deploy", false, "Deploy immediately after disabling (destroys disabled scenarios)")
}

func runDisable(cmd *cobra.Command, args []string) error {
	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	// Load config (single source of truth)
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	// Discover scenarios
	discovery := scenarios.NewDiscovery(paths.ScenariosPath())

	green := color.New(color.FgGreen).SprintFunc()
	red := color.New(color.FgRed).SprintFunc()
	dim := color.New(color.Faint).SprintFunc()

	var toDisable []*scenarios.Scenario
	var notFound []string

	// Get current enabled status from config
	enabledVars := cfg.GetEnabledScenarioVars()

	// Get all scenarios for filtering
	allScenarios, err := discovery.DiscoverAll()
	if err != nil {
		return fmt.Errorf("failed to discover scenarios: %w", err)
	}

	// Determine if we're doing bulk disable (--all, --category, --target, or glob patterns)
	hasFilters := disableAllFlag || disableCategory != "" || disableTarget != ""
	hasGlobPatterns := containsGlobPattern(args)

	if hasFilters || hasGlobPatterns {
		// Apply category/target filters first
		filter := scenarios.Filter{
			Category:    disableCategory,
			Target:      disableTarget,
			EnabledOnly: true, // Only consider enabled scenarios for disable
		}
		filtered := scenarios.FilterScenarios(allScenarios, filter, enabledVars)

		// If glob patterns provided, further filter by pattern matching
		if len(args) > 0 {
			toDisable = matchByPatterns(filtered, args)
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
			toDisable = filtered
		}
	} else {
		// Find specific scenarios by exact ID
		toDisable, notFound, err = discovery.FindByIDs(args)
		if err != nil {
			return fmt.Errorf("failed to find scenarios: %w", err)
		}
	}

	// Filter to only already-enabled scenarios
	var actuallyDisabling []*scenarios.Scenario
	var alreadyDisabled []*scenarios.Scenario

	for _, s := range toDisable {
		if enabledVars[s.Terraform.VariableName] {
			actuallyDisabling = append(actuallyDisabling, s)
		} else {
			alreadyDisabled = append(alreadyDisabled, s)
		}
	}

	// Check if we need confirmation (both targets affected and no --target specified)
	if !disableYes && disableTarget == "" && hasBothTargets(actuallyDisabling) {
		fmt.Println()
		fmt.Printf("This will disable %d scenario(s) for BOTH to-admin and to-bucket targets.\n", len(actuallyDisabling))
		fmt.Println("Use --target=admin or --target=bucket to disable only one target.")
		fmt.Println()
		if !confirmAction("Continue?") {
			fmt.Println("Aborted.")
			return nil
		}
	}

	// Update config with disabled scenarios
	for _, s := range actuallyDisabling {
		cfg.DisableScenario(s.Terraform.VariableName)
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

	if len(actuallyDisabling) == 0 && len(alreadyDisabled) == 0 && len(notFound) == 0 {
		fmt.Println(dim("No scenarios to disable."))
		return nil
	}

	if len(actuallyDisabling) > 0 {
		fmt.Printf("%s Disabled %d scenario(s):\n", green("OK"), len(actuallyDisabling))
		for _, s := range actuallyDisabling {
			fmt.Printf("  %s %s - %s\n", dim("o"), s.UniqueID(), truncate(s.Description, 50))
		}
	}

	if len(alreadyDisabled) > 0 {
		fmt.Println()
		fmt.Printf("%s Already disabled %d scenario(s):\n", dim("o"), len(alreadyDisabled))
		for _, s := range alreadyDisabled {
			fmt.Printf("  %s\n", s.UniqueID())
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

	if len(actuallyDisabling) > 0 {
		if disableDeploy {
			fmt.Println()
			// Run deploy
			if err := runDeploy(cmd, []string{}); err != nil {
				return err
			}
		} else {
			fmt.Println()
			fmt.Println("Run 'plabs deploy' to apply changes (this will destroy disabled scenarios)")
		}
	}

	return nil
}
