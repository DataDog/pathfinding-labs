package config

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/charmbracelet/huh"
	"github.com/charmbracelet/lipgloss"
	"gopkg.in/ini.v1"
)

// emailRegexp matches a basic valid email address: local@domain.tld
var emailRegexp = regexp.MustCompile(`^[^@\s]+@[^@\s]+\.[^@\s]+$`)

func validateEmail(s string) error {
	if s == "" {
		return fmt.Errorf("email address is required")
	}
	if !emailRegexp.MatchString(s) {
		return fmt.Errorf("please enter a valid email address (e.g. you@example.com)")
	}
	return nil
}

func validateBudgetLimit(s string) error {
	if s == "" {
		return fmt.Errorf("budget limit is required")
	}
	// Reject decimal input with a specific message so users understand why
	if strings.Contains(s, ".") {
		return fmt.Errorf("enter a round dollar amount with no cents (e.g. 50)")
	}
	n, err := strconv.Atoi(strings.TrimSpace(s))
	if err != nil {
		return fmt.Errorf("enter a whole dollar amount (e.g. 50)")
	}
	if n <= 0 {
		return fmt.Errorf("budget limit must be greater than $0")
	}
	return nil
}

// Wizard runs the interactive setup wizard
type Wizard struct{}

// NewWizard creates a new setup wizard
func NewWizard() *Wizard {
	return &Wizard{}
}

// SelectClouds prints the wizard header and asks which cloud(s) to
// configure. Split out from Run so the caller can check for required tools
// (aws CLI, gcloud CLI, etc.) scoped to only the clouds actually selected,
// before running the rest of the (potentially lengthy) account setup flow.
func (w *Wizard) SelectClouds() (awsSelected bool, gcpSelected bool, err error) {
	// Print header
	headerStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("86")).
		BorderStyle(lipgloss.DoubleBorder()).
		BorderForeground(lipgloss.Color("86")).
		Padding(0, 2)

	fmt.Println()
	fmt.Println(headerStyle.Render("Pathfinding Labs Setup"))
	fmt.Println()

	// Ask which cloud(s) to configure. AWS is selected by default so a user
	// just hitting enter gets today's AWS-only behavior unchanged.
	var selectedClouds []string
	cloudForm := huh.NewForm(
		huh.NewGroup(
			huh.NewMultiSelect[string]().
				Title("Which cloud(s) do you want to configure?").
				Options(
					huh.NewOption("AWS", "aws").Selected(true),
					huh.NewOption("GCP", "gcp"),
				).
				Value(&selectedClouds),
		),
	).WithTheme(huh.ThemeCatppuccin())

	if err := cloudForm.Run(); err != nil {
		return false, false, err
	}

	for _, c := range selectedClouds {
		switch c {
		case "aws":
			awsSelected = true
		case "gcp":
			gcpSelected = true
		}
	}
	// Fall back to AWS if the user deselects everything, since a workspace
	// with no configured cloud has nothing to do.
	if !awsSelected && !gcpSelected {
		awsSelected = true
	}

	return awsSelected, gcpSelected, nil
}

// Run executes the setup wizard's account-configuration flow and returns the
// workspace configuration. awsSelected/gcpSelected come from a prior call to
// SelectClouds.
// RunOptions holds optional overrides for the wizard Run call.
// Zero value is safe: all booleans default to false (no pre-set dev mode).
type RunOptions struct {
	// DevMode pre-configures the workspace for dev mode (local repo checkout).
	// When true, the wizard skips its own "use local dev copy?" question and
	// applies DevModePath directly. Corresponds to `plabs init --dev-mode`.
	DevMode     bool
	DevModePath string
}

