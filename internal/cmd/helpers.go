package cmd

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/fatih/color"

	plabsaws "github.com/DataDog/pathfinding-labs/internal/aws"
	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/repo"
	"github.com/DataDog/pathfinding-labs/internal/scenarios"
)

// getWorkingPaths returns the paths to use for the current operation.
// Loads config from ~/.plabs/plabs.yaml and uses the active workspace's
// dev_mode settings to determine which terraform directory to use.
func getWorkingPaths() (*repo.Paths, error) {
	cfg, err := config.Load()
	if err != nil {
		return repo.GetPaths()
	}
	ws := cfg.Active()
	return repo.GetPathsForWorkspace(cfg.ActiveName(), ws.DevMode, ws.DevModePath)
}

// isDevMode returns true if the active workspace has dev mode enabled
func isDevMode() bool {
	cfg, err := config.Load()
	if err != nil || cfg == nil {
		return false
	}
	return cfg.Active().DevMode
}

// containsGlobPattern checks if any of the args contain glob characters
func containsGlobPattern(args []string) bool {
	for _, arg := range args {
		if strings.Contains(arg, "*") || strings.Contains(arg, "?") {
			return true
		}
	}
	return false
}

// matchByPatterns filters scenarios by glob patterns
func matchByPatterns(allScenarios []*scenarios.Scenario, patterns []string) []*scenarios.Scenario {
	var matched []*scenarios.Scenario
	seen := make(map[string]bool)

	for _, s := range allScenarios {
		for _, pattern := range patterns {
			// Match against UniqueID (e.g., "lambda-001-to-admin") or base ID (e.g., "lambda-001")
			if matchesPattern(s.UniqueID(), pattern) || matchesPattern(s.ID(), pattern) {
				if !seen[s.Terraform.VariableName] {
					matched = append(matched, s)
					seen[s.Terraform.VariableName] = true
				}
				break
			}
		}
	}

	return matched
}

// matchesPattern checks if a string matches a glob pattern
func matchesPattern(s, pattern string) bool {
	// Use filepath.Match for glob matching
	matched, err := filepath.Match(pattern, s)
	if err != nil {
		return false
	}
	return matched
}

// hasBothTargets checks if a list of scenarios includes both to-admin and to-bucket variants
// for any base ID (e.g., both iam-002-to-admin and iam-002-to-bucket)
func hasBothTargets(scenarioList []*scenarios.Scenario) bool {
	baseIDs := make(map[string]map[string]bool)

	for _, s := range scenarioList {
		baseID := s.ID()
		if baseIDs[baseID] == nil {
			baseIDs[baseID] = make(map[string]bool)
		}
		baseIDs[baseID][s.Target] = true
	}

	for _, targets := range baseIDs {
		if targets["to-admin"] && targets["to-bucket"] {
			return true
		}
	}

	return false
}

// confirmAction prompts the user for confirmation and returns true if they confirm
func confirmAction(prompt string) bool {
	fmt.Printf("%s [y/N]: ", prompt)
	reader := bufio.NewReader(os.Stdin)
	response, err := reader.ReadString('\n')
	if err != nil {
		return false
	}
	response = strings.TrimSpace(strings.ToLower(response))
	return response == "y" || response == "yes"
}

// validateAWSCredentials checks that the configured AWS profiles have valid credentials
// before running terraform or AWS operations. Returns nil if valid, error if not.
func validateAWSCredentials(cfg *config.Config) error {
	if cfg == nil {
		return fmt.Errorf("configuration not loaded — run 'plabs init' to configure")
	}

	ws := cfg.Active()
	profile := ws.AWS.Prod.Profile
	if profile == "" {
		red := color.New(color.FgRed).SprintFunc()
		cyan := color.New(color.FgCyan).SprintFunc()
		fmt.Println()
		fmt.Println(red("AWS Credentials Error"))
		fmt.Println()
		fmt.Println("No AWS profile configured.")
		fmt.Printf("Run %s to configure.\n", cyan("plabs init"))
		fmt.Println()
		return fmt.Errorf("no AWS profile configured")
	}

	// For attacker in IAM user mode (bootstrapped), skip profile validation
	attackerProfile := ws.AWS.Attacker.Profile
	if ws.AWS.Attacker.Mode == "iam-user" && ws.AWS.Attacker.IAMAccessKeyID != "" {
		attackerProfile = "" // skip profile validation; using IAM creds
	}

	profiles := plabsaws.GetUniqueProfiles(
		ws.AWS.Prod.Profile,
		ws.AWS.Dev.Profile,
		ws.AWS.Ops.Profile,
		attackerProfile,
	)

	results, err := plabsaws.ValidateProfiles(profiles)
	if err != nil {
		red := color.New(color.FgRed).SprintFunc()
		yellow := color.New(color.FgYellow).SprintFunc()
		cyan := color.New(color.FgCyan).SprintFunc()
		fmt.Println()
		fmt.Println(red("AWS Credentials Error"))
		fmt.Println()
		fmt.Println("One or more AWS profiles have expired or invalid credentials:")
		fmt.Println()
		for _, r := range results {
			if !r.Valid {
				fmt.Printf("  %s Profile: %s\n", red("✗"), yellow(r.Profile))
			}
		}
		fmt.Println()
		fmt.Println("Run these commands to authenticate:")
		for _, r := range results {
			if !r.Valid {
				fmt.Printf("  %s\n", cyan(fmt.Sprintf("aws sso login --profile %s", r.Profile)))
			}
		}
		fmt.Println()
		return fmt.Errorf("AWS credential validation failed")
	}

	return nil
}

// crossAccountEnvErrors returns error strings for each scenario that requires a dev or ops
// AWS account profile that is not configured. The format mirrors the required-config error
// messages produced by enable/deploy so the user sees a consistent error surface.
func crossAccountEnvErrors(scenarioList []*scenarios.Scenario, ws *config.WorkspaceConfig) []string {
	var errs []string
	for _, s := range scenarioList {
		for _, env := range s.Environments {
			switch env {
			case "dev":
				if ws.AWS.Dev.Profile == "" {
					errs = append(errs, fmt.Sprintf(
						"  %s: requires a \"dev\" AWS account profile (not configured)\n    Set with: plabs config set dev-profile <aws-profile>",
						s.Name))
				}
			case "operations":
				if ws.AWS.Ops.Profile == "" {
					errs = append(errs, fmt.Sprintf(
						"  %s: requires an \"operations\" AWS account profile (not configured)\n    Set with: plabs config set ops-profile <aws-profile>",
						s.Name))
				}
			}
		}
	}
	return errs
}

// newDiscovery creates a Discovery instance wired to the current config.
// IncludeBeta is set from the loaded config so beta scenarios are hidden unless
// the user has run: plabs config set include-beta true
func newDiscovery(scenariosPath string) *scenarios.Discovery {
	cfg, _ := config.Load()
	d := scenarios.NewDiscovery(scenariosPath)
	if cfg != nil {
		d.WithIncludeBeta(cfg.IncludeBeta)
	}
	return d
}
