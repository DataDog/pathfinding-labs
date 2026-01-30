package config

import (
	"fmt"
	"os"
	"path/filepath"

	"gopkg.in/yaml.v3"
)

// Config represents the CLI configuration stored in ~/.plabs/config.yaml
type Config struct {
	// WorkingDirectory is the path to the terraform files (tfvars, modules)
	// In dev mode: the local repo path
	// In normal mode: ~/.plabs/pathfinding-labs/
	WorkingDirectory string `yaml:"working_directory,omitempty"`

	// DevMode indicates if plabs is using a local repository
	DevMode bool `yaml:"dev_mode"`

	// ProdAccountID is the production AWS account ID
	ProdAccountID string `yaml:"prod_account_id,omitempty"`

	// ProdProfile is the AWS profile for the production account
	ProdProfile string `yaml:"prod_profile,omitempty"`

	// DevAccountID is the development AWS account ID (optional)
	DevAccountID string `yaml:"dev_account_id,omitempty"`

	// DevProfile is the AWS profile for the development account (optional)
	DevProfile string `yaml:"dev_profile,omitempty"`

	// OpsAccountID is the operations AWS account ID (optional)
	OpsAccountID string `yaml:"ops_account_id,omitempty"`

	// OpsProfile is the AWS profile for the operations account (optional)
	OpsProfile string `yaml:"ops_profile,omitempty"`

	// Initialized indicates if plabs init has been run
	Initialized bool `yaml:"initialized"`
}

// Load loads the configuration from the specified path
func Load(path string) (*Config, error) {
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

// Save saves the configuration to the specified path
func (c *Config) Save(path string) error {
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
	return c.DevProfile == "" && c.OpsProfile == ""
}

// IsMultiAccountMode returns true if multiple accounts are configured
func (c *Config) IsMultiAccountMode() bool {
	return c.DevProfile != "" || c.OpsProfile != ""
}

// Validate checks if the configuration is valid
func (c *Config) Validate() error {
	// Only profile is required - account IDs are auto-derived from AWS
	if c.ProdProfile == "" {
		return fmt.Errorf("prod AWS profile is required")
	}
	return nil
}
