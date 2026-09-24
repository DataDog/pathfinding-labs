package cmd

import (
	"fmt"
	"os"
	"os/exec"
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
var initDevMode bool

var initCmd = &cobra.Command{
	Use:   "init",
	Short: "Initialize plabs and configure your cloud accounts",
	Long: `Initialize plabs by:
  1. Selecting which cloud(s) to configure (AWS, GCP)
  2. Checking for required tools (only for the selected cloud(s))
  3. Checking for/downloading terraform
  4. Cloning the pathfinding-labs repository
  5. Running the setup wizard to configure cloud accounts
  6. Loading CTF flag values (from --flag-file or flags.default.yaml in the repo),
     creating terraform.tfvars, and running terraform init`,
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

	// Compute paths for the active workspace (respects dev mode if already set,
	// or uses --dev-mode flag to pre-configure it without a wizard question).
	var devMode bool
	var devModePath string
	if initDevMode {
		// --dev-mode: detect the local repo path and skip the wizard's dev mode
		// question entirely, same as if the user had answered "yes" to it.
		detectedPath, err := config.DetectDevModePath()
		if err != nil {
			return fmt.Errorf("--dev-mode: %w", err)
		}
		devMode = true
		devModePath = detectedPath
	} else if existingWS != nil {
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
	red := color.New(color.FgRed).SprintFunc()

	fmt.Println()
	if activeWorkspace != "default" {
		fmt.Printf("%s (workspace: %s)\n", cyan("Initializing Pathfinding Labs..."), activeWorkspace)
	} else {
		fmt.Println(cyan("Initializing Pathfinding Labs..."))
	}
	fmt.Println()

	// Step 1: Ask which cloud(s) to configure, so the tool check right after
	// (and the account-setup wizard at the end) only ask about what's needed.
	fmt.Println("[1/6] Selecting cloud(s)...")
	wizard := config.NewWizard()
	awsSelected, gcpSelected, err := wizard.SelectClouds()
	if err != nil {
		return fmt.Errorf("setup wizard failed: %w", err)
	}

	// Step 2: Check required tools, scoped to the selected cloud(s)
	fmt.Println("[2/6] Checking required tools...")
	if err := checkDependencies(green, yellow, red, awsSelected, gcpSelected); err != nil {
		return err
	}

	// Step 3: Create directories
	fmt.Printf("[3/6] Creating directories at %s\n", paths.PlabsRoot)
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

	// Step 4: Check for/download terraform
	fmt.Println("[4/6] Checking for terraform...")
	installer := terraform.NewInstaller(paths.BinPath)
	tfPath, installResult, err := installer.EnsureInstalled()
	if err != nil {
		return fmt.Errorf("failed to ensure terraform is installed: %w", err)
	}
	switch installResult {
	case terraform.InstallResultFreshInstall:
		fmt.Printf(green("      Terraform v%s installed to %s\n"), terraform.TerraformVersion, tfPath)
	case terraform.InstallResultUpdated:
		fmt.Printf(green("      Terraform updated to v%s at %s\n"), terraform.TerraformVersion, tfPath)
	default:
		fmt.Printf(green("      Terraform v%s ready at %s\n"), terraform.TerraformVersion, tfPath)
	}

	// Step 5: Clone repository (skip for dev mode workspaces)
	fmt.Println("[5/6] Setting up pathfinding-labs repository...")
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

	// Step 6: Run setup wizard (account configuration for the selected clouds)
	fmt.Println("[6/6] Running setup wizard (account configuration)...")

	newWS, err := wizard.Run(awsSelected, gcpSelected, config.RunOptions{
		DevMode:     devMode,
		DevModePath: devModePath,
	})
	if err != nil {
		return fmt.Errorf("setup wizard failed: %w", err)
	}

	// The wizard determines ActiveCloud, so recompute paths now that it's
	// known — for GCP this points TerraformDir/StatePath at the separate
	// gcp/ root instead of the repo root used for steps 1-4 above (cloning,
	// terraform binary install, and directory setup are cloud-agnostic).
	paths, err = repo.GetPathsForWorkspaceAndCloud(activeWorkspace, newWS.ActiveCloudOrDefault(), devMode, devModePath)
	if err != nil {
		return fmt.Errorf("failed to get paths for active cloud: %w", err)
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
	runner := terraform.NewRunner(paths.BinPath, paths.TerraformDir, paths.StatePath)
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
	fmt.Println(cyan("       plabs apply"))
	fmt.Println()
	fmt.Println("    4. Run a demo attack:")
	fmt.Println(cyan("       plabs demo iam-002-to-admin"))
	fmt.Println()

	return nil
}

type depCheck struct {
	name     string
	binary   string
	required bool
	// hint shown when missing
	missingNote string
	installHint string
}

// checkDependencies prints a checklist of required and optional tools,
// scoped to the cloud(s) actually selected in the wizard — an AWS-only
// setup never asks about gcloud, and a GCP-only setup never asks about the
// aws CLI or the SSM session-manager-plugin. Returns an error if any
// required tool is missing.
func checkDependencies(green, yellow, red func(...interface{}) string, awsSelected, gcpSelected bool) error {
	checks := []depCheck{
		{
			name:     "git",
			binary:   "git",
			required: true,
			installHint: "  macOS:          brew install git\n" +
				"  Ubuntu/Debian:  sudo apt-get install git\n" +
				"  RHEL/CentOS:    sudo yum install git",
		},
	}

	if awsSelected {
		checks = append(checks,
			depCheck{
				name:     "aws CLI",
				binary:   "aws",
				required: true,
				installHint: "  macOS:          brew install awscli\n" +
					"  Linux:          https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html\n" +
					"  Windows:        https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-windows.html",
			},
			depCheck{
				name:        "session-manager-plugin",
				binary:      "session-manager-plugin",
				required:    false,
				missingNote: "SSM-based demos require it",
				installHint: "  https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html",
			},
		)
	}

	if gcpSelected {
		checks = append(checks, depCheck{
			name:     "gcloud CLI",
			binary:   "gcloud",
			required: true,
			installHint: "  macOS:          brew install --cask google-cloud-sdk\n" +
				"  Linux/Windows:  https://cloud.google.com/sdk/docs/install",
		})
	}

	// jq isn't tied to a specific cloud's demos, so always check it.
	checks = append(checks, depCheck{
		name:        "jq",
		binary:      "jq",
		required:    false,
		missingNote: "some demos require it",
		installHint: "  macOS:          brew install jq\n" +
			"  Ubuntu/Debian:  sudo apt-get install jq\n" +
			"  RHEL/CentOS:    sudo yum install jq",
	})

	var missingRequired []depCheck

	for _, c := range checks {
		_, err := exec.LookPath(c.binary)
		found := err == nil

		switch {
		case found:
			fmt.Printf("      %s %s\n", green("✓"), c.name)
		case c.required:
			fmt.Printf("      %s %s %s\n", red("✗"), c.name, red("(required — not installed)"))
			missingRequired = append(missingRequired, c)
		default:
			fmt.Printf("      %s %s %s\n", yellow("⚠"), c.name, yellow("(not installed — "+c.missingNote+")"))
		}
	}

	if len(missingRequired) > 0 {
		fmt.Println()
		fmt.Println(red("The following required tools are missing:"))
		for _, c := range missingRequired {
			fmt.Println()
			fmt.Printf("  %s\n", red(c.name))
			fmt.Println(c.installHint)
		}
		return fmt.Errorf("missing required tools — install them and run 'plabs init' again")
	}

	return nil
}

func init() {
	initCmd.Flags().StringVar(&initFlagFile, "flag-file", "", "Path to a YAML flag-set file (overrides flags.default.yaml in the repo). See flags.default.yaml for the schema.")
	initCmd.Flags().BoolVar(&initDevMode, "dev-mode", false, "Pre-configure dev mode using the local repository checkout (skips the wizard's dev-mode question)")

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
