package cmd

import (
	"bufio"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/charmbracelet/huh"
	"github.com/fatih/color"

	plabsaws "github.com/DataDog/pathfinding-labs/internal/aws"
	"github.com/DataDog/pathfinding-labs/internal/config"
	"github.com/DataDog/pathfinding-labs/internal/repo"
	"github.com/DataDog/pathfinding-labs/internal/scenarios"
	"github.com/DataDog/pathfinding-labs/internal/terraform"
)

// getWorkingPaths returns the paths to use for the current operation.
// Loads config from ~/.plabs/plabs.yaml and uses the active workspace's
// dev_mode settings to determine which terraform directory to use.
//
// On first call for a workspace that predates the shared-state backend,
// this also performs a one-time migration of any pre-existing
// per-directory terraform.tfstate into the workspace's canonical state
// path, so dev mode and normal mode stop tracking separate state files.
func getWorkingPaths() (*repo.Paths, error) {
	cfg, err := config.Load()
	if err != nil {
		return repo.GetPaths()
	}
	ws := cfg.Active()
	paths, err := repo.GetPathsForWorkspaceAndCloud(cfg.ActiveName(), ws.ActiveCloudOrDefault(), ws.DevMode, ws.DevModePath)
	if err != nil {
		return nil, err
	}

	// This legacy migration only ever applies to the AWS root (GCP never had
	// the pre-canonical-state per-directory layout), so skip it entirely
	// when the active cloud is anything else.
	if !ws.StateMigrated && ws.ActiveCloudOrDefault() == "aws" {
		candidates := []string{paths.RepoPath}
		if ws.DevModePath != "" {
			candidates = append(candidates, ws.DevModePath)
		}
		migrated, err := terraform.MigrateStateToCanonicalPath(paths.StatePath, candidates)
		if err != nil {
			return nil, err
		}
		if migrated {
			fmt.Println(color.New(color.FgCyan).Sprint("One-time migration: moved terraform state to " + paths.StatePath))
			fmt.Println("Dev mode and normal mode will now share this state file.")
		}

		ws.StateMigrated = true
		if err := cfg.Save(); err != nil {
			return nil, fmt.Errorf("state migration succeeded but failed to save config: %w", err)
		}
	}

	// Self-healing, independent of the one-time migration above: whichever
	// directory is active (managed clone or dev-mode checkout) may still
	// have a .terraform/ dir from before the local backend was pinned to
	// StatePath — e.g. because the migration above ran while the *other*
	// mode was active. Callers only re-run Init when IsInitialized() is
	// false, so without this, terraform would keep looking for state at
	// its old implicit per-directory location instead of the canonical
	// path shared across both modes.
	runner := terraform.NewRunner(paths.BinPath, paths.TerraformDir, paths.StatePath)
	if err := runner.ReconfigureBackendIfNeeded(); err != nil {
		return nil, fmt.Errorf("failed to reconfigure terraform backend: %w", err)
	}

	return paths, nil
}

// isDevMode returns true if the active workspace has dev mode enabled
func isDevMode() bool {
	cfg, err := config.Load()
	if err != nil || cfg == nil {
		return false
	}
	return cfg.Active().DevMode
}

// containsGlobPattern checks if any of the args contain glob characters
func containsGlobPattern(args []string) bool {
	for _, arg := range args {
		if strings.Contains(arg, "*") || strings.Contains(arg, "?") {
			return true
		}
	}
	return false
}

// matchByPatterns filters scenarios by glob patterns
func matchByPatterns(allScenarios []*scenarios.Scenario, patterns []string) []*scenarios.Scenario {
	var matched []*scenarios.Scenario
	seen := make(map[string]bool)

	for _, s := range allScenarios {
		for _, pattern := range patterns {
			// Match against UniqueID (e.g., "lambda-001-to-admin") or base ID (e.g., "lambda-001")
			if matchesPattern(s.UniqueID(), pattern) || matchesPattern(s.ID(), pattern) {
				if !seen[s.Terraform.VariableName] {
					matched = append(matched, s)
					seen[s.Terraform.VariableName] = true
				}
				break
			}
		}
	}

	return matched
}

// matchesPattern checks if a string matches a glob pattern
func matchesPattern(s, pattern string) bool {
	// Use filepath.Match for glob matching
	matched, err := filepath.Match(pattern, s)
	if err != nil {
		return false
	}
	return matched
}

