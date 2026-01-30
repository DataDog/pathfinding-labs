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
// By default, always uses ~/.plabs/pathfinding-labs.
// If dev mode is explicitly enabled in config, uses the local repo directory.
func getWorkingPaths() (*repo.Paths, error) {
	paths, err := repo.GetPaths()
	if err != nil {
		return nil, err
	}

	// Check if dev mode is explicitly enabled in config
	cfg, _ := config.Load(paths.ConfigPath)
	if cfg != nil && cfg.DevMode && cfg.WorkingDirectory != "" {
		// Verify the dev mode directory still exists and is valid
		scenariosPath := filepath.Join(cfg.WorkingDirectory, "modules", "scenarios")
		if _, err := os.Stat(scenariosPath); err == nil {
			// Use the configured dev mode directory
			return &repo.Paths{
				Home:       paths.Home,
				PlabsRoot:  paths.PlabsRoot,
				RepoPath:   cfg.WorkingDirectory,
				BinPath:    paths.BinPath,
				ConfigPath: paths.ConfigPath,
				TFVarsPath: filepath.Join(cfg.WorkingDirectory, "terraform.tfvars"),
			}, nil
		}
	}

	// Default: use ~/.plabs/pathfinding-labs
	return paths, nil
}

// isDevMode returns true if dev mode is explicitly enabled in config
func isDevMode() bool {
	paths, err := repo.GetPaths()
	if err != nil {
		return false
	}

	cfg, err := config.Load(paths.ConfigPath)
	if err != nil || cfg == nil {
		return false
	}

	return cfg.DevMode
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
