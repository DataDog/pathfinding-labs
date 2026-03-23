package tui

import (
	"fmt"
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
	styles     *Styles
	scenario   *scenarios.Scenario
	enabled    bool
	deployed   bool
	demoActive bool
	creds      *terraform.Credentials
	resources  []string // ARNs of deployed resources
	focused    bool
	width      int
	height     int
	scroll     int
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

// SetCredentials sets the credentials for the displayed scenario
func (d *DetailsPane) SetCredentials(creds *terraform.Credentials) {
	d.creds = creds
}

// ClearCredentials clears the credentials
func (d *DetailsPane) ClearCredentials() {
	d.creds = nil
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

	// Short Name (ID)
	lines = append(lines, d.styles.DetailLabel.Render("Short Name ")+d.styles.DetailHighlight.Bold(true).Render(d.scenario.UniqueID()))

	// Long Name (truncated if needed)
	name := d.scenario.Name
	if len(name) > contentWidth-11 {
		name = name[:contentWidth-14] + "..."
	}
	lines = append(lines, d.styles.DetailLabel.Render("Long Name  ")+d.styles.DetailValue.Render(name))

	// Status with color - show pending states
	var statusLine string
	statusLine = d.styles.DetailLabel.Render("Status     ")
	if d.enabled && d.deployed {
		statusLine += d.styles.EnvDeployed.Render("● Deployed")
	} else if d.enabled && !d.deployed {
		statusLine += d.styles.PendingDeployIndicator.Render() + d.styles.PendingDeployLabel.Render(" [Enablement pending apply]")
	} else if !d.enabled && d.deployed {
		statusLine += d.styles.PendingDestroyIndicator.Render() + d.styles.PendingDestroyLabel.Render(" [Disablement pending deploy]")
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
	lines = append(lines, d.styles.DetailLabel.Render("Target    ")+d.styles.DetailValue.Render(d.scenario.TargetShort()))
	lines = append(lines, d.styles.DetailLabel.Render("Cost      ")+d.styles.DetailValue.Render(d.scenario.CostEstimate))

	// Pathfinding.cloud link
	if d.scenario.PathfindingCloudID != "" {
		url := fmt.Sprintf("https://pathfinding.cloud/paths/%s", d.scenario.PathfindingCloudID)
		displayText := url
		if len(displayText) > contentWidth-10 {
			displayText = displayText[:contentWidth-13] + "..."
		}
		lines = append(lines, d.styles.DetailLabel.Render("Link      ")+hyperlink(url, d.styles.DetailHighlight.Render(displayText)))
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
		for _, perm := range d.scenario.Permissions.Required {
			permText := perm.Permission
			if len(permText) > contentWidth-2 {
				permText = permText[:contentWidth-5] + "..."
			}
			lines = append(lines, d.styles.DetailValue.Render("  "+permText))
		}
	}

	// Credentials (only if deployed)
	if d.deployed && d.creds != nil && d.creds.AccessKeyID != "" {
		lines = append(lines, "")
		lines = append(lines, d.styles.CredentialKey.Render("Starting Credentials")+sectionStyle.Render("  via Environment Variables"))
		lines = append(lines, "      "+d.styles.CredentialValue.Render(fmt.Sprintf("export AWS_ACCESS_KEY_ID=%s", d.creds.AccessKeyID)))
		lines = append(lines, "      "+d.styles.CredentialValue.Render(fmt.Sprintf("export AWS_SECRET_ACCESS_KEY=%s", d.creds.SecretAccessKey)))
		if d.creds.SessionToken != "" {
			lines = append(lines, "      "+d.styles.CredentialValue.Render(fmt.Sprintf("export AWS_SESSION_TOKEN=%s", d.creds.SessionToken)))
		}
		lines = append(lines, sectionStyle.Render("  via AWS Profile"))
		profileName := d.scenario.UniqueID()
		lines = append(lines, "      "+d.styles.CredentialValue.Render(fmt.Sprintf("[%s]", profileName)))
		lines = append(lines, "      "+d.styles.CredentialValue.Render(fmt.Sprintf("aws_access_key_id = %s", d.creds.AccessKeyID)))
		lines = append(lines, "      "+d.styles.CredentialValue.Render(fmt.Sprintf("aws_secret_access_key = %s", d.creds.SecretAccessKey)))
		if d.creds.SessionToken != "" {
			lines = append(lines, "      "+d.styles.CredentialValue.Render(fmt.Sprintf("aws_session_token = %s", d.creds.SessionToken)))
		}
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
