package config

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

const (
	// ConfigFileName is the name of the config file
	ConfigFileName = "plabs.yaml"
	// LegacyConfigFileName is the old config file name for migration
	LegacyConfigFileName = "config.yaml"
)

// Config represents the CLI configuration stored in ~/.plabs/plabs.yaml
// This is the single source of truth for all plabs configuration
type Config struct {
	// DevMode indicates if plabs is using a local repository for development
	DevMode bool `yaml:"dev_mode"`

	// DevModePath is the path to the local repo when dev mode is enabled
	DevModePath string `yaml:"dev_mode_path,omitempty"`

	// AWS contains all AWS account configuration
	AWS AWSConfig `yaml:"aws"`

	// Scenarios contains enabled scenarios configuration
	Scenarios ScenariosConfig `yaml:"scenarios"`

	// Initialized indicates if plabs init has been run
	Initialized bool `yaml:"initialized"`
}

// AWSConfig contains AWS account settings for all environments
type AWSConfig struct {
	Prod AccountConfig `yaml:"prod"`
	Dev  AccountConfig `yaml:"dev,omitempty"`
	Ops  AccountConfig `yaml:"ops,omitempty"`
}

// AccountConfig contains settings for a single AWS account/environment
type AccountConfig struct {
	Profile string `yaml:"profile,omitempty"`
	Region  string `yaml:"region,omitempty"`
}

// ScenariosConfig contains scenario enablement configuration
type ScenariosConfig struct {
	// Enabled is the list of enabled scenario variable names
	// Uses terraform variable names without the "enable_" prefix
	Enabled []string `yaml:"enabled,omitempty"`
}

// GetConfigPath returns the path to the config file
// Always returns ~/.plabs/plabs.yaml
func GetConfigPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("failed to get home directory: %w", err)
	}
	return filepath.Join(home, ".plabs", ConfigFileName), nil
}

// Load loads the configuration from ~/.plabs/plabs.yaml
// If plabs.yaml doesn't exist but legacy config.yaml does, it migrates the config
func Load() (*Config, error) {
	configPath, err := GetConfigPath()
	if err != nil {
		return nil, err
	}

	// Check if new config exists
	if _, err := os.Stat(configPath); os.IsNotExist(err) {
		// Try to migrate from legacy config.yaml
		legacyPath := filepath.Join(filepath.Dir(configPath), LegacyConfigFileName)
		if _, err := os.Stat(legacyPath); err == nil {
			cfg, err := migrateFromLegacy(legacyPath)
			if err != nil {
				return nil, fmt.Errorf("failed to migrate legacy config: %w", err)
			}
			// Save migrated config to new location
			if err := cfg.Save(); err != nil {
				return nil, fmt.Errorf("failed to save migrated config: %w", err)
			}
			// Sync terraform.tfvars to the appropriate directory
			var tfDir string
			if cfg.DevMode && cfg.DevModePath != "" {
				tfDir = cfg.DevModePath
			} else {
				tfDir = filepath.Join(filepath.Dir(configPath), "pathfinding-labs")
			}
			// Best effort - don't fail migration if tfvars sync fails
			_ = cfg.SyncTFVars(tfDir)
			return cfg, nil
		}
	}

	return LoadFromPath(configPath)
}

// LoadFromPath loads the configuration from a specific path
func LoadFromPath(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return &Config{}, nil
		}
		return nil, fmt.Errorf("failed to read config: %w", err)
	}

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("failed to parse config: %w", err)
	}

	return &cfg, nil
}

// LegacyConfig represents the old config.yaml format for migration
type LegacyConfig struct {
	WorkingDirectory string `yaml:"working_directory"`
	DevMode          bool   `yaml:"dev_mode"`
	ProdAccountID    string `yaml:"prod_account_id"`
	ProdProfile      string `yaml:"prod_profile"`
	ProdRegion       string `yaml:"prod_region"`
	DevAccountID     string `yaml:"dev_account_id"`
	DevProfile       string `yaml:"dev_profile"`
	DevRegion        string `yaml:"dev_region"`
	OpsAccountID     string `yaml:"ops_account_id"`
	OpsProfile       string `yaml:"ops_profile"`
	OpsRegion        string `yaml:"ops_region"`
	Initialized      bool   `yaml:"initialized"`
}

