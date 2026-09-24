// Package gcp provides shared helpers for inspecting the local machine's
// GCP credential state, used by both the TUI and CLI commands.
package gcp

import (
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

// AuthStatus describes the current state of the two GCP credential stores
// that plabs depends on: the `gcloud auth login` CLI session (used by demo
// scripts) and Application Default Credentials (used by Terraform).
type AuthStatus struct {
	CLIPresent bool   // gcloud is installed and has an active authenticated account
	ADCPresent bool   // Application Default Credentials file exists
	Account    string // active `gcloud auth list` account, "" if unavailable
}

// OK reports whether both credential stores are present.
func (s AuthStatus) OK() bool {
	return s.CLIPresent && s.ADCPresent
}

// CheckAuthStatus inspects the local machine's gcloud CLI session and ADC
// file. It shells out to `gcloud auth list`, so callers on a render loop
// (e.g. the TUI) must run it off the main goroutine via a command/message,
// not inline during a render.
func CheckAuthStatus() AuthStatus {
	var status AuthStatus

	status.ADCPresent = adcFileExists()

	if _, err := exec.LookPath("gcloud"); err != nil {
		return status
	}

	out, err := exec.Command("gcloud", "auth", "list", "--filter=status:ACTIVE", "--format=value(account)").Output()
	if err != nil {
		return status
	}

	account := strings.TrimSpace(strings.SplitN(string(out), "\n", 2)[0])
	if account != "" {
		status.CLIPresent = true
		status.Account = account
	}

	return status
}

// adcFileExists checks for the Application Default Credentials file at
// gcloud's default config location for the current OS.
func adcFileExists() bool {
	configDir := gcloudConfigDir()
	if configDir == "" {
		return false
	}
	_, err := os.Stat(filepath.Join(configDir, "application_default_credentials.json"))
	return err == nil
}

// gcloudConfigDir returns gcloud's default configuration directory,
// honoring CLOUDSDK_CONFIG when set.
func gcloudConfigDir() string {
	if dir := os.Getenv("CLOUDSDK_CONFIG"); dir != "" {
		return dir
	}

	if runtime.GOOS == "windows" {
		if appData := os.Getenv("APPDATA"); appData != "" {
			return filepath.Join(appData, "gcloud")
		}
		return ""
	}

	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}
	return filepath.Join(home, ".config", "gcloud")
}
