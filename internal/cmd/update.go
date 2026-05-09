package cmd

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/repo"
	"github.com/DataDog/pathfinding-labs/internal/updater"
)

var updateCmd = &cobra.Command{
	Use:   "update",
	Short: "Update scenarios from the remote repository",
	Long: `Pull the latest changes from the pathfinding-labs repository.

This will:
  - Check for local modifications (and warn if found)
  - Pull the latest scenarios and fixes
  - Show what changed

Use --from-local to sync from your local development directory instead of pulling
from the remote repository. This is useful when testing local changes.`,
	RunE: runUpdate,
}

var (
	forceUpdate bool
	fromLocal   string
)

func init() {
	updateCmd.Flags().BoolVarP(&forceUpdate, "force", "f", false, "Force update even with local changes (will stash changes)")
	updateCmd.Flags().StringVar(&fromLocal, "from-local", "", "Sync from a local directory instead of pulling from remote")
}

func runUpdate(cmd *cobra.Command, args []string) error {
	paths, err := getWorkingPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	green := color.New(color.FgGreen).SprintFunc()
	yellow := color.New(color.FgYellow).SprintFunc()
	cyan := color.New(color.FgCyan).SprintFunc()

	// Handle --from-local flag
	if fromLocal != "" {
		return runLocalSync(paths, fromLocal, green, yellow, cyan)
	}

	fmt.Println(cyan("Updating Pathfinding Labs..."))
	fmt.Println()

	// Get current commit before update
	beforeCommit, err := repo.GetCurrentCommit(paths.RepoPath)
	if err != nil {
		fmt.Printf(yellow("Warning: could not get current commit: %v\n"), err)
	}

	// Check for local changes
	hasChanges, err := repo.HasLocalChanges(paths.RepoPath)
	if err != nil {
		return fmt.Errorf("failed to check for local changes: %w", err)
	}

	if hasChanges {
		if !forceUpdate {
			fmt.Println(yellow("Local changes detected in repository."))
			fmt.Println("Your changes:")
			fmt.Println()
			// Show brief status
			fmt.Printf("  cd %s && git status --short\n", paths.RepoPath)
			fmt.Println()
			fmt.Println("Options:")
			fmt.Println("  1. Commit or stash your changes manually, then run 'plabs update'")
			fmt.Println("  2. Run 'plabs update --force' to stash changes automatically")
			fmt.Println("  3. Run 'cd ~/.plabs/pathfinding-labs && git checkout .' to discard changes")
			return fmt.Errorf("update aborted due to local changes")
		}

		// Force update - stash changes
		fmt.Println(yellow("Stashing local changes..."))
		// This is handled by the Update function returning an error
	}

	// Pull updates
	fmt.Println("Pulling latest changes...")
	if err := repo.Update(paths.RepoPath); err != nil {
		return err
	}

	// Get commit after update
	afterCommit, err := repo.GetCurrentCommit(paths.RepoPath)
	if err != nil {
		fmt.Printf(yellow("Warning: could not get new commit: %v\n"), err)
	}

	fmt.Println()
	if beforeCommit != afterCommit {
		fmt.Println(green("✓ Updated successfully!"))
		fmt.Printf("  Previous version: %s\n", beforeCommit)
		fmt.Printf("  Current version:  %s\n", afterCommit)
	} else {
		fmt.Println(green("✓ Already up to date"))
		fmt.Printf("  Current version: %s\n", afterCommit)
	}

	// Check if the plabs binary itself has an update available.
	if !isDevMode() {
		syncInstallMethod()
		if notice := updater.Check(version); notice != "" {
			fmt.Println()
			fmt.Println(yellow(notice))
		}
	}

	return nil
}

// runLocalSync syncs files from a local directory to ~/.plabs/pathfinding-labs/
func runLocalSync(paths *repo.Paths, localDir string, green, yellow, cyan func(a ...interface{}) string) error {
	// Resolve the local directory path
	if localDir == "." {
		var err error
		localDir, err = os.Getwd()
		if err != nil {
			return fmt.Errorf("failed to get current directory: %w", err)
		}
	}

	// Make absolute if relative
	if !filepath.IsAbs(localDir) {
		var err error
		localDir, err = filepath.Abs(localDir)
		if err != nil {
			return fmt.Errorf("failed to resolve path: %w", err)
		}
	}

	// Verify local directory exists and looks like pathfinding-labs
	if _, err := os.Stat(filepath.Join(localDir, "modules", "scenarios")); os.IsNotExist(err) {
		return fmt.Errorf("directory %s does not appear to be a pathfinding-labs repository (missing modules/scenarios)", localDir)
	}

	// Check if trying to sync to itself
	if localDir == paths.RepoPath {
		return fmt.Errorf("source and destination are the same directory")
	}

	fmt.Println(cyan("Syncing from local directory..."))
	fmt.Printf("  Source:      %s\n", localDir)
	fmt.Printf("  Destination: %s\n", paths.RepoPath)
	fmt.Println()

	// Use rsync to copy files (excludes .git, terraform state, etc.)
	rsyncArgs := []string{
		"-av",
		"--delete",
		"--exclude", ".git",
		"--exclude", ".terraform",
		"--exclude", "*.tfstate",
		"--exclude", "*.tfstate.*",
		"--exclude", ".terraform.lock.hcl",
		"--exclude", "terraform.tfvars",     // Don't overwrite user's tfvars
		"--exclude", "terraform.tfvars.bak*", // Don't copy backup files
		"--exclude", "plabs",                // Don't copy the binary
		"--exclude", ".claude",              // Don't copy Claude config
		"--exclude", ".idea",                // Don't copy IDE settings
		"--exclude", ".vscode",
		"--exclude", "*.log",
		localDir + "/",
		paths.RepoPath + "/",
	}

	cmd := exec.Command("rsync", rsyncArgs...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("rsync failed: %w", err)
	}

	fmt.Println()
	fmt.Println(green("✓ Synced successfully from local directory"))

	// Check if we need to run terraform init
	cfg, _ := config.Load()
	if cfg != nil {
		fmt.Println()
		fmt.Println(yellow("Note: You may need to run 'plabs deploy' or 'terraform init' to pick up module changes"))
	}

	return nil
}
