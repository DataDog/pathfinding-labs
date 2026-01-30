package demo

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

// Runner executes demo and cleanup scripts
type Runner struct {
	repoPath string
}

// NewRunner creates a new demo runner
func NewRunner(repoPath string) *Runner {
	return &Runner{repoPath: repoPath}
}

// RunDemo executes the demo_attack.sh script for a scenario
func (r *Runner) RunDemo(scenarioDir string) error {
	scriptPath := filepath.Join(scenarioDir, "demo_attack.sh")

	if _, err := os.Stat(scriptPath); os.IsNotExist(err) {
		return fmt.Errorf("demo script not found: %s", scriptPath)
	}

	return r.runScript(scriptPath, scenarioDir)
}

// RunCleanup executes the cleanup_attack.sh script for a scenario
func (r *Runner) RunCleanup(scenarioDir string) error {
	scriptPath := filepath.Join(scenarioDir, "cleanup_attack.sh")

	if _, err := os.Stat(scriptPath); os.IsNotExist(err) {
		return fmt.Errorf("cleanup script not found: %s", scriptPath)
	}

	return r.runScript(scriptPath, scenarioDir)
}

// runScript executes a shell script
func (r *Runner) runScript(scriptPath, workDir string) error {
	// Make sure script is executable
	if err := os.Chmod(scriptPath, 0755); err != nil {
		return fmt.Errorf("failed to make script executable: %w", err)
	}

	cmd := exec.Command("bash", scriptPath)
	cmd.Dir = workDir
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Stdin = os.Stdin

	// Set up environment - inherit current environment
	cmd.Env = os.Environ()

	// Add the repo path to help scripts find terraform outputs
	cmd.Env = append(cmd.Env, fmt.Sprintf("PLABS_REPO_PATH=%s", r.repoPath))

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("script execution failed: %w", err)
	}

	return nil
}

// HasDemo checks if a scenario has a demo script
func (r *Runner) HasDemo(scenarioDir string) bool {
	scriptPath := filepath.Join(scenarioDir, "demo_attack.sh")
	_, err := os.Stat(scriptPath)
	return err == nil
}

// HasCleanup checks if a scenario has a cleanup script
func (r *Runner) HasCleanup(scenarioDir string) bool {
	scriptPath := filepath.Join(scenarioDir, "cleanup_attack.sh")
	_, err := os.Stat(scriptPath)
	return err == nil
}

// GetDemoPath returns the path to the demo script
func (r *Runner) GetDemoPath(scenarioDir string) string {
	return filepath.Join(scenarioDir, "demo_attack.sh")
}

// GetCleanupPath returns the path to the cleanup script
func (r *Runner) GetCleanupPath(scenarioDir string) string {
	return filepath.Join(scenarioDir, "cleanup_attack.sh")
}
