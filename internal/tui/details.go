package tui

import (
	"fmt"
	"path/filepath"
	"strings"

	"github.com/DataDog/pathfinding-labs/internal/scenarios"
	"github.com/DataDog/pathfinding-labs/internal/terraform"
	"github.com/charmbracelet/lipgloss"
)

// hyperlink creates a clickable terminal hyperlink using OSC 8 escape sequence
// Works in modern terminals like iTerm2, GNOME Terminal, Windows Terminal, etc.
func hyperlink(url, text string) string {
	return fmt.Sprintf("\x1b]8;;%s\x07%s\x1b]8;;\x07", url, text)
}

// DetailsPane displays detailed information about the selected scenario
type DetailsPane struct {
	styles       *Styles
	scenario     *scenarios.Scenario
	enabled      bool
	deployed     bool
	demoActive   bool
	creds        *terraform.Credentials
	resources    []string          // ARNs of deployed resources
	configValues map[string]string // Per-scenario config values (key -> value)
	focused      bool
	width        int
	height       int
	scroll       int
}

// NewDetailsPane creates a new details pane
func NewDetailsPane(styles *Styles) *DetailsPane {
	return &DetailsPane{
		styles: styles,
	}
}

// SetScenario updates the displayed scenario
func (d *DetailsPane) SetScenario(s *scenarios.Scenario, enabled, deployed, demoActive bool) {
	d.scenario = s
	d.enabled = enabled
	d.deployed = deployed
	d.demoActive = demoActive
	d.scroll = 0
}

// SetConfigValues sets the per-scenario config values to display
func (d *DetailsPane) SetConfigValues(vals map[string]string) {
	d.configValues = vals
}

// SetCredentials sets the credentials for the displayed scenario
func (d *DetailsPane) SetCredentials(creds *terraform.Credentials) {
	d.creds = creds
}

// ClearCredentials clears the credentials
func (d *DetailsPane) ClearCredentials() {
	d.creds = nil
}

// HasCreds returns true when the scenario is deployed and credentials are available.
func (d *DetailsPane) HasCreds() bool {
	return d.deployed && d.creds != nil && d.creds.AccessKeyID != ""
}

// Creds returns the current credentials (may be nil).
func (d *DetailsPane) Creds() *terraform.Credentials {
	return d.creds
}

// SetResources sets the deployed resource ARNs for the displayed scenario
func (d *DetailsPane) SetResources(resources []string) {
	d.resources = resources
}

// ClearResources clears the resources
func (d *DetailsPane) ClearResources() {
	d.resources = nil
}

// SetFocused sets whether this pane is focused
func (d *DetailsPane) SetFocused(focused bool) {
	d.focused = focused
}

// SetSize sets the pane dimensions
func (d *DetailsPane) SetSize(width, height int) {
	d.width = width
	d.height = height
	d.clampScroll()
}

// clampScroll ensures scroll position is valid for current content and size
func (d *DetailsPane) clampScroll() {
	if d.scenario == nil {
		d.scroll = 0
		return
	}
	contentLines := d.buildContent()
	visible := d.visibleRows()
	if visible < 1 {
		visible = 1
	}
	maxScroll := len(contentLines) - visible
	if maxScroll < 0 {
		maxScroll = 0
	}
	if d.scroll > maxScroll {
		d.scroll = maxScroll
	}
	if d.scroll < 0 {
		d.scroll = 0
	}
}

// ScrollUp scrolls the content up
func (d *DetailsPane) ScrollUp() {
	if d.scroll > 0 {
		d.scroll--
	}
}

// ScrollDown scrolls the content down
func (d *DetailsPane) ScrollDown() {
	d.scroll++
}

// PageUp scrolls up by a page
func (d *DetailsPane) PageUp() {
	pageSize := d.visibleRows()
	if pageSize < 1 {
		pageSize = 1
	}
	d.scroll -= pageSize
	if d.scroll < 0 {
		d.scroll = 0
	}
}

// PageDown scrolls down by a page
func (d *DetailsPane) PageDown() {
	pageSize := d.visibleRows()
	if pageSize < 1 {
		pageSize = 1
	}
	d.scroll += pageSize
}

// GoToTop scrolls to the top
func (d *DetailsPane) GoToTop() {
	d.scroll = 0
}

