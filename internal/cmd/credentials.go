package cmd

import (
	"encoding/json"
	"fmt"
	"os"
	"strings"

	"github.com/spf13/cobra"

	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/terraform"
)

var credentialsFormat string

var credentialsCmd = &cobra.Command{
	Use:   "credentials <id>",
	Short: "Output credentials for a deployed scenario",
	Long: `Output starting credentials for a deployed scenario in various formats.

Formats:
  env      - Environment variable exports (default), ready for eval
  profile  - AWS credential file format
  json     - JSON object

Examples:
  plabs credentials iam-002-to-admin
  plabs credentials iam-002-to-admin --format=json
  eval $(plabs credentials iam-002-to-admin)`,
	Args: cobra.ExactArgs(1),
	RunE: runCredentials,
}

// credentialsAliasCmd is a separate instance for use as a subcommand of scenarios.
// Registered in scenarios.go init().
var credentialsAliasCmd = &cobra.Command{
	Use:   "credentials <id>",
	Short: "Output credentials for a deployed scenario",
	Long:  credentialsCmd.Long,
	Args:  cobra.ExactArgs(1),
	RunE:  runCredentials,
}

func init() {
	credentialsCmd.Flags().StringVar(&credentialsFormat, "format", "env", "Output format: env, profile, json")
	credentialsAliasCmd.Flags().StringVar(&credentialsFormat, "format", "env", "Output format: env, profile, json")
}

func runCredentials(cmd *cobra.Command, args []string) error {
	id := args[0]

	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	// Load config
	cfg, _ := config.Load()
	enabledVars := make(map[string]bool)
	if cfg != nil {
		enabledVars = cfg.GetEnabledScenarioVars()
	}

	// Find scenario
	discovery := newDiscovery(paths.ScenariosPath())
	scenario, err := discovery.FindEnabledByID(id, enabledVars)
	if err != nil {
		return fmt.Errorf("failed to find scenario: %w", err)
	}
	if scenario == nil {
		fmt.Fprintf(os.Stderr, "Error: scenario %q not found\n", id)
		fmt.Fprintf(os.Stderr, "Use 'plabs scenarios list' to see available scenarios\n")
		os.Exit(1)
	}

	// Check if enabled
	if !enabledVars[scenario.Terraform.VariableName] {
		fmt.Fprintf(os.Stderr, "Error: scenario %q is not enabled\n", scenario.UniqueID())
		fmt.Fprintf(os.Stderr, "Use 'plabs enable %s' to enable it first\n", scenario.UniqueID())
		os.Exit(1)
	}

	// Check if deployed
	runner := terraform.NewRunner(paths.BinPath, paths.TerraformDir)
	var outputs terraform.Outputs
	var deployedModules map[string]bool

	if !runner.IsInitialized() {
		fmt.Fprintf(os.Stderr, "Error: terraform is not initialized\n")
		fmt.Fprintf(os.Stderr, "Run 'plabs deploy' to deploy your scenarios\n")
		os.Exit(1)
	}

	outputJSON, err := runner.OutputJSON()
	if err != nil {
		return fmt.Errorf("failed to get terraform outputs: %w", err)
	}
	if outputJSON != "" {
		outputs, _ = terraform.ParseOutputs(outputJSON)
	}
	deployedModules = runner.GetDeployedModules()

	if !isScenarioDeployed(scenario, outputs, deployedModules) {
		fmt.Fprintf(os.Stderr, "Error: scenario %q is enabled but not yet deployed\n", scenario.UniqueID())
		fmt.Fprintf(os.Stderr, "Run 'plabs deploy' to deploy it\n")
		os.Exit(1)
	}

	// Get credentials
	outputName := getScenarioOutputName(scenario)
	creds, err := outputs.GetStartingCredentials(outputName)
	if err != nil {
		return fmt.Errorf("credentials not available for %q: %w", scenario.UniqueID(), err)
	}

	// Validate format
	format := strings.ToLower(credentialsFormat)
	if format != "env" && format != "profile" && format != "json" {
		return fmt.Errorf("invalid format %q: must be env, profile, or json", credentialsFormat)
	}

	switch format {
	case "env":
		fmt.Printf("export AWS_ACCESS_KEY_ID=%s\n", creds.AccessKeyID)
		fmt.Printf("export AWS_SECRET_ACCESS_KEY=%s\n", creds.SecretAccessKey)
		if creds.SessionToken != "" {
			fmt.Printf("export AWS_SESSION_TOKEN=%s\n", creds.SessionToken)
		}
	case "profile":
		fmt.Printf("[%s]\n", scenario.UniqueID())
		fmt.Printf("aws_access_key_id = %s\n", creds.AccessKeyID)
		fmt.Printf("aws_secret_access_key = %s\n", creds.SecretAccessKey)
		if creds.SessionToken != "" {
			fmt.Printf("aws_session_token = %s\n", creds.SessionToken)
		}
	case "json":
		obj := map[string]string{
			"access_key_id":     creds.AccessKeyID,
			"secret_access_key": creds.SecretAccessKey,
		}
		if creds.SessionToken != "" {
			obj["session_token"] = creds.SessionToken
		}
		data, err := json.MarshalIndent(obj, "", "  ")
		if err != nil {
			return fmt.Errorf("failed to marshal JSON: %w", err)
		}
		fmt.Println(string(data))
	}

	return nil
}
