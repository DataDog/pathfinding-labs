package cmd

import (
	"fmt"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/fatih/color"
	"github.com/spf13/cobra"

	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/repo"
	"github.com/DataDog/pathfinding-labs/internal/terraform"
	"github.com/DataDog/pathfinding-labs/internal/tui"
)

var tuiCmd = &cobra.Command{
	Use:   "tui",
	Short: "Launch the interactive TUI dashboard",
	Long: `Launch a full-screen interactive dashboard for managing Pathfinding Labs scenarios.

The TUI provides a visual interface for:
  - Browsing and filtering scenarios
  - Enabling/disabling scenarios
  - Deploying infrastructure
  - Running demos and cleanups
  - Viewing scenario details and credentials

Navigation:
  j/k, ↑/↓    Move cursor
  Tab         Switch between panes
  Space       Toggle enable/disable
  d           Deploy all enabled scenarios
  /           Filter scenarios
  ?           Show help
  q           Quit`,
	RunE: runTUI,
}

func init() {
	rootCmd.AddCommand(tuiCmd)
}

func runTUI(cmd *cobra.Command, args []string) error {
	paths, err := repo.GetPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	// Check if initialized - if not, run the setup wizard first
	if !paths.RepoExists() || !isInitialized(paths) {
		if err := runTUIInit(paths); err != nil {
			return err
		}
		// Refresh paths after init
		paths, err = getWorkingPaths()
		if err != nil {
			return fmt.Errorf("failed to get paths after init: %w", err)
		}
	} else {
		// Use working paths (respects dev mode)
		paths, err = getWorkingPaths()
		if err != nil {
			return fmt.Errorf("failed to get paths: %w", err)
		}
	}

	// Create the TUI model
	model := tui.NewModel(paths)

	// Run the TUI program
	p := tea.NewProgram(model, tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		return fmt.Errorf("failed to run TUI: %w", err)
	}

	return nil
}

// isInitialized checks if plabs has been initialized
func isInitialized(paths *repo.Paths) bool {
	cfg, err := config.Load(paths.ConfigPath)
	if err != nil {
		return false
	}
	return cfg.Initialized
}

// runTUIInit runs the initialization process before launching the TUI
func runTUIInit(paths *repo.Paths) error {
	green := color.New(color.FgGreen).SprintFunc()
	yellow := color.New(color.FgYellow).SprintFunc()
	cyan := color.New(color.FgCyan).SprintFunc()

	fmt.Println()
	fmt.Println(cyan("Pathfinding Labs needs to be initialized before using the TUI."))
	fmt.Println()

	// Step 1: Create directories
	fmt.Printf("[1/5] Creating directories at %s\n", paths.PlabsRoot)
	if err := paths.EnsureDirectories(); err != nil {
		return fmt.Errorf("failed to create directories: %w", err)
	}
	fmt.Println(green("      ✓ Directories created"))

	// Step 2: Check for git
	fmt.Println("[2/5] Checking for git...")
	if !repo.IsGitAvailable() {
		return fmt.Errorf("git is not installed. Please install git and try again.\n" +
			"  macOS: brew install git\n" +
			"  Ubuntu/Debian: sudo apt-get install git\n" +
			"  RHEL/CentOS: sudo yum install git")
	}
	fmt.Println(green("      ✓ Git is available"))

	// Step 3: Check for/download terraform
	fmt.Println("[3/5] Checking for terraform...")
	installer := terraform.NewInstaller(paths.BinPath)
	tfPath, err := installer.EnsureInstalled()
	if err != nil {
		return fmt.Errorf("failed to ensure terraform is installed: %w", err)
	}
	fmt.Printf(green("      ✓ Terraform available at %s\n"), tfPath)

	// Step 4: Clone repository if not exists
	fmt.Println("[4/5] Setting up pathfinding-labs repository...")
	if paths.RepoExists() {
		fmt.Println(yellow("      Repository already exists, skipping clone"))

		// Check for local changes
		hasChanges, err := repo.HasLocalChanges(paths.RepoPath)
		if err != nil {
			fmt.Printf(yellow("      Warning: could not check for local changes: %v\n"), err)
		} else if hasChanges {
			fmt.Println(yellow("      Note: Local changes detected in repository"))
		}
	} else {
		fmt.Printf("      Cloning to %s\n", paths.RepoPath)
		if err := repo.Clone(paths.RepoPath); err != nil {
			return fmt.Errorf("failed to clone repository: %w", err)
		}
		fmt.Println(green("      ✓ Repository cloned"))
	}

	// Step 5: Run setup wizard
	fmt.Println("[5/5] Running setup wizard...")

	wizard := config.NewWizard()
	cfg, err := wizard.Run()
	if err != nil {
		return fmt.Errorf("setup wizard failed: %w", err)
	}

	// Save CLI config
	cfg.WorkingDirectory = paths.RepoPath
	cfg.DevMode = isDevMode()
	if err := cfg.Save(paths.ConfigPath); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	// Create terraform.tfvars
	tfvars := terraform.NewTFVars(paths.TFVarsPath)
	if err := tfvars.InitFromConfig(cfg); err != nil {
		return fmt.Errorf("failed to create terraform.tfvars: %w", err)
	}
	fmt.Println(green("      ✓ Configuration saved"))

	// Run terraform init
	fmt.Println()
	fmt.Println("Running terraform init...")
	runner := terraform.NewRunner(paths.BinPath, paths.RepoPath)
	if err := runner.Init(); err != nil {
		return fmt.Errorf("terraform init failed: %w", err)
	}

	fmt.Println()
	fmt.Println(green("════════════════════════════════════════════════════════════"))
	fmt.Println(green("  Initialization complete! Launching TUI..."))
	fmt.Println(green("════════════════════════════════════════════════════════════"))
	fmt.Println()

	return nil
}
