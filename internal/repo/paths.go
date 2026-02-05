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

// GetPathsForMode returns paths with the TerraformDir set based on dev mode
// If devMode is true and devModePath is valid, use that directory for terraform
// Otherwise use the default ~/.plabs/pathfinding-labs
func GetPathsForMode(devMode bool, devModePath string) (*Paths, error) {
	paths, err := GetPaths()
	if err != nil {
		return nil, err
	}

	if devMode && devModePath != "" {
		// Verify the dev mode directory exists and is valid
		scenariosPath := filepath.Join(devModePath, "modules", "scenarios")
		if _, err := os.Stat(scenariosPath); err == nil {
			paths.TerraformDir = devModePath
			paths.TFVarsPath = filepath.Join(devModePath, "terraform.tfvars")
		}
	}

	return paths, nil
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
