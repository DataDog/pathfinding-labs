package cmd

import (
	"fmt"
	"os"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/repo"
	"github.com/DataDog/pathfinding-labs/internal/terraform"
)

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize plabs and configure your AWS accounts",
	Long: `Initialize plabs by:
  1. Checking for/downloading terraform
  2. Cloning the pathfinding-labs repository
  3. Running the setup wizard to configure AWS accounts
  4. Creating terraform.tfvars
  5. Running terraform init`,
	RunE: runInit,
}

func runInit(cmd *cobra.Command, args []string) error {
	paths, err := repo.GetPaths()
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	green := color.New(color.FgGreen).SprintFunc()
	yellow := color.New(color.FgYellow).SprintFunc()
	cyan := color.New(color.FgCyan).SprintFunc()

	fmt.Println()
	fmt.Println(cyan("Initializing Pathfinding Labs..."))
	fmt.Println()

	// Step 1: Create directories
	fmt.Printf("[1/5] Creating directories at %s\n", paths.PlabsRoot)
	if err := paths.EnsureDirectories(); err != nil {
		return fmt.Errorf("failed to create directories: %w", err)
	}
	fmt.Println(green("      Directories created"))

	// Step 2: Check for git
	fmt.Println("[2/5] Checking for git...")
	if !repo.IsGitAvailable() {
		return fmt.Errorf("git is not installed. Please install git and try again.\n" +
			"  macOS: brew install git\n" +
			"  Ubuntu/Debian: sudo apt-get install git\n" +
			"  RHEL/CentOS: sudo yum install git")
	}
	fmt.Println(green("      Git is available"))

	// Step 3: Check for/download terraform
	fmt.Println("[3/5] Checking for terraform...")
	installer := terraform.NewInstaller(paths.BinPath)
	tfPath, err := installer.EnsureInstalled()
	if err != nil {
		return fmt.Errorf("failed to ensure terraform is installed: %w", err)
	}
	fmt.Printf(green("      Terraform available at %s\n"), tfPath)

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
		fmt.Println(green("      Repository cloned"))
	}

	// Step 5: Run setup wizard
	fmt.Println("[5/5] Running setup wizard...")

	wizard := config.NewWizard()
	cfg, err := wizard.Run()
	if err != nil {
		return fmt.Errorf("setup wizard failed: %w", err)
	}

	// Save config to ~/.plabs/plabs.yaml (single source of truth)
	if err := cfg.Save(); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	// Generate terraform.tfvars from config
	if err := cfg.SyncTFVars(paths.TerraformDir); err != nil {
		return fmt.Errorf("failed to create terraform.tfvars: %w", err)
	}
	fmt.Println(green("      Configuration saved"))

	// Run terraform init
	fmt.Println()
	fmt.Println("Running terraform init...")
	runner := terraform.NewRunner(paths.BinPath, paths.TerraformDir)
	if err := runner.Init(); err != nil {
		return fmt.Errorf("terraform init failed: %w", err)
	}

	fmt.Println()
	fmt.Println(green("========================================================"))
	fmt.Println(green("  Pathfinding Labs initialization complete!"))
	fmt.Println(green("========================================================"))
	fmt.Println()
	fmt.Println("Next steps:")
	fmt.Println()
	fmt.Println("  " + cyan("Option 1: Interactive TUI (recommended)"))
	fmt.Println("    Launch the dashboard to browse, enable, and deploy scenarios:")
	fmt.Println(cyan("      plabs"))
	fmt.Println()
	fmt.Println("  " + cyan("Option 2: Command Line (great for use cases that require scripting)"))
	fmt.Println("    1. Browse available scenarios:")
	fmt.Println(cyan("       plabs scenarios list"))
	fmt.Println()
	fmt.Println("    2. Enable a scenario:")
	fmt.Println(cyan("       plabs enable iam-002-to-admin"))
	fmt.Println()
	fmt.Println("    3. Deploy enabled scenarios:")
	fmt.Println(cyan("       plabs deploy"))
	fmt.Println()
	fmt.Println("    4. Run a demo attack:")
	fmt.Println(cyan("       plabs demo iam-002-to-admin"))
	fmt.Println()

	return nil
}

func init() {
	// Check if already initialized when running non-init commands
	rootCmd.PersistentPreRunE = func(cmd *cobra.Command, args []string) error {
		// Skip check for init, version, help, and tui commands
		// TUI handles its own initialization flow
		if cmd.Name() == "init" || cmd.Name() == "version" || cmd.Name() == "help" || cmd.Name() == "tui" || cmd.Name() == "config" {
			return nil
		}

		// Allow running in dev mode (using local repository)
		if isDevMode() {
			return nil
		}

		paths, err := repo.GetPaths()
		if err != nil {
			return err
		}

		// Check if repo exists
		if !paths.RepoExists() {
			fmt.Fprintln(os.Stderr, "Pathfinding Labs is not initialized.")
			fmt.Fprintln(os.Stderr, "Run 'plabs init' to get started.")
			os.Exit(1)
		}

		return nil
	}
}
