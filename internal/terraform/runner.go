package terraform

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"sort"
	"strings"
)

// Runner executes terraform commands
type Runner struct {
	tfPath    string
	workDir   string
	installer *Installer
	extraEnv  []string // additional env vars injected into every terraform subprocess
}

// NewRunner creates a new terraform runner
func NewRunner(binDir, workDir string) *Runner {
	return &Runner{
		workDir:   workDir,
		installer: NewInstaller(binDir),
	}
}

// SetExtraEnv sets additional environment variables to inject into every
// terraform subprocess (e.g. TF_VAR_* credential variables that must not be
// written to terraform.tfvars on disk).
func (r *Runner) SetExtraEnv(env []string) {
	r.extraEnv = env
}

// buildEnv returns a clean environment with any extra vars appended.
func (r *Runner) buildEnv() []string {
	return append(CleanEnv(), r.extraEnv...)
}

// ensureTerraform makes sure terraform is available and sets tfPath
func (r *Runner) ensureTerraform() error {
	if r.tfPath != "" {
		return nil
	}

	path, err := r.installer.EnsureInstalled()
	if err != nil {
		return err
	}

	r.tfPath = path
	return nil
}

// Init runs terraform init
func (r *Runner) Init() error {
	if err := r.ensureTerraform(); err != nil {
		return err
	}

	cmd := exec.Command(r.tfPath, "init")
	cmd.Dir = r.workDir
	cmd.Env = r.buildEnv()
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin

	return cmd.Run()
}

// Plan runs terraform plan
func (r *Runner) Plan() error {
	if err := r.ensureTerraform(); err != nil {
		return err
	}

	cmd := exec.Command(r.tfPath, "plan")
	cmd.Dir = r.workDir
	cmd.Env = r.buildEnv()
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin

	return cmd.Run()
}

// Apply runs terraform apply
func (r *Runner) Apply(autoApprove bool) error {
	if err := r.ensureTerraform(); err != nil {
		return err
	}

	args := []string{"apply"}
	if autoApprove {
		args = append(args, "-auto-approve")
	}

	cmd := exec.Command(r.tfPath, args...)
	cmd.Dir = r.workDir
	cmd.Env = r.buildEnv()
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin

	return cmd.Run()
}

// ApplyTarget runs terraform apply targeting a specific module
func (r *Runner) ApplyTarget(target string, autoApprove bool) error {
	if err := r.ensureTerraform(); err != nil {
		return err
	}

	args := []string{"apply", "-target=" + target}
	if autoApprove {
		args = append(args, "-auto-approve")
	}

	cmd := exec.Command(r.tfPath, args...)
	cmd.Dir = r.workDir
	cmd.Env = r.buildEnv()
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin

	return cmd.Run()
}

// Destroy runs terraform destroy
func (r *Runner) Destroy(autoApprove bool) error {
	if err := r.ensureTerraform(); err != nil {
		return err
	}

	args := []string{"destroy"}
	if autoApprove {
		args = append(args, "-auto-approve")
	}

	cmd := exec.Command(r.tfPath, args...)
	cmd.Dir = r.workDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin

	return cmd.Run()
}

// Output runs terraform output and returns the result
func (r *Runner) Output(name string) (string, error) {
	if err := r.ensureTerraform(); err != nil {
		return "", err
	}

	args := []string{"output", "-raw"}
	if name != "" {
		args = append(args, name)
	}

	cmd := exec.Command(r.tfPath, args...)
	cmd.Dir = r.workDir

	var out bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		return "", err
	}

	return strings.TrimSpace(out.String()), nil
}

// CleanEnv returns a copy of the current environment with problematic variables removed.
// Exported so callers can build on it when constructing terraform subprocess environments.
func CleanEnv() []string {
	var env []string
	for _, e := range os.Environ() {
		// Skip OTEL variables that cause terraform to fail
		if strings.HasPrefix(e, "OTEL_") {
			continue
		}
		env = append(env, e)
	}
	return env
}

// cleanEnv is the unexported alias kept for internal use.
func cleanEnv() []string { return CleanEnv() }

