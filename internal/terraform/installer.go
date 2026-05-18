package terraform

import (
	"archive/zip"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

const (
	// TerraformVersion is the version plabs downloads and manages.
	// Bump this when cutting a new plabs release to pick up the latest Terraform.
	TerraformVersion = "1.15.3"
	// TerraformBaseURL is the base URL for downloading terraform
	TerraformBaseURL = "https://releases.hashicorp.com/terraform"
)

// Installer handles terraform binary installation
type Installer struct {
	binDir string
}

// NewInstaller creates a new terraform installer
func NewInstaller(binDir string) *Installer {
	return &Installer{binDir: binDir}
}

// GetTerraformPath returns the path to the plabs-managed terraform binary.
// plabs always uses its own binary to avoid interference from system terraform
// wrappers (e.g. tfenv) that may not be configured on the user's machine.
func (i *Installer) GetTerraformPath() (string, error) {
	plabsTf := filepath.Join(i.binDir, "terraform")
	if runtime.GOOS == "windows" {
		plabsTf += ".exe"
	}

	if _, err := os.Stat(plabsTf); err == nil {
		return plabsTf, nil
	}

	return "", fmt.Errorf("terraform not found; run 'plabs init' to install it")
}

// InstallResult describes what EnsureInstalled did.
type InstallResult int

const (
	InstallResultAlreadyCurrent InstallResult = iota
	InstallResultUpdated
	InstallResultFreshInstall
)

// EnsureInstalled makes sure the plabs-managed terraform binary is available and
// matches TerraformVersion, downloading it if missing or outdated.
// It never prints to stdout so it is safe to call from a TUI goroutine.
// The InstallResult return value lets callers surface status to the user.
func (i *Installer) EnsureInstalled() (string, InstallResult, error) {
	if path, err := i.GetTerraformPath(); err == nil {
		if i.isCorrectVersion(path) {
			return path, InstallResultAlreadyCurrent, nil
		}
		path, err = i.Download()
		return path, InstallResultUpdated, err
	}

	path, err := i.Download()
	return path, InstallResultFreshInstall, err
}

// isCorrectVersion returns true when the binary at path reports TerraformVersion.
func (i *Installer) isCorrectVersion(path string) bool {
	return i.installedVersion(path) == TerraformVersion
}

// installedVersion returns the short version string (e.g. "1.15.3") from the
// binary at path, or "" if it cannot be determined.
func (i *Installer) installedVersion(path string) string {
	cmd := exec.Command(path, "version", "-json")
	out, err := cmd.Output()
	if err != nil {
		// Fall back to plain version output
		cmd = exec.Command(path, "version")
		out, err = cmd.Output()
		if err != nil {
			return ""
		}
		// First line looks like "Terraform v1.15.3"
		line := strings.SplitN(string(out), "\n", 2)[0]
		line = strings.TrimPrefix(strings.TrimSpace(line), "Terraform v")
		return strings.TrimSpace(line)
	}

	// JSON output: {"terraform_version":"1.15.3",...}
	var result struct {
		Version string `json:"terraform_version"`
	}
	if err := json.Unmarshal(out, &result); err != nil {
		return ""
	}
	return result.Version
}

// Download downloads and installs terraform to the bin directory
func (i *Installer) Download() (string, error) {
	// Ensure bin directory exists
	if err := os.MkdirAll(i.binDir, 0755); err != nil {
		return "", fmt.Errorf("failed to create bin directory: %w", err)
	}

	// Determine OS and architecture
	goos := runtime.GOOS
	goarch := runtime.GOARCH

	// Map Go arch to Terraform arch
	arch := goarch
	if arch == "arm64" {
		arch = "arm64"
	} else if arch == "amd64" {
		arch = "amd64"
	}

	// Construct download URL
	filename := fmt.Sprintf("terraform_%s_%s_%s.zip", TerraformVersion, goos, arch)
	url := fmt.Sprintf("%s/%s/%s", TerraformBaseURL, TerraformVersion, filename)

	// Download the zip file
	resp, err := http.Get(url)
	if err != nil {
		return "", fmt.Errorf("failed to download terraform: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("failed to download terraform: HTTP %d", resp.StatusCode)
	}

	// Create temporary file for the zip
	tmpFile, err := os.CreateTemp("", "terraform-*.zip")
	if err != nil {
		return "", fmt.Errorf("failed to create temp file: %w", err)
	}
	defer os.Remove(tmpFile.Name())
	defer tmpFile.Close()

	// Copy download to temp file
	if _, err := io.Copy(tmpFile, resp.Body); err != nil {
		return "", fmt.Errorf("failed to save download: %w", err)
	}

	// Extract the binary
	tfPath := filepath.Join(i.binDir, "terraform")
	if runtime.GOOS == "windows" {
		tfPath += ".exe"
	}

	if err := i.extractZip(tmpFile.Name(), tfPath); err != nil {
		return "", fmt.Errorf("failed to extract terraform: %w", err)
	}

	// Make executable
	if err := os.Chmod(tfPath, 0755); err != nil {
		return "", fmt.Errorf("failed to make terraform executable: %w", err)
	}

	return tfPath, nil
}

// extractZip extracts the terraform binary from a zip file
func (i *Installer) extractZip(zipPath, destPath string) error {
	r, err := zip.OpenReader(zipPath)
	if err != nil {
		return err
	}
	defer r.Close()

	for _, f := range r.File {
		// Only extract the terraform binary
		if strings.HasPrefix(f.Name, "terraform") {
			rc, err := f.Open()
			if err != nil {
				return err
			}

			outFile, err := os.Create(destPath)
			if err != nil {
				rc.Close()
				return err
			}

			_, err = io.Copy(outFile, rc)
			rc.Close()
			outFile.Close()

			if err != nil {
				return err
			}
			return nil
		}
	}

	return fmt.Errorf("terraform binary not found in zip")
}

// GetVersion returns the version of the installed terraform
func (i *Installer) GetVersion() (string, error) {
	path, err := i.GetTerraformPath()
	if err != nil {
		return "", err
	}

	cmd := exec.Command(path, "version", "-json")
	out, err := cmd.Output()
	if err != nil {
		// Fall back to non-JSON version
		cmd = exec.Command(path, "version")
		out, err = cmd.Output()
		if err != nil {
			return "", err
		}
		// Parse first line
		lines := strings.Split(string(out), "\n")
		if len(lines) > 0 {
			return strings.TrimSpace(lines[0]), nil
		}
	}

	return strings.TrimSpace(string(out)), nil
}

// IsInstalled returns true if terraform is available
func (i *Installer) IsInstalled() bool {
	_, err := i.GetTerraformPath()
	return err == nil
}
