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
	TerraformDir string // Where terraform runs (changes based on mode)
	TFVarsPath   string // terraform.tfvars inside TerraformDir
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
		TerraformDir: repoPath, // Default to normal mode
		TFVarsPath:   filepath.Join(repoPath, "terraform.tfvars"),
	}, nil
}

// GetPathsForMode returns paths with the TerraformDir set based on dev mode.
// Deprecated: use GetPathsForWorkspace instead. Kept as an alias for the default workspace.
func GetPathsForMode(devMode bool, devModePath string) (*Paths, error) {
	return GetPathsForWorkspace("default", devMode, devModePath)
}

// GetPathsForWorkspace returns workspace-specific paths.
//
// For the "default" workspace, RepoPath is ~/.plabs/pathfinding-labs/ (backward compat).
// For any other named workspace, RepoPath is ~/.plabs/workspaces/<name>/pathfinding-labs/.
// When devMode is true and devModePath is valid, TerraformDir is set to devModePath
// regardless of workspace name.
func GetPathsForWorkspace(workspaceName string, devMode bool, devModePath string) (*Paths, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}

	plabsRoot := filepath.Join(home, PlabsDir)
	binPath := filepath.Join(plabsRoot, BinDir)
	configPath := filepath.Join(plabsRoot, ConfigFile)

	// Compute the repo path for this workspace.
	// "default" keeps the original path for zero-migration backward compat.
	var repoPath string
	if workspaceName == "" || workspaceName == "default" {
		repoPath = filepath.Join(plabsRoot, RepoDir)
	} else {
		repoPath = filepath.Join(plabsRoot, WorkspacesDir, workspaceName, RepoDir)
	}

	// Dev mode overrides the terraform directory.
	terraformDir := repoPath
	if devMode && devModePath != "" {
		scenariosPath := filepath.Join(devModePath, "modules", "scenarios")
		if _, err := os.Stat(scenariosPath); err == nil {
			terraformDir = devModePath
		}
	}

	return &Paths{
		Home:         home,
		PlabsRoot:    plabsRoot,
		RepoPath:     repoPath,
		BinPath:      binPath,
		ConfigPath:   configPath,
		TerraformDir: terraformDir,
		TFVarsPath:   filepath.Join(terraformDir, "terraform.tfvars"),
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

// ScenariosPath returns the path to the scenarios directory
// Uses TerraformDir so it respects dev mode
func (p *Paths) ScenariosPath() string {
	return filepath.Join(p.TerraformDir, "modules", "scenarios")
}

// IsDevMode returns true if the TerraformDir differs from the default RepoPath
func (p *Paths) IsDevMode() bool {
	return p.TerraformDir != p.RepoPath
}
