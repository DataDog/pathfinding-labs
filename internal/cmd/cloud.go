package cmd

import (
	"fmt"
	"os"
	"text/tabwriter"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	"github.com/DataDog/pathfinding-labs/internal/config"
)

var cloudCmd = &cobra.Command{
	Use:   "cloud",
	Short: "Manage the active cloud context",
	Long: `Manage which cloud (aws, gcp) plabs commands and the TUI operate against.

A workspace can hold credentials and enabled scenarios for multiple clouds at
once, but only one is "active" at a time — commands like enable, deploy,
plan, and status all implicitly target the active cloud's Terraform root and
scenario subtree. There is no --cloud flag; switch contexts with
'plabs cloud use <cloud>' instead.`,
}

var cloudListCmd = &cobra.Command{
	Use:   "list",
	Short: "List clouds configured for the active workspace",
	RunE:  runCloudList,
}

var cloudUseCmd = &cobra.Command{
	Use:   "use <aws|gcp>",
	Short: "Switch the active cloud context",
	Args:  cobra.ExactArgs(1),
	RunE:  runCloudUse,
}

func init() {
	cloudCmd.AddCommand(cloudListCmd)
	cloudCmd.AddCommand(cloudUseCmd)
}

// isCloudConfigured reports whether the given cloud has any account
// configuration set for the workspace, so `cloud list` can distinguish
// "configured" from "never set up".
func isCloudConfigured(ws *config.WorkspaceConfig, cloud string) bool {
	switch cloud {
	case "aws":
		return ws.AWS.Prod.Profile != ""
	case "gcp":
		return ws.GCP.Prod.ProjectID != ""
	default:
		return false
	}
}

func runCloudList(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load()
	if err != nil {
		cfg = config.NewDefaultConfig()
	}

	ws := cfg.Active()
	active := ws.ActiveCloudOrDefault()

	cyan := color.New(color.FgCyan).SprintFunc()
	green := color.New(color.FgGreen).SprintFunc()
	dim := color.New(color.Faint).SprintFunc()

	fmt.Println()
	w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
	fmt.Fprintf(w, "  CLOUD\tACTIVE\tCONFIGURED\n")
	fmt.Fprintf(w, "  -----\t------\t----------\n")

	for _, cloud := range []string{"aws", "gcp"} {
		activeMarker := ""
		displayName := cloud
		if cloud == active {
			activeMarker = green("*")
			displayName = cyan(cloud)
		}
		configured := dim("no")
		if isCloudConfigured(ws, cloud) {
			configured = green("yes")
		}
		fmt.Fprintf(w, "  %s\t%s\t%s\n", displayName, activeMarker, configured)
	}
	w.Flush()
	fmt.Println()

	return nil
}

func runCloudUse(cmd *cobra.Command, args []string) error {
	cloud := args[0]
	if cloud != "aws" && cloud != "gcp" {
		return fmt.Errorf("invalid cloud %q: must be \"aws\" or \"gcp\"", cloud)
	}

	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	ws := cfg.Active()

	if ws.ActiveCloudOrDefault() == cloud {
		cyan := color.New(color.FgCyan).SprintFunc()
		fmt.Printf("Already using cloud %s\n", cyan(cloud))
		return nil
	}

	if !isCloudConfigured(ws, cloud) {
		yellow := color.New(color.FgYellow).SprintFunc()
		cyan := color.New(color.FgCyan).SprintFunc()
		fmt.Printf("%s Cloud %q has no account configuration for this workspace yet.\n", yellow("Warning:"), cloud)
		fmt.Printf("  Run %s to configure it.\n", cyan("plabs init"))
	}

	ws.ActiveCloud = cloud

	if err := cfg.Save(); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	green := color.New(color.FgGreen).SprintFunc()
	cyan := color.New(color.FgCyan).SprintFunc()
	fmt.Printf("%s Switched active cloud to %s\n", green("OK"), cyan(cloud))
	fmt.Println()

	return nil
}
