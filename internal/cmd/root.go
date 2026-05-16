package cmd

import (
	"fmt"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	"github.com/DataDog/pathfinding-labs/internal/updater"
)

var (
	version       = "0.0.1"
	commit        = "unknown"
	installMethod = "unknown" // overridden via ldflags: "source" (Makefile) or "release" (goreleaser)
)

var rootCmd = &cobra.Command{
	Use:   "plabs",
	Short: "Pathfinding Labs - AWS attack path scenario management",
	Long: `plabs is a CLI tool for managing Pathfinding Labs scenarios.

Pathfinding Labs deploys intentionally vulnerable AWS configurations
to validate Cloud Security Posture Management (CSPM) tools and
train security teams on cloud attack paths.

Running 'plabs' with no arguments launches the interactive TUI dashboard.
All commands are also available for scripting:

  plabs              - Launch the interactive TUI dashboard
  plabs help         - Show this help message
  plabs init         - Set up plabs and configure your AWS accounts
  plabs scenarios    - Browse available attack scenarios
  plabs enable       - Enable a specific scenario
  plabs apply       - Deploy enabled scenarios to AWS`,
	SilenceUsage:  true,
	SilenceErrors: true,
	// Run TUI by default when no subcommand is provided
	RunE: func(cmd *cobra.Command, args []string) error {
		return runTUI(cmd, args)
	},
}

// Execute runs the root command
func Execute() error {
	return rootCmd.Execute()
}

func init() {
	rootCmd.AddCommand(initCmd)
	rootCmd.AddCommand(updateCmd)
	rootCmd.AddCommand(infoCmd)
	rootCmd.AddCommand(configCmd)
	rootCmd.AddCommand(scenariosCmd)
	rootCmd.AddCommand(enableCmd)
	rootCmd.AddCommand(disableCmd)
	rootCmd.AddCommand(statusCmd)
	rootCmd.AddCommand(deployCmd)
	rootCmd.AddCommand(planCmd)
	rootCmd.AddCommand(destroyCmd)
	rootCmd.AddCommand(demoCmd)
	rootCmd.AddCommand(cleanupCmd)
	rootCmd.AddCommand(credentialsCmd)
	rootCmd.AddCommand(outputCmd)
	rootCmd.AddCommand(workspaceCmd)
	rootCmd.AddCommand(versionCmd)
}

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print the version number",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Printf("plabs %s (commit: %s)\n", version, commit)
		syncInstallMethod()
		if notice := updater.Check(version); notice != "" {
			yellow := color.New(color.FgYellow).SprintFunc()
			fmt.Println()
			fmt.Println(yellow(notice))
		}
	},
}

// syncInstallMethod propagates the installMethod ldflag into the updater package
// before any update check is performed. Called once per surface that uses updater.Check.
func syncInstallMethod() {
	updater.InstallMethod = installMethod
}