func (w *Wizard) Run(awsSelected bool, gcpSelected bool, opts ...RunOptions) (*WorkspaceConfig, error) {
	var opt RunOptions
	if len(opts) > 0 {
		opt = opts[0]
	}

	// Explanation
	explanationStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("252"))
	dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("241"))
	highlightStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("86")).Bold(true)

	ws := &WorkspaceConfig{}
	if opt.DevMode {
		ws.DevMode = true
		ws.DevModePath = opt.DevModePath
	}

	if awsSelected {
		fmt.Println(explanationStyle.Render("Pathfinding Labs can work with 1, 2, or 3 AWS accounts:"))
		fmt.Println()
		fmt.Printf("  %s  Most scenarios run in a single account (called %s).\n",
			dimStyle.Render("*"),
			highlightStyle.Render("prod"))
		fmt.Printf("  %s  Adding a %s account enables dev->prod cross-account scenarios.\n",
			dimStyle.Render("*"),
			highlightStyle.Render("dev"))
		fmt.Printf("  %s  Adding an %s account enables ops->prod cross-account scenarios.\n",
			dimStyle.Render("*"),
			highlightStyle.Render("ops"))
		fmt.Println()
		fmt.Println(dimStyle.Render("  Account IDs are automatically derived from your AWS profiles."))
		fmt.Println()
	}

	// Get available AWS profiles
	profiles := getAWSProfiles()
	if len(profiles) == 0 {
		profiles = []string{"default"}
	}

	// Build profile options
	profileOptions := make([]huh.Option[string], len(profiles))
	for i, p := range profiles {
		profileOptions[i] = huh.NewOption(p, p)
	}

	var numAccounts string
	if awsSelected {
		// Ask how many accounts
		accountForm := huh.NewForm(
			huh.NewGroup(
				huh.NewSelect[string]().
					Title("How many AWS accounts do you want to configure?").
					Options(
						huh.NewOption("1 account (prod only)", "1").Selected(true),
						huh.NewOption("2 accounts (prod + dev)", "2"),
						huh.NewOption("3 accounts (prod + dev + ops)", "3"),
					).
					Value(&numAccounts),
			),
		).WithTheme(huh.ThemeCatppuccin())

		if err := accountForm.Run(); err != nil {
			return nil, err
		}

		// Configure prod account (always required)
		fmt.Println()
		accountHeaderStyle := lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("212")).
			Background(lipgloss.Color("236")).
			Padding(0, 1)
		fmt.Println(accountHeaderStyle.Render(" 1. Production Account (prod) "))
		fmt.Println(dimStyle.Render("   This is your primary account where most scenarios will run."))
		fmt.Println()

		var prodProfile string
		prodForm := huh.NewForm(
			huh.NewGroup(
				huh.NewSelect[string]().
					Title("Select AWS profile for PROD account").
					Description("Type to filter, arrows to navigate, enter to select").
					Options(profileOptions...).
					Filtering(true).
					Height(15).
					Value(&prodProfile),
			),
		).WithTheme(huh.ThemeCatppuccin())

		if err := prodForm.Run(); err != nil {
			return nil, err
		}
		ws.AWS.Prod.Profile = prodProfile

		// Ask for prod region
		prodRegion, err := askForRegion("prod", prodProfile)
		if err != nil {
			return nil, err
		}
		ws.AWS.Prod.Region = prodRegion

		// Configure dev account if needed
		if numAccounts == "2" || numAccounts == "3" {
			fmt.Println()
			fmt.Println(accountHeaderStyle.Render(" 2. Development Account (dev) "))
			fmt.Println(dimStyle.Render("   Used as the source account for dev->prod attack scenarios."))
			fmt.Println()

			var devProfile string
			devForm := huh.NewForm(
				huh.NewGroup(
					huh.NewSelect[string]().
						Title("Select AWS profile for DEV account").
						Description("Type to filter, arrows to navigate, enter to select").
						Options(profileOptions...).
						Filtering(true).
						Height(15).
						Value(&devProfile),
				),
			).WithTheme(huh.ThemeCatppuccin())

			if err := devForm.Run(); err != nil {
				return nil, err
			}
			ws.AWS.Dev.Profile = devProfile

			// Ask for dev region
			devRegion, err := askForRegion("dev", devProfile)
			if err != nil {
				return nil, err
			}
			ws.AWS.Dev.Region = devRegion
		}

		// Configure ops account if needed
		if numAccounts == "3" {
			fmt.Println()
			fmt.Println(accountHeaderStyle.Render(" 3. Operations Account (ops) "))
			fmt.Println(dimStyle.Render("   Used as the source account for ops->prod attack scenarios."))
			fmt.Println()

			var opsProfile string
			opsForm := huh.NewForm(
				huh.NewGroup(
					huh.NewSelect[string]().
						Title("Select AWS profile for OPS account").
						Description("Type to filter, arrows to navigate, enter to select").
						Options(profileOptions...).
						Filtering(true).
						Height(15).
						Value(&opsProfile),
				),
			).WithTheme(huh.ThemeCatppuccin())

			if err := opsForm.Run(); err != nil {
				return nil, err
			}
			ws.AWS.Ops.Profile = opsProfile

			// Ask for ops region
			opsRegion, err := askForRegion("ops", opsProfile)
			if err != nil {
				return nil, err
			}
			ws.AWS.Ops.Region = opsRegion
		}

		// Attacker account section (optional, independent of victim account count)
		fmt.Println()
		attackerHeaderStyle := lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("196")). // Red for attacker
			Background(lipgloss.Color("236")).
			Padding(0, 1)
		fmt.Println(attackerHeaderStyle.Render(" Attacker Account (optional) "))
		fmt.Println(dimStyle.Render("   A separate AWS account for adversary-controlled infrastructure"))
		fmt.Println(dimStyle.Render("   (e.g., ECR repos, S3 buckets used in attack scenarios)."))
		fmt.Println()

		var hasAttackerAccount bool
		attackerForm := huh.NewForm(
			huh.NewGroup(
				huh.NewConfirm().
					Title("Do you have a separate attacker-controlled AWS account?").
					Description("Optional - not required for most scenarios").
					Value(&hasAttackerAccount),
			),
		).WithTheme(huh.ThemeCatppuccin())

		if err := attackerForm.Run(); err != nil {
			return nil, err
		}

		if hasAttackerAccount {
			var attackerProfile string
			attackerProfileForm := huh.NewForm(
				huh.NewGroup(
					huh.NewSelect[string]().
						Title("Select AWS profile for ATTACKER account").
						Description("Type to filter, arrows to navigate, enter to select").
						Options(profileOptions...).
						Filtering(true).
						Height(15).
						Value(&attackerProfile),
				),
			).WithTheme(huh.ThemeCatppuccin())

			if err := attackerProfileForm.Run(); err != nil {
				return nil, err
			}

			attackerRegion, err := askForRegion("attacker", attackerProfile)
			if err != nil {
				return nil, err
			}

			// Ask how to authenticate to the attacker account
			var attackerAuthMode string
			authModeForm := huh.NewForm(
				huh.NewGroup(
					huh.NewSelect[string]().
						Title("How should plabs authenticate to the attacker account?").
						Options(
							huh.NewOption("Use the AWS profile directly", "profile").Selected(true),
							huh.NewOption("Create a dedicated IAM admin user (profile used once for setup, then IAM creds)", "iam-user"),
						).
						Value(&attackerAuthMode),
				),
			).WithTheme(huh.ThemeCatppuccin())

			if err := authModeForm.Run(); err != nil {
				return nil, err
			}

			ws.AWS.Attacker.Region = attackerRegion
			ws.AWS.Attacker.Mode = attackerAuthMode

			if attackerAuthMode == "iam-user" {
				// Store profile as setup profile; it will be used for bootstrap and destroy
				ws.AWS.Attacker.SetupProfile = attackerProfile
				ws.AWS.Attacker.Profile = attackerProfile // temporary, until bootstrap replaces with IAM creds
			} else {
				ws.AWS.Attacker.Profile = attackerProfile
			}
		}

		// Budget alerts section
		fmt.Println()
		budgetHeaderStyle := lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("214")). // Orange for cost/money
			Background(lipgloss.Color("236")).
			Padding(0, 1)
		fmt.Println(budgetHeaderStyle.Render(" Cost Protection "))
		fmt.Println(dimStyle.Render("   Set up AWS Budget alerts to avoid unexpected charges."))
		fmt.Println(dimStyle.Render("   First 2 budgets per account are FREE."))
		fmt.Println()

		var enableBudget bool
		budgetForm := huh.NewForm(
			huh.NewGroup(
				huh.NewConfirm().
					Title("Enable budget alerts?").
					Description("Get email notifications when AWS costs approach your limit").
					Value(&enableBudget),
			),
		).WithTheme(huh.ThemeCatppuccin())

		if err := budgetForm.Run(); err != nil {
			return nil, err
		}

		if enableBudget {
			var budgetEmail string
			var budgetLimit string

			budgetDetailsForm := huh.NewForm(
				huh.NewGroup(
					huh.NewInput().
						Title("Email for budget alerts").
						Description("AWS will send notifications to this address").
						Value(&budgetEmail).
						Validate(validateEmail),
					huh.NewInput().
						Title("Monthly budget limit (USD)").
						Description("Alerts at 50%, 80%, 100% actual and 100% forecasted").
						Placeholder("50").
						Value(&budgetLimit).
						Validate(validateBudgetLimit),
				),
			).WithTheme(huh.ThemeCatppuccin())

			if err := budgetDetailsForm.Run(); err != nil {
				return nil, err
			}

			ws.Budget.Enabled = true
			ws.Budget.Email = budgetEmail
			// validateBudgetLimit ensures Atoi succeeds and limit > 0
			ws.Budget.LimitUSD, _ = strconv.Atoi(strings.TrimSpace(budgetLimit))
		}
	} // awsSelected

	var gcpNumProjects string
	if gcpSelected {
		fmt.Println()
		gcpHeaderStyle := lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("39")). // Blue for GCP
			Background(lipgloss.Color("236")).
			Padding(0, 1)
		fmt.Println(gcpHeaderStyle.Render(" GCP Configuration "))
		fmt.Println(dimStyle.Render("   Terraform authenticates via Application Default Credentials (ADC)."))
		fmt.Println(dimStyle.Render("   Demo scripts also need your gcloud CLI login to be the SAME identity"))
		fmt.Println(dimStyle.Render("   as ADC, since Terraform grants impersonation rights to whichever"))
		fmt.Println(dimStyle.Render("   identity ADC detects. The simplest way to set up both at once:"))
		fmt.Println()
		fmt.Println(dimStyle.Render("     gcloud auth login --update-adc"))
		fmt.Println()
		fmt.Println(dimStyle.Render("   (or run `gcloud auth login` and `gcloud auth application-default"))
		fmt.Println(dimStyle.Render("   login` separately, as the same account, if you need them to differ)."))
		fmt.Println()

		gcpAccountForm := huh.NewForm(
			huh.NewGroup(
				huh.NewSelect[string]().
					Title("How many GCP projects do you want to configure?").
					Options(
						huh.NewOption("1 project (prod only)", "1").Selected(true),
						huh.NewOption("2 projects (prod + dev)", "2"),
						huh.NewOption("3 projects (prod + dev + ops)", "3"),
					).
					Value(&gcpNumProjects),
			),
		).WithTheme(huh.ThemeCatppuccin())

		if err := gcpAccountForm.Run(); err != nil {
			return nil, err
		}

		gcpProdProject, err := promptGCPProjectID("GCP project ID for PROD", "my-project-prod", "")
		if err != nil {
			return nil, err
		}
		ws.GCP.Prod.ProjectID = gcpProdProject

		if gcpNumProjects == "2" || gcpNumProjects == "3" {
			gcpDevProject, err := promptGCPProjectID("GCP project ID for DEV", "my-project-dev", "")
			if err != nil {
				return nil, err
			}
			ws.GCP.Dev.ProjectID = gcpDevProject
		}

		if gcpNumProjects == "3" {
			gcpOpsProject, err := promptGCPProjectID("GCP project ID for OPS", "my-project-ops", "")
			if err != nil {
				return nil, err
			}
			ws.GCP.Ops.ProjectID = gcpOpsProject
		}
	}

	// Set the active cloud context. With only one cloud configured, set it
	// automatically with no prompt; with more than one, ask which the
	// CLI/TUI should operate against by default (switchable later via
	// `plabs cloud use` or the TUI Settings overlay).
	if awsSelected && gcpSelected {
		var activeCloud string
		activeCloudForm := huh.NewForm(
			huh.NewGroup(
				huh.NewSelect[string]().
					Title("Which cloud do you want as your active context?").
					Description("This determines which scenarios and environments plabs operates on by default. Switch anytime with `plabs cloud use`.").
					Options(
						huh.NewOption("AWS", "aws").Selected(true),
						huh.NewOption("GCP", "gcp"),
					).
					Value(&activeCloud),
			),
		).WithTheme(huh.ThemeCatppuccin())
		if err := activeCloudForm.Run(); err != nil {
			return nil, err
		}
		ws.ActiveCloud = activeCloud
	} else if gcpSelected {
		ws.ActiveCloud = "gcp"
	} else {
		ws.ActiveCloud = "aws"
	}

	ws.Initialized = true

	// Summary
	fmt.Println()
	summaryStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("86"))
	fmt.Println(summaryStyle.Render("Configuration Summary"))
	fmt.Println(strings.Repeat("-", 50))

	labelStyle := lipgloss.NewStyle().Width(25).Foreground(lipgloss.Color("241"))
	valueStyle := lipgloss.NewStyle().Bold(true)

	if awsSelected {
		fmt.Printf("%s %s\n", labelStyle.Render("Prod profile:"), valueStyle.Render(ws.AWS.Prod.Profile))
		fmt.Printf("%s %s\n", labelStyle.Render("Prod region:"), valueStyle.Render(ws.AWS.Prod.Region))
		if ws.AWS.Dev.Profile != "" {
			fmt.Printf("%s %s\n", labelStyle.Render("Dev profile:"), valueStyle.Render(ws.AWS.Dev.Profile))
			fmt.Printf("%s %s\n", labelStyle.Render("Dev region:"), valueStyle.Render(ws.AWS.Dev.Region))
		}
		if ws.AWS.Ops.Profile != "" {
			fmt.Printf("%s %s\n", labelStyle.Render("Ops profile:"), valueStyle.Render(ws.AWS.Ops.Profile))
			fmt.Printf("%s %s\n", labelStyle.Render("Ops region:"), valueStyle.Render(ws.AWS.Ops.Region))
		}
		if ws.HasAttackerAccount() {
			attackerProfile := ws.AWS.Attacker.Profile
			if attackerProfile == "" {
				attackerProfile = ws.AWS.Attacker.SetupProfile
			}
			fmt.Printf("%s %s\n", labelStyle.Render("Attacker profile:"), valueStyle.Render(attackerProfile))
			fmt.Printf("%s %s\n", labelStyle.Render("Attacker region:"), valueStyle.Render(ws.AWS.Attacker.Region))
			if ws.AWS.Attacker.Mode == "iam-user" {
				fmt.Printf("%s %s\n", labelStyle.Render("Attacker auth mode:"), valueStyle.Render("IAM admin user (bootstrapped on first deploy)"))
			} else {
				fmt.Printf("%s %s\n", labelStyle.Render("Attacker auth mode:"), valueStyle.Render("AWS profile"))
			}
		}
		if ws.Budget.Enabled {
			fmt.Printf("%s %s\n", labelStyle.Render("Budget alerts:"), valueStyle.Render("Enabled"))
			fmt.Printf("%s %s\n", labelStyle.Render("Alert email:"), valueStyle.Render(ws.Budget.Email))
			fmt.Printf("%s %s\n", labelStyle.Render("Budget limit:"), valueStyle.Render(fmt.Sprintf("$%d/month", ws.Budget.LimitUSD)))
		}
	}

	if gcpSelected {
		fmt.Printf("%s %s\n", labelStyle.Render("GCP prod project:"), valueStyle.Render(ws.GCP.Prod.ProjectID))
		if ws.GCP.Dev.ProjectID != "" {
			fmt.Printf("%s %s\n", labelStyle.Render("GCP dev project:"), valueStyle.Render(ws.GCP.Dev.ProjectID))
		}
		if ws.GCP.Ops.ProjectID != "" {
			fmt.Printf("%s %s\n", labelStyle.Render("GCP ops project:"), valueStyle.Render(ws.GCP.Ops.ProjectID))
		}
	}

	if awsSelected && gcpSelected {
		fmt.Printf("%s %s\n", labelStyle.Render("Active cloud:"), valueStyle.Render(ws.ActiveCloud))
	}

	// Mode description
	if awsSelected {
		fmt.Println()
		switch numAccounts {
		case "1":
			fmt.Println(dimStyle.Render("Mode: Single-account (cross-account scenarios unavailable)"))
		case "2":
			fmt.Println(dimStyle.Render("Mode: 2 accounts (dev->prod cross-account scenarios available)"))
		case "3":
			fmt.Println(dimStyle.Render("Mode: 3 accounts (all cross-account scenarios available)"))
		}
	}
	fmt.Println()

	return ws, nil
}

