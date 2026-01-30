package scenarios

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

// Scenario represents the metadata from a scenario.yaml file
type Scenario struct {
	// Core metadata
	SchemaVersion      string `yaml:"schema_version"`
	Name               string `yaml:"name"`
	Description        string `yaml:"description"`
	CostEstimate       string `yaml:"cost_estimate"`
	PathfindingCloudID string `yaml:"pathfinding-cloud-id"`

	// Classification
	Category     string   `yaml:"category"`
	SubCategory  string   `yaml:"sub_category"`
	PathType     string   `yaml:"path_type"`
	Target       string   `yaml:"target"`
	Environments []string `yaml:"environments"`

	// Attack path
	AttackPath struct {
		Principals []string `yaml:"principals"`
		Summary    string   `yaml:"summary"`
	} `yaml:"attack_path"`

	// Permissions
	Permissions struct {
		Required []struct {
			Permission string `yaml:"permission"`
			Resource   string `yaml:"resource"`
		} `yaml:"required"`
		Helpful []struct {
			Permission string `yaml:"permission"`
			Purpose    string `yaml:"purpose"`
		} `yaml:"helpful"`
	} `yaml:"permissions"`

	// MITRE ATT&CK
	MitreAttack struct {
		Tactics    []string `yaml:"tactics"`
		Techniques []string `yaml:"techniques"`
	} `yaml:"mitre_attack"`

	// Terraform
	Terraform struct {
		VariableName string `yaml:"variable_name"`
		ModulePath   string `yaml:"module_path"`
	} `yaml:"terraform"`

	// Internal fields (not from YAML)
	FilePath string `yaml:"-"` // Path to the scenario.yaml file
	DirPath  string `yaml:"-"` // Directory containing the scenario
}

// LoadFromFile loads a scenario from a YAML file
func LoadFromFile(path string) (*Scenario, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("failed to read scenario file: %w", err)
	}

	var s Scenario
	if err := yaml.Unmarshal(data, &s); err != nil {
		return nil, fmt.Errorf("failed to parse scenario YAML: %w", err)
	}

	s.FilePath = path
	s.DirPath = filepath.Dir(path)

	return &s, nil
}

// ID returns the pathfinding cloud ID or name as a fallback
func (s *Scenario) ID() string {
	if s.PathfindingCloudID != "" {
		return s.PathfindingCloudID
	}
	return s.Name
}

// UniqueID returns a unique identifier that includes the target suffix
// This disambiguates scenarios that share the same pathfinding-cloud-id
// (e.g., "sts-001-to-admin" vs "sts-001-to-bucket")
func (s *Scenario) UniqueID() string {
	base := s.ID()
	if s.Target != "" {
		return base + "-" + s.Target
	}
	return base
}

// IsCrossAccount returns true if this is a cross-account scenario
func (s *Scenario) IsCrossAccount() bool {
	return s.PathType == "cross-account" || len(s.Environments) > 1
}

// RequiresMultiAccount returns true if the scenario requires multiple accounts
func (s *Scenario) RequiresMultiAccount() bool {
	return s.IsCrossAccount()
}

// HasDemo returns true if a demo_attack.sh script exists
func (s *Scenario) HasDemo() bool {
	_, err := os.Stat(filepath.Join(s.DirPath, "demo_attack.sh"))
	return err == nil
}

// HasCleanup returns true if a cleanup_attack.sh script exists
func (s *Scenario) HasCleanup() bool {
	_, err := os.Stat(filepath.Join(s.DirPath, "cleanup_attack.sh"))
	return err == nil
}

// DemoPath returns the path to the demo script
func (s *Scenario) DemoPath() string {
	return filepath.Join(s.DirPath, "demo_attack.sh")
}

// CleanupPath returns the path to the cleanup script
func (s *Scenario) CleanupPath() string {
	return filepath.Join(s.DirPath, "cleanup_attack.sh")
}

// CategoryShort returns a shortened category name for display
func (s *Scenario) CategoryShort() string {
	switch {
	case strings.Contains(s.Terraform.ModulePath, "privesc-self-escalation"):
		return "self-escalation"
	case strings.Contains(s.Terraform.ModulePath, "privesc-one-hop"):
		return "one-hop"
	case strings.Contains(s.Terraform.ModulePath, "privesc-multi-hop"):
		return "multi-hop"
	case strings.Contains(s.Terraform.ModulePath, "toxic-combo"):
		return "toxic-combo"
	case strings.Contains(s.Terraform.ModulePath, "tool-testing"):
		return "tool-testing"
	case strings.Contains(s.Terraform.ModulePath, "cross-account"):
		return "cross-account"
	default:
		return s.PathType
	}
}

// TargetShort returns a shortened target name for display
func (s *Scenario) TargetShort() string {
	switch s.Target {
	case "to-admin":
		return "admin"
	case "to-bucket":
		return "bucket"
	default:
		return s.Target
	}
}

// MitreIDs extracts just the technique IDs (e.g., "T1098" from "T1098.001 - Account Manipulation")
func (s *Scenario) MitreIDs() []string {
	var ids []string
	for _, t := range s.MitreAttack.Techniques {
		// Extract the technique ID (everything before " - ")
		parts := strings.SplitN(t, " - ", 2)
		if len(parts) > 0 {
			ids = append(ids, strings.TrimSpace(parts[0]))
		}
	}
	return ids
}
