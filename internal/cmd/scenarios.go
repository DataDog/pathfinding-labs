package cmd

import (
	"fmt"
	"os"
	"strings"

	"github.com/fatih/color"
	"github.com/spf13/cobra"
	"golang.org/x/term"

	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/scenarios"
	"github.com/DataDog/pathfinding-labs/internal/terraform"
)

// getTerminalWidth returns the terminal width, or a default of 80 if it can't be determined
func getTerminalWidth() int {
	width, _, err := term.GetSize(int(os.Stdout.Fd()))
	if err != nil || width <= 0 {
		return 80 // default fallback
	}
	return width
}

var scenariosCmd = &cobra.Command{
	Use:   "scenarios",
	Short: "Browse and manage attack scenarios",
	Long:  `Browse available attack scenarios, filter by category, and view details.`,
}

var scenariosListCmd = &cobra.Command{
	Use:   "list",
	Short: "List available scenarios",
	Long: `List all available attack scenarios.

Filter by category:
  plabs scenarios list --category=one-hop
  plabs scenarios list --category=self-escalation

Filter by target:
  plabs scenarios list --target=admin
  plabs scenarios list --target=bucket

Filter by cost:
  plabs scenarios list --cost=free

Filter by MITRE technique:
  plabs scenarios list --mitre=T1098

Show only enabled:
  plabs scenarios list --enabled`,
	RunE: runScenariosList,
}

var (
	filterCategory string
	filterTarget   string
	filterCost     string
	filterMitre    string
	filterEnabled  bool
	wideOutput     bool
)

func init() {
	scenariosListCmd.Flags().StringVar(&filterCategory, "category", "", "Filter by category (self-escalation, one-hop, multi-hop, toxic-combo, tool-testing, cross-account)")
	scenariosListCmd.Flags().StringVar(&filterTarget, "target", "", "Filter by target (admin, bucket)")
	scenariosListCmd.Flags().StringVar(&filterCost, "cost", "", "Filter by cost estimate (free, low, medium)")
	scenariosListCmd.Flags().StringVar(&filterMitre, "mitre", "", "Filter by MITRE ATT&CK technique ID (e.g., T1098)")
	scenariosListCmd.Flags().BoolVar(&filterEnabled, "enabled", false, "Show only enabled scenarios")
	scenariosListCmd.Flags().BoolVar(&wideOutput, "wide", false, "Show full descriptions (no truncation)")

	scenariosCmd.AddCommand(scenariosListCmd)

	// Add enable, disable, demo, cleanup as subcommands of scenarios
	// (they also exist at top level as aliases)
	scenariosCmd.AddCommand(enableCmd)
	scenariosCmd.AddCommand(disableCmd)
	scenariosCmd.AddCommand(demoCmd)
	scenariosCmd.AddCommand(cleanupCmd)
}