// RunForEnvironment runs the wizard for a single environment
// Returns the selected profile name
func (w *Wizard) RunForEnvironment(envName string, currentProfile string) (string, error) {
	// Get available AWS profiles
	profiles := getAWSProfiles()
	if len(profiles) == 0 {
		profiles = []string{"default"}
	}

	// Build profile options, putting current profile first if set
	var profileOptions []huh.Option[string]
	if currentProfile != "" {
		// Add current as first option
		profileOptions = append(profileOptions, huh.NewOption(currentProfile+" (current)", currentProfile))
		for _, p := range profiles {
			if p != currentProfile {
				profileOptions = append(profileOptions, huh.NewOption(p, p))
			}
		}
	} else {
		for _, p := range profiles {
			profileOptions = append(profileOptions, huh.NewOption(p, p))
		}
	}

	// Styling
	headerStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("212")).
		Background(lipgloss.Color("236")).
		Padding(0, 1)
	dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("241"))

	var envTitle, envDesc string
	switch envName {
	case "prod":
		envTitle = " Production Account (prod) "
		envDesc = "This is your primary account where most scenarios will run."
	case "dev":
		envTitle = " Development Account (dev) "
		envDesc = "Used as the source account for dev->prod attack scenarios."
	case "ops":
		envTitle = " Operations Account (ops) "
		envDesc = "Used as the source account for ops->prod attack scenarios."
	case "attacker":
		envTitle = " Attacker Account (attacker) "
		envDesc = "Adversary-controlled account for attack infrastructure (ECR, S3, etc)."
	default:
		return "", fmt.Errorf("unknown environment: %s", envName)
	}

	fmt.Println()
	fmt.Println(headerStyle.Render(envTitle))
	fmt.Println(dimStyle.Render("   " + envDesc))
	fmt.Println()

	var selectedProfile string
	form := huh.NewForm(
		huh.NewGroup(
			huh.NewSelect[string]().
				Title(fmt.Sprintf("Select AWS profile for %s account", strings.ToUpper(envName))).
				Description("Type to filter, arrows to navigate, enter to select").
				Options(profileOptions...).
				Filtering(true).
				Height(15).
				Value(&selectedProfile),
		),
	).WithTheme(huh.ThemeCatppuccin())

	if err := form.Run(); err != nil {
		return "", err
	}

	return selectedProfile, nil
}

