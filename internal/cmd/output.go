package cmd

import (
	"encoding/json"
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/DataDog/pathfinding-labs/internal/terraform"
)

var outputRaw bool

var outputCmd = &cobra.Command{
	Use:   "output <id>",
	Short: "Print the full terraform output block for a deployed scenario",
	Long: `Print the complete terraform output block for a deployed scenario as JSON.

By default the output is pretty-printed. Use --raw for minified JSON suitable
for piping to jq or other tools.

Examples:
  plabs output iam-002-to-admin
  plabs output iam-002-to-admin --raw | jq .starting_user_access_key_id
  plabs output iam-002-to-admin --raw | jq .admin_user_arn`,
	Args: cobra.ExactArgs(1),
	RunE: runOutput,
}

// outputAliasCmd is registered as a subcommand of scenarios.
var outputAliasCmd = &cobra.Command{
	Use:   "output <id>",
	Short: "Print the full terraform output block for a deployed scenario",
	Long:  outputCmd.Long,
	Args:  cobra.ExactArgs(1),
	RunE:  runOutput,
}

func init() {
	outputCmd.Flags().BoolVar(&outputRaw, "raw", false, "Output minified JSON (for piping to jq)")
	outputAliasCmd.Flags().BoolVar(&outputRaw, "raw", false, "Output minified JSON (for piping to jq)")
}

func runOutput(cmd *cobra.Command, args []string) error {
	id := args[0]

	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	// Find scenario by ID — does not require it to be enabled in config
	discovery := newDiscovery(paths.ScenariosPath())
	scenario, err := discovery.FindByID(id)
	if err != nil {
		return fmt.Errorf("failed to find scenario: %w", err)
	}
	if scenario == nil {
		fmt.Fprintf(os.Stderr, "Error: scenario %q not found\n", id)
		fmt.Fprintf(os.Stderr, "Use 'plabs scenarios list' to see available scenarios\n")
		os.Exit(1)
	}

	runner := terraform.NewRunner(paths.BinPath, paths.TerraformDir)
	if !runner.IsInitialized() {
		fmt.Fprintf(os.Stderr, "Error: terraform is not initialized\n")
		fmt.Fprintf(os.Stderr, "Run 'plabs deploy' to deploy your scenarios\n")
		os.Exit(1)
	}

	outputJSON, err := runner.OutputJSON()
	if err != nil {
		return fmt.Errorf("failed to get terraform outputs: %w", err)
	}

	outputs, err := terraform.ParseOutputs(outputJSON)
	if err != nil {
		return fmt.Errorf("failed to parse terraform outputs: %w", err)
	}

	outputName := getScenarioOutputName(scenario)
	block, exists := outputs.GetScenarioOutput(outputName)
	if !exists {
		fmt.Fprintf(os.Stderr, "Error: output key %q not found — is the scenario deployed?\n", outputName)
		fmt.Fprintf(os.Stderr, "Run 'plabs deploy' to deploy it\n")
		os.Exit(1)
	}
	if block == nil {
		fmt.Fprintf(os.Stderr, "Error: scenario %q is not deployed (output is null)\n", scenario.UniqueID())
		fmt.Fprintf(os.Stderr, "Run 'plabs deploy' to deploy it\n")
		os.Exit(1)
	}

	var data []byte
	if outputRaw {
		data, err = json.Marshal(block)
	} else {
		data, err = json.MarshalIndent(block, "", "  ")
	}
	if err != nil {
		return fmt.Errorf("failed to marshal output: %w", err)
	}

	fmt.Println(string(data))
	return nil
}
