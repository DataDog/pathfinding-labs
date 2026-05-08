package cmd

import (
	"fmt"
	"strings"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/terraform"
)

var showCmd = &cobra.Command{
	Use:   "show <id>",
	Short: "Show detailed information about a scenario",
	Long: `Show detailed information about a scenario, including its attack path,
permissions, MITRE ATT&CK mapping, credentials (if deployed), and resources.

Examples:
  plabs scenarios show iam-002
  plabs scenarios show iam-002-to-admin
  plabs scenarios show sts-001-to-bucket`,
	Args: cobra.ExactArgs(1),
	RunE: runShow,
}

func runShow(cmd *cobra.Command, args []string) error {
	id := args[0]

	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	// Load config
	cfg, _ := config.Load()
	enabledVars := make(map[string]bool)
	if cfg != nil {
		enabledVars = cfg.Active().GetEnabledScenarioVars()
	}

	// Find scenario by ID
	discovery := newDiscovery(paths.ScenariosPath())
	scenario, err := discovery.FindByID(id)
	if err != nil {
		return fmt.Errorf("failed to find scenario: %w", err)
	}
	if scenario == nil {
		return fmt.Errorf("scenario %q not found", id)
	}

	// Determine enabled and deployed status
	isEnabled := enabledVars[scenario.Terraform.VariableName]

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

	deployed := isScenarioDeployed(scenario, outputs, deployedModules)

	// Colors
	cyan := color.New(color.FgCyan).SprintFunc()
	green := color.New(color.FgGreen).SprintFunc()
	yellow := color.New(color.FgYellow).SprintFunc()
	red := color.New(color.FgRed).SprintFunc()
	dim := color.New(color.Faint).SprintFunc()
	bold := color.New(color.Bold).SprintFunc()
	costColor := color.New(color.FgHiYellow).SprintFunc()

	termWidth := getTerminalWidth()
	contentWidth := termWidth - 4
	if contentWidth < 40 {
		contentWidth = 40
	}

	// Header
	fmt.Println()
	fmt.Printf("%s %s %s\n", cyan("═══"), bold(fmt.Sprintf("Scenario: %s", scenario.UniqueID())), cyan("═══"))
	fmt.Println()

	// Name
	fmt.Printf("  %-14s %s\n", bold("Name"), scenario.Name)

	// Status (4-state)
	var statusStr string
	if isEnabled && deployed {
		statusStr = green("● Deployed")
	} else if isEnabled && !deployed {
		statusStr = yellow("● Pending deploy")
	} else if !isEnabled && deployed {
		statusStr = red("● Pending destroy")
	} else {
		statusStr = dim("○ Disabled")
	}
	fmt.Printf("  %-14s %s\n", bold("Status"), statusStr)

	// Demo active warning
	if scenario.HasDemoActive() {
		warnStyle := color.New(color.FgHiYellow).SprintFunc()
		fmt.Printf("  %-14s %s\n", bold("Demo"), warnStyle("\u26a0 Active \u2014 run cleanup to remove artifacts"))
	}

	// Category & Target
	fmt.Printf("  %-14s %s\n", bold("Category"), scenario.CategoryShort())
	fmt.Printf("  %-14s %s\n", bold("Target"), scenario.TargetShort())

	// Cost
	costStr := scenario.CostEstimate
	if costStr == "" {
		costStr = "unknown"
	}
	if costStr != "$0/mo" && costStr != "$0" && costStr != "unknown" {
		fmt.Printf("  %-14s %s\n", bold("Cost"), costColor(costStr))
	} else {
		fmt.Printf("  %-14s %s\n", bold("Cost"), dim(costStr))
	}

	// Link
	if scenario.PathfindingCloudID != "" {
		url := fmt.Sprintf("https://pathfinding.cloud/paths/%s", scenario.PathfindingCloudID)
		fmt.Printf("  %-14s %s\n", bold("Link"), cyan(url))
	}

	// Description
	if scenario.Description != "" {
		fmt.Println()
		fmt.Printf("  %s\n", cyan("Description"))
		wrapped := wordWrap(scenario.Description, contentWidth-4)
		for _, line := range strings.Split(wrapped, "\n") {
			fmt.Printf("    %s\n", line)
		}
	}

	// Attack Path
	if scenario.AttackPath.Summary != "" {
		fmt.Println()
		fmt.Printf("  %s\n", cyan("Attack Path"))
		wrapped := wordWrap(scenario.AttackPath.Summary, contentWidth-4)
		for _, line := range strings.Split(wrapped, "\n") {
			fmt.Printf("    %s\n", line)
		}
	}

	// Required Permissions
	if len(scenario.Permissions.Required) > 0 {
		fmt.Println()
		fmt.Printf("  %s\n", cyan("Required Permissions"))
		for _, entry := range scenario.Permissions.Required {
			if entry.Principal != "" {
				fmt.Printf("    %s\n", dim(entry.Principal))
			}
			for _, perm := range entry.Permissions {
				fmt.Printf("      %s %s\n", dim("*"), perm.Permission)
			}
		}
	}

	// MITRE ATT&CK
	if len(scenario.MitreAttack.Tactics) > 0 || len(scenario.MitreAttack.Techniques) > 0 {
		fmt.Println()
		fmt.Printf("  %s\n", cyan("MITRE ATT&CK"))
		if len(scenario.MitreAttack.Tactics) > 0 {
			fmt.Printf("    %-14s %s\n", bold("Tactics:"), strings.Join(scenario.MitreAttack.Tactics, ", "))
		}
		if len(scenario.MitreAttack.Techniques) > 0 {
			fmt.Printf("    %-14s %s\n", bold("Techniques:"), strings.Join(scenario.MitreAttack.Techniques, ", "))
		}
	}

	// Credentials (only if deployed)
	if deployed && outputs != nil {
		outputName := getScenarioOutputName(scenario)
		creds, err := outputs.GetStartingCredentials(outputName)
		if err == nil && creds != nil {
			fmt.Println()
			fmt.Printf("  %s %s\n", cyan("Starting Credentials"), dim("(Environment Variables)"))
			fmt.Printf("    export AWS_ACCESS_KEY_ID=%s\n", creds.AccessKeyID)
			fmt.Printf("    export AWS_SECRET_ACCESS_KEY=%s\n", creds.SecretAccessKey)
			if creds.SessionToken != "" {
				fmt.Printf("    export AWS_SESSION_TOKEN=%s\n", creds.SessionToken)
			}

			fmt.Println()
			fmt.Printf("  %s %s\n", cyan("Starting Credentials"), dim("(AWS Profile)"))
			fmt.Printf("    [%s]\n", scenario.UniqueID())
			fmt.Printf("    aws_access_key_id = %s\n", creds.AccessKeyID)
			fmt.Printf("    aws_secret_access_key = %s\n", creds.SecretAccessKey)
			if creds.SessionToken != "" {
				fmt.Printf("    aws_session_token = %s\n", creds.SessionToken)
			}
		}
	}

	// Deployed Resources (only if deployed)
	if deployed {
		outputName := getScenarioOutputName(scenario)
		resources, err := runner.GetModuleResources(outputName)
		if err == nil && len(resources) > 0 {
			fmt.Println()
			fmt.Printf("  %s\n", cyan("Deployed Resources"))
			for _, arn := range resources {
				displayARN := arn
				if len(displayARN) > contentWidth-6 {
					displayARN = displayARN[:contentWidth-9] + "..."
				}
				fmt.Printf("    %s %s\n", dim("*"), displayARN)
			}
		}
	}

	fmt.Println()
	return nil
}

// wordWrap wraps text to the given width, breaking at word boundaries
func wordWrap(text string, width int) string {
	if width <= 0 {
		return text
	}

	var lines []string
	var currentLine strings.Builder

	words := strings.Fields(text)
	for _, word := range words {
		if currentLine.Len()+len(word)+1 > width {
			if currentLine.Len() > 0 {
				lines = append(lines, currentLine.String())
				currentLine.Reset()
			}
		}
		if currentLine.Len() > 0 {
			currentLine.WriteString(" ")
		}
		currentLine.WriteString(word)
	}
	if currentLine.Len() > 0 {
		lines = append(lines, currentLine.String())
	}

	return strings.Join(lines, "\n")
}
