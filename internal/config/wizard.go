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
		dimStyle.Render("•"),
		highlightStyle.Render("prod"))
	fmt.Printf("  %s  Adding a %s account enables dev→prod cross-account scenarios.\n",
		dimStyle.Render("•"),
		highlightStyle.Render("dev"))
	fmt.Printf("  %s  Adding an %s account enables ops→prod cross-account scenarios.\n",
		dimStyle.Render("•"),
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

	prodForm := huh.NewForm(
		huh.NewGroup(
			huh.NewSelect[string]().
				Title("Select AWS profile for PROD account").
				Description("Type to filter, arrows to navigate, enter to select").
				Options(profileOptions...).
				Filtering(true).
				Height(15).
				Value(&cfg.ProdProfile),
		),
	).WithTheme(huh.ThemeCatppuccin())

	if err := prodForm.Run(); err != nil {
		return nil, err
	}

	// Configure dev account if needed
	if numAccounts == "2" || numAccounts == "3" {
		fmt.Println()
		fmt.Println(accountHeaderStyle.Render(" 2. Development Account (dev) "))
		fmt.Println(dimStyle.Render("   Used as the source account for dev→prod attack scenarios."))
		fmt.Println()

		devForm := huh.NewForm(
			huh.NewGroup(
				huh.NewSelect[string]().
					Title("Select AWS profile for DEV account").
					Description("Type to filter, arrows to navigate, enter to select").
					Options(profileOptions...).
					Filtering(true).
					Height(15).
					Value(&cfg.DevProfile),
			),
		).WithTheme(huh.ThemeCatppuccin())

		if err := devForm.Run(); err != nil {
			return nil, err
		}
		cfg.DevAccountID = "auto"
	}

	// Configure ops account if needed
	if numAccounts == "3" {
		fmt.Println()
		fmt.Println(accountHeaderStyle.Render(" 3. Operations Account (ops) "))
		fmt.Println(dimStyle.Render("   Used as the source account for ops→prod attack scenarios."))
		fmt.Println()

		opsForm := huh.NewForm(
			huh.NewGroup(
				huh.NewSelect[string]().
					Title("Select AWS profile for OPS account").
					Description("Type to filter, arrows to navigate, enter to select").
					Options(profileOptions...).
					Filtering(true).
					Height(15).
					Value(&cfg.OpsProfile),
			),
		).WithTheme(huh.ThemeCatppuccin())

		if err := opsForm.Run(); err != nil {
			return nil, err
		}
		cfg.OpsAccountID = "auto"
	}

	cfg.ProdAccountID = "auto"
	cfg.Initialized = true

	// Summary
	fmt.Println()
	summaryStyle := lipgloss.NewStyle().
		Bold(true).
		Foreground(lipgloss.Color("86"))
	fmt.Println(summaryStyle.Render("Configuration Summary"))
	fmt.Println(strings.Repeat("─", 50))

	labelStyle := lipgloss.NewStyle().Width(25).Foreground(lipgloss.Color("241"))
	valueStyle := lipgloss.NewStyle().Bold(true)

	fmt.Printf("%s %s\n", labelStyle.Render("Prod profile:"), valueStyle.Render(cfg.ProdProfile))
	if cfg.DevProfile != "" {
		fmt.Printf("%s %s\n", labelStyle.Render("Dev profile:"), valueStyle.Render(cfg.DevProfile))
	}
	if cfg.OpsProfile != "" {
		fmt.Printf("%s %s\n", labelStyle.Render("Ops profile:"), valueStyle.Render(cfg.OpsProfile))
	}

	// Mode description
	fmt.Println()
	switch numAccounts {
	case "1":
		fmt.Println(dimStyle.Render("Mode: Single-account (cross-account scenarios unavailable)"))
	case "2":
		fmt.Println(dimStyle.Render("Mode: 2 accounts (dev→prod cross-account scenarios available)"))
	case "3":
		fmt.Println(dimStyle.Render("Mode: 3 accounts (all cross-account scenarios available)"))
	}
	fmt.Println()

	return cfg, nil
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
			if strings.HasPrefix(name, "profile ") {
				name = strings.TrimPrefix(name, "profile ")
			}
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