// hasBothTargets checks if a list of scenarios includes both to-admin and to-bucket variants
// for any base ID (e.g., both iam-002-to-admin and iam-002-to-bucket)
func hasBothTargets(scenarioList []*scenarios.Scenario) bool {
	baseIDs := make(map[string]map[string]bool)

	for _, s := range scenarioList {
		baseID := s.ID()
		if baseIDs[baseID] == nil {
			baseIDs[baseID] = make(map[string]bool)
		}
		baseIDs[baseID][s.Target] = true
	}

	for _, targets := range baseIDs {
		if targets["to-admin"] && targets["to-bucket"] {
			return true
		}
	}

	return false
}

// confirmAction prompts the user for confirmation and returns true if they confirm
func confirmAction(prompt string) bool {
	fmt.Printf("%s [y/N]: ", prompt)
	reader := bufio.NewReader(os.Stdin)
	response, err := reader.ReadString('\n')
	if err != nil {
		return false
	}
	response = strings.TrimSpace(strings.ToLower(response))
	return response == "y" || response == "yes"
}

// validateAWSCredentials checks that the configured AWS profiles have valid credentials
// before running terraform or AWS operations. Returns nil if valid, error if not.
func validateAWSCredentials(cfg *config.Config) error {
	if cfg == nil {
		return fmt.Errorf("configuration not loaded — run 'plabs init' to configure")
	}

	ws := cfg.Active()

	if ws.ActiveCloudOrDefault() != "aws" {
		return validateGCPCredentials(ws)
	}
	profile := ws.AWS.Prod.Profile
	if profile == "" {
		red := color.New(color.FgRed).SprintFunc()
		cyan := color.New(color.FgCyan).SprintFunc()
		fmt.Println()
		fmt.Println(red("AWS Credentials Error"))
		fmt.Println()
		fmt.Println("No AWS profile configured.")
		fmt.Printf("Run %s to configure.\n", cyan("plabs init"))
		fmt.Println()
		return fmt.Errorf("no AWS profile configured")
	}

	// For attacker in IAM user mode (bootstrapped), skip profile validation
	attackerProfile := ws.AWS.Attacker.Profile
	if ws.AWS.Attacker.Mode == "iam-user" && ws.AWS.Attacker.IAMAccessKeyID != "" {
		attackerProfile = "" // skip profile validation; using IAM creds
	}

	profiles := plabsaws.GetUniqueProfiles(
		ws.AWS.Prod.Profile,
		ws.AWS.Dev.Profile,
		ws.AWS.Ops.Profile,
		attackerProfile,
	)

	results, err := plabsaws.ValidateProfiles(profiles)
	if err != nil {
		red := color.New(color.FgRed).SprintFunc()
		yellow := color.New(color.FgYellow).SprintFunc()
		cyan := color.New(color.FgCyan).SprintFunc()
		fmt.Println()
		fmt.Println(red("AWS Credentials Error"))
		fmt.Println()
		fmt.Println("One or more AWS profiles have expired or invalid credentials:")
		fmt.Println()
		for _, r := range results {
			if !r.Valid {
				fmt.Printf("  %s Profile: %s\n", red("✗"), yellow(r.Profile))
			}
		}
		fmt.Println()
		fmt.Println("Run these commands to authenticate:")
		for _, r := range results {
			if !r.Valid {
				fmt.Printf("  %s\n", cyan(fmt.Sprintf("aws sso login --profile %s", r.Profile)))
			}
		}
		fmt.Println()
		return fmt.Errorf("AWS credential validation failed")
	}

	return nil
}

// validateGCPCredentials mirrors validateAWSCredentials for GCP, with one
// difference: on AWS, an expired SSO session is often refreshed transparently
// by the profile's credential_process (aws-vault, aws-sso-util, etc.), which
// pops a browser device-auth flow with no extra step from the user. gcloud
// has no credential_process equivalent for Application Default Credentials,
// so on the first failure plabs asks the user which login to run and then
// runs it — rather than picking one automatically, since `gcloud auth login
// --update-adc` can reassign the user's gcloud CLI identity, not just ADC,
// and that's a decision the user should make each time, not plabs.
func validateGCPCredentials(ws *config.WorkspaceConfig) error {
	if err := validateGCPCredentialsOnce(ws, false); err == nil {
		return nil
	}

	mode, err := promptGCPReauthMode()
	if err != nil {
		return fmt.Errorf("GCP credential validation cancelled: %w", err)
	}
	if mode == "cancel" {
		return fmt.Errorf("GCP credential validation cancelled")
	}

	yellow := color.New(color.FgYellow).SprintFunc()
	fmt.Printf("\n%s Re-authenticating with GCP...\n\n", yellow("Attention:"))

	var loginCmd *exec.Cmd
	if mode == "both" {
		loginCmd = exec.Command("gcloud", "auth", "login", "--update-adc")
	} else {
		loginCmd = exec.Command("gcloud", "auth", "application-default", "login")
	}
	loginCmd.Stdin = os.Stdin
	loginCmd.Stdout = os.Stdout
	loginCmd.Stderr = os.Stderr
	_ = loginCmd.Run() // ignore error; the retry below surfaces whatever's still wrong

	return validateGCPCredentialsOnce(ws, true)
}

