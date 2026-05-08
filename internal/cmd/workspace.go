package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"text/tabwriter"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/repo"
)

var workspaceCmd = &cobra.Command{
	Use:   "workspace",
	Short: "Manage plabs workspaces",
	Long: `Manage plabs workspaces. Each workspace is a fully isolated environment
with its own AWS profiles, enabled scenarios, and Terraform state.

This is useful when managing labs across multiple AWS organizations
(e.g., work and personal), or for isolating dev-mode from normal-mode
deployments without losing state.

Single-workspace users (the default) see no difference — the "default"
workspace behaves exactly like plabs did before workspaces were introduced.`,
}

var workspaceListCmd = &cobra.Command{
	Use:   "list",
	Short: "List all workspaces",
	RunE:  runWorkspaceList,
}

var workspaceNewCmd = &cobra.Command{
	Use:   "new <name>",
	Short: "Create a new workspace",
	Long: `Create a new workspace entry. The workspace is created with empty AWS
configuration. After creation, switch to it with 'plabs workspace switch <name>'
and run 'plabs init' to configure it.`,
	Args: cobra.ExactArgs(1),
	RunE: runWorkspaceNew,
}

var workspaceSwitchCmd = &cobra.Command{
	Use:   "switch <name>",
	Short: "Switch to a different workspace",
	Args:  cobra.ExactArgs(1),
	RunE:  runWorkspaceSwitch,
}

var workspaceDeleteCmd = &cobra.Command{
	Use:   "delete <name>",
	Short: "Delete a workspace",
	Long: `Delete a workspace. Cannot delete the active workspace or "default".
If the workspace has Terraform state, --force is required.`,
	Args: cobra.ExactArgs(1),
	RunE: runWorkspaceDelete,
}

var workspaceDeleteForce bool

func init() {
	workspaceDeleteCmd.Flags().BoolVar(&workspaceDeleteForce, "force", false, "Force deletion even if Terraform state exists")
	workspaceCmd.AddCommand(workspaceListCmd)
	workspaceCmd.AddCommand(workspaceNewCmd)
	workspaceCmd.AddCommand(workspaceSwitchCmd)
	workspaceCmd.AddCommand(workspaceDeleteCmd)
}

var validWorkspaceName = regexp.MustCompile(`^[a-z0-9][a-z0-9-]{0,31}$`)

func runWorkspaceList(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load()
	if err != nil {
		cfg = config.NewDefaultConfig()
	}

	cyan := color.New(color.FgCyan).SprintFunc()
	green := color.New(color.FgGreen).SprintFunc()
	dim := color.New(color.Faint).SprintFunc()

	fmt.Println()

	w := tabwriter.NewWriter(os.Stdout, 0, 0, 3, ' ', 0)
	fmt.Fprintf(w, "  NAME\tACTIVE\tPROFILE\tSCENARIOS\tINITIALIZED\n")
	fmt.Fprintf(w, "  ----\t------\t-------\t---------\t-----------\n")

	active := cfg.ActiveName()
	for _, name := range cfg.WorkspaceNames() {
		ws := cfg.Workspaces[name]
		activeMarker := ""
		displayName := name
		if name == active {
			activeMarker = green("*")
			displayName = cyan(name)
		}
		profile := ws.AWS.Prod.Profile
		if profile == "" {
			profile = dim("(not set)")
		}
		initialized := dim("no")
		if ws.Initialized {
			initialized = green("yes")
		}
		scenarioCount := fmt.Sprintf("%d", len(ws.Scenarios.Enabled))
		fmt.Fprintf(w, "  %s\t%s\t%s\t%s\t%s\n", displayName, activeMarker, profile, scenarioCount, initialized)
	}
	w.Flush()

	fmt.Println()
	if cfg.WorkspaceCount() == 1 {
		fmt.Println(dim("  Use 'plabs workspace new <name>' to create additional workspaces"))
	}
	fmt.Println()

	return nil
}

