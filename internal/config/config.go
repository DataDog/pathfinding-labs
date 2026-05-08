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

// WorkspaceConfig holds all configuration scoped to a single workspace.
// A workspace is a fully isolated deployment environment with its own AWS
// accounts, enabled scenarios, terraform state, and dev mode setting.
type WorkspaceConfig struct {
	// DevMode indicates if this workspace uses a local repository for development
	DevMode bool `yaml:"dev_mode"`

	// DevModePath is the path to the local repo when dev mode is enabled
	DevModePath string `yaml:"dev_mode_path,omitempty"`

	// AWS contains all AWS account configuration for this workspace
	AWS AWSConfig `yaml:"aws"`

	// Scenarios contains enabled scenarios configuration for this workspace
	Scenarios ScenariosConfig `yaml:"scenarios"`

	// Budget contains AWS Budget alert configuration for this workspace
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

	// Initialized indicates if plabs init has been run for this workspace
	Initialized bool `yaml:"initialized"`

	// SLRFlags controls which service-linked roles Terraform should create.
	// Not persisted to YAML -- detected at deploy time and written to tfvars.
	SLRFlags *ServiceLinkedRoleFlags `yaml:"-"`
}

// Config is the top-level structure stored in ~/.plabs/plabs.yaml.
// It is a container for named workspaces. Most configuration lives inside
// a WorkspaceConfig reachable via Active().
type Config struct {
	// ActiveWorkspace is the name of the currently-active workspace.
	// Defaults to "default" when empty.
	ActiveWorkspace string `yaml:"active_workspace,omitempty"`

	// IncludeBeta controls whether scenarios marked status: "beta" are visible
	// in listings and the TUI. Global preference — not workspace-scoped.
	// Set with: plabs config set include-beta true
	IncludeBeta bool `yaml:"include_beta"`

	// Workspaces holds all named workspace configurations.
	Workspaces map[string]*WorkspaceConfig `yaml:"workspaces"`
}

// Active returns the WorkspaceConfig for the currently active workspace.
// Always returns a non-nil pointer; creates the workspace entry if missing.
func (c *Config) Active() *WorkspaceConfig {
	name := c.ActiveName()
	if c.Workspaces == nil {
		c.Workspaces = make(map[string]*WorkspaceConfig)
	}
	if ws, ok := c.Workspaces[name]; ok {
		return ws
	}
	// Create on first access (e.g., fresh config)
	ws := &WorkspaceConfig{}
	c.Workspaces[name] = ws
	return ws
}

// ActiveName returns the name of the currently active workspace.
// Returns "default" when no active workspace is set.
func (c *Config) ActiveName() string {
	if c.ActiveWorkspace == "" {
		return "default"
	}
	return c.ActiveWorkspace
}

// WorkspaceCount returns the number of configured workspaces.
func (c *Config) WorkspaceCount() int {
	return len(c.Workspaces)
}

// WorkspaceNames returns workspace names sorted alphabetically, with "default" first.
func (c *Config) WorkspaceNames() []string {
	names := make([]string, 0, len(c.Workspaces))
	for name := range c.Workspaces {
		names = append(names, name)
	}
	sort.Strings(names)
	// Promote "default" to the front
	for i, name := range names {
		if name == "default" {
			names = append([]string{"default"}, append(names[:i], names[i+1:]...)...)
			break
		}
	}
	return names
}

// NewDefaultConfig returns a minimal valid Config with a single empty default workspace.
func NewDefaultConfig() *Config {
	return newDefaultConfig()
}

// AWSConfig contains AWS account settings for all environments
type AWSConfig struct {
	Prod     AccountConfig  `yaml:"prod"`
	Dev      AccountConfig  `yaml:"dev,omitempty"`
	Ops      AccountConfig  `yaml:"ops,omitempty"`
	Attacker AttackerConfig `yaml:"attacker,omitempty"`
}

// AttackerConfig contains settings for the attacker AWS account.
// Supports two modes: "profile" (use AWS profile directly) and "iam-user"
// (bootstrap an IAM admin user, then use its credentials going forward).
type AttackerConfig struct {
	Profile        string `yaml:"profile,omitempty"`
	Region         string `yaml:"region,omitempty"`
	Mode           string `yaml:"mode,omitempty"`              // "profile" or "iam-user"
	SetupProfile   string `yaml:"setup_profile,omitempty"`     // original profile used for bootstrap/destroy in iam-user mode
	IAMAccessKeyID string `yaml:"iam_access_key_id,omitempty"` // stored after bootstrap
	IAMSecretKey   string `yaml:"iam_secret_key,omitempty"`    // stored after bootstrap
}

