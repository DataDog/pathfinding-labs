package tui

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/lipgloss"

	"github.com/DataDog/pathfinding-labs/internal/config"
)

// Environment represents an environment that can be selected
type Environment struct {
	Name      string // "prod", "dev", "ops"
	Label     string // "Prod", "Dev", "Ops"
	AccountID string
	Profile   string
	Enabled   bool
	Deployed  bool
}

// EnvironmentPane displays account configuration status
type EnvironmentPane struct {
	styles  *Styles
	config  *config.Config
	focused bool
	loading bool
	width   int
	height  int

	// Environments list (dynamically built based on config)
	environments []Environment
	selected     int // Currently selected index

	// Deployment status for each environment
	prodDeployed bool
	devDeployed  bool
	opsDeployed  bool

	// Enabled status for each environment
	prodEnabled bool
	devEnabled  bool
	opsEnabled  bool

	// Derived account IDs (from terraform outputs after first apply)
	derivedProdAccountID string
	derivedDevAccountID  string
	derivedOpsAccountID  string
}

// NewEnvironmentPane creates a new environment pane
func NewEnvironmentPane(styles *Styles) *EnvironmentPane {
	return &EnvironmentPane{
		styles:      styles,
		prodEnabled: true, // Prod enabled by default
		loading:     true, // Start in loading state
	}
}

// SetLoading sets the loading state
func (e *EnvironmentPane) SetLoading(loading bool) {
	e.loading = loading
}

// SetConfig updates the configuration
func (e *EnvironmentPane) SetConfig(cfg *config.Config) {
	e.config = cfg
	e.rebuildEnvironments()
}

// SetDeploymentStatus updates the deployment status for each environment
func (e *EnvironmentPane) SetDeploymentStatus(prod, dev, ops bool) {
	e.prodDeployed = prod
	e.devDeployed = dev
	e.opsDeployed = ops
	e.rebuildEnvironments()
}

// SetEnabledStatus updates the enabled status for each environment
func (e *EnvironmentPane) SetEnabledStatus(prod, dev, ops bool) {
	e.prodEnabled = prod
	e.devEnabled = dev
	e.opsEnabled = ops
	e.rebuildEnvironments()
}

// SetDerivedAccountIDs sets the account IDs derived from terraform outputs
func (e *EnvironmentPane) SetDerivedAccountIDs(prod, dev, ops string) {
	e.derivedProdAccountID = prod
	e.derivedDevAccountID = dev
	e.derivedOpsAccountID = ops
	e.rebuildEnvironments()
}