// gcpConfiguration describes one named `gcloud config configurations` entry.
type gcpConfiguration struct {
	Name      string
	Account   string
	ProjectID string
}

// getGCPConfigurations returns the user's named gcloud configurations by
// shelling out to `gcloud config configurations list`. Returns nil if
// gcloud isn't installed, the command fails, or no configuration has a
// project set — callers should fall back to a plain text input in that case.
func getGCPConfigurations() []gcpConfiguration {
	if _, err := exec.LookPath("gcloud"); err != nil {
		return nil
	}

	out, err := exec.Command("gcloud", "config", "configurations", "list", "--format=json").Output()
	if err != nil {
		return nil
	}

	var raw []struct {
		Name       string `json:"name"`
		Properties struct {
			Core struct {
				Account string `json:"account"`
				Project string `json:"project"`
			} `json:"core"`
		} `json:"properties"`
	}
	if err := json.Unmarshal(out, &raw); err != nil {
		return nil
	}

	configs := make([]gcpConfiguration, 0, len(raw))
	for _, r := range raw {
		if r.Properties.Core.Project == "" {
			continue
		}
		configs = append(configs, gcpConfiguration{
			Name:      r.Name,
			Account:   r.Properties.Core.Account,
			ProjectID: r.Properties.Core.Project,
		})
	}
	return configs
}

