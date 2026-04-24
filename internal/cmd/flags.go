package cmd

import (
	"fmt"
	"os"
	"sort"

	"github.com/fatih/color"
	"github.com/spf13/cobra"
	"gopkg.in/yaml.v3"

	"github.com/DataDog/pathfinding-labs/internal/config"
)

// `plabs flags` is the operator-facing command group for managing CTF flag
// values. Flag values flow: flags.default.yaml (or a vendor override file) →
// Config.Flags in ~/.plabs/plabs.yaml → scenario_flags map in
// terraform.tfvars → var.scenario_flags in root main.tf → flag_value input
// to each scenario module → the flag resource (SSM parameter or S3 object).
//
// Users never touch terraform.tfvars directly; every subcommand here updates
// Config.Flags and then calls SyncTFVars so downstream terraform stays in
// sync.

var flagsCmd = &cobra.Command{
	Use:   "flags",
	Short: "Manage CTF flag values for scenarios",
	Long: `Manage the CTF flag values injected into each scenario's flag resource.

Every non-tool-testing scenario ends with a CTF flag that the attacker must
retrieve. Flag values are keyed by scenario unique ID (e.g., "glue-003-to-admin")
and stored in ~/.plabs/plabs.yaml under the 'flags:' key.

Subcommands:
  plabs flags list                   # List currently configured flags
  plabs flags import <file>          # Replace all flags from a YAML file
  plabs flags set <id> <value>       # Set a single flag value
  plabs flags export <file>          # Write the current flag set to a file`,
}

var flagsImportCmd = &cobra.Command{
	Use:   "import <file>",
	Short: "Replace the current flag set with values from a YAML file",
	Long: `Load flag values from a YAML file and replace the current flag set.

Schema:
  flags:
    glue-003-to-admin: "flag{...}"
    iam-002-iam-createaccesskey-to-admin: "flag{...}"

This is the primary workflow for vendors hosting Pathfinding Labs: generate
a flag file, hand it to the vendor, and the vendor imports it before deploying.
All previously configured flags are replaced — use 'plabs flags set' to add
a single flag without replacing the rest.`,
	Args: cobra.ExactArgs(1),
	RunE: runFlagsImport,
}

var flagsListCmd = &cobra.Command{
	Use:   "list",
	Short: "List currently configured flags",
	RunE:  runFlagsList,
}

var flagsListReveal bool

var flagsSetCmd = &cobra.Command{
	Use:   "set <scenario-id> <value>",
	Short: "Set a single flag value",
	Args:  cobra.ExactArgs(2),
	RunE:  runFlagsSet,
}

var flagsExportCmd = &cobra.Command{
	Use:   "export <file>",
	Short: "Write the current flag set to a YAML file",
	Args:  cobra.ExactArgs(1),
	RunE:  runFlagsExport,
}

func init() {
	flagsListCmd.Flags().BoolVar(&flagsListReveal, "reveal", false, "Print full flag values (default: truncate to flag{...})")
	flagsCmd.AddCommand(flagsImportCmd)
	flagsCmd.AddCommand(flagsListCmd)
	flagsCmd.AddCommand(flagsSetCmd)
	flagsCmd.AddCommand(flagsExportCmd)
	rootCmd.AddCommand(flagsCmd)
}

func runFlagsImport(cmd *cobra.Command, args []string) error {
	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	path := args[0]
	prevCount := len(cfg.Flags)
	if err := cfg.LoadFlagsFromFile(path); err != nil {
		return err
	}
	if err := cfg.Save(); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}
	if err := cfg.SyncTFVars(paths.TerraformDir); err != nil {
		return fmt.Errorf("failed to sync terraform.tfvars: %w", err)
	}

	green := color.New(color.FgGreen).SprintFunc()
	fmt.Println()
	fmt.Printf("%s Imported %d flag(s) from %s (replaced %d previous)\n", green("OK"), len(cfg.Flags), path, prevCount)
	fmt.Println("Run 'plabs apply' to update the deployed flag resources.")
	return nil
}

func runFlagsList(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}
	if len(cfg.Flags) == 0 {
		fmt.Println("No flags configured. Run 'plabs flags import <file>' or 'plabs flags set <id> <value>'.")
		return nil
	}

	ids := make([]string, 0, len(cfg.Flags))
	for id := range cfg.Flags {
		ids = append(ids, id)
	}
	sort.Strings(ids)

	fmt.Printf("%d flag(s) configured:\n\n", len(cfg.Flags))
	for _, id := range ids {
		value := cfg.Flags[id]
		if !flagsListReveal {
			value = truncateFlag(value)
		}
		fmt.Printf("  %-55s %s\n", id, value)
	}
	if !flagsListReveal {
		fmt.Println("\nPass --reveal to print full flag values.")
	}
	return nil
}

func runFlagsSet(cmd *cobra.Command, args []string) error {
	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	id, value := args[0], args[1]
	cfg.SetFlag(id, value)
	if err := cfg.Save(); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}
	if err := cfg.SyncTFVars(paths.TerraformDir); err != nil {
		return fmt.Errorf("failed to sync terraform.tfvars: %w", err)
	}

	green := color.New(color.FgGreen).SprintFunc()
	fmt.Printf("%s Flag set for %s\n", green("OK"), id)
	fmt.Println("Run 'plabs apply' to update the deployed flag resource.")
	return nil
}

func runFlagsExport(cmd *cobra.Command, args []string) error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}
	if len(cfg.Flags) == 0 {
		return fmt.Errorf("no flags configured to export")
	}

	out := config.FlagSetFile{Flags: cfg.Flags}
	data, err := yaml.Marshal(out)
	if err != nil {
		return fmt.Errorf("failed to marshal flag set: %w", err)
	}
	// 0600 because the file contains CTF flag values vendors should keep private.
	if err := os.WriteFile(args[0], data, 0600); err != nil {
		return fmt.Errorf("failed to write %s: %w", args[0], err)
	}

	green := color.New(color.FgGreen).SprintFunc()
	fmt.Printf("%s Exported %d flag(s) to %s\n", green("OK"), len(cfg.Flags), args[0])
	return nil
}

// truncateFlag collapses a flag value to `flag{...}` (preserving the prefix
// and closing brace when present) so `plabs flags list` doesn't spray secrets
// onto the terminal by default.
func truncateFlag(value string) string {
	if len(value) <= 8 {
		return "***"
	}
	if len(value) > 6 && value[:5] == "flag{" && value[len(value)-1] == '}' {
		return "flag{...}"
	}
	return value[:4] + "..."
}
