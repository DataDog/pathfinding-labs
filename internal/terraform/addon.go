package terraform

import "fmt"

// Addon manages a user-supplied Terraform root (addon directory) that provisions
// account-level resources alongside the main pathfinding-labs scenarios.
//
// An addon has its own Terraform state and lifecycle. It is applied after the main
// root and destroyed before the main root.
type Addon struct {
	runner *Runner
}

// NewAddon creates an Addon that runs terraform in addonDir using the given binary
// directory and extra environment variables (typically TF_VAR_* for provider config).
func NewAddon(binDir, addonDir string, extraEnv []string) *Addon {
	return &Addon{
		runner: NewRunner(binDir, addonDir, WithEnv(extraEnv)),
	}
}

// IsInitialized reports whether terraform has been initialised in the addon directory.
func (a *Addon) IsInitialized() bool {
	return a.runner.IsInitialized()
}

// Init runs terraform init in the addon directory.
func (a *Addon) Init() error {
	return a.runner.Init()
}

// Plan runs terraform plan in the addon directory.
func (a *Addon) Plan() error {
	return a.runner.Plan()
}

// Apply runs terraform apply -auto-approve in the addon directory.
func (a *Addon) Apply() error {
	return a.runner.Apply(true)
}

// Destroy runs terraform destroy -auto-approve in the addon directory.
func (a *Addon) Destroy() error {
	return a.runner.Destroy(true)
}

// OutputValues returns the current terraform outputs of the addon as a flat
// map of output name → value. Sensitive values are included (the caller is
// responsible for handling them safely).
func (a *Addon) OutputValues() (map[string]any, error) {
	jsonStr, err := a.runner.OutputJSON()
	if err != nil {
		return nil, fmt.Errorf("failed to get addon outputs: %w", err)
	}
	outputs, err := ParseOutputs(jsonStr)
	if err != nil {
		return nil, fmt.Errorf("failed to parse addon outputs: %w", err)
	}
	result := make(map[string]any, len(outputs))
	for k, v := range outputs {
		result[k] = v.Value
	}
	return result, nil
}
