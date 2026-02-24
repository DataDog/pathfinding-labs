package tui

import (
	"github.com/charmbracelet/lipgloss"
)

// Color palette
var (
	colorPrimary    = lipgloss.Color("#7C3AED") // Purple
	colorSecondary  = lipgloss.Color("#06B6D4") // Cyan
	colorSuccess    = lipgloss.Color("#10B981") // Green
	colorWarning    = lipgloss.Color("#F59E0B") // Yellow
	colorError      = lipgloss.Color("#EF4444") // Red
	colorDim        = lipgloss.Color("#6B7280") // Gray
	colorText       = lipgloss.Color("#F3F4F6") // Light gray
	colorBackground = lipgloss.Color("#1F2937") // Dark gray
	colorBorder     = lipgloss.Color("#374151") // Border gray
	colorHighlight  = lipgloss.Color("#3B82F6") // Blue
)

// Styles holds all the lipgloss styles for the TUI
type Styles struct {
	// Base styles
	App           lipgloss.Style
	Title         lipgloss.Style
	Subtitle      lipgloss.Style
	StatusBar     lipgloss.Style
	StatusBarText lipgloss.Style

	// Panel styles
	Panel         lipgloss.Style
	PanelTitle    lipgloss.Style
	PanelFocused  lipgloss.Style
	PanelContent  lipgloss.Style
	PanelSelected lipgloss.Style

	// Environment pane
	EnvConfigured    lipgloss.Style
	EnvNotConfigured lipgloss.Style
	EnvDeployed      lipgloss.Style

	// Category pane
	CategorySelected lipgloss.Style
	CategoryNormal   lipgloss.Style

	// Scenario list
	ScenarioEnabled  lipgloss.Style
	ScenarioDisabled lipgloss.Style
	ScenarioDeployed lipgloss.Style
	ScenarioSelected lipgloss.Style
	ScenarioCursor   lipgloss.Style
	ScenarioID       lipgloss.Style
	ScenarioName     lipgloss.Style
	ScenarioCount    lipgloss.Style
	CategoryHeader   lipgloss.Style
	CostNonZero      lipgloss.Style

	// Details pane
	DetailLabel     lipgloss.Style
	DetailValue     lipgloss.Style
	DetailSection   lipgloss.Style
	DetailHighlight lipgloss.Style
	CredentialKey   lipgloss.Style
	CredentialValue lipgloss.Style

	// Overlay
	Overlay       lipgloss.Style
	OverlayTitle  lipgloss.Style
	OverlayText   lipgloss.Style
	OverlayDimmed lipgloss.Style

	// Indicators
	EnabledIndicator        lipgloss.Style
	DisabledIndicator       lipgloss.Style
	DeployedIndicator       lipgloss.Style
	PendingDeployIndicator  lipgloss.Style
	PendingDestroyIndicator lipgloss.Style
	PendingDeployLabel      lipgloss.Style
	PendingDestroyLabel     lipgloss.Style
	DemoActiveIndicator     lipgloss.Style
	DemoActiveLabel         lipgloss.Style

	// Help
	HelpKey  lipgloss.Style
	HelpDesc lipgloss.Style
	HelpSep  lipgloss.Style

	// Filter
	FilterPrompt lipgloss.Style
	FilterInput  lipgloss.Style
}