// GoToBottom scrolls to the bottom
func (d *DetailsPane) GoToBottom() {
	contentLines := d.buildContent()
	visible := d.visibleRows()
	maxScroll := len(contentLines) - visible
	if maxScroll < 0 {
		maxScroll = 0
	}
	d.scroll = maxScroll
}

// visibleRows returns the number of content rows that fit in the panel
func (d *DetailsPane) visibleRows() int {
	// Account for panel borders and title (same as scenarios pane)
	return d.height - 6
}

// buildContent builds the full content as a slice of lines
func (d *DetailsPane) buildContent() []string {
	var lines []string

	// Section header style without MarginTop (for windowed content)
	sectionStyle := lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("#06B6D4"))

	if d.scenario == nil {
		lines = append(lines, "")
		lines = append(lines, d.styles.DetailLabel.Render("Select a scenario"))
		return lines
	}

	contentWidth := d.width - 6
	if contentWidth < 20 {
		contentWidth = 20
	}

	// Long Name (truncated if needed) — use Title if set, fall back to Name
	name := d.scenario.Title
	if name == "" {
		name = d.scenario.Name
	}
	if len(name) > contentWidth-11 {
		name = name[:contentWidth-14] + "..."
	}
	lines = append(lines, d.styles.DetailLabel.Render("Long Name  ")+d.styles.DetailValue.Render(name))

	// Short Name (ID)
	lines = append(lines, d.styles.DetailLabel.Render("Short Name ")+d.styles.DetailHighlight.Bold(true).Render(d.scenario.UniqueID()))

	// Status with color - show pending states
	var statusLine string
	statusLine = d.styles.DetailLabel.Render("Status     ")
	if d.enabled && d.deployed {
		statusLine += d.styles.EnvDeployed.Render("● Deployed")
	} else if d.enabled && !d.deployed {
		statusLine += d.styles.PendingDeployIndicator.Render() + d.styles.PendingDeployLabel.Render(" [Enablement pending apply]")
	} else if !d.enabled && d.deployed {
		statusLine += d.styles.PendingDestroyIndicator.Render() + d.styles.PendingDestroyLabel.Render(" [Disablement pending apply]")
	} else {
		statusLine += d.styles.ScenarioDisabled.Render("○ Disabled")
	}
	lines = append(lines, statusLine)

	// Demo active warning
	if d.demoActive {
		demoLine := d.styles.DetailLabel.Render("Demo       ") + d.styles.DemoActiveLabel.Render("\u26a0 Active \u2014 run cleanup to remove artifacts")
		lines = append(lines, demoLine)
	}

	lines = append(lines, "") // blank line

	// Metadata fields
	lines = append(lines, d.styles.DetailLabel.Render("Category  ")+d.styles.DetailValue.Render(d.scenario.CategoryShort()))
	lines = append(lines, d.styles.DetailLabel.Render("Idle Cost ")+d.styles.DetailValue.Render(d.scenario.CostEstimate))

	// Links — labs guide is always present; the pathfinding.cloud path
	// reference appears alongside it when the scenario carries a path ID.
	// Slug rule mirrors pathfinding.cloud/scripts/generate-labs-json.py:
	// "{id}" for to-admin/none, "{id}-to-bucket" for to-bucket, directory
	// basename when no path ID is set.
	slug := d.scenario.PathfindingCloudID
	if slug != "" && d.scenario.Target == "to-bucket" {
		slug += "-to-bucket"
	}
	if slug == "" {
		slug = filepath.Base(d.scenario.DirPath)
	}
	labsURL := fmt.Sprintf("https://pathfinding.cloud/labs/%s", slug)
	lines = append(lines, d.styles.DetailLabel.Render("Lab Guide  ")+hyperlink(labsURL, d.styles.DetailHighlight.Render(labsURL)))
	if d.scenario.PathfindingCloudID != "" {
		pathURL := fmt.Sprintf("https://pathfinding.cloud/paths/%s", d.scenario.PathfindingCloudID)
		lines = append(lines, d.styles.DetailLabel.Render("Path  ")+hyperlink(pathURL, d.styles.DetailHighlight.Render(pathURL)))
	}

	// Description
	lines = append(lines, "")
	lines = append(lines, sectionStyle.Render("Description"))
	if d.scenario.Description != "" {
		wrapped := d.wordWrap(d.scenario.Description, contentWidth)
		for _, wl := range strings.Split(wrapped, "\n") {
			lines = append(lines, d.styles.DetailValue.Render(wl))
		}
	} else {
		lines = append(lines, d.styles.ScenarioDisabled.Render("No description available"))
	}

	// Attack Path Summary
	if d.scenario.AttackPath.Summary != "" {
		lines = append(lines, "")
		lines = append(lines, sectionStyle.Render("Attack Path"))
		wrapped := d.wordWrap(d.scenario.AttackPath.Summary, contentWidth)
		for _, wl := range strings.Split(wrapped, "\n") {
			lines = append(lines, d.styles.DetailValue.Render(wl))
		}
	}

	// Required Permissions
	if len(d.scenario.Permissions.Required) > 0 {
		lines = append(lines, "")
		lines = append(lines, sectionStyle.Render("Required Permissions"))
		for _, entry := range d.scenario.Permissions.Required {
			for _, perm := range entry.Permissions {
				permText := perm.Permission
				if len(permText) > contentWidth-2 {
					permText = permText[:contentWidth-5] + "..."
				}
				lines = append(lines, d.styles.DetailValue.Render("  "+permText))
			}
		}
	}

	// Required Preconditions
	if len(d.scenario.RequiredPreconditions) > 0 {
		lines = append(lines, "")
		lines = append(lines, sectionStyle.Render("Required Preconditions"))
		for _, precond := range d.scenario.RequiredPreconditions {
			var label string
			if precond.Resource != "" {
				label = precond.Resource + ": " + precond.Description
			} else {
				label = "[" + precond.Type + "] " + precond.Description
			}
			wrapped := d.wordWrap(label, contentWidth-4)
			first := true
			for _, wl := range strings.Split(wrapped, "\n") {
				if first {
					lines = append(lines, d.styles.DetailValue.Render("  • "+wl))
					first = false
				} else {
					lines = append(lines, d.styles.DetailValue.Render("    "+wl))
				}
			}
		}
	}

	// Per-scenario configuration (if declared in scenario.yaml)
	if d.scenario.HasConfig() {
		lines = append(lines, "")
		lines = append(lines, sectionStyle.Render("Configuration"))
		for _, cfgKey := range d.scenario.Config {
			currentVal := ""
			if d.configValues != nil {
				currentVal = d.configValues[cfgKey.Key]
			}

			keyLabel := d.styles.DetailLabel.Render("  " + cfgKey.Key + ": ")
			var valuePart string
			if currentVal != "" {
				valuePart = d.styles.CredentialValue.Render(currentVal)
			} else if cfgKey.Required {
				valuePart = d.styles.ScenarioDisabled.Render("(not set)") + " " + d.styles.DemoActiveLabel.Render("[required]")
			} else {
				valuePart = d.styles.ScenarioDisabled.Render("(not set)")
			}
			lines = append(lines, keyLabel+valuePart)

			if cfgKey.Description != "" {
				wrapped := d.wordWrap(cfgKey.Description, contentWidth-4)
				for _, wl := range strings.Split(wrapped, "\n") {
					lines = append(lines, d.styles.ScenarioDisabled.Render("    "+wl))
				}
			}
		}
	}

	// Start Learning — always shown, content depends on deployment state
	lines = append(lines, "")
	lines = append(lines, sectionStyle.Render("Start Learning (Lab key bindings)"))

	key := d.styles.CredentialKey // orange, same as cost indicators
	desc := d.styles.HelpDesc

	if d.deployed && d.creds != nil && d.creds.AccessKeyID != "" {
		lines = append(lines, "  "+key.Render("[x]    ")+"  "+desc.Render("spawn shell with starting credentials"))
		lines = append(lines, "       "+d.styles.ScenarioDisabled.Render("(type exit to return to TUI)"))
		lines = append(lines, "  "+key.Render("[y]    ")+"  "+desc.Render("copy credentials as environment variables"))
		lines = append(lines, "  "+key.Render("[Y]    ")+"  "+desc.Render("copy credentials as ~/.aws/credentials block"))
		if d.scenario.HasDemo() {
			lines = append(lines, "  "+key.Render("[r]    ")+"  "+desc.Render("run automated attack demo end to end"))
		}
		if d.scenario.HasCleanup() {
			lines = append(lines, "  "+key.Render("[c]    ")+"  "+desc.Render("clean up demo artifacts"))
		}
		if d.scenario.HasConfig() {
			lines = append(lines, "  "+key.Render("[e]    ")+"  "+desc.Render("edit scenario configuration"))
		}
		lines = append(lines, "")
		lines = append(lines, "  "+key.Render("[space]")+"  "+desc.Render("disable this scenario"))
		lines = append(lines, "  "+key.Render("[a]    ")+"  "+desc.Render("apply changes"))
	} else if d.enabled {
		lines = append(lines, "  "+d.styles.ScenarioDisabled.Render("Not yet deployed — apply to start learning"))
		lines = append(lines, "  "+key.Render("[a]    ")+"  "+desc.Render("deploy this scenario"))
		lines = append(lines, "  "+key.Render("[space]")+"  "+desc.Render("disable this scenario"))
		if d.scenario.HasConfig() {
			lines = append(lines, "  "+key.Render("[e]")+"  "+desc.Render("edit scenario configuration"))
		}
	} else {
		lines = append(lines, "  "+d.styles.ScenarioDisabled.Render("Not enabled — enable and deploy to start learning"))
		lines = append(lines, "  "+key.Render("[space]")+"  "+desc.Render("enable this scenario"))
		lines = append(lines, "  "+key.Render("[a]    ")+"  "+desc.Render("deploy once enabled"))
	}

	// Deployed Resources (only if deployed)
	if d.deployed && len(d.resources) > 0 {
		lines = append(lines, "")
		lines = append(lines, sectionStyle.Render("Deployed Resources"))
		for _, arn := range d.resources {
			displayARN := arn
			if len(displayARN) > contentWidth-2 {
				displayARN = displayARN[:contentWidth-5] + "..."
			}
			lines = append(lines, d.styles.DetailValue.Render("  • "+displayARN))
		}
	}

	return lines
}