// promptGCPProjectID asks for a GCP project ID. When named gcloud
// configurations exist, it first shows a select built from them (plus a
// manual-entry option), then a text input pre-filled with the choice so the
// user can still edit it before continuing. Selecting a configuration only
// pre-fills the field — it never runs `gcloud config configurations
// activate`, so it has no side effect on the user's global gcloud state.
// Falls back straight to the plain text input when gcloud is missing, the
// command errors, or no configuration has a project set.
func promptGCPProjectID(title, placeholder, currentProjectID string) (string, error) {
	projectID := currentProjectID

	configs := getGCPConfigurations()
	if len(configs) > 0 {
		const manualEntryValue = "__manual__"
		options := make([]huh.Option[string], 0, len(configs)+1)
		for _, c := range configs {
			options = append(options, huh.NewOption(
				fmt.Sprintf("%s (%s -> %s)", c.Name, c.Account, c.ProjectID),
				c.ProjectID,
			))
		}
		options = append(options, huh.NewOption("Enter manually", manualEntryValue))

		var choice string
		pickerForm := huh.NewForm(
			huh.NewGroup(
				huh.NewSelect[string]().
					Title(title).
					Description("Pre-fills the project ID below from a gcloud configuration; it does not change your active gcloud config.").
					Options(options...).
					Value(&choice),
			),
		).WithTheme(huh.ThemeCatppuccin())
		if err := pickerForm.Run(); err != nil {
			return "", err
		}
		if choice != manualEntryValue {
			projectID = choice
		}
	}

	inputForm := huh.NewForm(
		huh.NewGroup(
			huh.NewInput().
				Title(title).
				Placeholder(placeholder).
				Value(&projectID).
				Validate(func(s string) error {
					if strings.TrimSpace(s) == "" {
						return fmt.Errorf("project ID is required")
					}
					return nil
				}),
		),
	).WithTheme(huh.ThemeCatppuccin())
	if err := inputForm.Run(); err != nil {
		return "", err
	}

	return strings.TrimSpace(projectID), nil
}

