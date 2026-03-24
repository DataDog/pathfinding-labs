package terraform

import (
	"bufio"
	"os"
	"regexp"
	"sort"
)

// TFVars provides read access to terraform.tfvars files.
// Note: Writing to tfvars is now handled by config.Config.SyncTFVars()
// which generates tfvars from the single source of truth (plabs.yaml).
type TFVars struct {
	path string
}

// NewTFVars creates a new TFVars reader
func NewTFVars(path string) *TFVars {
	return &TFVars{path: path}
}

// Exists checks if the tfvars file exists
func (t *TFVars) Exists() bool {
	_, err := os.Stat(t.path)
	return err == nil
}

// GetEnabledScenarios returns a map of scenario variable names to their enabled state
// by reading the terraform.tfvars file.
func (t *TFVars) GetEnabledScenarios() (map[string]bool, error) {
	enabled := make(map[string]bool)

	if !t.Exists() {
		return enabled, nil
	}

	file, err := os.Open(t.path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	// Match lines like: enable_scenario_name = true
	enablePattern := regexp.MustCompile(`^\s*(enable_\S+)\s*=\s*(true|false)\s*$`)

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := scanner.Text()
		matches := enablePattern.FindStringSubmatch(line)
		if len(matches) == 3 {
			varName := matches[1]
			value := matches[2] == "true"
			enabled[varName] = value
		}
	}

	return enabled, scanner.Err()
}

// ListEnabledScenarios returns a sorted list of enabled scenario variable names
func (t *TFVars) ListEnabledScenarios() ([]string, error) {
	enabled, err := t.GetEnabledScenarios()
	if err != nil {
		return nil, err
	}

	var result []string
	for name, isEnabled := range enabled {
		if isEnabled {
			result = append(result, name)
		}
	}

	sort.Strings(result)
	return result, nil
}

// GetEnabledEnvironments returns the enabled state of each environment
// by reading the terraform.tfvars file.
func (t *TFVars) GetEnabledEnvironments() (prod, dev, ops, attacker bool, err error) {
	if !t.Exists() {
		return true, false, false, false, nil // Default: only prod enabled
	}

	content, err := t.readContent()
	if err != nil {
		return false, false, false, false, err
	}

	// Parse environment enabled flags
	prodPattern := regexp.MustCompile(`(?m)^\s*enable_prod_environment\s*=\s*(true|false)`)
	devPattern := regexp.MustCompile(`(?m)^\s*enable_dev_environment\s*=\s*(true|false)`)
	opsPattern := regexp.MustCompile(`(?m)^\s*enable_ops_environment\s*=\s*(true|false)`)
	attackerPattern := regexp.MustCompile(`(?m)^\s*enable_attacker_environment\s*=\s*(true|false)`)

	// Default prod to true if not specified
	prod = true
	if matches := prodPattern.FindStringSubmatch(content); len(matches) == 2 {
		prod = matches[1] == "true"
	}

	if matches := devPattern.FindStringSubmatch(content); len(matches) == 2 {
		dev = matches[1] == "true"
	}

	if matches := opsPattern.FindStringSubmatch(content); len(matches) == 2 {
		ops = matches[1] == "true"
	}

	if matches := attackerPattern.FindStringSubmatch(content); len(matches) == 2 {
		attacker = matches[1] == "true"
	}

	return prod, dev, ops, attacker, nil
}

// GetProfiles returns the AWS profiles configured in tfvars
func (t *TFVars) GetProfiles() (prod, dev, ops string, err error) {
	if !t.Exists() {
		return "", "", "", nil
	}

	content, err := t.readContent()
	if err != nil {
		return "", "", "", err
	}

	prodPattern := regexp.MustCompile(`prod_account_aws_profile\s*=\s*"([^"]+)"`)
	devPattern := regexp.MustCompile(`dev_account_aws_profile\s*=\s*"([^"]+)"`)
	opsPattern := regexp.MustCompile(`operations_account_aws_profile\s*=\s*"([^"]+)"`)

	if matches := prodPattern.FindStringSubmatch(content); len(matches) == 2 {
		prod = matches[1]
	}

	if matches := devPattern.FindStringSubmatch(content); len(matches) == 2 {
		dev = matches[1]
	}

	if matches := opsPattern.FindStringSubmatch(content); len(matches) == 2 {
		ops = matches[1]
	}

	return prod, dev, ops, nil
}

// readContent reads the entire tfvars file
func (t *TFVars) readContent() (string, error) {
	data, err := os.ReadFile(t.path)
	if err != nil {
		return "", err
	}
	return string(data), nil
}
