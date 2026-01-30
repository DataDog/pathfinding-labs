package repo

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// Update pulls the latest changes from the remote repository
func Update(repoPath string) error {
	// Check for local modifications
	hasChanges, err := HasLocalChanges(repoPath)
	if err != nil {
		return err
	}

	if hasChanges {
		return fmt.Errorf("local changes detected in %s\n"+
			"Please commit or stash your changes before updating:\n"+
			"  cd %s\n"+
			"  git stash  # to stash changes\n"+
			"  # or\n"+
			"  git checkout .  # to discard changes", repoPath, repoPath)
	}

	// Fetch and pull
	cmd := exec.Command("git", "pull", "--ff-only")
	cmd.Dir = repoPath
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("failed to update repository: %w", err)
	}

	return nil
}

// HasLocalChanges checks if there are uncommitted changes in the repository
func HasLocalChanges(repoPath string) (bool, error) {
	cmd := exec.Command("git", "status", "--porcelain")
	cmd.Dir = repoPath

	var out bytes.Buffer
	cmd.Stdout = &out

	if err := cmd.Run(); err != nil {
		return false, fmt.Errorf("failed to check git status: %w", err)
	}

	return strings.TrimSpace(out.String()) != "", nil
}

// GetCurrentCommit returns the current commit hash
func GetCurrentCommit(repoPath string) (string, error) {
	cmd := exec.Command("git", "rev-parse", "--short", "HEAD")
	cmd.Dir = repoPath

	var out bytes.Buffer
	cmd.Stdout = &out

	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("failed to get current commit: %w", err)
	}

	return strings.TrimSpace(out.String()), nil
}

// GetCurrentBranch returns the current branch name
func GetCurrentBranch(repoPath string) (string, error) {
	cmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")
	cmd.Dir = repoPath

	var out bytes.Buffer
	cmd.Stdout = &out

	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("failed to get current branch: %w", err)
	}

	return strings.TrimSpace(out.String()), nil
}

// GetRemoteURL returns the remote origin URL
func GetRemoteURL(repoPath string) (string, error) {
	cmd := exec.Command("git", "remote", "get-url", "origin")
	cmd.Dir = repoPath

	var out bytes.Buffer
	cmd.Stdout = &out

	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("failed to get remote URL: %w", err)
	}

	return strings.TrimSpace(out.String()), nil
}
