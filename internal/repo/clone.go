package repo

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

// Clone clones the pathfinding-labs repository to the specified path
func Clone(destPath string) error {
	// Check if git is available
	if _, err := exec.LookPath("git"); err != nil {
		return fmt.Errorf("git is not installed. Please install git and try again.\n" +
			"  macOS: brew install git\n" +
			"  Ubuntu/Debian: sudo apt-get install git\n" +
			"  RHEL/CentOS: sudo yum install git")
	}

	// Remove any existing incomplete clone
	if _, err := os.Stat(destPath); err == nil {
		if _, err := os.Stat(filepath.Join(destPath, ".git")); os.IsNotExist(err) {
			// Directory exists but is not a git repo - remove it
			if err := os.RemoveAll(destPath); err != nil {
				return fmt.Errorf("failed to remove incomplete clone: %w", err)
			}
		}
	}

	// Clone the repository
	cmd := exec.Command("git", "clone", "--depth", "1", RepoURL, destPath)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to clone repository: %w", err)
	}

	return nil
}

// CloneOrUpdate clones the repository if it doesn't exist, or updates it if it does
func CloneOrUpdate(destPath string) error {
	if _, err := os.Stat(filepath.Join(destPath, ".git")); os.IsNotExist(err) {
		return Clone(destPath)
	}
	return Update(destPath)
}

// IsGitAvailable checks if git is installed and accessible
func IsGitAvailable() bool {
	_, err := exec.LookPath("git")
	return err == nil
}
