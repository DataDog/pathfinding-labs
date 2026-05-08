package tui

import (
	"strings"

	"github.com/DataDog/pathfinding-labs/internal/scenarios"
)

// ActionsPane displays keyboard shortcuts and available actions
type ActionsPane struct {
	styles             *Styles
	scenario           *scenarios.Scenario
	enabled            bool
	deployed           bool
	demoActive         bool
	demoActiveCount    int // total number of scenarios with active demos
	showOnlyEnabled    bool
	showOnlyDemoActive bool
	focusedPane        Pane // Which pane is currently focused
	envEnabled         bool // Selected environment enabled state
	envDeployed        bool // Selected environment deployed state
	hasCreds           bool // Selected scenario has accessible credentials
	width              int
	height             int
}

// NewActionsPane creates a new actions pane
func NewActionsPane(styles *Styles) *ActionsPane {
	return &ActionsPane{
		styles:      styles,
		focusedPane: PaneScenarios,
	}
}

// SetScenario updates the displayed scenario
func (a *ActionsPane) SetScenario(s *scenarios.Scenario, enabled, deployed, demoActive bool) {
	a.scenario = s
	a.enabled = enabled
	a.deployed = deployed
	a.demoActive = demoActive
}

// SetDemoActiveCount updates the total demo-active count
func (a *ActionsPane) SetDemoActiveCount(count int) {
	a.demoActiveCount = count
}

// SetShowOnlyDemoActive updates the demo-active filter state for display
func (a *ActionsPane) SetShowOnlyDemoActive(showOnly bool) {
	a.showOnlyDemoActive = showOnly
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

// SetHasCreds updates whether the selected scenario has accessible credentials
func (a *ActionsPane) SetHasCreds(hasCreds bool) {
	a.hasCreds = hasCreds
}

// SetSize sets the pane dimensions
func (a *ActionsPane) SetSize(width, height int) {
	a.width = width
	a.height = height
}

// View renders the actions pane
func (a *ActionsPane) View() string {
	var sb strings.Builder

	sb.WriteString(a.styles.PanelTitle.Render("Key bindings"))
	sb.WriteString("\n\n")

	// Navigation keys (always shown)
	sb.WriteString(a.styles.HelpKey.Render(" ↑↓"))
	sb.WriteString(a.styles.HelpDesc.Render("  navigate"))
	sb.WriteString("\n")

	sb.WriteString(a.styles.HelpKey.Render(" tab"))
	sb.WriteString(a.styles.HelpDesc.Render(" switch pane"))
	sb.WriteString("\n")

	// Pane-specific navigation hints
	if a.focusedPane == PaneScenarios {
		sb.WriteString(a.styles.HelpKey.Render(" ←→"))
		sb.WriteString(a.styles.HelpDesc.Render("  collapse/expand"))
		sb.WriteString("\n")

		sb.WriteString(a.styles.HelpKey.Render(" ,"))
		sb.WriteString(a.styles.HelpDesc.Render("   collapse/expand all"))
		sb.WriteString("\n")

		sb.WriteString(a.styles.HelpKey.Render(" /"))
		sb.WriteString(a.styles.HelpDesc.Render("   filter"))
		sb.WriteString("\n")

		// Toggle enabled only - show current state
		if a.showOnlyEnabled {
			sb.WriteString(a.styles.HelpKey.Render(" ."))
			sb.WriteString(a.styles.HelpDesc.Render("   show all scenarios"))
			sb.WriteString("\n")
		} else {
			sb.WriteString(a.styles.HelpKey.Render(" ."))
			sb.WriteString(a.styles.HelpDesc.Render("   enabled scenarios only"))
			sb.WriteString("\n")
		}

		// Toggle demo-active only
		if a.showOnlyDemoActive {
			sb.WriteString(a.styles.HelpKey.Render(" !"))
			sb.WriteString(a.styles.HelpDesc.Render("   show all scenarios"))
			sb.WriteString("\n")
		} else {
			sb.WriteString(a.styles.HelpKey.Render(" !"))
			sb.WriteString(a.styles.HelpDesc.Render("   demo active only"))
			sb.WriteString("\n")
		}
	}

	// Help - always available
	sb.WriteString(a.styles.HelpKey.Render(" ?"))
	sb.WriteString(a.styles.HelpDesc.Render("   show all key bindings"))
	sb.WriteString("\n")

	// Divider — only when context-specific actions follow. The PaneScenarios
	// branch intentionally renders nothing, so showing a divider would leave a
	// trailing horizontal rule with no content under it.
	if a.focusedPane != PaneScenarios {
		sb.WriteString(a.styles.ScenarioDisabled.Render(" ───────────"))
		sb.WriteString("\n")
	}

	// Context-specific actions based on focused pane
	switch a.focusedPane {
	case PaneEnvironment:
		a.renderEnvironmentActions(&sb)
	case PaneDetails:
		if a.hasCreds {
			sb.WriteString(a.styles.HelpKey.Render(" x"))
			sb.WriteString(a.styles.HelpDesc.Render("   spawn shell with creds"))
			sb.WriteString("\n")
			sb.WriteString(a.styles.HelpKey.Render(" y"))
			sb.WriteString(a.styles.HelpDesc.Render("   copy as env vars"))
			sb.WriteString("\n")
			sb.WriteString(a.styles.HelpKey.Render(" Y"))
			sb.WriteString(a.styles.HelpDesc.Render("   copy as credentials file"))
			sb.WriteString("\n")
		} else {
			sb.WriteString(a.styles.ScenarioDisabled.Render(" View only"))
			sb.WriteString("\n")
		}
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
		sb.WriteString(a.styles.HelpKey.Render(" a"))
		sb.WriteString(a.styles.HelpDesc.Render("     apply"))
		sb.WriteString("\n")
	} else if !a.envEnabled && a.envDeployed {
		sb.WriteString(a.styles.HelpKey.Render(" space"))
		sb.WriteString(a.styles.HelpDesc.Render(" enable"))
		sb.WriteString("\n")
		sb.WriteString(a.styles.HelpKey.Render(" a"))
		sb.WriteString(a.styles.HelpDesc.Render("     apply (destroy)"))
		sb.WriteString("\n")
	} else {
		sb.WriteString(a.styles.HelpKey.Render(" space"))
		sb.WriteString(a.styles.HelpDesc.Render(" enable"))
		sb.WriteString("\n")
	}

	// Settings hint - always available in environment pane
	sb.WriteString(a.styles.HelpKey.Render(" s"))
	sb.WriteString(a.styles.HelpDesc.Render("     settings (profiles, budget)"))
	sb.WriteString("\n")
}


func (a *ActionsPane) wrapInPanel(content string) string {
	panelStyle := a.styles.Panel.Width(a.width - 2)
	return panelStyle.Render(content)
}
