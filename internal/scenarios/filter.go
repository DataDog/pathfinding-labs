package scenarios

import (
	"strings"
)

// Filter represents filtering criteria for scenarios
type Filter struct {
	Category    string
	Target      string
	Cost        string
	MitreID     string
	EnabledOnly bool
	PathType    string
}

// FilterScenarios filters a list of scenarios based on the provided criteria
func FilterScenarios(scenarios []*Scenario, filter Filter, enabledVars map[string]bool) []*Scenario {
	var result []*Scenario

	for _, s := range scenarios {
		if matchesFilter(s, filter, enabledVars) {
			result = append(result, s)
		}
	}

	return result
}

// matchesFilter checks if a scenario matches all filter criteria
func matchesFilter(s *Scenario, f Filter, enabledVars map[string]bool) bool {
	// Filter by category
	if f.Category != "" {
		if !matchesCategory(s, f.Category) {
			return false
		}
	}

	// Filter by target
	if f.Target != "" {
		if !strings.EqualFold(s.Target, f.Target) && !strings.EqualFold(s.TargetShort(), f.Target) {
			return false
		}
	}

	// Filter by cost
	if f.Cost != "" {
		if !strings.EqualFold(s.CostEstimate, f.Cost) {
			return false
		}
	}

	// Filter by MITRE technique
	if f.MitreID != "" {
		if !matchesMitre(s, f.MitreID) {
			return false
		}
	}

	// Filter by path type
	if f.PathType != "" {
		if !strings.EqualFold(s.PathType, f.PathType) {
			return false
		}
	}

	// Filter by enabled status
	if f.EnabledOnly {
		if enabledVars == nil {
			return false
		}
		if !enabledVars[s.Terraform.VariableName] {
			return false
		}
	}

	return true
}

// matchesCategory checks if a scenario matches a category filter
func matchesCategory(s *Scenario, category string) bool {
	category = strings.ToLower(category)

	// Match against short category
	if strings.EqualFold(s.CategoryShort(), category) {
		return true
	}

	// Match against full category
	if strings.EqualFold(s.Category, category) {
		return true
	}

	// Partial match
	if strings.Contains(strings.ToLower(s.CategoryShort()), category) {
		return true
	}

	return false
}

// matchesMitre checks if a scenario has a matching MITRE technique
func matchesMitre(s *Scenario, mitreID string) bool {
	mitreID = strings.ToUpper(mitreID)

	for _, id := range s.MitreIDs() {
		if strings.Contains(strings.ToUpper(id), mitreID) {
			return true
		}
	}

	// Also check raw techniques
	for _, t := range s.MitreAttack.Techniques {
		if strings.Contains(strings.ToUpper(t), mitreID) {
			return true
		}
	}

	return false
}

// GroupByCategory groups scenarios by their category
func GroupByCategory(scenarios []*Scenario) map[string][]*Scenario {
	groups := make(map[string][]*Scenario)

	for _, s := range scenarios {
		cat := s.CategoryShort()
		groups[cat] = append(groups[cat], s)
	}

	return groups
}

// GroupByTarget groups scenarios by their target
func GroupByTarget(scenarios []*Scenario) map[string][]*Scenario {
	groups := make(map[string][]*Scenario)

	for _, s := range scenarios {
		target := s.Target
		groups[target] = append(groups[target], s)
	}

	return groups
}

// GetUniqueCategories returns all unique categories from a list of scenarios
func GetUniqueCategories(scenarios []*Scenario) []string {
	cats := make(map[string]bool)
	for _, s := range scenarios {
		cats[s.CategoryShort()] = true
	}

	var result []string
	for c := range cats {
		result = append(result, c)
	}
	return result
}

// CountByCategory returns counts of scenarios per category
func CountByCategory(scenarios []*Scenario) map[string]int {
	counts := make(map[string]int)
	for _, s := range scenarios {
		counts[s.CategoryShort()]++
	}
	return counts
}
