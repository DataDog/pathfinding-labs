package scenarios

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDiscoverAll(t *testing.T) {
	// Find the project root by looking for go.mod
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatalf("failed to get working directory: %v", err)
	}

	// Walk up to find the project root
	projectRoot := cwd
	for i := 0; i < 5; i++ {
		if _, err := os.Stat(filepath.Join(projectRoot, "go.mod")); err == nil {
			break
		}
		projectRoot = filepath.Dir(projectRoot)
	}

	scenariosPath := filepath.Join(projectRoot, "modules", "scenarios")

	// Skip if scenarios directory doesn't exist (e.g., in CI without full repo)
	if _, err := os.Stat(scenariosPath); os.IsNotExist(err) {
		t.Skip("scenarios directory not found, skipping test")
	}

	discovery := NewDiscovery(scenariosPath)
	scenarios, err := discovery.DiscoverAll()
	if err != nil {
		t.Fatalf("DiscoverAll failed: %v", err)
	}

	if len(scenarios) == 0 {
		t.Error("expected to find at least one scenario")
	}

	// Verify each scenario has required fields
	for _, s := range scenarios {
		if s.Name == "" {
			t.Errorf("scenario at %s has empty name", s.FilePath)
		}
		if s.Terraform.VariableName == "" {
			t.Errorf("scenario %s has empty terraform variable name", s.Name)
		}
	}
}

func TestFindByID(t *testing.T) {
	// Find the project root
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatalf("failed to get working directory: %v", err)
	}

	projectRoot := cwd
	for i := 0; i < 5; i++ {
		if _, err := os.Stat(filepath.Join(projectRoot, "go.mod")); err == nil {
			break
		}
		projectRoot = filepath.Dir(projectRoot)
	}

	scenariosPath := filepath.Join(projectRoot, "modules", "scenarios")

	if _, err := os.Stat(scenariosPath); os.IsNotExist(err) {
		t.Skip("scenarios directory not found, skipping test")
	}

	discovery := NewDiscovery(scenariosPath)

	// Test finding a known scenario
	scenario, err := discovery.FindByID("iam-002")
	if err != nil {
		t.Fatalf("FindByID failed: %v", err)
	}

	if scenario == nil {
		t.Error("expected to find iam-002 scenario")
	}

	// Test finding a non-existent scenario
	scenario, err = discovery.FindByID("nonexistent-scenario")
	if err != nil {
		t.Fatalf("FindByID failed for non-existent: %v", err)
	}

	if scenario != nil {
		t.Error("expected nil for non-existent scenario")
	}
}

func TestFilterScenarios(t *testing.T) {
	scenarios := []*Scenario{
		{
			Name:               "test-one-hop-admin",
			PathfindingCloudID: "test-001",
			Target:             "to-admin",
			Terraform: struct {
				VariableName string `yaml:"variable_name"`
				ModulePath   string `yaml:"module_path"`
			}{
				VariableName: "enable_test_one_hop_admin",
				ModulePath:   "modules/scenarios/single-account/privesc-one-hop/to-admin/test",
			},
		},
		{
			Name:               "test-one-hop-bucket",
			PathfindingCloudID: "test-002",
			Target:             "to-bucket",
			Terraform: struct {
				VariableName string `yaml:"variable_name"`
				ModulePath   string `yaml:"module_path"`
			}{
				VariableName: "enable_test_one_hop_bucket",
				ModulePath:   "modules/scenarios/single-account/privesc-one-hop/to-bucket/test",
			},
		},
	}

	// Test target filter
	filter := Filter{Target: "to-admin"}
	filtered := FilterScenarios(scenarios, filter, nil)
	if len(filtered) != 1 {
		t.Errorf("expected 1 scenario, got %d", len(filtered))
	}
	if filtered[0].Name != "test-one-hop-admin" {
		t.Errorf("expected test-one-hop-admin, got %s", filtered[0].Name)
	}

	// Test enabled filter
	enabledVars := map[string]bool{
		"enable_test_one_hop_bucket": true,
	}
	filter = Filter{EnabledOnly: true}
	filtered = FilterScenarios(scenarios, filter, enabledVars)
	if len(filtered) != 1 {
		t.Errorf("expected 1 enabled scenario, got %d", len(filtered))
	}
}
