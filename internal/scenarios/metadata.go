package scenarios

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

// ScenarioConfigKey represents a configurable key declared by a scenario
// that requires a user-supplied value at deploy time.
type ScenarioConfigKey struct {
	Key         string `yaml:"key"`
	Description string `yaml:"description"`
	Required    bool   `yaml:"required"`
}

// Scenario represents the metadata from a scenario.yaml file
type Scenario struct {
	// Core metadata
	SchemaVersion      string `yaml:"schema_version"`
	Name               string `yaml:"name"`
	Title              string `yaml:"title"`
	Description        string `yaml:"description"`
	CostEstimate                string `yaml:"cost_estimate"`
	CostEstimateWhenDemoExecuted string `yaml:"cost_estimate_when_demo_executed"`
	PathfindingCloudID string `yaml:"pathfinding-cloud-id"`

	// Source metadata (for Attack Simulation scenarios)
	Source struct {
		URL    string `yaml:"url"`
		Title  string `yaml:"title"`
		Author string `yaml:"author"`
		Date   string `yaml:"date"`
	} `yaml:"source"`

	// Modifications from the original attack (for Attack Simulation scenarios)
	Modifications []string `yaml:"modifications"`

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

	// Required preconditions — what must already exist in the account for this attack to be viable.
	// Each entry has a type (aws-resource, network, external, configuration), an optional resource
	// name for aws-resource entries, and a description of the specific requirement.
	RequiredPreconditions []struct {
		Type        string `yaml:"type"`
		Resource    string `yaml:"resource,omitempty"`
		Description string `yaml:"description"`
	} `yaml:"required_preconditions,omitempty"`

	// Permissions
	Permissions struct {
		Required []struct {
			Principal     string `yaml:"principal"`
			PrincipalType string `yaml:"principal_type"`
			Permissions   []struct {
				Permission string `yaml:"permission"`
				Resource   string `yaml:"resource"`
			} `yaml:"permissions"`
		} `yaml:"required"`
		Helpful []struct {
			Principal     string `yaml:"principal"`
			PrincipalType string `yaml:"principal_type"`
			Permissions   []struct {
				Permission string `yaml:"permission"`
				Resource   string `yaml:"resource"`
				Purpose    string `yaml:"purpose"`
			} `yaml:"permissions"`
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

	// Demo configuration
	InteractiveDemo bool `yaml:"interactive_demo"` // If true, demo script needs terminal input

	// Config declares per-scenario configuration keys requiring user-supplied values at deploy time
	Config []ScenarioConfigKey `yaml:"config,omitempty"`

	// Status marks a scenario as "beta" to hide it from default listings.
	// Absence (empty string) means the scenario is stable and always visible.
	Status string `yaml:"status,omitempty"`

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

// HasDemoActive returns true if a .demo_active marker file exists
func (s *Scenario) HasDemoActive() bool {
	_, err := os.Stat(filepath.Join(s.DirPath, ".demo_active"))
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
	case strings.Contains(s.Terraform.ModulePath, "cspm-toxic-combo"):
		return "cspm-toxic-combo"
	case strings.Contains(s.Terraform.ModulePath, "cspm-misconfig"):
		return "cspm-misconfig"
	case strings.Contains(s.Terraform.ModulePath, "tool-testing"):
		return "tool-testing"
	case strings.Contains(s.Terraform.ModulePath, "cross-account"):
		return "cross-account"
	case strings.Contains(s.Terraform.ModulePath, "attack-simulation"):
		return "attack-simulation"
	case strings.Contains(s.Terraform.ModulePath, "/ctf/"):
		return "ctf"
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

// HasConfig returns true if this scenario declares configurable keys
func (s *Scenario) HasConfig() bool {
	return len(s.Config) > 0
}

// IsBeta returns true if this scenario is marked as beta and should be hidden by default
func (s *Scenario) IsBeta() bool {
	return s.Status == "beta"
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