// promptGCPReauthMode asks the user which gcloud login to run: "adc" updates
// Application Default Credentials only (used by Terraform); "both" runs
// `gcloud auth login --update-adc`, which also updates the CLI-session
// credential used by demo scripts' `gcloud ... --impersonate-service-account`
// calls, as the same identity as ADC — required since Terraform grants
// impersonation rights to whichever identity ADC detects.
func promptGCPReauthMode() (string, error) {
	var mode string
	form := huh.NewForm(
		huh.NewGroup(
			huh.NewSelect[string]().
				Title("GCP credentials need re-authenticating. Which login do you want to run?").
				Options(
					huh.NewOption("ADC + CLI login (gcloud auth login --update-adc) — recommended", "both"),
					huh.NewOption("ADC only (gcloud auth application-default login)", "adc"),
					huh.NewOption("Cancel", "cancel"),
				).
				Value(&mode),
		),
	).WithTheme(huh.ThemeCatppuccin())

	if err := form.Run(); err != nil {
		return "", err
	}
	return mode, nil
}

// validateGCPCredentialsOnce performs a single ADC + project-access check.
// showHelp controls whether failure prints the manual re-auth instructions —
// suppressed on the first attempt from validateGCPCredentials since that
// caller auto-retries via a fresh login instead.
func validateGCPCredentialsOnce(ws *config.WorkspaceConfig, showHelp bool) error {
	red := color.New(color.FgRed).SprintFunc()
	cyan := color.New(color.FgCyan).SprintFunc()
	yellow := color.New(color.FgYellow).SprintFunc()

	printGCPAuthHelp := func(projectID string) {
		fmt.Println()
		fmt.Println(red("GCP Credentials Error"))
		fmt.Println()
		if projectID != "" {
			fmt.Printf("Your Application Default Credentials cannot access project %s.\n", yellow(projectID))
		} else {
			fmt.Println("Application Default Credentials (ADC) are not configured or have expired.")
		}
		fmt.Println()

		// Show the active gcloud account so the user knows which one is in use.
		if out, err := exec.Command("gcloud", "auth", "list",
			"--filter=status:ACTIVE", "--format=value(account)").Output(); err == nil {
			if account := strings.TrimSpace(string(out)); account != "" {
				fmt.Printf("  Active gcloud account: %s\n", yellow(account))
				fmt.Println()
			}
		}

		fmt.Println("Re-authenticate and try again. Pick based on whether you also run demo scripts:")
		fmt.Println()
		fmt.Printf("  %s  (ADC + CLI login, same identity — needed for demo scripts)\n", cyan("gcloud auth login --update-adc"))
		fmt.Printf("  %s  (ADC only)\n", cyan("gcloud auth application-default login"))
		fmt.Println()
		if projectID != "" {
			fmt.Println("Make sure to log in with the account that has access to the configured project.")
			fmt.Println()
		}
	}

	// Step 1: Get an ADC access token. This may succeed even when the token is
	// stale (RAPT expiry), so we verify it with a real API call below.
	tokenCmd := exec.Command("gcloud", "auth", "application-default", "print-access-token")
	tokenCmd.Env = os.Environ()
	tokenOut, err := tokenCmd.Output()
	if err != nil {
		if showHelp {
			printGCPAuthHelp("")
		}
		return fmt.Errorf("GCP Application Default Credentials not configured")
	}
	token := strings.TrimSpace(string(tokenOut))

	// Step 2: Verify the token actually works against the configured project.
	// Skip when no project is configured (e.g. first-run before plabs init).
	projectID := ws.GCP.Prod.ProjectID
	if projectID == "" {
		return nil
	}

	req, err := http.NewRequest("GET",
		"https://cloudresourcemanager.googleapis.com/v1/projects/"+projectID, nil)
	if err != nil {
		// Shouldn't happen; skip the network check rather than blocking apply.
		return nil
	}
	req.Header.Set("Authorization", "Bearer "+token)

	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		// Network error — warn but don't block (offline/air-gapped environment).
		fmt.Printf("%s Could not verify GCP project access (network error) — proceeding.\n", yellow("Warning:"))
		return nil
	}
	defer func() { _, _ = io.Copy(io.Discard, resp.Body); resp.Body.Close() }()

	if resp.StatusCode == http.StatusOK {
		return nil
	}

	if showHelp {
		printGCPAuthHelp(projectID)
	}
	return fmt.Errorf("GCP credentials cannot access project %s (HTTP %d)", projectID, resp.StatusCode)
}

