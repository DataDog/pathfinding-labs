package terraform

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// Runner executes terraform commands
type Runner struct {
	tfPath    string
	workDir   string
	installer *Installer
}

// NewRunner creates a new terraform runner
func NewRunner(binDir, workDir string) *Runner {
	return &Runner{
		workDir:   workDir,
		installer: NewInstaller(binDir),
	}
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

// cleanEnv returns a copy of the current environment with problematic variables removed
func cleanEnv() []string {
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