// DefaultStyles returns the default style configuration
func DefaultStyles() *Styles {
	s := &Styles{}

	// Base styles
	s.App = lipgloss.NewStyle()
	s.Title = lipgloss.NewStyle().
		Bold(true).
		Foreground(colorText)
	s.Subtitle = lipgloss.NewStyle().
		Foreground(colorDim)
	s.StatusBar = lipgloss.NewStyle().
		Background(lipgloss.Color("#1F2937")).
		Padding(0, 1)
	s.StatusBarText = lipgloss.NewStyle().
		Foreground(colorDim)

	// Panel styles
	s.Panel = lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(colorBorder).
		Padding(0, 1)
	s.PanelTitle = lipgloss.NewStyle().
		Bold(true).
		Foreground(colorSecondary) // Cyan for visual pop
	s.PanelFocused = lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(colorPrimary).
		Padding(0, 1)
	s.PanelContent = lipgloss.NewStyle().
		Foreground(colorText)
	s.PanelSelected = lipgloss.NewStyle().
		Background(colorPrimary).
		Foreground(colorText)

	// Environment pane
	s.EnvConfigured = lipgloss.NewStyle().
		Foreground(colorSuccess)
	s.EnvNotConfigured = lipgloss.NewStyle().
		Foreground(colorDim)
	s.EnvDeployed = lipgloss.NewStyle().
		Foreground(colorSuccess).
		Bold(true)

	// Category pane
	s.CategorySelected = lipgloss.NewStyle().
		Bold(true).
		Foreground(colorPrimary)
	s.CategoryNormal = lipgloss.NewStyle().
		Foreground(colorText)

	// Scenario list
	s.ScenarioEnabled = lipgloss.NewStyle().
		Foreground(colorSuccess)
	s.ScenarioDisabled = lipgloss.NewStyle().
		Foreground(colorDim)
	s.ScenarioDeployed = lipgloss.NewStyle().
		Foreground(colorSuccess).
		Bold(true)
	s.ScenarioSelected = lipgloss.NewStyle().
		Background(lipgloss.Color("#374151")).
		Foreground(colorText)
	s.ScenarioCursor = lipgloss.NewStyle().
		Foreground(colorPrimary).
		Bold(true)
	s.ScenarioID = lipgloss.NewStyle().
		Foreground(colorSecondary)
	s.ScenarioName = lipgloss.NewStyle().
		Foreground(colorText)
	s.ScenarioCount = lipgloss.NewStyle().
		Foreground(colorDim)
	s.CategoryHeader = lipgloss.NewStyle().
		Bold(true).
		Foreground(colorText).
		MarginTop(1)
	s.CostNonZero = lipgloss.NewStyle().
		Foreground(colorWarning) // Orange to match running cost

	// Details pane
	s.DetailLabel = lipgloss.NewStyle().
		Foreground(colorDim).
		Width(12)
	s.DetailValue = lipgloss.NewStyle().
		Foreground(colorText)
	s.DetailSection = lipgloss.NewStyle().
		Bold(true).
		Foreground(colorSecondary).
		MarginTop(1)
	s.DetailHighlight = lipgloss.NewStyle().
		Foreground(colorHighlight)
	s.CredentialKey = lipgloss.NewStyle().
		Foreground(colorWarning)
	s.CredentialValue = lipgloss.NewStyle().
		Foreground(colorText)

	// Overlay
	s.Overlay = lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(colorPrimary).
		Padding(1, 2)
	s.OverlayTitle = lipgloss.NewStyle().
		Bold(true).
		Foreground(colorText).
		MarginBottom(1)
	s.OverlayText = lipgloss.NewStyle().
		Foreground(colorText)
	s.OverlayDimmed = lipgloss.NewStyle().
		Foreground(colorDim)

	// Indicators
	s.EnabledIndicator = lipgloss.NewStyle().
		Foreground(colorSuccess).
		SetString("●")
	s.DisabledIndicator = lipgloss.NewStyle().
		Foreground(colorDim).
		SetString("○")
	s.DeployedIndicator = lipgloss.NewStyle().
		Foreground(colorSuccess).
		SetString("✓")
	s.PendingDeployIndicator = lipgloss.NewStyle().
		Foreground(colorWarning).
		SetString("●")
	s.PendingDestroyIndicator = lipgloss.NewStyle().
		Foreground(colorError).
		SetString("●")
	s.PendingDeployLabel = lipgloss.NewStyle().
		Foreground(colorWarning)
	s.PendingDestroyLabel = lipgloss.NewStyle().
		Foreground(colorError)
	s.DemoActiveIndicator = lipgloss.NewStyle().
		Foreground(colorWarning).
		SetString("\u26a0")
	s.DemoActiveLabel = lipgloss.NewStyle().
		Foreground(colorWarning)

	// Help
	s.HelpKey = lipgloss.NewStyle().
		Foreground(colorSecondary)
	s.HelpDesc = lipgloss.NewStyle().
		Foreground(colorDim)
	s.HelpSep = lipgloss.NewStyle().
		Foreground(colorDim).
		SetString(" · ")

	// Filter
	s.FilterPrompt = lipgloss.NewStyle().
		Foreground(colorSecondary)
	s.FilterInput = lipgloss.NewStyle().
		Foreground(colorText)

	return s
}