// OutputJSON runs terraform output -json and returns the result
func (r *Runner) OutputJSON() (string, error) {
	if err := r.ensureTerraform(); err != nil {
		return "", err
	}

	cmd := exec.Command(r.tfPath, "output", "-json")
	cmd.Dir = r.workDir
	cmd.Env = cleanEnv()

	var out bytes.Buffer
	cmd.Stdout = &out

	if err := cmd.Run(); err != nil {
		return "", err
	}

	return out.String(), nil
}

// Show runs terraform show
func (r *Runner) Show() error {
	if err := r.ensureTerraform(); err != nil {
		return err
	}

	cmd := exec.Command(r.tfPath, "show")
	cmd.Dir = r.workDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	return cmd.Run()
}

// Validate runs terraform validate
func (r *Runner) Validate() error {
	if err := r.ensureTerraform(); err != nil {
		return err
	}

	cmd := exec.Command(r.tfPath, "validate")
	cmd.Dir = r.workDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	return cmd.Run()
}

// IsInitialized checks if terraform has been initialized in the work directory
func (r *Runner) IsInitialized() bool {
	_, err := os.Stat(fmt.Sprintf("%s/.terraform", r.workDir))
	return err == nil
}

// StateList returns the list of resources in the terraform state
func (r *Runner) StateList() ([]string, error) {
	if err := r.ensureTerraform(); err != nil {
		return nil, err
	}

	cmd := exec.Command(r.tfPath, "state", "list")
	cmd.Dir = r.workDir
	cmd.Env = cleanEnv()

	var out bytes.Buffer
	cmd.Stdout = &out

	if err := cmd.Run(); err != nil {
		// Empty state is not an error
		return nil, nil
	}

	lines := strings.Split(strings.TrimSpace(out.String()), "\n")
	if len(lines) == 1 && lines[0] == "" {
		return nil, nil
	}

	return lines, nil
}

// IsModuleDeployed checks if a module has resources in the terraform state
func (r *Runner) IsModuleDeployed(moduleName string) bool {
	resources, err := r.StateList()
	if err != nil || resources == nil {
		return false
	}

	// Look for resources with the module prefix
	// Module names in state look like: module.module_name[0].resource_type.resource_name
	modulePrefix := fmt.Sprintf("module.%s", moduleName)

	for _, resource := range resources {
		if strings.HasPrefix(resource, modulePrefix) {
			return true
		}
	}

	return false
}

// GetDeployedModules returns a set of module names that have resources in state
func (r *Runner) GetDeployedModules() map[string]bool {
	resources, err := r.StateList()
	if err != nil || resources == nil {
		return nil
	}

	deployed := make(map[string]bool)
	for _, resource := range resources {
		// Extract module name from resource address
		// Format: module.module_name[0].resource_type.resource_name
		if strings.HasPrefix(resource, "module.") {
			// Remove "module." prefix and extract the module name
			rest := strings.TrimPrefix(resource, "module.")
			// Find the end of module name (could be [ or .)
			endIdx := strings.IndexAny(rest, "[.")
			if endIdx > 0 {
				moduleName := rest[:endIdx]
				deployed[moduleName] = true
			}
		}
	}

	return deployed
}

// GetTerraformPath returns the path to the terraform binary
func (r *Runner) GetTerraformPath() (string, error) {
	return r.installer.GetTerraformPath()
}

// GetTerraformVersion returns the terraform version
func (r *Runner) GetTerraformVersion() (string, error) {
	return r.installer.GetVersion()
}

// GetModuleResources returns ARNs for all resources in a specific module
func (r *Runner) GetModuleResources(moduleName string) ([]string, error) {
	if err := r.ensureTerraform(); err != nil {
		return nil, err
	}

	// Run terraform show -json to get full state with attributes
	cmd := exec.Command(r.tfPath, "show", "-json")
	cmd.Dir = r.workDir
	cmd.Env = cleanEnv()

	var out bytes.Buffer
	cmd.Stdout = &out

	if err := cmd.Run(); err != nil {
		return nil, err
	}

	return parseModuleARNs(out.Bytes(), moduleName)
}

