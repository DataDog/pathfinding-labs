package cmd

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/repo"
	"github.com/DataDog/pathfinding-labs/internal/scenarios"
)

// getWorkingPaths returns the paths to use for the current operation.
// Loads config from ~/.plabs/plabs.yaml and uses dev_mode settings to determine
// which terraform directory to use.
func getWorkingPaths() (*repo.Paths, error) {
	// Load config from the canonical location
	cfg, err := config.Load()
	if err != nil {
		// Config might not exist yet, return default paths
		return repo.GetPaths()
	}

	// Get paths with mode awareness
	return repo.GetPathsForMode(cfg.DevMode, cfg.DevModePath)
}

// getConfig loads the configuration from the canonical location
func getConfig() (*config.Config, error) {
	return config.Load()
}

// isDevMode returns true if dev mode is enabled in config
func isDevMode() bool {
	cfg, err := config.Load()
	if err != nil || cfg == nil {
		return false
	}
	return cfg.DevMode
}

// getDevModePath returns the dev mode path if enabled, empty string otherwise
func getDevModePath() string {
	cfg, err := config.Load()
	if err != nil || cfg == nil {
		return ""
	}
	if cfg.DevMode {
		return cfg.DevModePath
	}
	return ""
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

// syncTFVars regenerates terraform.tfvars from the config
func syncTFVars() error {
	cfg, err := config.Load()
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	return cfg.SyncTFVars(paths.TerraformDir)
}