// AccountConfig contains settings for a single AWS account/environment
type AccountConfig struct {
	Profile string `yaml:"profile,omitempty"`
	Region  string `yaml:"region,omitempty"`
}

// ScenariosConfig contains scenario enablement configuration
type ScenariosConfig struct {
	// Enabled is the list of enabled scenario variable names.
	// Uses terraform variable names without the "enable_" prefix.
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
}

// GetConfigPath returns the path to the config file.
// Always returns ~/.plabs/plabs.yaml.
func GetConfigPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("failed to get home directory: %w", err)
	}
	return filepath.Join(home, ".plabs", ConfigFileName), nil
}

// Load loads the configuration from ~/.plabs/plabs.yaml.
// If plabs.yaml doesn't exist but legacy config.yaml does, it migrates the config.
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
			ws := cfg.Active()
			var tfDir string
			if ws.DevMode && ws.DevModePath != "" {
				tfDir = ws.DevModePath
			} else {
				tfDir = filepath.Join(filepath.Dir(configPath), "pathfinding-labs")
			}
			// Best effort — don't fail migration if tfvars sync fails
			_ = cfg.Active().SyncTFVars(tfDir)
			return cfg, nil
		}
	}

	return LoadFromPath(configPath)
}

// LoadFromPath loads the configuration from a specific path.
// Handles both the current workspace format and the old flat format,
// automatically migrating flat configs on first load.
func LoadFromPath(path string) (*Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		if os.IsNotExist(err) {
			return newDefaultConfig(), nil
		}
		return nil, fmt.Errorf("failed to read config: %w", err)
	}

	// Probe: detect whether this is the new workspace format or the old flat format.
	// The new format always has a top-level "workspaces" key.
	var probe map[string]interface{}
	if err := yaml.Unmarshal(data, &probe); err != nil {
		return nil, fmt.Errorf("failed to parse config: %w", err)
	}

	if _, hasWorkspaces := probe["workspaces"]; hasWorkspaces {
		// New workspace format
		var cfg Config
		if err := yaml.Unmarshal(data, &cfg); err != nil {
			return nil, fmt.Errorf("failed to parse config: %w", err)
		}
		if cfg.Workspaces == nil {
			cfg.Workspaces = make(map[string]*WorkspaceConfig)
		}
		// Ensure the active workspace always exists
		name := cfg.ActiveName()
		if _, ok := cfg.Workspaces[name]; !ok {
			cfg.Workspaces[name] = &WorkspaceConfig{}
		}
		return &cfg, nil
	}

	// Old flat format: parse with the legacy flat struct and migrate in memory.
	var flat flatConfig
	if err := yaml.Unmarshal(data, &flat); err != nil {
		return nil, fmt.Errorf("failed to parse legacy flat config: %w", err)
	}
	cfg := migrateFlat(&flat)

	// Auto-save the migrated format so future loads use the new structure.
	if saveErr := cfg.SaveToPath(path); saveErr != nil {
		// Non-fatal: continue with the in-memory migrated config
		fmt.Fprintf(os.Stderr, "Warning: could not save migrated config: %v\n", saveErr)
	}
	return cfg, nil
}

// newDefaultConfig returns a minimal valid Config with an empty default workspace.
func newDefaultConfig() *Config {
	return &Config{
		ActiveWorkspace: "default",
		Workspaces:      map[string]*WorkspaceConfig{"default": {}},
	}
}

// flatConfig mirrors the OLD (pre-workspace) Config struct for reading legacy files.
// Used only during migration; never written to disk.
type flatConfig struct {
	DevMode         bool                           `yaml:"dev_mode"`
	DevModePath     string                         `yaml:"dev_mode_path,omitempty"`
	AWS             AWSConfig                      `yaml:"aws"`
	Scenarios       ScenariosConfig                `yaml:"scenarios"`
	Budget          BudgetConfig                   `yaml:"budget,omitempty"`
	ScenarioConfigs map[string]map[string]string   `yaml:"scenario_configs,omitempty"`
	Flags           map[string]string              `yaml:"flags,omitempty"`
	IncludeBeta     bool                           `yaml:"include_beta"`
	Initialized     bool                           `yaml:"initialized"`
}