// RunForGCPEnvironment runs the wizard for a single GCP environment's
// project ID. Mirrors RunForEnvironment's AWS profile flow: when named
// gcloud configurations exist, offers a select to pre-fill the project ID
// (see promptGCPProjectID); otherwise falls back to a plain validated text
// input, since GCP auth comes from Application Default Credentials rather
// than a profile the input alone could fully determine.
func (w *Wizard) RunForGCPEnvironment(envName string, currentProjectID string) (string, error) {
	headerStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("39")). // Blue for GCP
		Background(lipgloss.Color("236")).
		Padding(0, 1)
	dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("241"))

	var envTitle, envDesc string
	switch envName {
	case "prod":
		envTitle = " Production Project (prod) "
		envDesc = "This is your primary project where most scenarios will run."
	case "dev":
		envTitle = " Development Project (dev) "
		envDesc = "Used as the source project for dev->prod attack scenarios."
	case "ops":
		envTitle = " Operations Project (ops) "
		envDesc = "Used as the source project for ops->prod attack scenarios."
	default:
		return "", fmt.Errorf("unknown environment: %s", envName)
	}

	fmt.Println()
	fmt.Println(headerStyle.Render(envTitle))
	fmt.Println(dimStyle.Render("   " + envDesc))
	fmt.Println()

	return promptGCPProjectID(
		fmt.Sprintf("GCP project ID for %s", strings.ToUpper(envName)),
		fmt.Sprintf("my-project-%s", envName),
		currentProjectID,
	)
}

