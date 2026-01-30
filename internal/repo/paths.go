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
	// ConfigFile is the name of the CLI config file
	ConfigFile = "config.yaml"
	// RepoURL is the GitHub repository URL
	RepoURL = "https://github.com/DataDog/pathfinding-labs.git"
)

// Paths holds all the important paths for plabs
type Paths struct {
	Home       string // User's home directory
	PlabsRoot  string // ~/.plabs
	RepoPath   string // ~/.plabs/pathfinding-labs
	BinPath    string // ~/.plabs/bin
	ConfigPath string // ~/.plabs/config.yaml
	TFVarsPath string // ~/.plabs/pathfinding-labs/terraform.tfvars
}

// GetPaths returns the paths for the current user
func GetPaths() (*Paths, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return nil, err
	}

	plabsRoot := filepath.Join(home, PlabsDir)
	repoPath := filepath.Join(plabsRoot, RepoDir)

	return &Paths{
		Home:       home,
		PlabsRoot:  plabsRoot,
		RepoPath:   repoPath,
		BinPath:    filepath.Join(plabsRoot, BinDir),
		ConfigPath: filepath.Join(plabsRoot, ConfigFile),
		TFVarsPath: filepath.Join(repoPath, "terraform.tfvars"),
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

// TFVarsExists checks if terraform.tfvars exists
func (p *Paths) TFVarsExists() bool {
	_, err := os.Stat(p.TFVarsPath)
	return err == nil
}

// ScenariosPath returns the path to the scenarios directory
func (p *Paths) ScenariosPath() string {
	return filepath.Join(p.RepoPath, "modules", "scenarios")
}