// migrateFromLegacy reads the old config.yaml format and converts to new format
func migrateFromLegacy(legacyPath string) (*Config, error) {
	data, err := os.ReadFile(legacyPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read legacy config: %w", err)
	}

	var legacy LegacyConfig
	if err := yaml.Unmarshal(data, &legacy); err != nil {
		return nil, fmt.Errorf("failed to parse legacy config: %w", err)
	}

	// Convert to new format
	cfg := &Config{
		DevMode:     legacy.DevMode,
		DevModePath: legacy.WorkingDirectory,
		AWS: AWSConfig{
			Prod: AccountConfig{
				Profile: legacy.ProdProfile,
				Region:  legacy.ProdRegion,
			},
			Dev: AccountConfig{
				Profile: legacy.DevProfile,
				Region:  legacy.DevRegion,
			},
			Ops: AccountConfig{
				Profile: legacy.OpsProfile,
				Region:  legacy.OpsRegion,
			},
		},
		Initialized: legacy.Initialized,
	}

	return cfg, nil
}

// Save saves the configuration to ~/.plabs/plabs.yaml
func (c *Config) Save() error {
	configPath, err := GetConfigPath()
	if err != nil {
		return err
	}
	return c.SaveToPath(configPath)
}

// SaveToPath saves the configuration to a specific path
func (c *Config) SaveToPath(path string) error {
	// Ensure directory exists
	if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
		return fmt.Errorf("failed to create config directory: %w", err)
	}

	data, err := yaml.Marshal(c)
	if err != nil {
		return fmt.Errorf("failed to marshal config: %w", err)
	}

	if err := os.WriteFile(path, data, 0644); err != nil {
		return fmt.Errorf("failed to write config: %w", err)
	}

	return nil
}

// IsSingleAccountMode returns true if only the prod account is configured
func (c *Config) IsSingleAccountMode() bool {
	return c.AWS.Dev.Profile == "" && c.AWS.Ops.Profile == ""
}

// IsMultiAccountMode returns true if multiple accounts are configured
func (c *Config) IsMultiAccountMode() bool {
	return c.AWS.Dev.Profile != "" || c.AWS.Ops.Profile != ""
}

// Validate checks if the configuration is valid
func (c *Config) Validate() error {
	// Only profile is required - account IDs are auto-derived from AWS
	if c.AWS.Prod.Profile == "" {
		return fmt.Errorf("prod AWS profile is required")
	}
	return nil
}

// IsScenarioEnabled checks if a scenario is enabled (by variable name)
func (c *Config) IsScenarioEnabled(variableName string) bool {
	// Normalize: remove "enable_" prefix if present
	name := strings.TrimPrefix(variableName, "enable_")
	for _, s := range c.Scenarios.Enabled {
		if s == name || s == variableName {
			return true
		}
	}
	return false
}

// EnableScenario adds a scenario to the enabled list
func (c *Config) EnableScenario(variableName string) {
	// Normalize: remove "enable_" prefix for storage
	name := strings.TrimPrefix(variableName, "enable_")
	if !c.IsScenarioEnabled(name) {
		c.Scenarios.Enabled = append(c.Scenarios.Enabled, name)
		sort.Strings(c.Scenarios.Enabled)
	}
}

// DisableScenario removes a scenario from the enabled list
func (c *Config) DisableScenario(variableName string) {
	// Normalize: remove "enable_" prefix
	name := strings.TrimPrefix(variableName, "enable_")
	var newEnabled []string
	for _, s := range c.Scenarios.Enabled {
		if s != name && s != variableName {
			newEnabled = append(newEnabled, s)
		}
	}
	c.Scenarios.Enabled = newEnabled
}

