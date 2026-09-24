package repo

import (
	"os"
	"path/filepath"
)

const (
	// PlabsDir is the name of the plabs directory in user's home
	PlabsDir = ".plabs"
	// RepoDir is the name of the cloned repository directory
	RepoDir = "pathfinding-labs"
	// BinDir is the directory for downloaded binaries
	BinDir = "bin"
	// WorkspacesDir is the directory containing named workspace repos
	WorkspacesDir = "workspaces"
	// StateDir is the directory containing canonical terraform state files,
	// one per workspace, shared between dev mode and normal mode
	StateDir = "state"
	// ConfigFile is the name of the CLI config file (single source of truth)
	ConfigFile = "plabs.yaml"
	// LegacyConfigFile is the old config file name (for migration)
	LegacyConfigFile = "config.yaml"
	// RepoURL is the GitHub repository URL
	RepoURL = "https://github.com/DataDog/pathfinding-labs.git"
)

// Paths holds all the important paths for plabs
type Paths struct {
	Home         string // User's home directory
	PlabsRoot    string // ~/.plabs
	RepoPath     string // ~/.plabs/pathfinding-labs (cloned repo, used in normal mode)
	BinPath      string // ~/.plabs/bin
	ConfigPath   string // ~/.plabs/plabs.yaml (ALWAYS here, single source of truth)
	RootDir      string // Repo root respecting dev mode, independent of active cloud — shared parent of every cloud's Terraform root
	TerraformDir string // Where terraform runs for the active cloud (changes based on mode and cloud)
	TFVarsPath   string // terraform.tfvars inside TerraformDir
	StatePath    string // Canonical terraform.tfstate path for the active cloud (ALWAYS here, independent of mode)
}

// GetPaths returns the paths for the current user
// Returns default paths without mode awareness - use GetPathsWithConfig for mode-aware paths
func GetPaths() (*Paths, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}

	plabsRoot := filepath.Join(home, PlabsDir)
	repoPath := filepath.Join(plabsRoot, RepoDir)

	return &Paths{
		Home:         home,
		PlabsRoot:    plabsRoot,
		RepoPath:     repoPath,
		BinPath:      filepath.Join(plabsRoot, BinDir),
		ConfigPath:   filepath.Join(plabsRoot, ConfigFile),
		RootDir:      repoPath,
		TerraformDir: repoPath, // Default to normal mode
		TFVarsPath:   filepath.Join(repoPath, "terraform.tfvars"),
		StatePath:    filepath.Join(plabsRoot, StateDir, "terraform.tfstate"),
	}, nil
}

// GetPathsForMode returns paths with the TerraformDir set based on dev mode.
// Deprecated: use GetPathsForWorkspace instead. Kept as an alias for the default workspace.
func GetPathsForMode(devMode bool, devModePath string) (*Paths, error) {
	return GetPathsForWorkspace("default", devMode, devModePath)
}

// GetPathsForWorkspace returns workspace-specific paths for the AWS cloud
// context. Kept as the AWS-scoped entry point so every pre-existing call
// site continues to behave identically with zero migration; new,
// cloud-aware call sites should use GetPathsForWorkspaceAndCloud instead.
func GetPathsForWorkspace(workspaceName string, devMode bool, devModePath string) (*Paths, error) {
	return GetPathsForWorkspaceAndCloud(workspaceName, "aws", devMode, devModePath)
}

// GetPathsForWorkspaceAndCloud returns workspace- and cloud-scoped paths.
//
// For the "default" workspace, RepoPath is ~/.plabs/pathfinding-labs/ (backward compat).
// For any other named workspace, RepoPath is ~/.plabs/workspaces/<name>/pathfinding-labs/.
// When devMode is true and devModePath is valid, RootDir is set to devModePath
// regardless of workspace name.
//
// cloud selects which Terraform root TerraformDir/TFVarsPath/StatePath point
// at: "aws" (or "") uses RootDir directly (the repo root, unchanged from
// before clouds existed); "gcp" uses RootDir/gcp — a separate root module
// with its own state, so AWS and GCP deployments never share a backend.
// RootDir/ScenariosPath() are cloud-independent: both clouds' scenario
// modules are discovered from the same top-level modules/scenarios tree.
func GetPathsForWorkspaceAndCloud(workspaceName string, cloud string, devMode bool, devModePath string) (*Paths, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}

	plabsRoot := filepath.Join(home, PlabsDir)
	binPath := filepath.Join(plabsRoot, BinDir)
	configPath := filepath.Join(plabsRoot, ConfigFile)

	// Compute the repo path and canonical state path for this workspace.
	// "default" keeps the original paths for zero-migration backward compat.
	var repoPath, statePath string
	if workspaceName == "" || workspaceName == "default" {
		repoPath = filepath.Join(plabsRoot, RepoDir)
		statePath = filepath.Join(plabsRoot, StateDir, "terraform.tfstate")
	} else {
		repoPath = filepath.Join(plabsRoot, WorkspacesDir, workspaceName, RepoDir)
		statePath = filepath.Join(plabsRoot, StateDir, workspaceName, "terraform.tfstate")
	}

	// Dev mode overrides the root directory, but NOT the state path:
	// state always lives at statePath so switching modes never orphans
	// resources tracked under the other directory's local state file.
	rootDir := repoPath
	if devMode && devModePath != "" {
		scenariosPath := filepath.Join(devModePath, "modules", "scenarios")
		if _, err := os.Stat(scenariosPath); err == nil {
			rootDir = devModePath
		}
	}

	terraformDir := rootDir
	if cloud == "gcp" {
		terraformDir = filepath.Join(rootDir, "gcp")
		statePath = filepath.Join(filepath.Dir(statePath), "gcp", filepath.Base(statePath))
	}

	return &Paths{
		Home:         home,
		PlabsRoot:    plabsRoot,
		RepoPath:     repoPath,
		BinPath:      binPath,
		ConfigPath:   configPath,
		RootDir:      rootDir,
		TerraformDir: terraformDir,
		TFVarsPath:   filepath.Join(terraformDir, "terraform.tfvars"),
		StatePath:    statePath,
	}, nil
}

// EnsureDirectories creates the necessary directories if they don't exist
func (p *Paths) EnsureDirectories() error {
	dirs := []string{p.PlabsRoot, p.BinPath}
	for _, dir := range dirs {
		if err := os.MkdirAll(dir, 0755); err != nil {
			return err
		}
	}
	return nil
}

// RepoExists checks if the repository has been cloned
func (p *Paths) RepoExists() bool {
	_, err := os.Stat(filepath.Join(p.RepoPath, ".git"))
	return err == nil
}

// TFVarsExists checks if terraform.tfvars exists in the terraform directory
func (p *Paths) TFVarsExists() bool {
	_, err := os.Stat(p.TFVarsPath)
	return err == nil
}

// ScenariosPath returns the path to the scenarios directory.
// Uses RootDir (not TerraformDir) so it respects dev mode but stays the
// same regardless of which cloud is active — every cloud's scenario
// modules live under one shared top-level modules/scenarios tree, even
// though each cloud runs terraform from its own root (TerraformDir).
func (p *Paths) ScenariosPath() string {
	return filepath.Join(p.RootDir, "modules", "scenarios")
}

// IsDevMode returns true if RootDir differs from the default RepoPath
func (p *Paths) IsDevMode() bool {
	return p.RootDir != p.RepoPath
}