// BudgetResult contains the result from budget configuration
type BudgetResult struct {
	Enabled  bool
	Email    string
	LimitUSD int
}

// RunForBudget runs the wizard for budget configuration
// Returns the updated budget settings
func (w *Wizard) RunForBudget(current BudgetConfig) (*BudgetResult, error) {
	// Styling
	headerStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("214")). // Orange for cost/money
		Background(lipgloss.Color("236")).
		Padding(0, 1)
	dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("241"))

	fmt.Println()
	fmt.Println(headerStyle.Render(" Budget Alerts (Cost Protection) "))
	fmt.Println(dimStyle.Render("   Get email notifications when AWS costs approach your limit."))
	fmt.Println(dimStyle.Render("   First 2 budgets per account are FREE."))
	fmt.Println()

	var enableBudget bool = current.Enabled
	enableForm := huh.NewForm(
		huh.NewGroup(
			huh.NewConfirm().
				Title("Enable budget alerts?").
				Description("Get email notifications when AWS costs approach your limit").
				Value(&enableBudget),
		),
	).WithTheme(huh.ThemeCatppuccin())

	if err := enableForm.Run(); err != nil {
		return nil, err
	}

	result := &BudgetResult{
		Enabled:  enableBudget,
		Email:    current.Email,
		LimitUSD: current.LimitUSD,
	}

	if !enableBudget {
		return result, nil
	}

	// If enabling, ask for email and limit
	budgetEmail := current.Email
	budgetLimit := ""
	if current.LimitUSD > 0 {
		budgetLimit = strconv.Itoa(current.LimitUSD)
	}

	detailsForm := huh.NewForm(
		huh.NewGroup(
			huh.NewInput().
				Title("Email for budget alerts").
				Description("AWS will send notifications to this address").
				Value(&budgetEmail).
				Validate(validateEmail),
			huh.NewInput().
				Title("Monthly budget limit (USD)").
				Description("Alerts at 50%, 80%, 100% actual and 100% forecasted").
				Placeholder("50").
				Value(&budgetLimit).
				Validate(validateBudgetLimit),
		),
	).WithTheme(huh.ThemeCatppuccin())

	if err := detailsForm.Run(); err != nil {
		return nil, err
	}

	result.Email = budgetEmail
	// validateBudgetLimit ensures Atoi succeeds and limit > 0
	if limit, err := strconv.Atoi(strings.TrimSpace(budgetLimit)); err == nil {
		result.LimitUSD = limit
	} else {
		result.LimitUSD = 50 // fallback (should not be reached after validation
	}

	return result, nil
}

