package scenarios

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// Discovery handles finding and loading scenarios from the filesystem
type Discovery struct {
	basePath string
}

// NewDiscovery creates a new scenario discovery instance
func NewDiscovery(basePath string) *Discovery {
	return &Discovery{basePath: basePath}
}

// DiscoverAll finds and loads all scenarios from the scenarios directory
func (d *Discovery) DiscoverAll() ([]*Scenario, error) {
	var scenarios []*Scenario

	err := filepath.Walk(d.basePath, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}

		// Skip directories and non-scenario files
		if info.IsDir() || info.Name() != "scenario.yaml" {
			return nil
		}

		// Skip end-of-life paths
		if strings.Contains(path, "end-of-life") {
			return nil
		}

		scenario, err := LoadFromFile(path)
		if err != nil {
			// Log warning but continue discovering other scenarios
			return nil
		}

		scenarios = append(scenarios, scenario)
		return nil
	})

	if err != nil {
		return nil, err
	}

	// Sort scenarios by ID for consistent ordering
	sort.Slice(scenarios, func(i, j int) bool {
		return scenarios[i].ID() < scenarios[j].ID()
	})

	return scenarios, nil
}

// FindByID finds a scenario by its pathfinding cloud ID or unique ID (with target suffix)
// Supports both "sts-001" (returns first match) and "sts-001-to-admin" (exact match)
func (d *Discovery) FindByID(id string) (*Scenario, error) {
	scenarios, err := d.DiscoverAll()
	if err != nil {
		return nil, err
	}

	// Normalize the search ID
	id = strings.ToLower(strings.TrimSpace(id))

	// First, try exact match on UniqueID (e.g., "sts-001-to-admin")
	for _, s := range scenarios {
		if strings.ToLower(s.UniqueID()) == id {
			return s, nil
		}
	}

	// Then try match on base pathfinding-cloud-id (e.g., "sts-001")
	for _, s := range scenarios {
		if strings.ToLower(s.PathfindingCloudID) == id {
			return s, nil
		}
		// Also match by name
		if strings.ToLower(s.Name) == id {
			return s, nil
		}
	}

	return nil, nil
}

// FindAllByID finds all scenarios matching a pathfinding cloud ID or unique ID
// This handles cases where multiple scenarios share the same base ID
func (d *Discovery) FindAllByID(id string) ([]*Scenario, error) {
	scenarios, err := d.DiscoverAll()
	if err != nil {
		return nil, err
	}

	// Normalize the search ID
	id = strings.ToLower(strings.TrimSpace(id))

	var matches []*Scenario

	// First check for exact UniqueID match
	for _, s := range scenarios {
		if strings.ToLower(s.UniqueID()) == id {
			return []*Scenario{s}, nil // Exact match, return just this one
		}
	}

	// Then find all with matching base ID
	for _, s := range scenarios {
		if strings.ToLower(s.PathfindingCloudID) == id {
			matches = append(matches, s)
			continue
		}
		if strings.ToLower(s.Name) == id {
			matches = append(matches, s)
		}
	}

	return matches, nil
}

// FindEnabledByID finds the enabled scenario matching an ID
// Supports both base IDs ("sts-001") and unique IDs ("sts-001-to-admin")
func (d *Discovery) FindEnabledByID(id string, enabledVars map[string]bool) (*Scenario, error) {
	matches, err := d.FindAllByID(id)
	if err != nil {
		return nil, err
	}

	// Return the first enabled match
	for _, s := range matches {
		if enabledVars[s.Terraform.VariableName] {
			return s, nil
		}
	}

	// If none are enabled, return the first match (or nil if no matches)
	if len(matches) > 0 {
		return matches[0], nil
	}

	return nil, nil
}

// FindByIDs finds multiple scenarios by their IDs
// Supports UniqueID (iam-006-to-admin), base ID (iam-006), or name
// Base IDs return all matching variants (both to-admin and to-bucket)
func (d *Discovery) FindByIDs(ids []string) ([]*Scenario, []string, error) {
	scenarios, err := d.DiscoverAll()
	if err != nil {
		return nil, nil, err
	}

	// Build lookup maps
	// uniqueIDLookup: exact match on UniqueID (e.g., "iam-006-to-admin")
	uniqueIDLookup := make(map[string]*Scenario)
	// baseIDLookup: all scenarios sharing a base ID (e.g., "iam-006" -> [to-admin, to-bucket])
	baseIDLookup := make(map[string][]*Scenario)
	// nameLookup: lookup by name
	nameLookup := make(map[string]*Scenario)

	for _, s := range scenarios {
		uniqueIDLookup[strings.ToLower(s.UniqueID())] = s
		baseID := strings.ToLower(s.PathfindingCloudID)
		baseIDLookup[baseID] = append(baseIDLookup[baseID], s)
		nameLookup[strings.ToLower(s.Name)] = s
	}

	var found []*Scenario
	var notFound []string
	seen := make(map[string]bool) // Avoid duplicates

	for _, id := range ids {
		id = strings.ToLower(strings.TrimSpace(id))
		matched := false

		// First try exact UniqueID match
		if s, ok := uniqueIDLookup[id]; ok {
			if !seen[s.Terraform.VariableName] {
				found = append(found, s)
				seen[s.Terraform.VariableName] = true
			}
			matched = true
		} else if scenarios, ok := baseIDLookup[id]; ok {
			// Then try base ID (returns all variants)
			for _, s := range scenarios {
				if !seen[s.Terraform.VariableName] {
					found = append(found, s)
					seen[s.Terraform.VariableName] = true
				}
			}
			matched = true
		} else if s, ok := nameLookup[id]; ok {
			// Finally try name
			if !seen[s.Terraform.VariableName] {
				found = append(found, s)
				seen[s.Terraform.VariableName] = true
			}
			matched = true
		}

		if !matched {
			notFound = append(notFound, id)
		}
	}

	return found, notFound, nil
}

// GetCategories returns all unique categories
func (d *Discovery) GetCategories() ([]string, error) {
	scenarios, err := d.DiscoverAll()
	if err != nil {
		return nil, err
	}

	categories := make(map[string]bool)
	for _, s := range scenarios {
		categories[s.CategoryShort()] = true
	}

	var result []string
	for c := range categories {
		result = append(result, c)
	}
	sort.Strings(result)
	return result, nil
}

// GetTargets returns all unique targets
func (d *Discovery) GetTargets() ([]string, error) {
	scenarios, err := d.DiscoverAll()
	if err != nil {
		return nil, err
	}

	targets := make(map[string]bool)
	for _, s := range scenarios {
		targets[s.Target] = true
	}

	var result []string
	for t := range targets {
		result = append(result, t)
	}
	sort.Strings(result)
	return result, nil
}