// GetEnabledScenarioVars returns a map of scenario variable names to their enabled state
// Returns full variable names with "enable_" prefix for terraform compatibility
func (c *Config) GetEnabledScenarioVars() map[string]bool {
	enabled := make(map[string]bool)
	for _, s := range c.Scenarios.Enabled {
		// Add both forms for compatibility
		enabled[s] = true
		if !strings.HasPrefix(s, "enable_") {
			enabled["enable_"+s] = true
		}
	}
	return enabled
}

// GenerateTFVars generates the content for terraform.tfvars
func (c *Config) GenerateTFVars() string {
	var lines []string

	// Add header
	lines = append(lines, "# Pathfinding Labs Configuration")
	lines = append(lines, "# Generated by plabs - DO NOT EDIT DIRECTLY")
	lines = append(lines, "# Use 'plabs config' and 'plabs enable/disable' to modify")
	lines = append(lines, "")

	// Add account configuration
	// NOTE: Account IDs are automatically derived from AWS profiles via aws_caller_identity
	lines = append(lines, "# AWS Account Configuration")
	lines = append(lines, "# Account IDs are auto-derived from profiles - no need to specify them!")
	lines = append(lines, "enable_prod_environment  = true")
	lines = append(lines, fmt.Sprintf("prod_account_aws_profile = %q", c.AWS.Prod.Profile))
	if c.AWS.Prod.Region != "" {
		lines = append(lines, fmt.Sprintf("aws_region               = %q", c.AWS.Prod.Region))
	}
	lines = append(lines, "")

	// Dev environment (optional)
	if c.AWS.Dev.Profile != "" {
		lines = append(lines, "# Dev Environment (for cross-account scenarios)")
		lines = append(lines, "enable_dev_environment  = true")
		lines = append(lines, fmt.Sprintf("dev_account_aws_profile = %q", c.AWS.Dev.Profile))
		lines = append(lines, "")
	}

	// Ops environment (optional)
	if c.AWS.Ops.Profile != "" {
		lines = append(lines, "# Ops Environment (for cross-account scenarios)")
		lines = append(lines, "enable_ops_environment         = true")
		lines = append(lines, fmt.Sprintf("operations_account_aws_profile = %q", c.AWS.Ops.Profile))
		lines = append(lines, "")
	}

	// Add enabled scenarios section
	lines = append(lines, "# Enabled Scenarios")
	if len(c.Scenarios.Enabled) == 0 {
		lines = append(lines, "# Use 'plabs enable <scenario-id>' to enable scenarios")
	} else {
		for _, scenario := range c.Scenarios.Enabled {
			varName := scenario
			if !strings.HasPrefix(varName, "enable_") {
				varName = "enable_" + varName
			}
			lines = append(lines, fmt.Sprintf("%s = true", varName))
		}
	}
	lines = append(lines, "")

	return strings.Join(lines, "\n")
}

// SyncTFVars writes the terraform.tfvars to the specified terraform directory
func (c *Config) SyncTFVars(terraformDir string) error {
	tfvarsPath := filepath.Join(terraformDir, "terraform.tfvars")
	content := c.GenerateTFVars()
	return os.WriteFile(tfvarsPath, []byte(content), 0644)
}

// Legacy compatibility - helper to get profile values in the old format
// ProdProfile returns the prod profile for backwards compatibility
func (c *Config) ProdProfile() string {
	return c.AWS.Prod.Profile
}

// DevProfile returns the dev profile for backwards compatibility
func (c *Config) DevProfile() string {
	return c.AWS.Dev.Profile
}

// OpsProfile returns the ops profile for backwards compatibility
func (c *Config) OpsProfile() string {
	return c.AWS.Ops.Profile
}

// ProdRegion returns the prod region for backwards compatibility
func (c *Config) ProdRegion() string {
	return c.AWS.Prod.Region
}