func runWorkspaceNew(cmd *cobra.Command, args []string) error {
	name := args[0]

	if !validWorkspaceName.MatchString(name) {
		return fmt.Errorf("invalid workspace name %q: must match [a-z0-9][a-z0-9-]{0,31}", name)
	}
	if name == "default" {
		return fmt.Errorf("cannot create a workspace named \"default\": it already exists")
	}

	cfg, err := config.Load()
	if err != nil {
		cfg = config.NewDefaultConfig()
	}

	if _, exists := cfg.Workspaces[name]; exists {
		return fmt.Errorf("workspace %q already exists", name)
	}

	newWS := &config.WorkspaceConfig{}

	// Copy flags from the current active workspace's repo into the new workspace.
	// All workspaces share the same flag values (they come from the same upstream repo),
	// so seeding at creation time means the new workspace never deploys flag{MISSING}.
	activeWS := cfg.Active()
	if activePaths, pathErr := repo.GetPathsForWorkspace(cfg.ActiveName(), activeWS.DevMode, activeWS.DevModePath); pathErr == nil {
		candidate := filepath.Join(activePaths.TerraformDir, DefaultFlagFileName)
		if _, statErr := os.Stat(candidate); statErr == nil {
			_ = newWS.LoadFlagsFromFile(candidate)
		}
	}

	cfg.Workspaces[name] = newWS

	if err := cfg.Save(); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	green := color.New(color.FgGreen).SprintFunc()
	cyan := color.New(color.FgCyan).SprintFunc()
	fmt.Printf("%s Created workspace %q\n", green("OK"), name)
	if len(newWS.Flags) > 0 {
		fmt.Printf("  Seeded %d CTF flag(s) from active workspace\n", len(newWS.Flags))
	}
	fmt.Println()
	fmt.Printf("Next steps:\n")
	fmt.Printf("  1. Switch to it:  %s\n", cyan(fmt.Sprintf("plabs workspace switch %s", name)))
	fmt.Printf("  2. Initialize it: %s\n", cyan("plabs init"))
	fmt.Println()

	return nil
}

func runWorkspaceSwitch(cmd *cobra.Command, args []string) error {
	name := args[0]

	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	if _, exists := cfg.Workspaces[name]; !exists {
		names := cfg.WorkspaceNames()
		return fmt.Errorf("workspace %q does not exist\n\nAvailable workspaces: %s", name, strings.Join(names, ", "))
	}

	if cfg.ActiveName() == name {
		cyan := color.New(color.FgCyan).SprintFunc()
		fmt.Printf("Already on workspace %s\n", cyan(name))
		return nil
	}

	// Warn if current workspace has a terraform lock
	currentWS := cfg.Active()
	if currentPaths, pathErr := repo.GetPathsForWorkspace(cfg.ActiveName(), currentWS.DevMode, currentWS.DevModePath); pathErr == nil {
		lockFile := currentPaths.TerraformDir + "/.terraform.tfstate.lock.info"
		if _, statErr := os.Stat(lockFile); statErr == nil {
			yellow := color.New(color.FgYellow).SprintFunc()
			fmt.Printf("%s Terraform lock file detected in current workspace (%s).\n", yellow("Warning:"), cfg.ActiveName())
			fmt.Println("  A terraform operation may be in progress. Switching anyway.")
			fmt.Println()
		}
	}

	cfg.ActiveWorkspace = name

	if err := cfg.Save(); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	green := color.New(color.FgGreen).SprintFunc()
	cyan := color.New(color.FgCyan).SprintFunc()
	ws := cfg.Active()

	fmt.Printf("%s Switched to workspace %s\n", green("OK"), cyan(name))
	if !ws.Initialized {
		fmt.Println()
		fmt.Printf("  This workspace is not yet initialized. Run %s to set it up.\n", cyan("plabs init"))
	}
	fmt.Println()

	return nil
}

func runWorkspaceDelete(cmd *cobra.Command, args []string) error {
	name := args[0]

	if name == "default" {
		return fmt.Errorf("cannot delete the \"default\" workspace")
	}

	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	if _, exists := cfg.Workspaces[name]; !exists {
		return fmt.Errorf("workspace %q does not exist", name)
	}

	if cfg.ActiveName() == name {
		return fmt.Errorf("cannot delete the active workspace %q\n\nSwitch to another workspace first: plabs workspace switch default", name)
	}

	ws := cfg.Workspaces[name]
	paths, pathErr := repo.GetPathsForWorkspace(name, ws.DevMode, ws.DevModePath)
	if pathErr == nil {
		stateFile := paths.TerraformDir + "/terraform.tfstate"
		if info, statErr := os.Stat(stateFile); statErr == nil && info.Size() > 2 {
			if !workspaceDeleteForce {
				return fmt.Errorf("workspace %q has Terraform state\n\nDestroy infrastructure first, or use --force to delete anyway (this will not destroy AWS resources)", name)
			}
			yellow := color.New(color.FgYellow).SprintFunc()
			fmt.Printf("%s Deleting workspace with existing Terraform state\n", yellow("Warning:"))
		}
	}

	delete(cfg.Workspaces, name)

	if err := cfg.Save(); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	green := color.New(color.FgGreen).SprintFunc()
	cyan := color.New(color.FgCyan).SprintFunc()
	fmt.Printf("%s Deleted workspace %q\n", green("OK"), name)

	// Offer to delete the workspace directory for non-default workspaces
	if pathErr == nil && !ws.DevMode {
		wsDir := paths.TerraformDir
		if _, statErr := os.Stat(wsDir); statErr == nil {
			fmt.Println()
			fmt.Printf("  Workspace directory still exists at: %s\n", wsDir)
			fmt.Printf("  To remove it: %s\n", cyan(fmt.Sprintf("rm -rf %s", wsDir)))
		}
	}
	fmt.Println()

	return nil
}