// migrateFlat converts the old flat config format to the new workspace-aware format.
// All existing config is placed into the "default" workspace.
func migrateFlat(flat *flatConfig) *Config {
	ws := &WorkspaceConfig{
		DevMode:         flat.DevMode,
		DevModePath:     flat.DevModePath,
		AWS:             flat.AWS,
		Scenarios:       flat.Scenarios,
		Budget:          flat.Budget,
		ScenarioConfigs: flat.ScenarioConfigs,
		Flags:           flat.Flags,
		Initialized:     flat.Initialized,
	}
	return &Config{
		ActiveWorkspace: "default",
		IncludeBeta:     flat.IncludeBeta,
		Workspaces:      map[string]*WorkspaceConfig{"default": ws},
	}
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

// migrateFromLegacy reads the old config.yaml format and converts to new workspace format.
func migrateFromLegacy(legacyPath string) (*Config, error) {
	data, err := os.ReadFile(legacyPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read legacy config: %w", err)
	}

	var legacy LegacyConfig
	if err := yaml.Unmarshal(data, &legacy); err != nil {
		return nil, fmt.Errorf("failed to parse legacy config: %w", err)
	}

	ws := &WorkspaceConfig{
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

	return &Config{
		ActiveWorkspace: "default",
		Workspaces:      map[string]*WorkspaceConfig{"default": ws},
	}, nil
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

// --- WorkspaceConfig methods ---
// All methods that operate on workspace-scoped data live here.

// HasAttackerAccount returns true if an attacker account is configured
func (w *WorkspaceConfig) HasAttackerAccount() bool {
	return w.AWS.Attacker.Profile != "" || w.AWS.Attacker.IAMAccessKeyID != ""
}

// IsAttackerBootstrapped returns true if the attacker IAM user has been bootstrapped
func (w *WorkspaceConfig) IsAttackerBootstrapped() bool {
	return w.AWS.Attacker.Mode == "iam-user" && w.AWS.Attacker.IAMAccessKeyID != ""
}

// GetAttackerTFVarEnv returns TF_VAR_* environment variable strings for the attacker
// IAM user credentials. These should be injected into terraform process environments
// instead of writing credentials to terraform.tfvars.
func (w *WorkspaceConfig) GetAttackerTFVarEnv() []string {
	if !w.IsAttackerBootstrapped() {
		return nil
	}
	return []string{
		"TF_VAR_attacker_iam_user_access_key=" + w.AWS.Attacker.IAMAccessKeyID,
		"TF_VAR_attacker_iam_user_secret_key=" + w.AWS.Attacker.IAMSecretKey,
	}
}

// IsSingleAccountMode returns true if only the prod account is configured
func (w *WorkspaceConfig) IsSingleAccountMode() bool {
	return w.AWS.Dev.Profile == "" && w.AWS.Ops.Profile == ""
}

// IsMultiAccountMode returns true if multiple accounts are configured
func (w *WorkspaceConfig) IsMultiAccountMode() bool {
	return w.AWS.Dev.Profile != "" || w.AWS.Ops.Profile != ""
}

// Validate checks if the workspace configuration is valid
func (w *WorkspaceConfig) Validate() error {
	if w.AWS.Prod.Profile == "" {
		return fmt.Errorf("prod AWS profile is required")
	}
	return nil
}

// IsScenarioEnabled checks if a scenario is enabled (by variable name)
func (w *WorkspaceConfig) IsScenarioEnabled(variableName string) bool {
	name := strings.TrimPrefix(variableName, "enable_")
	for _, s := range w.Scenarios.Enabled {
		if s == name || s == variableName {
			return true
		}
	}
	return false
}

// EnableScenario adds a scenario to the enabled list
func (w *WorkspaceConfig) EnableScenario(variableName string) {
	name := strings.TrimPrefix(variableName, "enable_")
	if !w.IsScenarioEnabled(name) {
		w.Scenarios.Enabled = append(w.Scenarios.Enabled, name)
		sort.Strings(w.Scenarios.Enabled)
	}
}

// DisableScenario removes a scenario from the enabled list
func (w *WorkspaceConfig) DisableScenario(variableName string) {
	name := strings.TrimPrefix(variableName, "enable_")
	var newEnabled []string
	for _, s := range w.Scenarios.Enabled {
		if s != name && s != variableName {
			newEnabled = append(newEnabled, s)
		}
	}
	w.Scenarios.Enabled = newEnabled
}

// GetEnabledScenarioVars returns a map of scenario variable names to their enabled state.
// Returns full variable names with "enable_" prefix for terraform compatibility.
func (w *WorkspaceConfig) GetEnabledScenarioVars() map[string]bool {
	enabled := make(map[string]bool)
	for _, s := range w.Scenarios.Enabled {
		enabled[s] = true
		if !strings.HasPrefix(s, "enable_") {
			enabled["enable_"+s] = true
		}
	}
	return enabled
}

// GenerateTFVars generates the content for terraform.tfvars
func (w *WorkspaceConfig) GenerateTFVars() string {
	var lines []string

	lines = append(lines, "# Pathfinding Labs Configuration")
	lines = append(lines, "# Generated by plabs - DO NOT EDIT DIRECTLY")
	lines = append(lines, "# Use 'plabs config' and 'plabs enable/disable' to modify")
	lines = append(lines, "")

	// Account configuration
	lines = append(lines, "# AWS Account Configuration")
	lines = append(lines, "# Account IDs are auto-derived from profiles - no need to specify them!")
	lines = append(lines, "enable_prod_environment  = true")
	lines = append(lines, fmt.Sprintf("prod_account_aws_profile = %q", w.AWS.Prod.Profile))
	if w.AWS.Prod.Region != "" {
		lines = append(lines, fmt.Sprintf("aws_region               = %q", w.AWS.Prod.Region))
	}
	lines = append(lines, "")

	if w.AWS.Dev.Profile != "" {
		lines = append(lines, "# Dev Environment (for cross-account scenarios)")
		lines = append(lines, "enable_dev_environment  = true")
		lines = append(lines, fmt.Sprintf("dev_account_aws_profile = %q", w.AWS.Dev.Profile))
		lines = append(lines, "")
	}

	if w.AWS.Ops.Profile != "" {
		lines = append(lines, "# Ops Environment (for cross-account scenarios)")
		lines = append(lines, "enable_ops_environment         = true")
		lines = append(lines, fmt.Sprintf("operations_account_aws_profile = %q", w.AWS.Ops.Profile))
		lines = append(lines, "")
	}

	if w.HasAttackerAccount() {
		lines = append(lines, "# Attacker Environment (adversary-controlled account)")
		lines = append(lines, "enable_attacker_environment    = true")

		if w.AWS.Attacker.Mode == "iam-user" && w.AWS.Attacker.IAMAccessKeyID != "" {
			lines = append(lines, "attacker_account_use_iam_user  = true")
		} else {
			profile := w.AWS.Attacker.Profile
			if profile == "" && w.AWS.Attacker.SetupProfile != "" {
				profile = w.AWS.Attacker.SetupProfile
			}
			if profile != "" {
				lines = append(lines, fmt.Sprintf("attacker_account_aws_profile   = %q", profile))
			}
		}
		lines = append(lines, "")
	}

	lines = append(lines, "# Enabled Scenarios")
	if len(w.Scenarios.Enabled) == 0 {
		lines = append(lines, "# Use 'plabs enable <scenario-id>' to enable scenarios")
	} else {
		for _, scenario := range w.Scenarios.Enabled {
			varName := scenario
			if !strings.HasPrefix(varName, "enable_") {
				varName = "enable_" + varName
			}
			lines = append(lines, fmt.Sprintf("%s = true", varName))
		}
	}
	lines = append(lines, "")

	if len(w.ScenarioConfigs) > 0 {
		lines = append(lines, "# Scenario specific configurations")
		scenarioNames := make([]string, 0, len(w.ScenarioConfigs))
		for name := range w.ScenarioConfigs {
			scenarioNames = append(scenarioNames, name)
		}
		sort.Strings(scenarioNames)
		for _, scenarioName := range scenarioNames {
			vals := w.ScenarioConfigs[scenarioName]
			keys := make([]string, 0, len(vals))
			for k := range vals {
				keys = append(keys, k)
			}
			sort.Strings(keys)
			for _, k := range keys {
				varName := strings.ReplaceAll(scenarioName, "-", "_") + "_" + k
				lines = append(lines, fmt.Sprintf("%s = %q", varName, vals[k]))
			}
		}
		lines = append(lines, "")
	}

	if len(w.Flags) > 0 {
		lines = append(lines, "# CTF scenario flags (loaded from flags.default.yaml or a vendor override file)")
		lines = append(lines, "scenario_flags = {")
		flagIDs := make([]string, 0, len(w.Flags))
		for id := range w.Flags {
			flagIDs = append(flagIDs, id)
		}
		sort.Strings(flagIDs)
		for _, id := range flagIDs {
			lines = append(lines, fmt.Sprintf("  %q = %q", id, w.Flags[id]))
		}
		lines = append(lines, "}")
		lines = append(lines, "")
	}

	if w.Budget.Enabled && w.Budget.Email != "" {
		lines = append(lines, "# Budget Alerts")
		lines = append(lines, "enable_budget_alerts = true")
		lines = append(lines, fmt.Sprintf("budget_alert_email   = %q", w.Budget.Email))
		if w.Budget.LimitUSD > 0 {
			lines = append(lines, fmt.Sprintf("budget_limit_usd     = %d", w.Budget.LimitUSD))
		} else {
			lines = append(lines, "budget_limit_usd     = 50")
		}
		lines = append(lines, "")
	}

	if w.SLRFlags != nil {
		lines = append(lines, "# Service-Linked Role Creation (auto-detected by plabs)")
		lines = append(lines, fmt.Sprintf("create_autoscaling_slr = %t", w.SLRFlags.CreateAutoScaling))
		lines = append(lines, fmt.Sprintf("create_spot_slr        = %t", w.SLRFlags.CreateSpot))
		lines = append(lines, fmt.Sprintf("create_apprunner_slr   = %t", w.SLRFlags.CreateAppRunner))
		lines = append(lines, "")
	}

	return strings.Join(lines, "\n")
}

// SyncTFVars writes the terraform.tfvars to the specified terraform directory
func (w *WorkspaceConfig) SyncTFVars(terraformDir string) error {
	tfvarsPath := filepath.Join(terraformDir, "terraform.tfvars")
	content := w.GenerateTFVars()
	return os.WriteFile(tfvarsPath, []byte(content), 0644)
}

// ProdProfile returns the prod profile (legacy compatibility helper)
func (w *WorkspaceConfig) ProdProfile() string {
	return w.AWS.Prod.Profile
}

// DevProfile returns the dev profile (legacy compatibility helper)
func (w *WorkspaceConfig) DevProfile() string {
	return w.AWS.Dev.Profile
}

// OpsProfile returns the ops profile (legacy compatibility helper)
func (w *WorkspaceConfig) OpsProfile() string {
	return w.AWS.Ops.Profile
}

// ProdRegion returns the prod region (legacy compatibility helper)
func (w *WorkspaceConfig) ProdRegion() string {
	return w.AWS.Prod.Region
}

// GetScenarioConfig returns the value for a per-scenario config key.
func (w *WorkspaceConfig) GetScenarioConfig(scenarioName, key string) (string, bool) {
	if w.ScenarioConfigs == nil {
		return "", false
	}
	vals, ok := w.ScenarioConfigs[scenarioName]
	if !ok {
		return "", false
	}
	v, ok := vals[key]
	return v, ok
}

// SetScenarioConfig stores a per-scenario config value.
func (w *WorkspaceConfig) SetScenarioConfig(scenarioName, key, value string) {
	if w.ScenarioConfigs == nil {
		w.ScenarioConfigs = make(map[string]map[string]string)
	}
	if w.ScenarioConfigs[scenarioName] == nil {
		w.ScenarioConfigs[scenarioName] = make(map[string]string)
	}
	w.ScenarioConfigs[scenarioName][key] = value
}

// GetAllScenarioConfigs returns all config values for a given scenario.
func (w *WorkspaceConfig) GetAllScenarioConfigs(scenarioName string) map[string]string {
	if w.ScenarioConfigs == nil {
		return nil
	}
	return w.ScenarioConfigs[scenarioName]
}

// FlagSetFile is the on-disk schema for flags.default.yaml and vendor override files.
type FlagSetFile struct {
	Flags map[string]string `yaml:"flags"`
}

// LoadFlagsFromFile reads a YAML flag-set file and replaces w.Flags with its contents.
func (w *WorkspaceConfig) LoadFlagsFromFile(path string) error {
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
	w.Flags = file.Flags
	return nil
}

// GetFlag returns the flag value for a given scenario unique ID.
func (w *WorkspaceConfig) GetFlag(scenarioUniqueID string) (string, bool) {
	if w.Flags == nil {
		return "", false
	}
	v, ok := w.Flags[scenarioUniqueID]
	return v, ok
}

// SetFlag sets a single flag value.
func (w *WorkspaceConfig) SetFlag(scenarioUniqueID, value string) {
	if w.Flags == nil {
		w.Flags = make(map[string]string)
	}
	w.Flags[scenarioUniqueID] = value
}