// printTerraformAuthHint re-validates AWS credentials after a terraform operation fails and
// prints a targeted "re-authenticate" message when a profile is found to be expired.
// It checks the setup profile for attacker (used during destroy) in addition to the
// regular profiles. Call this immediately after a failed terraform.Runner operation.
func printTerraformAuthHint(cfg *config.Config) {
	if cfg == nil {
		return
	}
	ws := cfg.Active()
	if ws.ActiveCloudOrDefault() != "aws" {
		return
	}

	red := color.New(color.FgRed).SprintFunc()
	cyan := color.New(color.FgCyan).SprintFunc()

	// Build the full set of profiles to check, including the attacker setup profile
	// (which may differ from the normal attacker profile used during deploy).
	attackerProfile := ws.AWS.Attacker.Profile
	if ws.AWS.Attacker.Mode == "iam-user" {
		// Destroy switches to the setup profile, so check that one.
		if ws.AWS.Attacker.SetupProfile != "" {
			attackerProfile = ws.AWS.Attacker.SetupProfile
		} else {
			attackerProfile = ""
		}
	}

	profiles := plabsaws.GetUniqueProfiles(
		ws.AWS.Prod.Profile,
		ws.AWS.Dev.Profile,
		ws.AWS.Ops.Profile,
		attackerProfile,
	)

	var expired []string
	for _, p := range profiles {
		if p == "" {
			continue
		}
		result := plabsaws.ValidateProfile(p)
		if !result.Valid {
			expired = append(expired, p)
		}
	}

	if len(expired) == 0 {
		return
	}

	fmt.Println()
	fmt.Println(red("Authentication Error"))
	fmt.Println()
	fmt.Println("The following AWS profile(s) are not authenticated:")
	fmt.Println()
	for _, p := range expired {
		fmt.Printf("  %s  %s\n", red("✗"), p)
	}
	fmt.Println()
	fmt.Println("Re-authenticate and retry:")
	fmt.Println()
	for _, p := range expired {
		fmt.Printf("  %s\n", cyan(fmt.Sprintf("aws sso login --profile %s", p)))
	}
	fmt.Println()
}

// crossAccountEnvErrors returns error strings for each scenario that requires a dev or ops
// AWS account profile that is not configured. The format mirrors the required-config error
// messages produced by enable/deploy so the user sees a consistent error surface.
func crossAccountEnvErrors(scenarioList []*scenarios.Scenario, ws *config.WorkspaceConfig) []string {
	var errs []string
	for _, s := range scenarioList {
		for _, env := range s.Environments {
			switch env {
			case "dev":
				if ws.AWS.Dev.Profile == "" {
					errs = append(errs, fmt.Sprintf(
						"  %s: requires a \"dev\" AWS account profile (not configured)\n    Set with: plabs config set dev-profile <aws-profile>",
						s.Name))
				}
			case "operations":
				if ws.AWS.Ops.Profile == "" {
					errs = append(errs, fmt.Sprintf(
						"  %s: requires an \"operations\" AWS account profile (not configured)\n    Set with: plabs config set ops-profile <aws-profile>",
						s.Name))
				}
			}
		}
	}
	return errs
}

// newDiscovery creates a Discovery instance wired to the current config.
// IncludeBeta is set from the loaded config so beta scenarios are hidden unless
// the user has run: plabs config set include-beta true. Results are also
// filtered to the active workspace's active cloud, so AWS commands never see
// GCP scenarios and vice versa.
func newDiscovery(scenariosPath string) *scenarios.Discovery {
	cfg, _ := config.Load()
	d := scenarios.NewDiscovery(scenariosPath)
	if cfg != nil {
		d.WithIncludeBeta(cfg.IncludeBeta)
		d.WithCloud(cfg.Active().ActiveCloudOrDefault())
	}
	return d
}