// rebuildEnvironments rebuilds the environments list based on current config
func (e *EnvironmentPane) rebuildEnvironments() {
	e.environments = nil

	if e.config == nil {
		return
	}

	// Helper to get best account ID (prefer derived, fall back to config, show placeholder if "auto" or empty)
	getAccountID := func(derived, fromConfig string) string {
		if derived != "" {
			return derived
		}
		if fromConfig != "" && fromConfig != "auto" {
			return fromConfig
		}
		return "" // Will show "Pending first deploy" in the UI
	}

	// Prod is always available
	e.environments = append(e.environments, Environment{
		Name:      "prod",
		Label:     "Prod",
		AccountID: getAccountID(e.derivedProdAccountID, ""),
		Profile:   e.config.AWS.Prod.Profile,
		Enabled:   e.prodEnabled,
		Deployed:  e.prodDeployed,
	})

	// Dev (if configured)
	if e.config.AWS.Dev.Profile != "" {
		e.environments = append(e.environments, Environment{
			Name:      "dev",
			Label:     "Dev",
			AccountID: getAccountID(e.derivedDevAccountID, ""),
			Profile:   e.config.AWS.Dev.Profile,
			Enabled:   e.devEnabled,
			Deployed:  e.devDeployed,
		})
	}

	// Ops (if configured)
	if e.config.AWS.Ops.Profile != "" {
		e.environments = append(e.environments, Environment{
			Name:      "ops",
			Label:     "Ops",
			AccountID: getAccountID(e.derivedOpsAccountID, ""),
			Profile:   e.config.AWS.Ops.Profile,
			Enabled:   e.opsEnabled,
			Deployed:  e.opsDeployed,
		})
	}

	// Ensure selected is within bounds
	if e.selected >= len(e.environments) {
		e.selected = len(e.environments) - 1
	}
	if e.selected < 0 {
		e.selected = 0
	}
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

// MoveUp moves selection up
func (e *EnvironmentPane) MoveUp() {
	if e.selected > 0 {
		e.selected--
	}
}

// MoveDown moves selection down
func (e *EnvironmentPane) MoveDown() {
	if e.selected < len(e.environments)-1 {
		e.selected++
	}
}

// Selected returns the currently selected environment
func (e *EnvironmentPane) Selected() *Environment {
	if len(e.environments) == 0 || e.selected >= len(e.environments) {
		return nil
	}
	return &e.environments[e.selected]
}

// Toggle toggles the enabled state of the selected environment
// Returns the environment name and new enabled state
func (e *EnvironmentPane) Toggle() (string, bool) {
	if len(e.environments) == 0 || e.selected >= len(e.environments) {
		return "", false
	}

	env := &e.environments[e.selected]
	env.Enabled = !env.Enabled

	// Update internal state
	switch env.Name {
	case "prod":
		e.prodEnabled = env.Enabled
	case "dev":
		e.devEnabled = env.Enabled
	case "ops":
		e.opsEnabled = env.Enabled
	}

	return env.Name, env.Enabled
}

// HasPendingChanges returns true if any environment's enabled state differs from deployed state
func (e *EnvironmentPane) HasPendingChanges() bool {
	for _, env := range e.environments {
		if env.Enabled != env.Deployed {
			return true
		}
	}
	return false
}

// GetEnabledCount returns the number of enabled environments
func (e *EnvironmentPane) GetEnabledCount() int {
	count := 0
	for _, env := range e.environments {
		if env.Enabled {
			count++
		}
	}
	return count
}

// GetDeployedCount returns the number of deployed environments
func (e *EnvironmentPane) GetDeployedCount() int {
	count := 0
	for _, env := range e.environments {
		if env.Deployed {
			count++
		}
	}
	return count
}

// View renders the environment pane
func (e *EnvironmentPane) View() string {
	var sb strings.Builder

	// Title with account mode
	titleStyle := e.styles.PanelTitle
	dimStyle := e.styles.EnvNotConfigured

	// Calculate available width for mode text (account for panel padding/borders)
	availableWidth := e.width - 4 // panel padding
	baseTitle := "Environments"

	// Determine mode text based on available space
	var modeText string
	if e.config != nil && e.config.IsMultiAccountMode() {
		fullText := " (Multi-account mode)"
		shortText := " (multi)"
		if len(baseTitle)+len(fullText) <= availableWidth {
			modeText = fullText
		} else {
			modeText = shortText
		}
	} else {
		fullText := " (Single-account mode)"
		shortText := " (single)"
		if len(baseTitle)+len(fullText) <= availableWidth {
			modeText = fullText
		} else {
			modeText = shortText
		}
	}

	sb.WriteString(titleStyle.Render(baseTitle))
	sb.WriteString(dimStyle.Render(modeText))
	sb.WriteString("\n\n")

	if e.loading {
		sb.WriteString(e.styles.EnvNotConfigured.Render("  Loading..."))
		return e.wrapInPanel(sb.String())
	}

	if e.config == nil {
		sb.WriteString(e.styles.EnvNotConfigured.Render("  No config"))
		return e.wrapInPanel(sb.String())
	}

	// Render each environment
	for i, env := range e.environments {
		if i > 0 {
			sb.WriteString("\n")
		}
		sb.WriteString(e.renderEnvironment(env, i == e.selected))
	}

	return e.wrapInPanel(sb.String())
}

func (e *EnvironmentPane) renderEnvironment(env Environment, isSelected bool) string {
	var sb strings.Builder

	// Selection indicator (only when focused)
	selectionPrefix := "  "
	if e.focused && isSelected {
		selectionPrefix = "> "
	}

	// Status indicator based on enabled and deployed state
	var indicator string
	if env.Enabled && env.Deployed {
		indicator = e.styles.EnabledIndicator.Render() // Green - enabled and deployed
	} else if env.Enabled && !env.Deployed {
		indicator = lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B")).Render("●") // Yellow - enabled but not deployed
	} else if !env.Enabled && env.Deployed {
		indicator = lipgloss.NewStyle().Foreground(lipgloss.Color("#EF4444")).Render("●") // Red - disabled but still deployed
	} else {
		indicator = e.styles.DisabledIndicator.Render() // Gray - disabled and not deployed
	}

	// Environment name with selection highlight
	var nameStyle lipgloss.Style
	if env.Enabled {
		nameStyle = e.styles.EnvConfigured.Bold(true)
	} else {
		nameStyle = e.styles.EnvNotConfigured
	}

	if e.focused && isSelected {
		nameStyle = nameStyle.Reverse(true)
	}

	// Status text for the name line
	var statusText string
	var statusStyle lipgloss.Style
	if env.Enabled && env.Deployed {
		statusText = "deployed"
		statusStyle = e.styles.EnvDeployed
	} else if env.Enabled && !env.Deployed {
		statusText = "pending deploy"
		statusStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#F59E0B"))
	} else if !env.Enabled && env.Deployed {
		statusText = "pending destroy"
		statusStyle = lipgloss.NewStyle().Foreground(lipgloss.Color("#EF4444"))
	} else {
		statusText = "disabled"
		statusStyle = e.styles.EnvNotConfigured
	}

	// Name line with status: "● Prod · deployed"
	dotSeparator := e.styles.EnvNotConfigured.Render(" · ")
	sb.WriteString(fmt.Sprintf("%s%s %s%s%s\n", selectionPrefix, indicator, nameStyle.Render(env.Label), dotSeparator, statusStyle.Render(statusText)))

	// Account ID line (formatted like profile line)
	displayID := env.AccountID
	if displayID == "" {
		displayID = "(pending)"
	} else if len(displayID) > 12 {
		displayID = displayID[:12]
	}
	accountLabel := fmt.Sprintf("    Account Id: %s", displayID)
	sb.WriteString(e.styles.EnvNotConfigured.Render(accountLabel))
	sb.WriteString("\n")

	// Profile line
	profileLabel := fmt.Sprintf("    Profile: %s", env.Profile)
	if len(profileLabel) > e.width-6 {
		profileLabel = profileLabel[:e.width-9] + "..."
	}
	sb.WriteString(e.styles.EnvNotConfigured.Render(profileLabel))

	return sb.String()
}

func (e *EnvironmentPane) wrapInPanel(content string) string {
	// Choose panel style based on focus
	panelStyle := e.styles.Panel
	if e.focused {
		panelStyle = e.styles.PanelFocused
	}

	// Set both width and height to keep the panel size constant
	panelStyle = panelStyle.Width(e.width - 2).Height(e.height - 2)
	return panelStyle.Render(content)
}
