package cmd

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/fatih/color"
	"github.com/spf13/cobra"

	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/repo"
	"github.com/DataDog/pathfinding-labs/internal/terraform"
)

// DefaultFlagFileName is the file plabs looks for in the repo root during
// `plabs init` when no --flag-file override is supplied.
const DefaultFlagFileName = "flags.default.yaml"

var initFlagFile string

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize plabs and configure your AWS accounts",
	Long: `Initialize plabs by:
  1. Checking for/downloading terraform
  2. Cloning the pathfinding-labs repository
  3. Running the setup wizard to configure AWS accounts
  4. Loading CTF flag values (from --flag-file or flags.default.yaml in the repo)
  5. Creating terraform.tfvars
  6. Running terraform init`,
	RunE: runInit,
}

func runInit(cmd *cobra.Command, args []string) error {
	// Determine the active workspace so init targets the right environment.
	existingCfg, _ := config.Load()
	activeWorkspace := "default"
	var existingWS *config.WorkspaceConfig
	if existingCfg != nil {
		activeWorkspace = existingCfg.ActiveName()
		existingWS = existingCfg.Active()
	}

	// Compute paths for the active workspace (respects dev mode if already set).
	var devMode bool
	var devModePath string
	if existingWS != nil {
		devMode = existingWS.DevMode
		devModePath = existingWS.DevModePath
	}
	paths, err := repo.GetPathsForWorkspace(activeWorkspace, devMode, devModePath)
	if err != nil {
		return fmt.Errorf("failed to get paths: %w", err)
	}

	green := color.New(color.FgGreen).SprintFunc()
	yellow := color.New(color.FgYellow).SprintFunc()
	cyan := color.New(color.FgCyan).SprintFunc()

	fmt.Println()
	if activeWorkspace != "default" {
		fmt.Printf("%s (workspace: %s)\n", cyan("Initializing Pathfinding Labs..."), activeWorkspace)
	} else {
		fmt.Println(cyan("Initializing Pathfinding Labs..."))
	}
	fmt.Println()

	// Step 1: Create directories
	fmt.Printf("[1/5] Creating directories at %s\n", paths.PlabsRoot)
	if err := paths.EnsureDirectories(); err != nil {
		return fmt.Errorf("failed to create directories: %w", err)
	}
	// Also ensure workspace-specific repo directory exists for non-default workspaces
	if activeWorkspace != "default" {
		if err := os.MkdirAll(filepath.Dir(paths.RepoPath), 0755); err != nil {
			return fmt.Errorf("failed to create workspace directory: %w", err)
		}
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

	// Step 4: Clone repository (skip for dev mode workspaces)
	fmt.Println("[4/5] Setting up pathfinding-labs repository...")
	if devMode {
		fmt.Printf(yellow("      Dev mode: using local repository at %s\n"), devModePath)
		if _, err := os.Stat(filepath.Join(devModePath, "modules", "scenarios")); err != nil {
			return fmt.Errorf("dev mode path does not appear to be a pathfinding-labs repository: %s", devModePath)
		}
	} else if paths.RepoExists() {
		fmt.Println(yellow("      Repository already exists, skipping clone"))

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
	newWS, err := wizard.Run()
	if err != nil {
		return fmt.Errorf("setup wizard failed: %w", err)
	}

	// Load CTF flag values. Explicit --flag-file wins. Otherwise fall back to
	// flags.default.yaml in the terraform directory if it exists.
	flagFilePath := initFlagFile
	if flagFilePath == "" {
		candidate := filepath.Join(paths.TerraformDir, DefaultFlagFileName)
		if _, err := os.Stat(candidate); err == nil {
			flagFilePath = candidate
		}
	}
	if flagFilePath != "" {
		if err := newWS.LoadFlagsFromFile(flagFilePath); err != nil {
			return fmt.Errorf("failed to load flag file: %w", err)
		}
		fmt.Printf(green("      Loaded %d CTF flag(s) from %s\n"), len(newWS.Flags), flagFilePath)
	} else {
		fmt.Println(yellow("      No flag file found; scenarios will deploy with default flag{MISSING}"))
	}
	newWS.Initialized = true

	// Merge the wizard result into the top-level config and save.
	topCfg := existingCfg
	if topCfg == nil {
		topCfg = &config.Config{
			ActiveWorkspace: activeWorkspace,
			Workspaces:      make(map[string]*config.WorkspaceConfig),
		}
	}
	if topCfg.Workspaces == nil {
		topCfg.Workspaces = make(map[string]*config.WorkspaceConfig)
	}
	// Preserve dev mode settings from the existing workspace config
	newWS.DevMode = devMode
	newWS.DevModePath = devModePath
	topCfg.Workspaces[activeWorkspace] = newWS

	if err := topCfg.Save(); err != nil {
		return fmt.Errorf("failed to save config: %w", err)
	}

	// Generate terraform.tfvars from workspace config
	if err := newWS.SyncTFVars(paths.TerraformDir); err != nil {
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
	initCmd.Flags().StringVar(&initFlagFile, "flag-file", "", "Path to a YAML flag-set file (overrides flags.default.yaml in the repo). See flags.default.yaml for the schema.")

	// Check if already initialized when running non-init commands
	rootCmd.PersistentPreRunE = func(cmd *cobra.Command, args []string) error {
		// Skip check for init, version, help, and tui commands
		// TUI handles its own initialization flow
		// CommandPath() returns the full path e.g. "plabs config set", so we check
		// for " config" to exempt "plabs config" and all its subcommands (set, show, sync).
		if cmd.Name() == "init" || cmd.Name() == "version" || cmd.Name() == "help" || cmd.Name() == "tui" || strings.Contains(cmd.CommandPath(), " config") || strings.Contains(cmd.CommandPath(), " workspace") || strings.Contains(cmd.CommandPath(), " completion") {
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
