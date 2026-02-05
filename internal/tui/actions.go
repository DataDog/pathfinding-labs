package tui

import (
	"strings"

	"github.com/DataDog/pathfinding-labs/internal/scenarios"
)

// ActionsPane displays keyboard shortcuts and available actions
type ActionsPane struct {
	styles          *Styles
	scenario        *scenarios.Scenario
	enabled         bool
	deployed        bool
	showOnlyEnabled bool
	focusedPane     Pane // Which pane is currently focused
	envEnabled      bool // Selected environment enabled state
	envDeployed     bool // Selected environment deployed state
	width           int
	height          int
}

// NewActionsPane creates a new actions pane
func NewActionsPane(styles *Styles) *ActionsPane {
	return &ActionsPane{
		styles:      styles,
		focusedPane: PaneScenarios,
	}
}

// SetScenario updates the displayed scenario
func (a *ActionsPane) SetScenario(s *scenarios.Scenario, enabled, deployed bool) {
	a.scenario = s
	a.enabled = enabled
	a.deployed = deployed
}

// SetShowOnlyEnabled updates the enabled filter state for display
func (a *ActionsPane) SetShowOnlyEnabled(showOnly bool) {
	a.showOnlyEnabled = showOnly
}

// SetFocusedPane sets which pane is currently focused
func (a *ActionsPane) SetFocusedPane(pane Pane) {
	a.focusedPane = pane
}

// SetEnvironment updates the selected environment state
func (a *ActionsPane) SetEnvironment(enabled, deployed bool) {
	a.envEnabled = enabled
	a.envDeployed = deployed
}

// SetSize sets the pane dimensions
func (a *ActionsPane) SetSize(width, height int) {
	a.width = width
	a.height = height
}

// View renders the actions pane
func (a *ActionsPane) View() string {
	var sb strings.Builder

	sb.WriteString(a.styles.PanelTitle.Render("Shortcuts"))
	sb.WriteString("\n")

	// Navigation keys (always shown)
	sb.WriteString(a.styles.HelpKey.Render(" ↑↓"))
	sb.WriteString(a.styles.HelpDesc.Render(" navigate"))
	sb.WriteString("\n")

	sb.WriteString(a.styles.HelpKey.Render(" tab"))
	sb.WriteString(a.styles.HelpDesc.Render(" switch pane"))
	sb.WriteString("\n")

	// Pane-specific navigation hints
	if a.focusedPane == PaneScenarios {
		sb.WriteString(a.styles.HelpKey.Render(" ←→"))
		sb.WriteString(a.styles.HelpDesc.Render(" collapse"))
		sb.WriteString("\n")

		sb.WriteString(a.styles.HelpKey.Render(" /"))
		sb.WriteString(a.styles.HelpDesc.Render("  filter"))
		sb.WriteString("\n")

		// Toggle enabled only - show current state
		if a.showOnlyEnabled {
			sb.WriteString(a.styles.HelpKey.Render(" ."))
			sb.WriteString(a.styles.HelpDesc.Render("  show all"))
			sb.WriteString("\n")
		} else {
			sb.WriteString(a.styles.HelpKey.Render(" ."))
			sb.WriteString(a.styles.HelpDesc.Render("  enabled only"))
			sb.WriteString("\n")
		}
	}

	// Divider
	sb.WriteString(a.styles.ScenarioDisabled.Render(" ───────────"))
	sb.WriteString("\n")

	// Context-specific actions based on focused pane
	switch a.focusedPane {
	case PaneEnvironment:
		a.renderEnvironmentActions(&sb)
	case PaneScenarios:
		a.renderScenarioActions(&sb)
	case PaneDetails:
		sb.WriteString(a.styles.ScenarioDisabled.Render(" View only"))
		sb.WriteString("\n")
	}

	return a.wrapInPanel(sb.String())
}

func (a *ActionsPane) renderEnvironmentActions(sb *strings.Builder) {
	if a.envEnabled && a.envDeployed {
		sb.WriteString(a.styles.HelpKey.Render(" space"))
		sb.WriteString(a.styles.HelpDesc.Render(" disable"))
		sb.WriteString("\n")
		sb.WriteString(a.styles.ScenarioDisabled.Render(" (will destroy)"))
		sb.WriteString("\n")
	} else if a.envEnabled && !a.envDeployed {
		sb.WriteString(a.styles.HelpKey.Render(" space"))
		sb.WriteString(a.styles.HelpDesc.Render(" disable"))
		sb.WriteString("\n")
		sb.WriteString(a.styles.HelpKey.Render(" d"))
		sb.WriteString(a.styles.HelpDesc.Render("     deploy"))
		sb.WriteString("\n")
	} else if !a.envEnabled && a.envDeployed {
		sb.WriteString(a.styles.HelpKey.Render(" space"))
		sb.WriteString(a.styles.HelpDesc.Render(" enable"))
		sb.WriteString("\n")
		sb.WriteString(a.styles.HelpKey.Render(" d"))
		sb.WriteString(a.styles.HelpDesc.Render("     deploy (destroy)"))
		sb.WriteString("\n")
	} else {
		sb.WriteString(a.styles.HelpKey.Render(" space"))
		sb.WriteString(a.styles.HelpDesc.Render(" enable"))
		sb.WriteString("\n")
	}
}

func (a *ActionsPane) renderScenarioActions(sb *strings.Builder) {
	if a.scenario == nil {
		sb.WriteString(a.styles.ScenarioDisabled.Render(" Select scenario"))
		sb.WriteString("\n")
	} else if a.deployed {
		sb.WriteString(a.styles.HelpKey.Render(" space"))
		sb.WriteString(a.styles.HelpDesc.Render(" disable"))
		sb.WriteString("\n")
		if a.scenario.HasDemo() {
			sb.WriteString(a.styles.HelpKey.Render(" r"))
			sb.WriteString(a.styles.HelpDesc.Render("     run demo"))
			sb.WriteString("\n")
		}
		if a.scenario.HasCleanup() {
			sb.WriteString(a.styles.HelpKey.Render(" c"))
			sb.WriteString(a.styles.HelpDesc.Render("     cleanup"))
			sb.WriteString("\n")
		}
		sb.WriteString(a.styles.HelpKey.Render(" D"))
		sb.WriteString(a.styles.HelpDesc.Render("     destroy scenarios"))
		sb.WriteString("\n")
		sb.WriteString(a.styles.HelpKey.Render(" ^D"))
		sb.WriteString(a.styles.HelpDesc.Render("    destroy all"))
		sb.WriteString("\n")
	} else if a.enabled {
		sb.WriteString(a.styles.HelpKey.Render(" space"))
		sb.WriteString(a.styles.HelpDesc.Render(" disable"))
		sb.WriteString("\n")
		sb.WriteString(a.styles.HelpKey.Render(" d"))
		sb.WriteString(a.styles.HelpDesc.Render("     deploy"))
		sb.WriteString("\n")
	} else {
		sb.WriteString(a.styles.HelpKey.Render(" space"))
		sb.WriteString(a.styles.HelpDesc.Render(" enable"))
		sb.WriteString("\n")
	}
}

func (a *ActionsPane) wrapInPanel(content string) string {
	panelStyle := a.styles.Panel.Width(a.width - 2)
	return panelStyle.Render(content)
}
