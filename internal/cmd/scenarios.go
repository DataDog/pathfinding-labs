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
  plabs scenarios list --enabled

Show only deployed:
  plabs scenarios list --deployed`,
	RunE: runScenariosList,
}

var (
	filterCategory   string
	filterTarget     string
	filterCost       string
	filterMitre      string
	filterEnabled    bool
	filterDeployed   bool
	filterDemoActive bool
	wideOutput       bool
)

func init() {
	scenariosListCmd.Flags().StringVar(&filterCategory, "category", "", "Filter by category (self-escalation, one-hop, multi-hop, cross-account, cspm-misconfig, cspm-toxic-combo, tool-testing)")
	scenariosListCmd.Flags().StringVar(&filterTarget, "target", "", "Filter by target (admin, bucket)")
	scenariosListCmd.Flags().StringVar(&filterCost, "cost", "", "Filter by cost estimate (free, low, medium)")
	scenariosListCmd.Flags().StringVar(&filterMitre, "mitre", "", "Filter by MITRE ATT&CK technique ID (e.g., T1098)")
	scenariosListCmd.Flags().BoolVar(&filterEnabled, "enabled", false, "Show only enabled scenarios")
	scenariosListCmd.Flags().BoolVar(&filterDeployed, "deployed", false, "Show only deployed scenarios")
	scenariosListCmd.Flags().BoolVar(&filterDemoActive, "demo-active", false, "Show only scenarios with active demos")
	scenariosListCmd.Flags().BoolVar(&wideOutput, "wide", false, "Show full descriptions (no truncation)")

	scenariosCmd.AddCommand(scenariosListCmd)
	scenariosCmd.AddCommand(showCmd)
	scenariosCmd.AddCommand(credentialsAliasCmd)
	scenariosCmd.AddCommand(outputAliasCmd)

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
	cfg, _ := config.Load()
	singleAccountMode := cfg == nil || !cfg.IsMultiAccountMode()

	// Discover all scenarios
	discovery := newDiscovery(paths.ScenariosPath())
	allScenarios, err := discovery.DiscoverAll()
	if err != nil {
		return fmt.Errorf("failed to discover scenarios: %w", err)
	}

	// Get enabled status from config (source of truth)
	enabledVars := make(map[string]bool)
	if cfg != nil {
		enabledVars = cfg.GetEnabledScenarioVars()
	}

	// Load deployment state for 4-state indicators and --deployed filter
	runner := terraform.NewRunner(paths.BinPath, paths.TerraformDir)
	var outputs terraform.Outputs
	var deployedModules map[string]bool

	if runner.IsInitialized() {
		outputJSON, err := runner.OutputJSON()
		if err == nil && outputJSON != "" {
			outputs, _ = terraform.ParseOutputs(outputJSON)
		}
		deployedModules = runner.GetDeployedModules()
	}

	// Build deployed lookup
	deployedVars := make(map[string]bool)
	for _, s := range allScenarios {
		if isScenarioDeployed(s, outputs, deployedModules) {
			deployedVars[s.Terraform.VariableName] = true
		}
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

	// Apply --deployed filter
	if filterDeployed {
		var deployedFiltered []*scenarios.Scenario
		for _, s := range filtered {
			if deployedVars[s.Terraform.VariableName] {
				deployedFiltered = append(deployedFiltered, s)
			}
		}
		filtered = deployedFiltered
	}

	// Apply --demo-active filter
	if filterDemoActive {
		var demoActiveFiltered []*scenarios.Scenario
		for _, s := range filtered {
			if s.HasDemoActive() {
				demoActiveFiltered = append(demoActiveFiltered, s)
			}
		}
		filtered = demoActiveFiltered
	}

	// Colors
	green := color.New(color.FgGreen).SprintFunc()
	yellow := color.New(color.FgYellow).SprintFunc()
	red := color.New(color.FgRed).SprintFunc()
	cyan := color.New(color.FgCyan).SprintFunc()
	dim := color.New(color.Faint).SprintFunc()
	bold := color.New(color.Bold).SprintFunc()
	costColor := color.New(color.FgHiYellow).SprintFunc()

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

	// Single Account - CSPM
	cspmMisconfig := scenarioGroup{}
	toxicCombo := scenarioGroup{}
	toolTesting := scenarioGroup{}

	// Cross-Account
	crossAccountDevToProd := scenarioGroup{}
	crossAccountOpsToProd := scenarioGroup{}

	// CTF
	ctf := scenarioGroup{}

	// Categorize each scenario
	for _, s := range filtered {
		path := s.Terraform.ModulePath

		switch {
		case strings.Contains(path, "/ctf/"):
			ctf.scenarios = append(ctf.scenarios, s)
		case strings.Contains(path, "cross-account/dev-to-prod"):
			crossAccountDevToProd.scenarios = append(crossAccountDevToProd.scenarios, s)
		case strings.Contains(path, "cross-account/ops-to-prod"):
			crossAccountOpsToProd.scenarios = append(crossAccountOpsToProd.scenarios, s)
		case strings.Contains(path, "cspm-toxic-combo"):
			toxicCombo.scenarios = append(toxicCombo.scenarios, s)
		case strings.Contains(path, "cspm-misconfig"):
			cspmMisconfig.scenarios = append(cspmMisconfig.scenarios, s)
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
			isDeployed := deployedVars[s.Terraform.VariableName]
			isCrossAccountUnavailable := singleAccountMode && s.RequiresMultiAccount()

			id := s.UniqueID()

			// 4-state status indicator
			var status string
			if isEnabled && isDeployed {
				status = green("●") // enabled + deployed
			} else if isEnabled && !isDeployed {
				status = yellow("●") // enabled, pending deploy
			} else if !isEnabled && isDeployed {
				status = red("●") // disabled, pending destroy
			} else if isCrossAccountUnavailable {
				status = dim("○") // unavailable
			} else {
				status = dim("○") // disabled
			}

			idStr := fmt.Sprintf("%-24s", id)

			// Cost suffix
			costSuffix := ""
			if s.CostEstimate != "" {
				costSuffix = fmt.Sprintf(" (%s)", s.CostEstimate)
			}
			costSuffixLen := len(costSuffix)

			// Calculate available width for description
			// Format: indent + "  " + status + " " + id (24) + " " + description + costSuffix
			usedWidth := len(indent) + 2 + 1 + 1 + 24 + 1 + costSuffixLen
			descWidth := termWidth - usedWidth
			if descWidth < 20 {
				descWidth = 20 // minimum description width
			}

			// Color the cost suffix
			var coloredCostSuffix string
			if costSuffix != "" {
				if s.CostEstimate != "$0/mo" && s.CostEstimate != "$0" {
					coloredCostSuffix = costColor(costSuffix)
				} else {
					coloredCostSuffix = dim(costSuffix)
				}
			}

			// Demo active indicator
			demoActiveSuffix := ""
			if s.HasDemoActive() {
				demoActiveSuffix = costColor(" \u26a0 demo active")
			}

			if isCrossAccountUnavailable {
				desc := s.Description
				suffix := " [requires multi-account]"
				if !wideOutput {
					desc = truncate(desc, descWidth-len(suffix))
				}
				fmt.Printf("%s  %s %s %s%s%s\n", indent, status, dim(idStr), dim(desc+suffix), coloredCostSuffix, demoActiveSuffix)
			} else {
				desc := s.Description
				if !wideOutput {
					desc = truncate(desc, descWidth)
				}
				fmt.Printf("%s  %s %s %s%s%s\n", indent, status, cyan(idStr), desc, coloredCostSuffix, demoActiveSuffix)
			}
		}
	}

	// Print Single Account section
	hasSingleAccount := len(selfEscalationAdmin.scenarios) > 0 || len(oneHopAdmin.scenarios) > 0 ||
		len(multiHopAdmin.scenarios) > 0 || len(selfEscalationBucket.scenarios) > 0 ||
		len(oneHopBucket.scenarios) > 0 || len(multiHopBucket.scenarios) > 0 ||
		len(cspmMisconfig.scenarios) > 0 || len(toxicCombo.scenarios) > 0 || len(toolTesting.scenarios) > 0

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

		// CSPM
		hasCSPM := len(cspmMisconfig.scenarios) > 0 || len(toxicCombo.scenarios) > 0
		if hasCSPM {
			fmt.Println()
			fmt.Printf("  %s\n", bold("CSPM"))
			printSection("Misconfig", cspmMisconfig, "    ")
			printSection("Toxic Combo", toxicCombo, "    ")
		}

		// Tool Testing
		if len(toolTesting.scenarios) > 0 {
			fmt.Println()
			printSection("Tool Testing", toolTesting, "  ")
		}
	}

	// Print CTF section
	if len(ctf.scenarios) > 0 {
		fmt.Println()
		fmt.Printf("%s\n", cyan("══════════════════════════════════════════════════════════════"))
		fmt.Printf("%s\n", bold("CTF"))
		fmt.Printf("%s\n", cyan("══════════════════════════════════════════════════════════════"))
		fmt.Println()
		printSection("Challenges", ctf, "  ")
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
	deployedCount := 0
	demoActiveCount := 0
	var runningCost float64
	for _, s := range filtered {
		isEnabled := enabledVars[s.Terraform.VariableName]
		isDeployed := deployedVars[s.Terraform.VariableName]
		if isEnabled {
			enabledCount++
		}
		if isDeployed {
			deployedCount++
		}
		if isEnabled && isDeployed {
			runningCost += parseCostString(s.CostEstimate)
		}
		if s.HasDemoActive() {
			demoActiveCount++
		}
	}

	fmt.Println(dim("─────────────────────────────────────────────────────────────"))

	// Status legend
	legendParts := []string{
		fmt.Sprintf("%s = deployed", green("●")),
		fmt.Sprintf("%s = pending", yellow("●")),
		fmt.Sprintf("%s = pending destroy", red("●")),
		fmt.Sprintf("%s = disabled", dim("○")),
	}

	// Build summary line
	summaryParts := []string{
		fmt.Sprintf("Total: %d scenarios", len(filtered)),
		fmt.Sprintf("Enabled: %s", green(fmt.Sprintf("%d", enabledCount))),
		fmt.Sprintf("Deployed: %s", green(fmt.Sprintf("%d", deployedCount))),
	}

	if demoActiveCount > 0 {
		summaryParts = append(summaryParts, fmt.Sprintf("Demo active: %s", costColor(fmt.Sprintf("%d \u26a0", demoActiveCount))))
	}

	if runningCost > 0 {
		costPerDay := runningCost / 30
		summaryParts = append(summaryParts,
			fmt.Sprintf("Running cost: %s %s",
				costColor(fmt.Sprintf("$%.0f/mo", runningCost)),
				dim(fmt.Sprintf("($%.2f/day)", costPerDay))))
	} else {
		summaryParts = append(summaryParts, fmt.Sprintf("Running cost: %s", dim("$0/mo")))
	}

	fmt.Println(strings.Join(summaryParts, " | "))
	fmt.Printf("%s\n", dim(strings.Join(legendParts, "  ")))
	fmt.Println()
	fmt.Printf("Use %s to enable a scenario\n", cyan("plabs scenarios enable <id>"))
	fmt.Printf("Use %s to view scenario details\n", cyan("plabs scenarios show <id>"))
	fmt.Println()

	return nil
}

// parseCostString extracts the numeric value from a cost string like "$8/mo"
func parseCostString(cost string) float64 {
	if cost == "" {
		return 0
	}
	cost = strings.TrimPrefix(cost, "$")
	cost = strings.TrimSuffix(cost, "/mo")
	cost = strings.TrimSuffix(cost, "/month")

	var value float64
	fmt.Sscanf(cost, "%f", &value)
	return value
}

// truncate shortens a string to maxLen characters
func truncate(s string, maxLen int) string {
	if maxLen <= 3 {
		return s
	}
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen-3] + "..."
}
