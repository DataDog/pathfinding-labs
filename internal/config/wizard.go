package config

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
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
