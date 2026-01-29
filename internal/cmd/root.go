package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var (
	version = "dev"
	commit  = "unknown"
)

var rootCmd = &cobra.Command{
	Use:   "plabs",
	Short: "Pathfinding Labs - AWS attack path scenario management",
	Long: `plabs is a CLI tool for managing Pathfinding Labs scenarios.

Pathfinding Labs deploys intentionally vulnerable AWS configurations
to validate Cloud Security Posture Management (CSPM) tools and
train security teams on cloud attack paths.

Get started with:
  plabs init     - Set up plabs and configure your AWS accounts
  plabs scenarios list - Browse available attack scenarios
  plabs enable iam-002 - Enable a specific scenario
  plabs deploy   - Deploy enabled scenarios to AWS`,
	SilenceUsage:  true,
	SilenceErrors: true,
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
	rootCmd.AddCommand(versionCmd)
}

var versionCmd = &cobra.Command{
	Use:   "version",
	Short: "Print the version number",
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Printf("plabs %s (commit: %s)\n", version, commit)
	},
}

// exitWithError prints an error message and exits
func exitWithError(format string, args ...interface{}) {
	fmt.Fprintf(os.Stderr, "Error: "+format+"\n", args...)
	os.Exit(1)
}
