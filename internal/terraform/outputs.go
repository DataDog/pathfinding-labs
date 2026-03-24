package terraform

import (
	"encoding/json"
	"fmt"
)

// OutputValue represents a terraform output value
type OutputValue struct {
	Sensitive bool            `json:"sensitive"`
	Type      json.RawMessage `json:"type"`
	Value     interface{}     `json:"value"`
}

// Outputs represents all terraform outputs
type Outputs map[string]OutputValue

// ParseOutputs parses terraform output JSON
func ParseOutputs(jsonData string) (Outputs, error) {
	var outputs Outputs
	if err := json.Unmarshal([]byte(jsonData), &outputs); err != nil {
		return nil, fmt.Errorf("failed to parse terraform outputs: %w", err)
	}
	return outputs, nil
}

// Get retrieves a specific output value as a string
func (o Outputs) Get(name string) (string, bool) {
	val, exists := o[name]
	if !exists {
		return "", false
	}

	switch v := val.Value.(type) {
	case string:
		return v, true
	case nil:
		return "", true
	default:
		// Convert to JSON for complex types
		data, err := json.Marshal(v)
		if err != nil {
			return "", false
		}
		return string(data), true
	}
}

// GetMap retrieves a specific output value as a map
func (o Outputs) GetMap(name string) (map[string]interface{}, bool) {
	val, exists := o[name]
	if !exists {
		return nil, false
	}

	if val.Value == nil {
		return nil, true
	}

	if m, ok := val.Value.(map[string]interface{}); ok {
		return m, true
	}

	return nil, false
}

// GetScenarioOutput retrieves the output for a specific scenario
func (o Outputs) GetScenarioOutput(scenarioOutputName string) (map[string]interface{}, bool) {
	return o.GetMap(scenarioOutputName)
}

// GetStartingCredentials extracts starting user credentials from a scenario output
func (o Outputs) GetStartingCredentials(scenarioOutputName string) (*Credentials, error) {
	scenarioOutput, exists := o.GetMap(scenarioOutputName)
	if !exists {
		return nil, fmt.Errorf("scenario output %q not found", scenarioOutputName)
	}

	if scenarioOutput == nil {
		return nil, fmt.Errorf("scenario %q is not deployed (output is null)", scenarioOutputName)
	}

	creds := &Credentials{}

	// Try different credential field naming conventions
	accessKeyFields := []string{"starting_user_access_key_id", "starting_role_access_key_id", "access_key_id"}
	secretKeyFields := []string{"starting_user_secret_access_key", "starting_role_secret_access_key", "secret_access_key"}

	for _, field := range accessKeyFields {
		if val, ok := scenarioOutput[field].(string); ok && val != "" {
			creds.AccessKeyID = val
			break
		}
	}

	for _, field := range secretKeyFields {
		if val, ok := scenarioOutput[field].(string); ok && val != "" {
			creds.SecretAccessKey = val
			break
		}
	}

	// Session token is optional
	if val, ok := scenarioOutput["session_token"].(string); ok {
		creds.SessionToken = val
	}

	if creds.AccessKeyID == "" || creds.SecretAccessKey == "" {
		return nil, fmt.Errorf("credentials not found in scenario output")
	}

	return creds, nil
}

// Credentials holds AWS credentials
type Credentials struct {
	AccessKeyID     string
	SecretAccessKey string
	SessionToken    string
}

// Exists checks if an output exists and has a non-null value (for simple values like strings)
func (o Outputs) Exists(name string) bool {
	val, exists := o[name]
	return exists && val.Value != nil
}

// IsDeployed checks if a scenario appears to be deployed based on outputs
func (o Outputs) IsDeployed(scenarioOutputName string) bool {
	val, exists := o.GetMap(scenarioOutputName)
	return exists && val != nil
}

// GetDeployedScenarios returns a list of scenario output names that are deployed
func (o Outputs) GetDeployedScenarios() []string {
	var deployed []string
	for name, val := range o {
		// Skip non-scenario outputs
		if val.Value == nil {
			continue
		}
		// Scenario outputs are typically maps
		if _, ok := val.Value.(map[string]interface{}); ok {
			deployed = append(deployed, name)
		}
	}
	return deployed
}

// GetAccountIDs returns the derived account IDs from terraform outputs
func (o Outputs) GetAccountIDs() (prod, dev, ops, attacker string) {
	prod, _ = o.Get("prod_account_id")
	dev, _ = o.Get("dev_account_id")
	ops, _ = o.Get("operations_account_id")
	attacker, _ = o.Get("attacker_account_id")
	return prod, dev, ops, attacker
}