// GetAllModuleResources returns a map of module name to their resource ARNs
func (r *Runner) GetAllModuleResources() (map[string][]string, error) {
	if err := r.ensureTerraform(); err != nil {
		return nil, err
	}

	// Run terraform show -json to get full state with attributes
	cmd := exec.Command(r.tfPath, "show", "-json")
	cmd.Dir = r.workDir
	cmd.Env = cleanEnv()

	var out bytes.Buffer
	cmd.Stdout = &out

	if err := cmd.Run(); err != nil {
		return nil, err
	}

	return parseAllModuleARNs(out.Bytes())
}

// tfShowJSON represents the structure of terraform show -json output
type tfShowJSON struct {
	Values *tfStateValues `json:"values"`
}

type tfStateValues struct {
	RootModule *tfModule `json:"root_module"`
}

type tfModule struct {
	Resources    []tfResource `json:"resources"`
	ChildModules []tfModule   `json:"child_modules"`
	Address      string       `json:"address"`
}

type tfResource struct {
	Address string                 `json:"address"`
	Type    string                 `json:"type"`
	Name    string                 `json:"name"`
	Values  map[string]interface{} `json:"values"`
}

// parseModuleARNs extracts ARNs for resources in a specific module
func parseModuleARNs(data []byte, moduleName string) ([]string, error) {
	var state tfShowJSON
	if err := json.Unmarshal(data, &state); err != nil {
		return nil, err
	}

	if state.Values == nil || state.Values.RootModule == nil {
		return nil, nil
	}

	// Normalize module name (remove [0] suffix if present)
	moduleName = strings.TrimSuffix(moduleName, "[0]")
	modulePrefix := "module." + moduleName

	var arns []string
	collectARNs(state.Values.RootModule, modulePrefix, &arns)

	sort.Strings(arns)
	return arns, nil
}

// parseAllModuleARNs extracts ARNs for all modules
func parseAllModuleARNs(data []byte) (map[string][]string, error) {
	var state tfShowJSON
	if err := json.Unmarshal(data, &state); err != nil {
		return nil, err
	}

	if state.Values == nil || state.Values.RootModule == nil {
		return nil, nil
	}

	result := make(map[string][]string)
	collectAllModuleARNs(state.Values.RootModule, result)

	// Sort ARNs within each module
	for module := range result {
		sort.Strings(result[module])
	}

	return result, nil
}

// collectARNs recursively collects ARNs from a module and its children
func collectARNs(module *tfModule, modulePrefix string, arns *[]string) {
	// Check if this module matches
	if strings.HasPrefix(module.Address, modulePrefix) {
		for _, resource := range module.Resources {
			if arn := extractARN(resource.Values); arn != "" {
				*arns = append(*arns, arn)
			}
		}
	}

	// Recurse into child modules
	for i := range module.ChildModules {
		collectARNs(&module.ChildModules[i], modulePrefix, arns)
	}
}

// collectAllModuleARNs recursively collects ARNs for all scenario modules
func collectAllModuleARNs(module *tfModule, result map[string][]string) {
	// Extract module name from address (e.g., "module.single_account_..." -> "single_account_...")
	if strings.HasPrefix(module.Address, "module.") {
		moduleName := strings.TrimPrefix(module.Address, "module.")
		// Remove [0] suffix if present
		moduleName = strings.TrimSuffix(moduleName, "[0]")

		// Only include scenario modules (not environment modules)
		if strings.HasPrefix(moduleName, "single_account_") ||
			strings.HasPrefix(moduleName, "cross_account_") ||
			strings.HasPrefix(moduleName, "tool_testing_") {

			for _, resource := range module.Resources {
				if arn := extractARN(resource.Values); arn != "" {
					result[moduleName] = append(result[moduleName], arn)
				}
			}
		}
	}

	// Recurse into child modules
	for i := range module.ChildModules {
		collectAllModuleARNs(&module.ChildModules[i], result)
	}
}

// extractARN extracts an ARN from resource values
func extractARN(values map[string]interface{}) string {
	// Try common ARN field names
	if arn, ok := values["arn"].(string); ok && arn != "" {
		return arn
	}
	return ""
}