func runScenariosList(cmd *cobra.Command, args []string) error {
	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	// Load config to check if single-account mode
	cfg, _ := config.Load(paths.ConfigPath)
	singleAccountMode := cfg == nil || cfg.IsSingleAccountMode()

	// Discover all scenarios
	discovery := scenarios.NewDiscovery(paths.ScenariosPath())
	allScenarios, err := discovery.DiscoverAll()
	if err != nil {
		return fmt.Errorf("failed to discover scenarios: %w", err)
	}

	// Get enabled status
	tfvars := terraform.NewTFVars(paths.TFVarsPath)
	enabledVars, err := tfvars.GetEnabledScenarios()
	if err != nil {
		enabledVars = make(map[string]bool)
	}

	// Apply filters
	filter := scenarios.Filter{
		Category:    filterCategory,
		Target:      filterTarget,
		Cost:        filterCost,
		MitreID:     filterMitre,
		EnabledOnly: filterEnabled,
	}

	filtered := scenarios.FilterScenarios(allScenarios, filter, enabledVars)

	// Colors
	green := color.New(color.FgGreen).SprintFunc()
	cyan := color.New(color.FgCyan).SprintFunc()
	dim := color.New(color.Faint).SprintFunc()
	bold := color.New(color.Bold).SprintFunc()

	fmt.Println()
	fmt.Printf("%s (%d scenarios)\n", bold("Available Scenarios"), len(filtered))

	// Organize scenarios hierarchically like the README
	type scenarioGroup struct {
		scenarios []*scenarios.Scenario
	}

	// Single Account - Privilege Escalation to Admin
	selfEscalationAdmin := scenarioGroup{}
	oneHopAdmin := scenarioGroup{}
	multiHopAdmin := scenarioGroup{}

	// Single Account - Privilege Escalation to Bucket
	selfEscalationBucket := scenarioGroup{}
	oneHopBucket := scenarioGroup{}
	multiHopBucket := scenarioGroup{}

	// Single Account - Other
	toxicCombo := scenarioGroup{}
	toolTesting := scenarioGroup{}

	// Cross-Account
	crossAccountDevToProd := scenarioGroup{}
	crossAccountOpsToProd := scenarioGroup{}

	// Categorize each scenario
	for _, s := range filtered {
		path := s.Terraform.ModulePath

		switch {
		case strings.Contains(path, "cross-account/dev-to-prod"):
			crossAccountDevToProd.scenarios = append(crossAccountDevToProd.scenarios, s)
		case strings.Contains(path, "cross-account/ops-to-prod"):
			crossAccountOpsToProd.scenarios = append(crossAccountOpsToProd.scenarios, s)
		case strings.Contains(path, "toxic-combo"):
			toxicCombo.scenarios = append(toxicCombo.scenarios, s)
		case strings.Contains(path, "tool-testing"):
			toolTesting.scenarios = append(toolTesting.scenarios, s)
		case strings.Contains(path, "privesc-self-escalation") && strings.Contains(path, "to-admin"):
			selfEscalationAdmin.scenarios = append(selfEscalationAdmin.scenarios, s)
		case strings.Contains(path, "privesc-self-escalation") && strings.Contains(path, "to-bucket"):
			selfEscalationBucket.scenarios = append(selfEscalationBucket.scenarios, s)
		case strings.Contains(path, "privesc-one-hop") && strings.Contains(path, "to-admin"):
			oneHopAdmin.scenarios = append(oneHopAdmin.scenarios, s)
		case strings.Contains(path, "privesc-one-hop") && strings.Contains(path, "to-bucket"):
			oneHopBucket.scenarios = append(oneHopBucket.scenarios, s)
		case strings.Contains(path, "privesc-multi-hop") && strings.Contains(path, "to-admin"):
			multiHopAdmin.scenarios = append(multiHopAdmin.scenarios, s)
		case strings.Contains(path, "privesc-multi-hop") && strings.Contains(path, "to-bucket"):
			multiHopBucket.scenarios = append(multiHopBucket.scenarios, s)
		}
	}

	// Get terminal width for dynamic truncation
	termWidth := getTerminalWidth()

	// Helper to print a section
	printSection := func(title string, group scenarioGroup, indent string) {
		if len(group.scenarios) == 0 {
			return
		}
		fmt.Printf("%s%s (%d)\n", indent, bold(title), len(group.scenarios))
		for _, s := range group.scenarios {
			isEnabled := enabledVars[s.Terraform.VariableName]
			isCrossAccountUnavailable := singleAccountMode && s.RequiresMultiAccount()

			id := s.UniqueID()
			var status string
			if isEnabled {
				status = green("●")
			} else if isCrossAccountUnavailable {
				status = dim("○")
			} else {
				status = "○"
			}

			idStr := fmt.Sprintf("%-24s", id)

			// Calculate available width for description
			// Format: indent + "  " + status + " " + id (24) + " " + description
			usedWidth := len(indent) + 2 + 1 + 1 + 24 + 1
			descWidth := termWidth - usedWidth
			if descWidth < 20 {
				descWidth = 20 // minimum description width
			}

			if isCrossAccountUnavailable {
				desc := s.Description
				suffix := " [requires multi-account]"
				if !wideOutput {
					// Account for the suffix in truncation
					desc = truncate(desc, descWidth-len(suffix))
				}
				fmt.Printf("%s  %s %s %s\n", indent, status, dim(idStr), dim(desc+suffix))
			} else {
				desc := s.Description
				if !wideOutput {
					desc = truncate(desc, descWidth)
				}
				fmt.Printf("%s  %s %s %s\n", indent, status, cyan(idStr), desc)
			}
		}
	}

	// Print Single Account section
	hasSingleAccount := len(selfEscalationAdmin.scenarios) > 0 || len(oneHopAdmin.scenarios) > 0 ||
		len(multiHopAdmin.scenarios) > 0 || len(selfEscalationBucket.scenarios) > 0 ||
		len(oneHopBucket.scenarios) > 0 || len(multiHopBucket.scenarios) > 0 ||
		len(toxicCombo.scenarios) > 0 || len(toolTesting.scenarios) > 0

	if hasSingleAccount {
		fmt.Println()
		fmt.Printf("%s\n", cyan("══════════════════════════════════════════════════════════════"))
		fmt.Printf("%s\n", bold("SINGLE ACCOUNT"))
		fmt.Printf("%s\n", cyan("══════════════════════════════════════════════════════════════"))

		// Privilege Escalation to Admin
		hasPrivEscAdmin := len(selfEscalationAdmin.scenarios) > 0 || len(oneHopAdmin.scenarios) > 0 || len(multiHopAdmin.scenarios) > 0
		if hasPrivEscAdmin {
			fmt.Println()
			fmt.Printf("  %s\n", bold("Privilege Escalation to Admin"))
			printSection("Self-Escalation", selfEscalationAdmin, "    ")
			printSection("One-Hop", oneHopAdmin, "    ")
			printSection("Multi-Hop", multiHopAdmin, "    ")
		}

		// Privilege Escalation to Bucket
		hasPrivEscBucket := len(selfEscalationBucket.scenarios) > 0 || len(oneHopBucket.scenarios) > 0 || len(multiHopBucket.scenarios) > 0
		if hasPrivEscBucket {
			fmt.Println()
			fmt.Printf("  %s\n", bold("Privilege Escalation to Bucket"))
			printSection("Self-Escalation", selfEscalationBucket, "    ")
			printSection("One-Hop", oneHopBucket, "    ")
			printSection("Multi-Hop", multiHopBucket, "    ")
		}

		// Toxic Combinations
		if len(toxicCombo.scenarios) > 0 {
			fmt.Println()
			printSection("Toxic Combinations", toxicCombo, "  ")
		}

		// Tool Testing
		if len(toolTesting.scenarios) > 0 {
			fmt.Println()
			printSection("Tool Testing", toolTesting, "  ")
		}
	}

	// Print Cross-Account section
	hasCrossAccount := len(crossAccountDevToProd.scenarios) > 0 || len(crossAccountOpsToProd.scenarios) > 0
	if hasCrossAccount {
		fmt.Println()
		fmt.Printf("%s\n", cyan("══════════════════════════════════════════════════════════════"))
		fmt.Printf("%s\n", bold("CROSS-ACCOUNT"))
		fmt.Printf("%s\n", cyan("══════════════════════════════════════════════════════════════"))
		fmt.Println()

		printSection("Dev to Prod", crossAccountDevToProd, "  ")
		printSection("Ops to Prod", crossAccountOpsToProd, "  ")
	}

	fmt.Println()

	// Summary
	enabledCount := 0
	for _, s := range filtered {
		if enabledVars[s.Terraform.VariableName] {
			enabledCount++
		}
	}

	fmt.Println(dim("─────────────────────────────────────────────────────────────"))
	fmt.Printf("Total: %d scenarios | Enabled: %s | %s = enabled\n",
		len(filtered),
		green(fmt.Sprintf("%d", enabledCount)),
		green("●"))
	fmt.Println()
	fmt.Printf("Use %s to enable a scenario\n", cyan("plabs scenarios enable <id>"))
	fmt.Printf("Use %s to filter by category\n", cyan("plabs scenarios list --category=<cat>"))
	fmt.Println()

	return nil
}

// truncate shortens a string to maxLen characters
func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen-3] + "..."
}