// View renders the details pane
func (d *DetailsPane) View() string {
	var sb strings.Builder

	// Title
	titleStyle := d.styles.PanelTitle.Width(d.width - 4)
	sb.WriteString(titleStyle.Render("Scenario Details"))
	sb.WriteString("\n")

	// Build all content lines
	contentLines := d.buildContent()

	// Calculate visible area
	visible := d.visibleRows()
	if visible < 1 {
		visible = 1
	}

	// Clamp scroll to valid range
	maxScroll := len(contentLines) - visible
	if maxScroll < 0 {
		maxScroll = 0
	}
	if d.scroll > maxScroll {
		d.scroll = maxScroll
	}
	if d.scroll < 0 {
		d.scroll = 0
	}

	// Render only visible lines
	end := d.scroll + visible
	if end > len(contentLines) {
		end = len(contentLines)
	}

	renderedLines := 0
	for i := d.scroll; i < end; i++ {
		sb.WriteString("\n")
		sb.WriteString(contentLines[i])
		renderedLines++
	}

	// Pad with empty lines to fill the visible area (keeps panel height constant)
	for i := renderedLines; i < visible; i++ {
		sb.WriteString("\n")
	}

	return d.wrapInPanel(sb.String())
}

func (d *DetailsPane) wordWrap(text string, width int) string {
	if width <= 0 {
		return text
	}

	var lines []string
	var currentLine strings.Builder

	words := strings.Fields(text)
	for _, word := range words {
		if currentLine.Len()+len(word)+1 > width {
			if currentLine.Len() > 0 {
				lines = append(lines, currentLine.String())
				currentLine.Reset()
			}
		}
		if currentLine.Len() > 0 {
			currentLine.WriteString(" ")
		}
		currentLine.WriteString(word)
	}
	if currentLine.Len() > 0 {
		lines = append(lines, currentLine.String())
	}

	return strings.Join(lines, "\n")
}

func (d *DetailsPane) wrapInPanel(content string) string {
	panelStyle := d.styles.Panel
	if d.focused {
		panelStyle = d.styles.PanelFocused
	}

	// Set both width and height to keep the panel size constant
	panelStyle = panelStyle.Width(d.width - 2).Height(d.height - 2)
	return panelStyle.Render(content)
}
