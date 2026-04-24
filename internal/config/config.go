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

	// Budget contains AWS Budget alert configuration
	Budget BudgetConfig `yaml:"budget,omitempty"`

	// ScenarioConfigs stores per-scenario user-supplied configuration values.
	// Outer key is the scenario name; inner key is the config key.
	ScenarioConfigs map[string]map[string]string `yaml:"scenario_configs,omitempty"`

	// Flags maps scenario unique IDs (e.g., "glue-003-to-admin") to CTF flag
	// values. Loaded from flags.default.yaml in the repo root at init time, or
	// from a vendor-supplied file via `plabs init --flag-file` or
	// `plabs flags import`. Emitted to terraform.tfvars as a single
	// `scenario_flags = { ... }` map variable.
	Flags map[string]string `yaml:"flags,omitempty"`

	// Initialized indicates if plabs init has been run
	Initialized bool `yaml:"initialized"`

	// SLRFlags controls which service-linked roles Terraform should create.
	// Not persisted to YAML -- detected at deploy time and written to tfvars.
	SLRFlags *ServiceLinkedRoleFlags `yaml:"-"`
}

// AWSConfig contains AWS account settings for all environments
type AWSConfig struct {
	Prod     AccountConfig  `yaml:"prod"`
	Dev      AccountConfig  `yaml:"dev,omitempty"`
	Ops      AccountConfig  `yaml:"ops,omitempty"`
	Attacker AttackerConfig `yaml:"attacker,omitempty"`
}

