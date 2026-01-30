package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"

	"github.com/DataDog/pathfinding-labs/internal/config"
)

// EnvironmentPane displays account configuration status
type EnvironmentPane struct {
	styles  *Styles
	config  *config.Config
	focused bool
	width   int
	height  int

	// Deployment status for each environment
	prodDeployed bool
	devDeployed  bool
	opsDeployed  bool
}

// NewEnvironmentPane creates a new environment pane
func NewEnvironmentPane(styles *Styles) *EnvironmentPane {
	return &EnvironmentPane{
		styles: styles,
	}
}

// SetConfig updates the configuration
func (e *EnvironmentPane) SetConfig(cfg *config.Config) {
	e.config = cfg
}

// SetDeploymentStatus updates the deployment status for each environment
func (e *EnvironmentPane) SetDeploymentStatus(prod, dev, ops bool) {
	e.prodDeployed = prod
	e.devDeployed = dev
	e.opsDeployed = ops
}

// SetFocused sets whether this pane is focused
func (e *EnvironmentPane) SetFocused(focused bool) {
	e.focused = focused
}

// SetSize sets the pane dimensions
func (e *EnvironmentPane) SetSize(width, height int) {
	e.width = width
	e.height = height
}

// View renders the environment pane
func (e *EnvironmentPane) View() string {
	var sb strings.Builder

	// Title
	titleStyle := e.styles.PanelTitle.Width(e.width - 4)
	sb.WriteString(titleStyle.Render("Environment"))
	sb.WriteString("\n")

	if e.config == nil {
		sb.WriteString(e.styles.EnvNotConfigured.Render("  No config"))
		return e.wrapInPanel(sb.String())
	}

	// Prod account (always shown)
	sb.WriteString(e.renderAccount("Prod", e.config.ProdAccountID, e.config.ProdProfile, e.prodDeployed))

	// Dev account (if configured)
	if e.config.DevAccountID != "" {
		sb.WriteString("\n")
		sb.WriteString(e.renderAccount("Dev", e.config.DevAccountID, e.config.DevProfile, e.devDeployed))
	}

	// Ops account (if configured)
	if e.config.OpsAccountID != "" {
		sb.WriteString("\n")
		sb.WriteString(e.renderAccount("Ops", e.config.OpsAccountID, e.config.OpsProfile, e.opsDeployed))
	}

	// Account mode
	sb.WriteString("\n\n")
	if e.config.IsMultiAccountMode() {
		sb.WriteString(e.styles.EnvConfigured.Render("Multi-account mode"))
	} else {
		sb.WriteString(e.styles.EnvNotConfigured.Render("Single-account mode"))
	}

	return e.wrapInPanel(sb.String())
}

func (e *EnvironmentPane) renderAccount(name, accountID, profile string, deployed bool) string {
	var sb strings.Builder

	if accountID == "" {
		indicator := e.styles.DisabledIndicator.Render()
		label := e.styles.EnvNotConfigured.Render(fmt.Sprintf("%s: not configured", name))
		sb.WriteString(fmt.Sprintf("%s %s", indicator, label))
		return sb.String()
	}

	// Determine indicator based on deployment status
	var indicator string
	if deployed {
		indicator = e.styles.EnabledIndicator.Render()
	} else {
		indicator = lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B")).Render("●")
	}

	// Account name and ID
	nameStyle := e.styles.EnvConfigured.Bold(true)
	sb.WriteString(fmt.Sprintf("%s %s\n", indicator, nameStyle.Render(name)))

	// Account ID (truncated if needed)
	displayID := accountID
	if len(displayID) > 12 {
		displayID = displayID[:12]
	}
	sb.WriteString(fmt.Sprintf("  %s\n", e.styles.DetailValue.Render(displayID)))

	// Profile
	profileLabel := fmt.Sprintf("  profile: %s", profile)
	if len(profileLabel) > e.width-6 {
		profileLabel = profileLabel[:e.width-9] + "..."
	}
	sb.WriteString(e.styles.EnvNotConfigured.Render(profileLabel))

	// Deployment status
	if deployed {
		sb.WriteString("\n")
		sb.WriteString(e.styles.EnvDeployed.Render("  deployed"))
	}

	return sb.String()
}

func (e *EnvironmentPane) wrapInPanel(content string) string {
	// Choose panel style based on focus
	panelStyle := e.styles.Panel
	if e.focused {
		panelStyle = e.styles.PanelFocused
	}

	panelStyle = panelStyle.Width(e.width - 2)
	return panelStyle.Render(content)
}