// Common AWS regions for selection
var awsRegions = []string{
	"us-east-1",      // N. Virginia
	"us-east-2",      // Ohio
	"us-west-1",      // N. California
	"us-west-2",      // Oregon
	"eu-west-1",      // Ireland
	"eu-west-2",      // London
	"eu-west-3",      // Paris
	"eu-central-1",   // Frankfurt
	"eu-north-1",     // Stockholm
	"ap-northeast-1", // Tokyo
	"ap-northeast-2", // Seoul
	"ap-southeast-1", // Singapore
	"ap-southeast-2", // Sydney
	"ap-south-1",     // Mumbai
	"sa-east-1",      // Sao Paulo
	"ca-central-1",   // Canada
}

// getAWSRegionForProfile returns the region configured for a profile in AWS config files
func getAWSRegionForProfile(profileName string) string {
	home, err := os.UserHomeDir()
	if err != nil {
		return ""
	}

	// Check ~/.aws/config (primary location for regions)
	configPath := filepath.Join(home, ".aws", "config")
	if cfg, err := ini.Load(configPath); err == nil {
		// For non-default profiles, AWS config uses "profile xyz" format
		sectionName := profileName
		if profileName != "default" {
			sectionName = "profile " + profileName
		}

		if section, err := cfg.GetSection(sectionName); err == nil {
			if region := section.Key("region").String(); region != "" {
				return region
			}
		}
	}

	// Fallback: check environment variable
	if region := os.Getenv("AWS_DEFAULT_REGION"); region != "" {
		return region
	}
	if region := os.Getenv("AWS_REGION"); region != "" {
		return region
	}

	return ""
}

// getAWSProfiles returns a list of available AWS CLI profiles
func getAWSProfiles() []string {
	profileSet := make(map[string]bool)

	// Check ~/.aws/credentials
	home, err := os.UserHomeDir()
	if err != nil {
		return []string{"default"}
	}

	credPath := filepath.Join(home, ".aws", "credentials")
	if cfg, err := ini.Load(credPath); err == nil {
		for _, section := range cfg.Sections() {
			name := section.Name()
			if name != "DEFAULT" && name != "" {
				profileSet[name] = true
			}
		}
	}

	// Check ~/.aws/config
	configPath := filepath.Join(home, ".aws", "config")
	if cfg, err := ini.Load(configPath); err == nil {
		for _, section := range cfg.Sections() {
			name := section.Name()
			if name == "DEFAULT" || name == "" {
				continue
			}
			// Config file uses "profile xyz" format
			name = strings.TrimPrefix(name, "profile ")
			profileSet[name] = true
		}
	}

	// Convert to sorted slice
	profiles := make([]string, 0, len(profileSet))
	for p := range profileSet {
		profiles = append(profiles, p)
	}
	sort.Strings(profiles)

	// Ensure "default" is first if it exists
	for i, p := range profiles {
		if p == "default" && i != 0 {
			profiles = append([]string{"default"}, append(profiles[:i], profiles[i+1:]...)...)
			break
		}
	}

	return profiles
}

// askForRegion prompts the user to select a region for an environment
// It checks the AWS config for a default region and pre-selects it if found
func askForRegion(envName string, profileName string) (string, error) {
	// Get the region from AWS config if available
	defaultRegion := getAWSRegionForProfile(profileName)

	// Build region options
	var regionOptions []huh.Option[string]

	// If we found a region in the profile, add it first as the recommended option
	if defaultRegion != "" {
		regionOptions = append(regionOptions, huh.NewOption(defaultRegion+" (from profile)", defaultRegion))
	}

	// Add all regions, skipping the default if it was already added
	for _, region := range awsRegions {
		if region != defaultRegion {
			regionOptions = append(regionOptions, huh.NewOption(region, region))
		}
	}

	var selectedRegion string

	// Set default value if we found one
	if defaultRegion != "" {
		selectedRegion = defaultRegion
	}

	regionForm := huh.NewForm(
		huh.NewGroup(
			huh.NewSelect[string]().
				Title(fmt.Sprintf("Select AWS region for %s account", strings.ToUpper(envName))).
				Description("This is where your resources will be deployed").
				Options(regionOptions...).
				Height(12).
				Value(&selectedRegion),
		),
	).WithTheme(huh.ThemeCatppuccin())

	if err := regionForm.Run(); err != nil {
		return "", err
	}

	return selectedRegion, nil
}