// AttackerConfig contains settings for the attacker AWS account
// Supports two modes: "profile" (use AWS profile directly) and "iam-user"
// (bootstrap an IAM admin user, then use its credentials going forward)
type AttackerConfig struct {
	Profile        string `yaml:"profile,omitempty"`
	Region         string `yaml:"region,omitempty"`
	Mode           string `yaml:"mode,omitempty"`               // "profile" or "iam-user"
	SetupProfile   string `yaml:"setup_profile,omitempty"`      // original profile used for bootstrap/destroy in iam-user mode
	IAMAccessKeyID string `yaml:"iam_access_key_id,omitempty"`  // stored after bootstrap
	IAMSecretKey   string `yaml:"iam_secret_key,omitempty"`     // stored after bootstrap
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

// BudgetConfig contains AWS Budget alert settings
type BudgetConfig struct {
	// Enabled indicates if budget alerts are enabled
	Enabled bool `yaml:"enabled"`

	// Email is the address to receive budget alerts
	Email string `yaml:"email,omitempty"`

	// LimitUSD is the monthly budget limit in USD
	LimitUSD int `yaml:"limit_usd,omitempty"`
}

// ServiceLinkedRoleFlags tracks which SLRs Terraform should create.
// Set to false for roles that already exist in the target account.
// These are NOT persisted to config -- they're detected at deploy time and
// written directly into terraform.tfvars.
type ServiceLinkedRoleFlags struct {
	CreateAutoScaling bool
	CreateSpot        bool
	CreateAppRunner   bool
	CreateMWAA        bool
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

	// Use 0600 permissions since config may contain IAM credentials
	if err := os.WriteFile(path, data, 0600); err != nil {
		return fmt.Errorf("failed to write config: %w", err)
	}

	return nil
}

// HasAttackerAccount returns true if an attacker account is configured
func (c *Config) HasAttackerAccount() bool {
	return c.AWS.Attacker.Profile != "" || c.AWS.Attacker.IAMAccessKeyID != ""
}

// IsAttackerBootstrapped returns true if the attacker IAM user has been bootstrapped
func (c *Config) IsAttackerBootstrapped() bool {
	return c.AWS.Attacker.Mode == "iam-user" && c.AWS.Attacker.IAMAccessKeyID != ""
}

// GetAttackerTFVarEnv returns TF_VAR_* environment variable strings for the attacker
// IAM user credentials. These should be injected into terraform process environments
// instead of writing credentials to terraform.tfvars.
func (c *Config) GetAttackerTFVarEnv() []string {
	if !c.IsAttackerBootstrapped() {
		return nil
	}
	return []string{
		"TF_VAR_attacker_iam_user_access_key=" + c.AWS.Attacker.IAMAccessKeyID,
		"TF_VAR_attacker_iam_user_secret_key=" + c.AWS.Attacker.IAMSecretKey,
	}
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

	// Attacker environment (optional)
	if c.HasAttackerAccount() {
		lines = append(lines, "# Attacker Environment (adversary-controlled account)")
		lines = append(lines, "enable_attacker_environment    = true")

		if c.AWS.Attacker.Mode == "iam-user" && c.AWS.Attacker.IAMAccessKeyID != "" {
			// IAM user mode (bootstrapped): credentials are injected via TF_VAR_* env vars
			// at runtime — never written to disk. See GetAttackerTFVarEnv().
			lines = append(lines, "attacker_account_use_iam_user  = true")
		} else {
			// Profile mode, or IAM user mode not yet bootstrapped (use setup profile)
			profile := c.AWS.Attacker.Profile
			if profile == "" && c.AWS.Attacker.SetupProfile != "" {
				profile = c.AWS.Attacker.SetupProfile
			}
			if profile != "" {
				lines = append(lines, fmt.Sprintf("attacker_account_aws_profile   = %q", profile))
			}
		}
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

	// Scenario-specific configurations
	if len(c.ScenarioConfigs) > 0 {
		lines = append(lines, "# Scenario specific configurations")
		scenarioNames := make([]string, 0, len(c.ScenarioConfigs))
		for name := range c.ScenarioConfigs {
			scenarioNames = append(scenarioNames, name)
		}
		sort.Strings(scenarioNames)
		for _, scenarioName := range scenarioNames {
			vals := c.ScenarioConfigs[scenarioName]
			keys := make([]string, 0, len(vals))
			for k := range vals {
				keys = append(keys, k)
			}
			sort.Strings(keys)
			for _, k := range keys {
				// Terraform variable names cannot contain hyphens in var.NAME expressions,
				// so we convert hyphens in the scenario name to underscores.
				varName := strings.ReplaceAll(scenarioName, "-", "_") + "_" + k
				lines = append(lines, fmt.Sprintf("%s = %q", varName, vals[k]))
			}
		}
		lines = append(lines, "")
	}

	// CTF scenario flags. Emitted as a single map(string) so root main.tf can
	// lookup(var.scenario_flags, "<scenario-id>", "flag{MISSING}") per module.
	// Keys are scenario unique IDs (e.g., "glue-003-to-admin").
	if len(c.Flags) > 0 {
		lines = append(lines, "# CTF scenario flags (loaded from flags.default.yaml or a vendor override file)")
		lines = append(lines, "scenario_flags = {")
		flagIDs := make([]string, 0, len(c.Flags))
		for id := range c.Flags {
			flagIDs = append(flagIDs, id)
		}
		sort.Strings(flagIDs)
		for _, id := range flagIDs {
			lines = append(lines, fmt.Sprintf("  %q = %q", id, c.Flags[id]))
		}
		lines = append(lines, "}")
		lines = append(lines, "")
	}

	// Add budget configuration
	if c.Budget.Enabled && c.Budget.Email != "" {
		lines = append(lines, "# Budget Alerts")
		lines = append(lines, "enable_budget_alerts = true")
		lines = append(lines, fmt.Sprintf("budget_alert_email   = %q", c.Budget.Email))
		if c.Budget.LimitUSD > 0 {
			lines = append(lines, fmt.Sprintf("budget_limit_usd     = %d", c.Budget.LimitUSD))
		} else {
			lines = append(lines, "budget_limit_usd     = 50")
		}
		lines = append(lines, "")
	}

	// Add service-linked role creation flags when detected
	if c.SLRFlags != nil {
		lines = append(lines, "# Service-Linked Role Creation (auto-detected by plabs)")
		lines = append(lines, fmt.Sprintf("create_autoscaling_slr = %t", c.SLRFlags.CreateAutoScaling))
		lines = append(lines, fmt.Sprintf("create_spot_slr        = %t", c.SLRFlags.CreateSpot))
		lines = append(lines, fmt.Sprintf("create_apprunner_slr   = %t", c.SLRFlags.CreateAppRunner))
		lines = append(lines, fmt.Sprintf("create_mwaa_slr        = %t", c.SLRFlags.CreateMWAA))
		lines = append(lines, "")
	}

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

// GetScenarioConfig returns the value for a per-scenario config key.
// Returns the value and true if found, empty string and false if not set.
func (c *Config) GetScenarioConfig(scenarioName, key string) (string, bool) {
	if c.ScenarioConfigs == nil {
		return "", false
	}
	vals, ok := c.ScenarioConfigs[scenarioName]
	if !ok {
		return "", false
	}
	v, ok := vals[key]
	return v, ok
}

// SetScenarioConfig stores a per-scenario config value and writes it into
// terraform.tfvars using the naming convention {scenario-name}-{key} = "value".
func (c *Config) SetScenarioConfig(scenarioName, key, value string) {
	if c.ScenarioConfigs == nil {
		c.ScenarioConfigs = make(map[string]map[string]string)
	}
	if c.ScenarioConfigs[scenarioName] == nil {
		c.ScenarioConfigs[scenarioName] = make(map[string]string)
	}
	c.ScenarioConfigs[scenarioName][key] = value
}

// GetAllScenarioConfigs returns all config values for a given scenario.
// Returns nil if no values have been set.
func (c *Config) GetAllScenarioConfigs(scenarioName string) map[string]string {
	if c.ScenarioConfigs == nil {
		return nil
	}
	return c.ScenarioConfigs[scenarioName]
}

// FlagSetFile is the on-disk schema for flags.default.yaml and vendor override
// files. Keys of `Flags` are scenario unique IDs (e.g., "glue-003-to-admin");
// values are the flag strings (e.g., "flag{glue_003_admin_captured}").
type FlagSetFile struct {
	Flags map[string]string `yaml:"flags"`
}

// LoadFlagsFromFile reads a YAML flag-set file and replaces c.Flags with its
// contents. Used by `plabs init --flag-file`, `plabs flags import`, and the
// default-flag loader that reads flags.default.yaml from the repo root during
// init. Returns an error if the file is missing, unreadable, or has a shape
// other than `{flags: {id: value, ...}}`.
func (c *Config) LoadFlagsFromFile(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("failed to read flag file %s: %w", path, err)
	}
	var file FlagSetFile
	if err := yaml.Unmarshal(data, &file); err != nil {
		return fmt.Errorf("failed to parse flag file %s: %w", path, err)
	}
	if file.Flags == nil {
		return fmt.Errorf("flag file %s has no top-level `flags:` key", path)
	}
	c.Flags = file.Flags
	return nil
}

// GetFlag returns the flag value for a given scenario unique ID. The second
// return value is true if a flag is set, false if missing. Used by the
// `plabs enable` flag-presence check.
func (c *Config) GetFlag(scenarioUniqueID string) (string, bool) {
	if c.Flags == nil {
		return "", false
	}
	v, ok := c.Flags[scenarioUniqueID]
	return v, ok
}

// SetFlag sets a single flag value and ensures the map is initialized. Used by
// `plabs flags set`.
func (c *Config) SetFlag(scenarioUniqueID, value string) {
	if c.Flags == nil {
		c.Flags = make(map[string]string)
	}
	c.Flags[scenarioUniqueID] = value
}
