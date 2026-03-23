package config

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/charmbracelet/huh"
	"github.com/charmbracelet/lipgloss"
	"gopkg.in/ini.v1"
)

// Wizard runs the interactive setup wizard
type Wizard struct{}

// NewWizard creates a new setup wizard
func NewWizard() *Wizard {
	return &Wizard{}
}

// Run executes the setup wizard and returns the configuration
func (w *Wizard) Run() (*Config, error) {
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

	// Explanation
	explanationStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("252"))
	dimStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("241"))
	highlightStyle := lipgloss.NewStyle().Foreground(lipgloss.Color("86")).Bold(true)

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

	cfg := &Config{}
	var numAccounts string

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
	cfg.AWS.Prod.Profile = prodProfile

	// Ask for prod region
	prodRegion, err := askForRegion("prod", prodProfile)
	if err != nil {
		return nil, err
	}
	cfg.AWS.Prod.Region = prodRegion

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
		cfg.AWS.Dev.Profile = devProfile

		// Ask for dev region
		devRegion, err := askForRegion("dev", devProfile)
		if err != nil {
			return nil, err
		}
		cfg.AWS.Dev.Region = devRegion
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
		cfg.AWS.Ops.Profile = opsProfile

		// Ask for ops region
		opsRegion, err := askForRegion("ops", opsProfile)
		if err != nil {
			return nil, err
		}
		cfg.AWS.Ops.Region = opsRegion
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

		cfg.AWS.Attacker.Region = attackerRegion
		cfg.AWS.Attacker.Mode = attackerAuthMode

		if attackerAuthMode == "iam-user" {
			// Store profile as setup profile; it will be used for bootstrap and destroy
			cfg.AWS.Attacker.SetupProfile = attackerProfile
			cfg.AWS.Attacker.Profile = attackerProfile // temporary, until bootstrap replaces with IAM creds
		} else {
			cfg.AWS.Attacker.Profile = attackerProfile
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
					Validate(func(s string) error {
						if !strings.Contains(s, "@") {
							return fmt.Errorf("please enter a valid email address")
						}
						return nil
					}),
				huh.NewInput().
					Title("Monthly budget limit (USD)").
					Description("Alerts at 50%, 80%, 100% actual and 100% forecasted").
					Placeholder("50").
					Value(&budgetLimit),
			),
		).WithTheme(huh.ThemeCatppuccin())

		if err := budgetDetailsForm.Run(); err != nil {
			return nil, err
		}

		cfg.Budget.Enabled = true
		cfg.Budget.Email = budgetEmail
		if limit, err := strconv.Atoi(budgetLimit); err == nil && limit > 0 {
			cfg.Budget.LimitUSD = limit
		} else {
			cfg.Budget.LimitUSD = 50 // default
		}
	}

	cfg.Initialized = true

	// Summary
	fmt.Println()
	summaryStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("86"))
	fmt.Println(summaryStyle.Render("Configuration Summary"))
	fmt.Println(strings.Repeat("-", 50))

	labelStyle := lipgloss.NewStyle().Width(25).Foreground(lipgloss.Color("241"))
	valueStyle := lipgloss.NewStyle().Bold(true)

	fmt.Printf("%s %s\n", labelStyle.Render("Prod profile:"), valueStyle.Render(cfg.AWS.Prod.Profile))
	fmt.Printf("%s %s\n", labelStyle.Render("Prod region:"), valueStyle.Render(cfg.AWS.Prod.Region))
	if cfg.AWS.Dev.Profile != "" {
		fmt.Printf("%s %s\n", labelStyle.Render("Dev profile:"), valueStyle.Render(cfg.AWS.Dev.Profile))
		fmt.Printf("%s %s\n", labelStyle.Render("Dev region:"), valueStyle.Render(cfg.AWS.Dev.Region))
	}
	if cfg.AWS.Ops.Profile != "" {
		fmt.Printf("%s %s\n", labelStyle.Render("Ops profile:"), valueStyle.Render(cfg.AWS.Ops.Profile))
		fmt.Printf("%s %s\n", labelStyle.Render("Ops region:"), valueStyle.Render(cfg.AWS.Ops.Region))
	}
	if cfg.HasAttackerAccount() {
		attackerProfile := cfg.AWS.Attacker.Profile
		if attackerProfile == "" {
			attackerProfile = cfg.AWS.Attacker.SetupProfile
		}
		fmt.Printf("%s %s\n", labelStyle.Render("Attacker profile:"), valueStyle.Render(attackerProfile))
		fmt.Printf("%s %s\n", labelStyle.Render("Attacker region:"), valueStyle.Render(cfg.AWS.Attacker.Region))
		if cfg.AWS.Attacker.Mode == "iam-user" {
			fmt.Printf("%s %s\n", labelStyle.Render("Attacker auth mode:"), valueStyle.Render("IAM admin user (bootstrapped on first deploy)"))
		} else {
			fmt.Printf("%s %s\n", labelStyle.Render("Attacker auth mode:"), valueStyle.Render("AWS profile"))
		}
	}
	if cfg.Budget.Enabled {
		fmt.Printf("%s %s\n", labelStyle.Render("Budget alerts:"), valueStyle.Render("Enabled"))
		fmt.Printf("%s %s\n", labelStyle.Render("Alert email:"), valueStyle.Render(cfg.Budget.Email))
		fmt.Printf("%s %s\n", labelStyle.Render("Budget limit:"), valueStyle.Render(fmt.Sprintf("$%d/month", cfg.Budget.LimitUSD)))
	}

	// Mode description
	fmt.Println()
	switch numAccounts {
	case "1":
		fmt.Println(dimStyle.Render("Mode: Single-account (cross-account scenarios unavailable)"))
	case "2":
		fmt.Println(dimStyle.Render("Mode: 2 accounts (dev->prod cross-account scenarios available)"))
	case "3":
		fmt.Println(dimStyle.Render("Mode: 3 accounts (all cross-account scenarios available)"))
	}
	fmt.Println()

	return cfg, nil
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
				Validate(func(s string) error {
					if s == "" {
						return fmt.Errorf("email is required when budget alerts are enabled")
					}
					if !strings.Contains(s, "@") {
						return fmt.Errorf("please enter a valid email address")
					}
					return nil
				}),
			huh.NewInput().
				Title("Monthly budget limit (USD)").
				Description("Alerts at 50%, 80%, 100% actual and 100% forecasted").
				Placeholder("50").
				Value(&budgetLimit),
		),
	).WithTheme(huh.ThemeCatppuccin())

	if err := detailsForm.Run(); err != nil {
		return nil, err
	}

	result.Email = budgetEmail
	if limit, err := strconv.Atoi(budgetLimit); err == nil && limit > 0 {
		result.LimitUSD = limit
	} else {
		result.LimitUSD = 50 // default
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
